local Queue = require 'EmberRoutesProbe/PrecheckQueue'
local Surfaces = require 'EmberRoutesProbe/CraftSurfaces'
local Recipe = require 'EmberRoutesProbe/ProductionRecipe'
local Production = require 'EmberRoutesProbe/Production'
local CraftYield = require 'EmberRoutesProbe/ProductionYield'
local Registry = require 'EmberRoutesProbe/ContainerRegistry'
local Runtime = require 'EmberRoutesProbe/TaskRuntime'
local Signals = require 'EmberRoutesProbe/LaborSignals'
local Wake = require 'EmberRoutesProbe/PlanningWake'
local CookingOrders = require 'EmberRoutesProbe/CookingOrders'
local Probe = require 'EmberRoutesProbe/Boot'

local evaluations = Queue.new(4)
local decisionScans = {}
local planGenerations = {}

local CraftingProvider = {
    category = 'crafting',
    defaultPriority = 3,
}

local function waiting(o, e)
    return o and o.category ~= 'cooking' and o == e.order and not o.jobId and o.state == 'WAITING'
        and e.generation == (planGenerations[o.id] or 0)
end

function CraftingProvider.waiting(o, e)
    return waiting(o, e)
end

function CraftingProvider.reset()
    evaluations:clear()
    decisionScans = {}
    planGenerations = {}
end

function CraftingProvider.evaluations()
    return evaluations
end

function CraftingProvider.pending(npcId)
    return evaluations:get(npcId)
end

function CraftingProvider.cancel(npcId)
    evaluations:remove(npcId)
end

function CraftingProvider.bumpGeneration(orderId)
    planGenerations[orderId] = (planGenerations[orderId] or 0) + 1
    return planGenerations[orderId]
end

function CraftingProvider.cleanupOrder(orderId, readyWorkers)
    if readyWorkers then
        for _, npcId in ipairs(readyWorkers) do
            local e = evaluations:get(npcId)
            if e and e.orderId == orderId then evaluations:remove(npcId) end
        end
    end
    planGenerations[orderId] = nil
end

function CraftingProvider.scanStatus(npcId, orders)
    local scan = decisionScans[npcId]
    if not scan then return true, nil end
    if scan.unknown then return false, scan.watch end
    if orders then
        for _, order in ipairs(orders) do
            local oId = type(order) == 'table' and order.id or order
            if not scan.seen[oId] then return false, scan.watch end
        end
    end
    return true, scan.watch
end

function CraftingProvider.discover(env)
    local evaluation = evaluations:get(env.npcId)
    if evaluation and evaluation.ready then
        local o = env.orders and env.orders[evaluation.orderId]
        local spec, reason
        if waiting(o, evaluation) and not Wake.changed(evaluation.watch) and env.now <= evaluation.expires and env.priority > 0 then
            spec, reason = Recipe.inspect(env.actor, env.npc, evaluation.object, o.recipeId, true, false)
        end
        if spec then
            local offer = env.directory:upsert('craft:' .. o.id, o.revision, 'crafting', env.entry.id)
            if offer and not offer.jobId then
                env.candidates[#env.candidates + 1] = {
                    key = offer.key,
                    category = 'crafting',
                    allowed = true,
                    score = 1 / (o.sequence + 1),
                    order = o,
                    object = evaluation.object,
                    revision = offer.revision
                }
            end
        else
            if o and reason and env.signal then env.signal(o, reason) end
            evaluations:remove(env.npcId)
            evaluation = nil
        end
    end

    local orders = env.orderIds or {}
    local scan = decisionScans[env.npcId]
    if not scan or scan.sequence ~= env.sequence or scan.scope ~= env.entry.id or scan.revision ~= env.priorities.revision
        or env.now >= scan.expires or Wake.changed(scan.watch) then
        scan = {
            sequence = env.sequence,
            scope = env.entry.id,
            revision = env.priorities.revision,
            cursor = 0,
            seen = {},
            expires = env.now + 10000,
            watch = Wake.capture(env.entry)
        }
        decisionScans[env.npcId] = scan
    end

    for _ = 1, math.min(3, #orders) do
        scan.cursor = scan.cursor % #orders + 1
        local orderItem = orders[scan.cursor]
        local orderId = type(orderItem) == 'table' and orderItem.id or orderItem
        local o = env.orders and env.orders[orderId]
        if o then
            local rr1 = env.retryReady and env.retryReady(o, env.npcId, env.now)
            if rr1 == nil then rr1 = true end
            if o.category == 'cooking' or o.jobId or o.state ~= 'WAITING' or env.priority == 0 or not rr1 then
                scan.seen[o.id] = true
            end
            local eg = evaluations:get(env.npcId)
            local es = evaluations:size()
            if o.category ~= 'cooking' and not o.jobId and o.state == 'WAITING' and env.priority > 0 and not eg
                and #env.candidates == 0 and es < 4 and rr1 then
                local object, reason
                if o.surfaceId then
                    object, reason = Surfaces.resolve((Registry.data().craftSurfaces or {})[o.surfaceId], o.surfaceId)
                end
                local spec, why
                if not reason then
                    spec, why = Recipe.inspect(env.actor, env.npc, object, o.recipeId, true, false)
                end
                scan.seen[o.id] = true
                if (reason and string.find(reason, 'UNLOADED', 1, true)) or (why and string.find(why, 'UNLOADED', 1, true)) then
                    scan.unknown = true
                end
                local watch = Wake.capture(env.entry)
                if spec and not CookingOrders.parentAllows(o) then
                    spec = nil
                    why = 'COOKING_PARENT_WAIT'
                end
                if spec then
                    local e = {
                        orderId = o.id,
                        order = o,
                        generation = planGenerations[o.id] or 0,
                        object = object,
                        scopeId = env.entry.id,
                        watch = watch,
                        started = env.now,
                        request = require('EmberRoutesProbe/ProductionChain').new(
                            env.actor, env.npc, env.entry, o.recipeId, CraftYield.remaining(o), object, 'offer:' .. o.id, false, o.preferences
                        )
                    }
                    evaluations:put(env.npcId, e)
                else
                    if why == 'NPC_RECIPE_UNKNOWN' and Probe.idleStudy then
                        local read = Recipe.read(o.recipeId)
                        if read and read.recipe and read.recipe.getName then
                            local meta = read.recipe.getMetaRecipe and read.recipe:getMetaRecipe()
                            local keys = { read.recipe:getName() }
                            if meta and meta ~= '' then keys[#keys + 1] = meta end
                            if read.recipe.getTranslationName then keys[#keys + 1] = read.recipe:getTranslationName() end
                            if env.setStudyTarget then
                                env.setStudyTarget({ orderId = o.id, recipeId = o.recipeId, knowledge = keys })
                            end
                        end
                    end
                    if env.cool then env.cool(o, env.npcId, { watch = watch }, reason or why, env.now) end
                    if env.signal then env.signal(o, reason or why) end
                end
            end
        end
    end
end

function CraftingProvider.claim(selected, npcId, jobId, env)
    local o = selected.order
    if not CookingOrders.parentAllows(o) then return 'TASK_CHANGED' end
    o.jobId, o.npcId, o.state = jobId, npcId, 'CLAIMING'
    o.revision = o.revision + 1
    local result = Production.execute(env.actor, 'run', selected.object, npcId, {
        recipeId = o.recipeId,
        quantity = CraftYield.remaining(o),
        settlementId = env.entry.id,
        taskId = jobId,
        orderId = o.id,
        chain = true,
        nonPreemptive = true,
        preferences = o.preferences
    })
    if result ~= 'QUEUED' then
        o.jobId = nil
        o.npcId = nil
        o.state = 'WAITING'
        if env.cool then env.cool(o, npcId, { watch = Wake.capture(env.entry) }, result, env.now) end
        if env.signal then env.signal(o, result) end
    end
    return result
end

function CraftingProvider.step(env)
    if evaluations:size() == 0 then return 0, 0 end
    local ops, slices = evaluations:step(128, function(id, e)
        local binding = env.eligible and env.eligible(env.actor, id, e.scopeId)
        local hasCargo = env.hasCargo and env.hasCargo(env.actor, id)
        local record = env.record and env.record(id)
        local o = env.orders and env.orders[e.orderId]
        local prio = env.priorities and env.priorities(id)
        local craftP = prio and prio.crafting or 0
        return binding and not hasCargo and (not record or record.state == 'DONE')
            and waiting(o, e) and craftP > 0
            and (not e.ready or env.now <= e.expires and not Wake.changed(e.watch))
    end, function(id, e, plan, reason)
        if plan then
            e.ready = true
            e.expires = env.now + 1000
            if env.onReady then env.onReady(id) end
        else
            local scan = decisionScans[id]
            if scan and reason and (string.find(reason, 'UNLOADED', 1, true) or string.find(reason, 'OBSERV', 1, true)
                or string.find(reason, 'SCAN_LIMIT', 1, true)) then
                scan.unknown = true
            end
            if env.cool then env.cool(e.order, id, e, reason, env.now) end
            if env.signal then env.signal(e.order, reason) end
            evaluations:remove(id)
        end
    end, getTimestampMs)
    return ops, slices
end

function CraftingProvider.reconcile(env)
    local orders = env and env.orders
    if not orders then
        local root = Registry.data()
        local pw = root and root.publicWork
        orders = pw and pw.orders
    end
    if not orders then return end
    local directory = env and env.directory or { release = function() end }
    local catalogEpoch = env and env.catalogEpoch

    local Business = require 'EmberRoutesProbe/BusinessJobs'
    local jobs
    for _, o in pairs(orders) do
        if o.category ~= 'cooking' and o.jobId then
            local r
            if Business.record then
                r = Business.record(o.jobId, 'CRAFT')
            else
                jobs = jobs or Business.records('CRAFT')
                r = jobs[o.jobId]
            end
            if r and r.released and (r.activityYield or o.craftProgress) then
                local patch, why = CraftYield.settle(o, r)
                if patch then
                    local npcId, jobId = o.npcId, o.jobId
                    directory:release('craft:' .. o.id, jobId, { effects = 'KNOWN', obligationsCleared = true })
                    o.craftProgress = patch.progress
                    o.state = patch.state
                    o.jobId = nil
                    o.npcId = nil
                    o.reason = o.state == 'WAITING' and 'ACTIVITY_YIELD' or nil
                    o.revision = o.revision + 1
                    planGenerations[o.id] = (planGenerations[o.id] or 0) + 1
                    if catalogEpoch and o.settlementId then
                        catalogEpoch[o.settlementId] = (catalogEpoch[o.settlementId] or 0) + 1
                    end
                    Signals.changed(npcId)
                elseif why then
                    o.state = 'RECONCILE_REQUIRED'
                    if env.signal then env.signal(o, why) end
                end
            elseif r then
                local state = r.released and (r.state == 'DONE' and 'DONE' or 'CANCELLED') or r.state
                if o.state ~= state then
                    o.state = state
                    o.revision = o.revision + 1
                    Signals.changed(o.npcId)
                end
                if env.signal then env.signal(o, r.reason) end
            elseif not Runtime.current():status(o.npcId, o.jobId) then
                local saved = (Registry.data().taskJobs or { byId = {} }).byId[o.jobId]
                if saved then
                    o.state = 'RECONCILE_REQUIRED'
                    if env.signal then env.signal(o, 'JOB_INDEX_CONFLICT') end
                else
                    directory:release('craft:' .. o.id, o.jobId, { effects = 'KNOWN', obligationsCleared = true })
                    o.jobId = nil
                    o.npcId = nil
                    o.state = 'WAITING'
                    if env.signal then env.signal(o, 'WAITING_CLAIM') end
                end
            end
        end
    end
end

function CraftingProvider.idle(npcId, entry, target)
    if target and Probe.idleStudy then
        Probe.idleStudy(npcId, entry, target)
    end
end

function CraftingProvider.hasWork(env)
    local orders = env and env.orders
    if not orders then
        local root = Registry.data()
        local pw = root and root.publicWork
        orders = pw and pw.orders
    end
    if orders then
        for _, o in pairs(orders) do
            if o.category ~= 'cooking' then return true end
        end
        return false
    end
    return evaluations:size() > 0
end

return CraftingProvider
