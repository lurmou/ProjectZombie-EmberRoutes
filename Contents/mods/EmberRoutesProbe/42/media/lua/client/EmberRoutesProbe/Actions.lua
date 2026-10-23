local Probe = require "EmberRoutesProbe/Boot"
local Log = require "EmberRoutesProbe/Log"
local Batch = require "EmberRoutesProbe/Batch"
local Diagnostic=require 'EmberRoutesProbe/TaskDiagnostic'
local View=require 'EmberRoutesProbe/InventoryView'
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISEatFoodAction"
require "TimedActions/ISDrinkFluidAction"
require "TimedActions/ISInventoryTransferAction"

local Actions = { fixtures = nil, batch = nil, actor = nil, lastState = nil }
local controlled
local function log(message) Log.write("ACTION", message) end
local function now() return getTimestampMs() end

local function busy()
    return Actions.batch and Actions.batch.state == "RUNNING"
end

local function clearQueue(npc,body)
    -- clear() stops the engine action before clearing the Lua queue (native partial consumption).
    if body then return body.clear() end
    ISTimedActionQueue.clear(npc)
end

function Actions.cancel(reason, npcId,body)
    if npcId and Actions.fixtures and EmberRoutesProbeJava.carrierId(Actions.fixtures.npc)~=npcId then return end
    if not body and Diagnostic.active(controlled) then
        if not npcId or npcId==controlled.binding.id then return Diagnostic.cancel(controlled,reason) end
        return
    end
    if busy() then Actions.batch:cancel(reason or "USER") end
    if Actions.fixtures and (body or Probe.controlledExecution~=true) then clearQueue(Actions.fixtures.npc,body) end
end

local function cleanup(body)
    local f = Actions.fixtures
    if not f then return true end
    if Probe.controlledExecution==true and not body then return false end
    if body and not body.current() then return false end
    local root = f.npc:getInventory()
    if f.bag then
        local contents = f.bag:getItems()
        if contents:size()>512 then Actions.cleanupBlocked=true return false end
        for i = 0, contents:size() - 1 do
            local found = false
            for _, fixture in ipairs(f.items) do
                if contents:get(i) == fixture then found = true break end
            end
            if not found then
                Actions.cleanupBlocked = true
                log("CLEANUP_BLOCKED untracked item in fixture bag")
                return false
            end
        end
    end
    -- Check every location before removing anything; never dispose an unrelated item.
    for _, item in ipairs(f.items) do
        local container = item:getContainer()
        if Probe.controlledExecution==true and not container then
            Actions.cleanupBlocked=true log('CLEANUP_BLOCKED missing original fixture') return false
        end
        if container and container ~= root and container ~= f.bag then
            Actions.cleanupBlocked = true
            log("CLEANUP_BLOCKED fixture moved to an unexpected container id=" .. item:getID())
            return false
        end
    end
    for i = #f.items, 1, -1 do
        local item = f.items[i]
        local container = item:getContainer()
        if container then container:Remove(item) end
    end
    if body then
        if not body.clear() then return false end
    else ISTimedActionQueue.queues[f.npc] = nil end
    Actions.fixtures = nil
    Actions.cleanupBlocked = false
    if Actions.batch and Actions.batch.state ~= "RUNNING" then
        -- Keep scalar evidence, release closures that still refer to the removed body.
        Actions.batch.steps = {}
        Actions.batch.current = nil
    end
    log("FIXTURES_CLEANED")
    return true
end

local function prepare(npc)
    if Actions.fixtures then
        if Actions.fixtures.npc == npc and Actions.fixtures.ready then return Actions.fixtures end
        if not cleanup() then error("previous fixtures could not be cleaned") end
    end
    local f = { npc = npc, items = {} }
    Actions.fixtures = f -- retain partial construction for cleanup after an error
    local root = npc:getInventory()
    local function add(kind)
        local item = root:AddItem(kind)
        if not item then error("fixture unavailable: " .. kind) end
        f.items[#f.items + 1] = item
        item:getModData().EmberRoutesProbeFixture = Probe.build.version
        return item
    end
    f.bagItem = add("Base.Bag_Schoolbag")
    f.bag = f.bagItem:getInventory()
    f.cargo = add("Base.Pencil")
    f.cargo:setCondition(math.max(1, f.cargo:getConditionMax() - 1))
    f.cargo:getModData().EmberRoutesProbeSentinel = "original-instance"
    f.cargoID = f.cargo:getID()
    f.condition = f.cargo:getCondition()
    f.food = add("Base.Bread")
    f.water = add("Base.WaterBottle")
    if not f.water:getFluidContainer() or f.water:getFluidContainer():getAmount() <= 0 then
        error("filled fluid fixture unavailable")
    end
    -- Leave room for measurable consumption without starting at severe needs.
    npc:getStats():set(CharacterStat.HUNGER, 0.4)
    npc:getStats():set(CharacterStat.THIRST, 0.4)
    f.ready = true
    log("FIXTURES_READY cargoID=" .. f.cargoID .. " food=" .. f.food:getHungChange()
        .. " fluid=" .. f.water:getFluidContainer():getAmount())
    return f
end

function Actions.isBusy() return busy() end
function Actions.cleanupForHaul(npc,body)
    if npc and Actions.fixtures and Actions.fixtures.npc~=npc then return true end
    if busy() then return false end
    return cleanup(body)
end

local function cargoCheck(f, dest)
    local item = f.cargo
    local count = (f.npc:getInventory():getItems():contains(item) and 1 or 0)
        + (f.bag:getItems():contains(item) and 1 or 0)
    local valid = item:getContainer() == dest and dest:getItems():contains(item) and count == 1
        and item:getID() == f.cargoID and item:getCondition() == f.condition
        and item:getModData().EmberRoutesProbeSentinel == "original-instance"
    return valid, "cargoID=" .. item:getID() .. " copies=" .. count .. " condition=" .. item:getCondition()
end

local function actionStep(f, name, kind, cancelAt, dest)
    local body=f.body
    local step = { name = name }
    local action, stopped, performed, attempted, cancelled, settledAt
    local beforeHunger, beforeThirst, beforeFood, beforeWater, source
    function step.start()
        if body and not body.current() then return 'FAILED','CONTROL_REQUIRED' end
        local npc = f.npc
        if not EmberRoutesProbeJava.carrierActive(npc) then error("carrier unavailable or moving") end
        if not npc:getCharacterActions():isEmpty() then error("carrier already has a native action") end
        local stats = npc:getStats()
        beforeHunger = stats:get(CharacterStat.HUNGER)
        beforeThirst = stats:get(CharacterStat.THIRST)
        beforeFood = math.abs(f.food:getHungChange())
        beforeWater = f.water:getFluidContainer():getAmount()
        if kind == "eat" then
            if f.food:getContainer() ~= npc:getInventory() or beforeFood < 0.04 then error("food exhausted") end
            action = ISEatFoodAction:new(npc, f.food, 0.25)
        elseif kind == "drink" then
            if f.water:getContainer() ~= npc:getInventory() or beforeWater < 0.1 then error("water exhausted") end
            action = ISDrinkFluidAction:new(npc, f.water, 0.25)
        else
            source = f.cargo:getContainer()
            if source == dest or (source ~= npc:getInventory() and source ~= f.bag) then error("invalid fixture source") end
            action = ISInventoryTransferAction:new(npc, f.cargo, source, dest, 120)
            -- Both containers are on this NPC; native selectedContainer stays nil,
            -- avoiding player-slot loot UI. No global action class is patched.
        end
        local nativeStop, nativePerform, nativeValid = action.stop, action.perform, action.isValid
        local nativeAnim,nativeUpdate=action.startActionAnim,action.update
        action.isValid=function(self) return (not body or body.current()) and nativeValid(self) end
        if nativeAnim then action.startActionAnim=function(self) if not body or body.current() then return nativeAnim(self) end end end
        if nativeUpdate then action.update=function(self) if not body or body.current() then return nativeUpdate(self) end end end
        action.useProgressBar = false
        action.forceProgressBar = false
        action.stop = function(self)
            if body and (stopped or performed or not body.retained()) then return end
            stopped = true
            nativeStop(self)
        end
        action.perform = function(self)
            if body and (attempted or stopped or not body.current() or not self:isValid()) then return end
            attempted=true
            nativePerform(self)
            performed = true
        end
        if body then assert(body.add(action),'CONTROL_REQUIRED') else ISTimedActionQueue.add(action) end
    end
    function step.cancel() clearQueue(f.npc,body) end
    function step.poll(time)
        if cancelAt and not cancelled and action.action and action:isStarted()
                and action:getJobDelta() >= cancelAt then
            if action:getJobDelta() >= 1 then return "FAILED", "cancel window missed" end
            cancelled = true
            clearQueue(f.npc,body)
            settledAt = time + 500
        end
        if ISTimedActionQueue.hasAction(action) then return "WAIT" end
        if not settledAt then settledAt = time + 500 end
        if time < settledAt then return "WAIT" end
        if cancelAt then
            if not cancelled or not stopped or performed then return "FAILED", "expected native cancellation" end
        elseif not performed or stopped then return "FAILED", "queue ended without native completion" end
        local stats = f.npc:getStats()
        if kind == "transfer" then
            local valid, details = cargoCheck(f, cancelAt and source or dest)
            return valid and "PASSED" or "FAILED", details
        elseif kind == "eat" then
            local consumed = beforeFood - math.abs(f.food:getHungChange())
            local hungerDelta = beforeHunger - stats:get(CharacterStat.HUNGER)
            local valid = consumed > 0.0001 and hungerDelta > 0.0001
            -- Full native completion must consume the requested fraction of base hunger.
            local requested = math.abs(f.food:getBaseHunger()) * 0.25
            if cancelAt then valid = valid and consumed < requested - 0.0001
            else valid = valid and math.abs(consumed - requested) < 0.002 end
            return valid and "PASSED" or "FAILED", "foodConsumed=" .. consumed .. " hungerReduced=" .. hungerDelta
        else
            local consumed = beforeWater - f.water:getFluidContainer():getAmount()
            local thirstDelta = beforeThirst - stats:get(CharacterStat.THIRST)
            local requested = beforeWater * 0.25
            local valid = consumed > 0.0001 and thirstDelta > 0.0001
            if cancelAt then valid = valid and consumed < requested - 0.0001
            else valid = valid and math.abs(consumed - requested) < 0.002 end
            return valid and "PASSED" or "FAILED", "fluidConsumed=" .. consumed .. " thirstReduced=" .. thirstDelta
        end
    end
    return step
end

local function observeStep(f)
    local step = { name = "IDLE_NO_REPEAT" }
    local endTime, food, water
    function step.start()
        endTime = now() + 2000
        food = f.food:getHungChange()
        water = f.water:getFluidContainer():getAmount()
    end
    function step.cancel() end
    function step.poll(time)
        local valid, detail = cargoCheck(f, f.npc:getInventory())
        if not valid or food ~= f.food:getHungChange() or water ~= f.water:getFluidContainer():getAmount()
                or not f.npc:getCharacterActions():isEmpty() then
            return "FAILED", "unexpected repeated effect " .. detail
        end
        return time < endTime and "WAIT" or "PASSED", detail
    end
    return step
end

function Actions.report()
    if not Actions.batch then log("REPORT no batch") return "NO_REPORT" end
    log("REPORT state=" .. Actions.batch.state .. " cases=" .. #Actions.batch.records)
    for _, entry in ipairs(Actions.batch.records) do
        log("REPORT " .. entry.name .. " " .. entry.state .. " " .. entry.detail)
    end
    return Actions.batch.state
end

local function execute(actor, command,c)
    if command == "report" then return Actions.report() end
    if not c and Actions.fixtures and EmberRoutesProbeJava.selectedId
        and EmberRoutesProbeJava.carrierId(Actions.fixtures.npc)~=EmberRoutesProbeJava.selectedId() then return "FIXTURE_OTHER_NPC" end
    if command == "cancel" then
        if Probe.cancelAll then Probe.cancelAll("USER") else Actions.cancel("USER") end
        return "CANCELLED"
    end
    if Probe.haulBusy and Probe.haulBusy() then return "BUSY" end
    if not c and command ~= "cleanup" and Probe.cancelCompanion then Probe.cancelCompanion("ACTION_ORDER") end
    if not c and command ~= "report" and Probe.cancelWork then Probe.cancelWork("ACTION_ORDER") end
    if busy() then return "BUSY" end
    if command == "cleanup" then return cleanup(c and c.body) and "CLEANED" or "CLEANUP_BLOCKED" end
    if not Probe.ready or not Probe.hasJava() then return Probe.unavailableCode() end
    local npc = c and c.npc or EmberRoutesProbeJava.actionCarrier(actor)
    if not npc then return "CARRIER_UNAVAILABLE" end
    local health = npc:getBodyDamage():getOverallBodyHealth()
    if health < 95 then
        log("START_REFUSED reason=INJURED health=" .. health .. " minimum=95; no fixtures created")
        return "INJURED"
    end
    if command == "suite" then
        if not cleanup(c and c.body) then return "CLEANUP_BLOCKED" end
    end
    local f = prepare(npc)
    f.body=c and c.body
    if not f or not f.bag or not f.ready then error("incomplete fixture setup") end
    if command == "prepare" then return "FIXTURES_READY" end
    local steps
    if command == "suite" then
        steps = {
            actionStep(f, "PACK_INSTANCE", "transfer", nil, f.bag),
            actionStep(f, "UNPACK_INSTANCE", "transfer", nil, npc:getInventory()),
            actionStep(f, "EAT_EFFECT", "eat"),
            actionStep(f, "DRINK_EFFECT", "drink"),
            actionStep(f, "CANCEL_TRANSFER", "transfer", 0.25, f.bag),
            actionStep(f, "CANCEL_EAT_PARTIAL", "eat", 0.35),
            actionStep(f, "CANCEL_DRINK_PARTIAL", "drink", 0.35),
            actionStep(f, "REPEAT_PACK", "transfer", nil, f.bag),
            actionStep(f, "REPEAT_UNPACK", "transfer", nil, npc:getInventory()),
            observeStep(f),
        }
    elseif command == "eat" or command == "drink" then
        steps = { actionStep(f, string.upper(command), command) }
    elseif command == "pack" or command == "unpack" then
        steps = { actionStep(f, string.upper(command), "transfer", nil, command == "pack" and f.bag or npc:getInventory()) }
    else return "INVALID_COMMAND" end
    Actions.actor = actor
    Actions.lastState = nil
    Actions.batch = Batch.new(steps, log)
    log("BATCH_STARTED cases=" .. #steps)
    return "STARTED"
end

local function evidence()
    local f=Actions.fixtures
    if not f then return {effects='KNOWN',ids={}} end
    local ids={} local known=true
    local containers={f.npc:getInventory()} if f.bag then containers[#containers+1]=f.bag end
    local index=View.index(containers)
    for _,item in ipairs(f.items) do
        ids[#ids+1]=item:getID()
        if not index or View.find(index,item:getID())~=item then known=false end
        local container=item:getContainer()
        if container~=f.npc:getInventory() and container~=f.bag then known=false end
        if container and not container:getItems():contains(item) then known=false end
    end
    if f.bag then
        local contents=f.bag:getItems()
        if contents:size()>512 then return {effects='UNKNOWN',ids=ids} end
        for i=0,contents:size()-1 do
            local owned=false for _,item in ipairs(f.items) do if item==contents:get(i) then owned=true break end end
            if not owned then known=false end
        end
    end
    return {effects=known and 'KNOWN' or 'UNKNOWN',ids=ids}
end
function Actions.fixtureEvidence(npc)
    if npc and Actions.fixtures and Actions.fixtures.npc~=npc then return {effects='KNOWN',ids={}} end
    return evidence()
end
local function dispatch(actor,command)
    if Probe.controlledExecution~=true or command=='report' then return execute(actor,command) end
    if command=='cancel' then
        if controlled and controlled.binding.id==EmberRoutesProbeJava.selectedId() then Diagnostic.cancel(controlled,'USER') end
        return 'STOP_REQUESTED'
    end
    if command~='cleanup' and command~='prepare' and command~='suite' and command~='eat' and command~='drink'
        and command~='pack' and command~='unpack' then return 'INVALID_COMMAND' end
    if Diagnostic.active(controlled) then return 'BUSY' end
    local result,c=Diagnostic.submit(actor,'ACTIONS',{
        assets=true,recovery=command=='cleanup',
        validate=function(binding)
            return not busy() and (not Probe.haulBusy or not Probe.haulBusy())
                and (not Actions.fixtures or Actions.fixtures.npc==binding.handle)
                and (command=='cleanup' or binding.handle:getBodyDamage():getOverallBodyHealth()>=95)
        end,
        start=function(context)
            context.result=execute(actor,command,context) context.recovered=context.result=='CLEANED'
            return context.result=='STARTED' or context.result=='FIXTURES_READY' or context.recovered,context.result
        end,
        tick=function(context) Actions.tick(context) end,
        finished=function() return not busy() end,
        pause=function(context,reason) Actions.cancel(reason,context.binding.id,context.body) end,
        evidence=evidence})
    if c then controlled=c end
    return result
end

function Actions.execute(actor, command)
    local ok, result = pcall(dispatch, actor, command)
    if not ok then
        Actions.cancel("ERROR")
        log("ERROR " .. tostring(result))
        result = "ERROR"
    end
    if result == "INJURED" then actor:Say(getText("IGUI_EmberRoutesProbe_ActionInjured"))
    else actor:Say(getText("IGUI_EmberRoutesProbe_ActionResult") .. " " .. tostring(result)) end
    return result
end

function Actions.tick(context)
    local f = Actions.fixtures
    if not f or not f.npc then return end
    local body=f.body
    if body and (not context or context~=controlled or context.body~=body or not body.current()) then return end
    local npc = f.npc
    if not Probe.ready or not EmberRoutesProbeJava.carrierActive(npc) then
        if not Actions.cleanupBlocked then
            Actions.cancel("CARRIER_LIFECYCLE")
            cleanup()
        end
        return
    end
    if not busy() then return end
    if npc:getBodyDamage():getOverallBodyHealth() < 95 then
        Actions.cancel("INJURED")
    else
        -- Catch only this optional test boundary. Fail the batch visibly; never hide native errors.
        local ok, err = pcall(Actions.batch.tick, Actions.batch, now())
        if not ok then
            Actions.cancel("ERROR")
            log("ERROR " .. tostring(err))
        end
    end
    local state = Actions.batch.state
    if state ~= "RUNNING" and state ~= Actions.lastState then
        Actions.lastState = state
        if Actions.actor and not Actions.actor:isDead() then
            if Actions.batch.reason == "INJURED" then Actions.actor:Say(getText("IGUI_EmberRoutesProbe_ActionInjured"))
            else Actions.actor:Say(getText("IGUI_EmberRoutesProbe_ActionResult") .. " " .. state .. " " .. #Actions.batch.records) end
        end
    end
end

Probe.cancelActions = Actions.cancel
Probe.tickActions = Actions.tick
return Actions
