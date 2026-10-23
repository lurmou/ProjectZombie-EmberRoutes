local Probe = require "EmberRoutesProbe/Boot"
local Log = require "EmberRoutesProbe/Log"
local Actions = require "EmberRoutesProbe/Actions"
local Batch = require "EmberRoutesProbe/Batch"
local Rules = require "EmberRoutesProbe/HaulRules"
local Diagnostic=require 'EmberRoutesProbe/TaskDiagnostic'
local Driver=require 'EmberRoutesProbe/Driver'
require "TimedActions/ISInventoryTransferAction"

local Haul = { endpoints = {}, fixtures = {}, batch = nil }
local controlled
local function log(message) Log.write("HAUL", message) end
local function now() return getTimestampMs() end
local function newID()
    -- Verified in current vanilla Foraging; older lint inventories omit this global.
    local create = _G.getRandomUUID
    if type(create) ~= "function" then error("UUID_API_UNAVAILABLE") end
    return create()
end
function Haul.busy() return Haul.batch and Haul.batch.state == "RUNNING" end

local function validEndpoint(endpoint, role)
    if not endpoint then return false, "ENDPOINT_MISSING" end
    local object, container = endpoint.object, endpoint.container
    local square = object:getSquare()
    local tag = object:getModData().EmberRoutesProbeContainer or {}
    local attached = square ~= nil and square:getObjects():contains(object)
    local cell = getCell()
    local loaded = square ~= nil and cell ~= nil and cell:getGridSquare(square:getX(), square:getY(), square:getZ()) == square
    return Rules.endpoint(role, tag.role, endpoint.id, tag.id, attached, object:getContainer() == container, loaded)
end

local function endpointsValid()
    for _, role in ipairs({ "source", "destination" }) do
        local valid, reason = validEndpoint(Haul.endpoints[role], role)
        if not valid then return false, role .. ":" .. reason end
    end
    if Haul.endpoints.source.container == Haul.endpoints.destination.container then return false, "SAME_CONTAINER" end
    return true, "VALID"
end

function Haul.cancel(reason, npcId,body)
    if npcId and Haul.npc and EmberRoutesProbeJava.carrierId(Haul.npc)~=npcId then return end
    if not body and Diagnostic.active(controlled) then
        if not npcId or npcId==controlled.binding.id then return Diagnostic.cancel(controlled,reason) end
        return
    end
    if Haul.busy() then
        Haul.batch:cancel(reason or "USER")
        if body then body.stop()
        elseif Haul.npc and Probe.controlledExecution~=true then EmberRoutesProbeJava.stopCarrier(Haul.npc) end
        log("INTERRUPTED items retained in their actual containers")
    end
end

function Haul.cleanup(npc,body)
    if npc and Haul.npc and Haul.npc~=npc then return true end
    if Haul.busy() then return false end
    if Probe.controlledExecution==true and (#Haul.fixtures>0 or Haul.npc) and not body then return false end
    if body and not body.current() then return false end
    for _, fixture in ipairs(Haul.fixtures) do
        local container = fixture.item:getContainer()
        if container and container ~= fixture.root and container ~= fixture.source and container ~= fixture.destination then
            log("CLEANUP_BLOCKED itemID=" .. fixture.id)
            return false
        end
        if not container or not Rules.item(fixture.item, { fixture.root, fixture.source, fixture.destination }, container, fixture) then
            log("CLEANUP_BLOCKED fixture state or identity changed")
            return false
        end
    end
    for _, fixture in ipairs(Haul.fixtures) do
        local container = fixture.item:getContainer()
        if container then container:Remove(fixture.item) end
    end
    Haul.fixtures = {}
    if Haul.batch then Haul.batch.steps = {} Haul.batch.current = nil end
    if body then
        if not body.clear() then return false end
    elseif Haul.npc then ISTimedActionQueue.queues[Haul.npc] = nil end
    Haul.npc, Haul.actor = nil, nil
    log("FIXTURES_CLEANED")
    return true
end

local function reachable(endpoint)
    local npc = Haul.npc
    local square = endpoint.object:getSquare()
    local current = npc:getCurrentSquare()
    return square and current and Rules.near(npc:getX(), npc:getY(), npc:getZ(),
        square:getX() + 0.5, square:getY() + 0.5, square:getZ()) and current:canReachTo(square)
end

local function moveStep(name, endpoint)
    local body,binding=Haul.body,Haul.binding
    local step = { name = name }
    local requested = false
    function step.start()
        if body and not body.current() then return 'FAILED','CONTROL_REQUIRED' end
        if reachable(endpoint) then return end
        local square = luautils.getCorrectSquareForWall(Haul.npc, endpoint.object:getSquare())
        if not square then return "FAILED", "CONTAINER_SQUARE_UNAVAILABLE" end
        local adjacent
        local excluded = {}
        -- Vanilla permits some solidtrans tiles by fences/windows. The probe
        -- movement contract is stricter; exclude these before asking it to move.
        for attempt = 1, 8 do
            local candidate = AdjacentFreeTileFinder.Find(square, Haul.npc, excluded)
            if not candidate then break end
            local cell = getCell()
            local loaded = cell and cell:getGridSquare(candidate:getX(), candidate:getY(), candidate:getZ()) == candidate
            if loaded and candidate:TreatAsSolidFloor() and not candidate:isSolid() and not candidate:isSolidTrans() then
                adjacent = candidate
                break
            end
            excluded[#excluded + 1] = candidate
            log("APPROACH_TILE_REJECTED pos=" .. candidate:getX() .. "," .. candidate:getY() .. "," .. candidate:getZ()
                .. " loaded=" .. tostring(loaded) .. " attempt=" .. attempt)
        end
        if not adjacent then return "FAILED", "NO_WALKABLE_ADJACENT_TILE" end
        log("APPROACH_TARGET pos=" .. adjacent:getX() .. "," .. adjacent:getY() .. "," .. adjacent:getZ())
        local result
        if body then result=Driver.move(binding,Haul.actor,{x=adjacent:getX()+0.5,y=adjacent:getY()+0.5,z=adjacent:getZ()},body)
        elseif EmberRoutesProbeJava.commandFor then
            result=EmberRoutesProbeJava.commandFor(EmberRoutesProbeJava.carrierId(Haul.npc),"move",Haul.actor,
                adjacent:getX()+0.5,adjacent:getY()+0.5,adjacent:getZ())
        else result=EmberRoutesProbeJava.command("move",Haul.actor,
            adjacent:getX()+0.5,adjacent:getY()+0.5,adjacent:getZ()) end
        if not string.find(result, "^MOVE_REQUESTED") then return "FAILED", result end
        requested = true
    end
    function step.poll()
        if not requested then return "PASSED", "already adjacent and reachable" end
        local result = EmberRoutesProbeJava.motionResult(Haul.npc)
        if result == "MOVING" then return "WAIT" end
        if result ~= "REACHED" then return "FAILED", "movement=" .. result end
        return reachable(endpoint) and "PASSED" or "FAILED", "movement=" .. result .. " reach checked"
    end
    function step.cancel()
        if body then body.stop() elseif Haul.npc then EmberRoutesProbeJava.stopCarrier(Haul.npc) end
    end
    return step
end

local function transferStep(name, fixture, source, destination, endpoint)
    local body=Haul.body
    local step = { name = name }
    local action, performed, attempted, stopped, settle
    function step.start()
        if body and not body.current() then return 'FAILED','CONTROL_REQUIRED' end
        if not EmberRoutesProbeJava.carrierActive(Haul.npc) or not reachable(endpoint) then return "FAILED", "NOT_AT_CONTAINER" end
        if fixture.item:getContainer() ~= source or not source:getItems():contains(fixture.item) then return "FAILED", "SOURCE_CHANGED" end
        if not destination:hasRoomFor(Haul.npc, fixture.item) then return "FAILED", "DESTINATION_FULL" end
        if not Haul.npc:getCharacterActions():isEmpty() then return "FAILED", "NATIVE_ACTION_BUSY" end
        action = ISInventoryTransferAction:new(Haul.npc, fixture.item, source, destination, 90)
        action.useProgressBar, action.forceProgressBar = false, false
        local nativeAnim, nativeUpdate = action.startActionAnim, action.update
        local nativePerform, nativeStop, nativeValid = action.perform, action.stop, action.isValid
        action.isValid = function(self)
            local endpointsOK = endpointsValid()
            return (not body or body.current()) and endpointsOK and EmberRoutesProbeJava.carrierActive(self.character) and reachable(endpoint)
                and Rules.item(fixture.item, { fixture.root, fixture.source, fixture.destination }, source, fixture)
                and nativeValid(self)
        end
        action.startActionAnim = function(self)
            if body and not body.current() then return end
            nativeAnim(self)
            -- World-container actions normally select a real player's loot UI.
            -- This instance keeps the native animation/effects, without that selection.
            self.selectedContainer = nil
        end
        action.update = function(self)
            if body and not body.current() then return end
            nativeUpdate(self)
            self.character:faceThisObject(endpoint.object)
        end
        action.perform = function(self)
            if body and (attempted or stopped or not body.current()) then return end
            attempted=true
            -- Revalidate at the actual effect boundary, including revocation after the last Lua tick.
            if not self:isValid() then
                self:stop()
                log("TRANSFER_REFUSED current tag, location or instance state invalid")
                return
            end
            nativePerform(self)
            performed = true
        end
        action.stop = function(self)
            if body and (performed or stopped or not body.retained()) then return end
            stopped=true nativeStop(self)
        end
        if body then assert(body.add(action),'CONTROL_REQUIRED') else ISTimedActionQueue.add(action) end
    end
    function step.poll(time)
        if ISTimedActionQueue.hasAction(action) then return "WAIT" end
        if not performed or stopped then return "FAILED", "native action ended without completion" end
        if not settle then settle = time + 250 end
        if time < settle then return "WAIT" end
        local valid, details = Rules.item(fixture.item, { fixture.root, fixture.source, fixture.destination }, destination, fixture)
        return valid and "PASSED" or "FAILED", details
    end
    function step.cancel()
        if body then body.clear() elseif Haul.npc then ISTimedActionQueue.clear(Haul.npc) end
    end
    return step
end

local function observeStep()
    local step = { name = "VERIFY_RETURNED_NO_REPEAT" }
    local endTime
    function step.start() endTime = now() + 2000 end
    function step.poll(time)
        for _, fixture in ipairs(Haul.fixtures) do
            local valid, details = Rules.item(fixture.item, { fixture.root, fixture.source, fixture.destination }, fixture.source, fixture)
            if not valid then return "FAILED", details end
        end
        if not Haul.npc:getCharacterActions():isEmpty() then return "FAILED", "native queue not empty" end
        return time < endTime and "WAIT" or "PASSED", "three original items returned; queues empty"
    end
    function step.cancel() end
    return step
end

local function start(actor,c)
    if Haul.busy() or Actions.isBusy() then return "BUSY" end
    local valid, reason = endpointsValid()
    if not valid then return reason end
    local npc = c and c.npc or EmberRoutesProbeJava.actionCarrier(actor)
    if not npc then return "CARRIER_UNAVAILABLE" end
    local health = npc:getBodyDamage():getOverallBodyHealth()
    if health < 95 then
        log("START_REFUSED reason=INJURED health=" .. health .. " minimum=95; no fixtures created")
        return "INJURED"
    end
    if not npc:getCharacterActions():isEmpty() then return "NATIVE_ACTION_BUSY" end
    if not Haul.cleanup(npc,c and c.body) or not Actions.cleanupForHaul(npc,c and c.body) then return "CLEANUP_BLOCKED" end
    Haul.npc, Haul.actor = npc, actor
    Haul.body,Haul.binding=c and c.body,c and c.binding
    local source, destination = Haul.endpoints.source, Haul.endpoints.destination
    for _, kind in ipairs({ "Base.Pencil", "Base.Screwdriver", "Base.Spoon" }) do
        local token = newID()
        local item = source.container:AddItem(kind)
        if not item then error("FIXTURE_UNAVAILABLE " .. kind) end
        local fixture = { item = item, source = source.container, destination = destination.container,
            root = npc:getInventory(), id = item:getID(), condition = item:getCondition(), name = item:getName(), token = token }
        Haul.fixtures[#Haul.fixtures + 1] = fixture
        item:getModData().EmberRoutesHaulFixture = token
        item:setCondition(math.max(1, item:getConditionMax() - 1))
        fixture.id, fixture.condition, fixture.name = item:getID(), item:getCondition(), item:getName()
        log("FIXTURE itemID=" .. fixture.id .. " type=" .. kind)
    end
    local steps = {}
    local function route(label, from, to)
        steps[#steps + 1] = moveStep(label .. "_APPROACH_SOURCE", from)
        for i, fixture in ipairs(Haul.fixtures) do
            steps[#steps + 1] = transferStep(label .. "_TAKE_" .. i, fixture, from.container, fixture.root, from)
        end
        steps[#steps + 1] = moveStep(label .. "_APPROACH_DESTINATION", to)
        for i, fixture in ipairs(Haul.fixtures) do
            steps[#steps + 1] = transferStep(label .. "_PUT_" .. i, fixture, fixture.root, to.container, to)
        end
    end
    route("OUTBOUND", source, destination)
    route("RETURN", destination, source)
    steps[#steps + 1] = observeStep()
    Haul.batch = Batch.new(steps, log)
    log("JOB_STARTED cases=" .. #steps .. " source=" .. source.id .. " destination=" .. destination.id)
    return "STARTED"
end

function Haul.report()
    if not Haul.batch then return "NO_REPORT" end
    log("REPORT state=" .. Haul.batch.state .. " cases=" .. #Haul.batch.records .. " reason=" .. tostring(Haul.batch.reason))
    for _, entry in ipairs(Haul.batch.records) do log("REPORT " .. entry.name .. " " .. entry.state .. " " .. entry.detail) end
    for _, fixture in ipairs(Haul.fixtures) do
        log("ITEM_LOCATION itemID=" .. fixture.id .. " root=" .. tostring(fixture.item:getContainer() == fixture.root)
            .. " source=" .. tostring(fixture.item:getContainer() == fixture.source)
            .. " destination=" .. tostring(fixture.item:getContainer() == fixture.destination))
    end
    return Haul.batch.state
end

local function execute(actor, command, object,c)
    if not Probe.ready or not Probe.hasJava() or isClient() or isServer() then return "DRIVER_UNAVAILABLE" end
    if command == "report" then return Haul.report() end
    if not c and Haul.npc and EmberRoutesProbeJava.selectedId
        and EmberRoutesProbeJava.carrierId(Haul.npc)~=EmberRoutesProbeJava.selectedId() then return "FIXTURE_OTHER_NPC" end
    if command == "cancel" then Haul.cancel("USER") return "CANCELLED" end
    if command == "cleanup" then return Haul.cleanup(nil,c and c.body) and "CLEANED" or "CLEANUP_BLOCKED" end
    if command == "run" then
        if not c and Probe.cancelWork then Probe.cancelWork("HAUL_ORDER") end
        if not c and Probe.cancelCompanion then Probe.cancelCompanion("HAUL_ORDER") end
        return start(actor,c)
    end
    if command == "untag" then
        if object then
            local data = object:getModData()
            if data.EmberRoutesProbeContainer then data.EmberRoutesProbeContainer.role = nil end
        end
        return "UNTAGGED"
    end
    if command ~= "source" and command ~= "destination" then return "INVALID_COMMAND" end
    if Haul.busy() then return "BUSY" end
    if not object or not object:getSquare() or not object:getSquare():getObjects():contains(object)
            or not object:getContainer() then return "WORLD_CONTAINER_REQUIRED" end
    if not Rules.near(actor:getX(), actor:getY(), actor:getZ(), object:getSquare():getX() + 0.5,
            object:getSquare():getY() + 0.5, object:getSquare():getZ()) then return "TOO_FAR_TO_TAG" end
    local data = object:getModData()
    data.EmberRoutesProbeContainer = data.EmberRoutesProbeContainer or { id = newID() }
    data.EmberRoutesProbeContainer.role = command
    Haul.endpoints[command] = { object = object, container = object:getContainer(), id = data.EmberRoutesProbeContainer.id }
    log("TAGGED role=" .. command .. " id=" .. Haul.endpoints[command].id)
    return "TAGGED"
end

local function evidence(npc)
    if npc and Haul.npc and Haul.npc~=npc then return {effects='KNOWN',ids={}} end
    local ids={} local known=true
    for _,fixture in ipairs(Haul.fixtures) do
        ids[#ids+1]=fixture.id
        local container=fixture.item:getContainer()
        if not container or not Rules.item(fixture.item,{fixture.root,fixture.source,fixture.destination},container,fixture) then known=false end
    end
    return {effects=known and 'KNOWN' or 'UNKNOWN',ids=ids}
end
Haul.fixtureEvidence=evidence
local function combinedEvidence(c)
    local own=evidence(c.npc)
    local other=Actions.fixtureEvidence(c.npc)
    for _,id in ipairs(other.ids) do own.ids[#own.ids+1]=id end
    if other.effects~='KNOWN' then own.effects='UNKNOWN' end
    return own
end
local function dispatch(actor,command,object)
    if Probe.controlledExecution~=true or (command~='run' and command~='cancel' and command~='cleanup') then
        return execute(actor,command,object)
    end
    if command=='cancel' then
        if controlled and controlled.binding.id==EmberRoutesProbeJava.selectedId() then Diagnostic.cancel(controlled,'USER') end
        return 'STOP_REQUESTED'
    end
    if Diagnostic.active(controlled) then return 'BUSY' end
    local source,destination=Haul.endpoints.source,Haul.endpoints.destination
    local result,c=Diagnostic.submit(actor,'HAUL',{
        assets=true,recovery=command=='cleanup',
        validate=function(binding)
            return not Haul.busy() and not Actions.isBusy() and (not Haul.npc or Haul.npc==binding.handle)
                and (command=='cleanup' or (source==Haul.endpoints.source and destination==Haul.endpoints.destination
                    and endpointsValid() and binding.handle:getBodyDamage():getOverallBodyHealth()>=95))
        end,
        start=function(context)
            if command=='cleanup' and not Actions.cleanupForHaul(context.npc,context.body) then return false,'CLEANUP_BLOCKED' end
            context.result=execute(actor,command,object,context) context.recovered=context.result=='CLEANED'
            return context.result=='STARTED' or context.recovered,context.result
        end,
        tick=function(context) Haul.tick(context) end,
        finished=function() return not Haul.busy() end,
        pause=function(context,reason) Haul.cancel(reason,context.binding.id,context.body) end,
        evidence=combinedEvidence})
    if c then controlled=c end
    return result
end

function Haul.execute(actor, command, object)
    local ok, result = pcall(dispatch, actor, command, object)
    if not ok then Haul.cancel("ERROR") log("ERROR " .. tostring(result)) result = "ERROR" end
    if result == "INJURED" then actor:Say(getText("IGUI_EmberRoutesProbe_HaulInjured"))
    else actor:Say(getText("IGUI_EmberRoutesProbe_HaulResult") .. " " .. tostring(result)) end
    return result
end

function Haul.tick(context)
    if not Haul.busy() then return end
    if Haul.body and (not context or context~=controlled or context.body~=Haul.body or not Haul.body.current()) then return end
    local valid, reason = endpointsValid()
    if valid then
        if not EmberRoutesProbeJava.carrierPresent(Haul.npc) then reason = "CARRIER_UNAVAILABLE"
        elseif Haul.actor:isDead() then reason = "ACTOR_DEAD"
        elseif Haul.npc:getBodyDamage():getOverallBodyHealth() < 95 then reason = "INJURED"
        else reason = nil end
    end
    if reason then
        Haul.cancel(reason)
        if not Haul.actor:isDead() then
            if reason == "INJURED" then Haul.actor:Say(getText("IGUI_EmberRoutesProbe_HaulInjured"))
            else Haul.actor:Say(getText("IGUI_EmberRoutesProbe_HaulResult") .. " CANCELLED " .. reason) end
        end
        return
    end
    local ok, err = pcall(Haul.batch.tick, Haul.batch, now())
    if not ok then Haul.cancel("ERROR") log("ERROR " .. tostring(err)) end
    if not Haul.busy() then
        Haul.actor:Say(getText("IGUI_EmberRoutesProbe_HaulResult") .. " " .. Haul.batch.state .. " " .. #Haul.batch.records
            .. (Haul.batch.reason and " " .. Haul.batch.reason or ""))
    end
end

Probe.tickHaul, Probe.cancelHaul, Probe.cleanupHaul, Probe.haulBusy = Haul.tick, Haul.cancel, Haul.cleanup, Haul.busy
Probe.resetHaul = function()
    if not Haul.cleanup() then return false end
    Haul.endpoints = {}
    return true
end
return Haul
