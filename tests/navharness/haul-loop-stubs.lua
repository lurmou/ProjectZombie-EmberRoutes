-- Haul-loop harness stubs (tests/navharness/haul-loop-stubs.lua).
--
-- Complete stub set for running the REAL HaulAgent.lua headless under
-- lua5.4. Deliberately self-contained: do NOT reuse the stubs from
-- tests/lua/haul-source-backoff-test.lua -- that file is stale (its Store
-- lacks settleHaulLines) and belongs to another work item.
--
-- Bridge model (Java motion trace -> scripted Lua bridge):
--   Spike4 (real EmberPathfinder + ProbeMovement on the synthetic world,
--   see motion-trace-spike4.txt) measured scenario B -- path ends 0.5 short
--   of the final waypoint -- as MOVING for 1.88s then PATH_ENDED.
--   The bridge below reproduces exactly that: command("move") -> MOVING for
--   19 ticks of 100ms (1.9s), then PATH_ENDED, on every attempt.
--   The 100ms tick quantisation adds ~0.1s of detection lag versus the
--   1.88s Java measurement; walk durations are therefore reported as
--   ~2.0s and the trace notes the quantisation.
--   Kahlua-in-JVM is NOT used here: KahluaLaborTest reads stdlib.lua from
--   a hardcoded Windows path that does not exist on this machine, so the
--   Lua half of this harness runs only under lua5.4.
local M = {}

-- spec = {
--   lines = { { itemId=1, custodyState='UNCOLLECTED'|'CARRIED',
--               sourceId='sourceA', destinationId='destA' }, ... },
--   sources = { 'sourceA', 'sourceB', ... },       -- TAKE endpoints
--   destinations = { 'destA', 'destB', ... },      -- PUT endpoints
--   recordSource = 'sourceA',   -- r.source: the ONLY key api.resume gates on
--   recordDestination = 'destA',
--   motionTicks = 19,           -- MOVING ticks per attempt (Spike4-B: 1.88s)
-- }
function M.install(spec)
    local ctx = { spec = spec, now = 100, events = {}, moves = {}, logLines = {} }
    local function logEvent(kind, detail)
        ctx.events[#ctx.events + 1] = { t = ctx.now, kind = kind, detail = detail }
    end
    ctx.logEvent = logEvent

    -- Simulated engine clock. Clock.nowMs() (real, shared/) reads the
    -- global getTimestampMs fresh on every call, so advancing ctx.now
    -- moves every production deadline/backoff in lockstep.
    _G.getTimestampMs = function() return ctx.now end
    _G.isClient = function() return false end
    _G.isServer = function() return false end
    _G.ISTimedActionQueue = { clear = function() end }

    -- Endpoints and per-item handles.
    local endpoints = {}
    local function endpoint(id)
        if not endpoints[id] then
            local inv = {}
            function inv:getFreeCapacity() return 20 end
            endpoints[id] = { id = id, container = inv }
        end
        return endpoints[id]
    end
    for _, id in ipairs(spec.sources) do endpoint(id) end
    for _, id in ipairs(spec.destinations) do endpoint(id) end
    ctx.endpoints = endpoints

    local items = {}
    local function itemFor(id)
        if not items[id] then
            items[id] = {
                getID = function() return id end,
                getUnequippedWeight = function() return 1 end,
                getFullType = function() return 'Base.HaulItem' .. tostring(id) end,
            }
        end
        return items[id]
    end

    local root = {}
    function root:hasRoomFor() return true end
    local actions = { isEmpty = function() return true end }
    local npc = {
        getInventory = function() return root end,
        getCharacterActions = function() return actions end,
        getBodyDamage = function()
            return { getOverallBodyHealth = function() return 100 end }
        end,
    }
    local actor = { isDead = function() return false end }
    ctx.actor = actor

    local record = {
        id = 'haul', npcId = 'npc', format = 3, producer = 'LOGISTICS',
        scopeId = 'local-world', settlementId = 'base',
        source = spec.recordSource, destination = spec.recordDestination,
        generation = 1, routeRevision = 0, state = 'PAUSED',
        reason = 'LOAD_RECOVERY', manifest = {},
    }
    for _, l in ipairs(spec.lines) do
        record.manifest[#record.manifest + 1] = {
            itemId = l.itemId, custodyState = l.custodyState,
            sourceId = l.sourceId, destinationId = l.destinationId,
        }
    end
    ctx.record = record

    local token = {}
    local Store = {
        record = function() return record end,
        valid = function() return true end,
        claim = function() return token end,
        publish = function() return true end,
        pause = function() return token end,
        releaseCapacity = function() return true end,
        capacity = function() return true end,
        finish = function() return true end,
        settleHaulLines = function() return true end,
    }
    package.loaded['EmberRoutesProbe/Work/LaborStore'] = Store
    package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry'] = {
        resolve = function(id) return endpoints[id] end,
        revalidate = function(ep) return ep end,
    }
    package.loaded['EmberRoutesProbe/Hauling/HaulManifest'] = {
        valid = function(r) return r == record end,
        pending = function(l)
            return l.custodyState ~= 'DELIVERED' and l.custodyState ~= 'WITHDRAWN'
        end,
        claimItemIds = function()
            local ids = {}
            for _, l in ipairs(record.manifest) do
                if l.custodyState ~= 'DELIVERED' and l.custodyState ~= 'WITHDRAWN' then
                    ids[#ids + 1] = l.itemId
                end
            end
            return ids
        end,
        line = function(r, id)
            for _, l in ipairs(r.manifest) do
                if l.itemId == id then return l end
            end
        end,
    }
    -- where: 1 = NPC inventory (held / CARRIED), 2 = source container.
    -- A line's item is reported at the place its custodyState implies, so
    -- the TAKE leg sees UNCOLLECTED items at their source and the PUT leg
    -- sees CARRIED items on the NPC.
    package.loaded['EmberRoutesProbe/Warehouse/InventoryView'] = {
        scan = function()
            return { step = function() return {} end }
        end,
        find = function(_, id)
            for _, l in ipairs(record.manifest) do
                if l.itemId == id then
                    if l.custodyState == 'CARRIED' then return itemFor(id), 1 end
                    return itemFor(id), 2
                end
            end
        end,
    }
    package.loaded['EmberRoutesProbe/Work/LaborProducers'] = {
        transfer = function() return true end,
        freeCarry = function() return 20 end,
    }
    package.loaded['EmberRoutesProbe/Runtime/Driver'] = {
        bindId = function() return { id = 'npc', handle = npc } end,
    }
    package.loaded['EmberRoutesProbe/Runtime/TaskRuntime'] = {}
    -- Routing.new -> nil: no fallback search. Any endpoint rotation the
    -- trace shows therefore comes from HaulAgent's own per-line
    -- destination loop, not from a routing search.
    package.loaded['EmberRoutesProbe/Hauling/HaulRouting'] = {
        accept = function() return true end,
        new = function() return nil end,
    }
    package.loaded['EmberRoutesProbe/Work/LaborSignals'] = { changed = function() end }
    package.loaded['EmberRoutesProbe/Kernel/Boot'] = { ready = true, controlledExecution = false }
    package.loaded['EmberRoutesProbe/Kernel/Log'] = {
        write = function(tag, msg)
            ctx.logLines[#ctx.logLines + 1] = { t = ctx.now, tag = tag, msg = msg }
        end,
    }
    package.loaded['EmberRoutesProbe/Logistics/DeliveryTarget'] = {}
    package.loaded['EmberRoutesProbe/Warehouse/DisplayNames'] = { name = function() return 'Worker' end }
    package.loaded['EmberRoutesProbe/Hauling/HaulJobs'] = { commit = function() return true end }
    package.loaded['EmberRoutesProbe/SelfCare/HealthAssessment'] = { canWork = function() return true end }

    -- Scripted bridge. One motion model for every attempt (Spike4-B):
    -- MOVING for motionTicks ticks, then PATH_ENDED. The endpoint the
    -- move was issued for is recorded, so the trace shows WHICH endpoint
    -- each walk went to -- the whole point of the multi-line scenario.
    local motion, moveCountdown = 'IDLE', 0
    local currentMove = nil
    _G.EmberRoutesProbeJava = {
        carrierPresent = function() return true end,
        stopCarrier = function() motion = 'STOPPED' return true end,
        carrierActive = function() return motion ~= 'MOVING' end,
        motionResult = function() return motion end,
        command = function()
            motion, moveCountdown = 'MOVING', spec.motionTicks or 19
            return 'MOVE_REQUESTED'
        end,
    }
    package.loaded['EmberRoutesProbe/Work/WorkTransfer'] = {
        reachable = function() return false end,
        move = function(_, endpoint)
            return {
                start = function()
                    currentMove = { tStart = ctx.now, endpoint = endpoint.id }
                    ctx.moves[#ctx.moves + 1] = currentMove
                    logEvent('MOVE_START', 'endpoint=' .. endpoint.id)
                    _G.EmberRoutesProbeJava.command('move')
                end,
                poll = function()
                    if motion == 'MOVING' then
                        moveCountdown = moveCountdown - 1
                        if moveCountdown <= 0 then motion = 'PATH_ENDED' end
                        return 'WAIT'
                    end
                    if motion ~= 'REACHED' then
                        currentMove.tEnd = ctx.now
                        currentMove.outcome = motion
                        logEvent('MOVE_END',
                            'endpoint=' .. currentMove.endpoint .. ' outcome=' .. motion
                            .. ' walkMs=' .. tostring(ctx.now - currentMove.tStart))
                        return 'FAILED', 'movement=' .. motion
                    end
                    return 'PASSED'
                end,
            }
        end,
    }

    -- Real production modules required by HaulAgent capture the stub
    -- tables as upvalues at require time. Drop them from the require
    -- cache so every scenario re-requires them against ITS OWN fresh
    -- stubs (otherwise scenario 2+ would silently drive scenario 1's
    -- record -- that exact bug showed up as "S2: 0 walks, all resumes
    -- gated" on the first multi-scenario run). Clock is stateless (it
    -- reads _G.getTimestampMs fresh per call) and stays cached.
    package.loaded['EmberRoutesProbe/Hauling/HaulAgent'] = nil
    package.loaded['EmberRoutesProbe/Logistics/DeliveryFlow'] = nil

    return ctx
end

return M
