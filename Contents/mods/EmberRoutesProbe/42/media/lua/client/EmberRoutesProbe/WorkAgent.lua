local Probe = require "EmberRoutesProbe/Boot"
local Log = require "EmberRoutesProbe/Log"
local Registry = require "EmberRoutesProbe/ContainerRegistry"
local Transfer = require "EmberRoutesProbe/WorkTransfer"
local Actions = require "EmberRoutesProbe/Actions"
local Haul = require "EmberRoutesProbe/Haul"
local Policy = require "EmberRoutesProbe/InventoryPolicy"
local View = require "EmberRoutesProbe/InventoryView"
local Store=require "EmberRoutesProbe/LaborStore"
local Driver=require "EmberRoutesProbe/Driver"
local Producers=require "EmberRoutesProbe/LaborProducers"
local Batch=require "EmberRoutesProbe/WorkBatch"
local Factory={}
function Factory.new(npcId)
local Work = { context = nil, step = nil, nextTick = 0 }
local function log(text) Log.write("WORK", text) end
local function message(result)
    local code = string.match(tostring(result), "^(%u[%u_]*)") or "ERROR"
    local key = "IGUI_EmberRoutesProbe_WorkCode_" .. code
    local translated = getText(key)
    return translated == key and code or translated
end
local function say(actor, result, reason)
    local text = message(result)
    local amount = string.match(tostring(result), "^%u[%u_]* (%d+/?%d*)")
    if amount then text = text .. " " .. amount end
    if reason and reason ~= "" then text = text .. " — " .. message(reason) end
    actor:Say(getText("IGUI_EmberRoutesProbe_WorkResult") .. " " .. text)
end

function Work.eligible(item)
    return Producers.eligible(item)
end

function Work.locate(id, source, root, destination)
    local index, reason = View.index({source, root, destination})
    if not index then return nil, nil, reason end
    return View.find(index, id)
end

local function job() return Store.record(npcId) end
local function carrier(actor)
    local binding=Driver.bindId(actor,npcId) return binding and binding.handle
end
local Signals=require "EmberRoutesProbe/LaborSignals"
local function setState(record, state, reason)
    record.state, record.reason = state, reason or ""
    Signals.changed(record.npcId)
    log("STATE task=" .. record.id .. " npc=" .. record.npcId .. " state=" .. state .. " reason=" .. record.reason
        .. " delivered=" .. (record.delivered or 0) .. "/" .. #record.items)
end

function Work.busy() return Work.context ~= nil end

function Work.pause(reason)
    local context = Work.context
    if not context then return end
    -- Invalidate effect closures before clearing native queues.
    Work.context, Work.step = nil, nil
    local token=Store.pause(context.job)
    setState(context.job, "PAUSED", reason or "USER")
    ISTimedActionQueue.clear(context.npc)
    ISTimedActionQueue.queues[context.npc]=nil
    EmberRoutesProbeJava.stopCarrier(context.npc)
    local ok,held=pcall(Work.hasCargo,context.actor)
    if ok and not held then Store.releaseCapacity(token) end
    if not context.job.producer and context.actor and not context.actor:isDead() then
        say(context.actor, "PAUSED", context.job.reason)
    end
end

local function endpoints(record)
    local source, reason = Registry.resolve(record.source, "take", record.scopeId)
    if not source then return nil, nil, reason end
    local destination
    destination, reason = Registry.resolve(record.destination, "put", record.scopeId)
    if not destination then return nil, nil, reason end
    if source.container == destination.container then return nil, nil, "SAME_CONTAINER" end
    return source, destination
end

local function validate(context)
    if Work.context ~= context or isClient() or isServer() or not Probe.ready then return false, "DRIVER_UNAVAILABLE" end
    if not Store.valid(context.job,context.generation,context.token) then return false,"STALE_TASK" end
    if context.actor:isDead() or not EmberRoutesProbeJava.carrierPresent(context.npc)
            or EmberRoutesProbeJava.carrierId(context.npc) ~= context.job.npcId then return false, "CARRIER_UNAVAILABLE" end
    if context.npc:getBodyDamage():getOverallBodyHealth() < 95 then return false, "INJURED" end
    local source,reason=Registry.revalidate(context.source,"take",context.job.scopeId)
    if not source then return false,reason end
    local destination
    destination,reason=Registry.revalidate(context.destination,"put",context.job.scopeId)
    if not destination then return false,reason end
    return Producers.check(context)
end

local function launch(actor, record)
    if record.format ~= 1 or record.kind ~= "EXPLICIT_TRANSFER" or record.executor ~= "ENTITY"
            or record.scopeId ~= "local-world" or type(record.items) ~= "table" or #record.items > 30 then
        return "TASK_FORMAT_UNSUPPORTED"
    end
    local npc = carrier(actor)
    if not npc then
        if not EmberRoutesProbeJava.carrierFor and EmberRoutesProbeJava.controlledCarrier(actor) then return "NPC_ID_MISMATCH" end
        return "CARRIER_UNAVAILABLE"
    end
    if EmberRoutesProbeJava.carrierId(npc) ~= record.npcId then return "NPC_ID_MISMATCH" end
    local source, destination, reason = endpoints(record)
    if not source or not destination then return reason end
    if npc:getBodyDamage():getOverallBodyHealth() < 95 then return "INJURED" end
    -- Check every ID before accepting intent. Re-check again at each effect.
    local index,indexReason
    if not record.producer then
        index,indexReason=View.index({source.container,npc:getInventory(),destination.container})
        if not index then return indexReason end
    end
    local seen, missing, held = {}, nil, false
    for _, id in ipairs(record.items) do
        if seen[id] then return "TASK_ITEM_ID_DUPLICATED" end
        seen[id] = true
        if type(id)~="number" or id~=id or math.abs(id)==math.huge then return "TASK_ITEM_INVALID" end
        local item, location, why
        if index then item,location,why=View.find(index,id) end
        if index and not item then
            if why ~= "ITEM_MISSING" then return why .. " item=" .. id end
            missing = why .. " item=" .. id
        elseif location == 2 then held = true end
    end
    -- Let already held cargo reach safety before reporting a missing later item.
    if missing and not held then return missing end
    local preview={actor=actor,npc=npc,job=record,source=source,destination=destination}
    local allowed,producerReason=Producers.check(preview)
    if not allowed then return producerReason end
    Probe.cancelAll("WORK_ORDER",npcId)
    if not Haul.cleanup(npc) or not Actions.cleanupForHaul(npc) then return "CLEANUP_BLOCKED" end
    if not npc:getCharacterActions():isEmpty() then return "NATIVE_ACTION_BUSY" end
    local token,claimReason=Store.claim(record)
    if not token then return claimReason end
    EmberRoutesProbeJava.stopCarrier(npc)
    local context = { actor=actor, npc=npc, job=record, source=source, destination=destination,
        generation=record.generation,token=token }
    context.valid = function() return validate(context) end
    context.eligible = function(item) return Work.eligible(item) and Registry.accepts(context.destination,item) end
    context.transferred=function(item,_,to)
        if Store.valid(record,context.generation,token) and to==destination.container
            and item:getContainer()==to and to:getItems():contains(item) then Store.releaseCapacity(token,item:getID()) end
    end
    Work.context, Work.step, Work.nextTick = context, nil, 0
    setState(record, "RUNNING", "EXPLICIT_START")
    return "STARTED " .. #record.items
end

function Work.assign(actor,intent)
    if Work.busy() then return "BUSY" end
    local previous=job()
    if previous and previous.state~="DONE" then return "TASK_EXISTS_RESUME_OR_CLEAR" end
    if previous and Work.hasCargo(actor) then return "CARGO_RETAINED_RESUME_FIRST" end
    if type(intent)~="table" or not Producers.handlers[intent.producer] or type(intent.items)~="table"
        or #intent.items<1 or #intent.items>30 or type(intent.source)~="string" or type(intent.destination)~="string" then return "TASK_FORMAT_UNSUPPORTED" end
    local ids={} for _,id in ipairs(intent.items) do ids[#ids+1]=id end
    if intent.weights then
        if type(intent.weights)~="table" then return "TASK_FORMAT_UNSUPPORTED" end
        for _,id in ipairs(ids) do if type(intent.weights[id])~="number" then return "TASK_FORMAT_UNSUPPORTED" end end
    end
    local record={id=Registry.id(),npcId=npcId,source=intent.source,destination=intent.destination,items=ids,phase="COLLECT",
        state="PAUSED",reason="CREATED",delivered=0,format=1,kind="EXPLICIT_TRANSFER",scopeId="local-world",executor="ENTITY",
        producer=intent.producer,settlementId=intent.settlementId,sourceMode=intent.sourceMode}
    local result=launch(actor,record)
    if Work.busy() then
        Store.publish(record)
        if intent.weights then
            local ok,reason=Store.capacityBatch(Work.context.token,record.destination,intent.weights,
                Work.context.destination.container:getFreeCapacity(Work.context.npc))
            if not ok then Work.pause(reason) return reason end
        end
    end
    return result
end

function Work.resume(actor)
    if Work.busy() then return "BUSY" end
    local record=job() if not record then return "NO_TASK" end
    if record.state=="DONE" then return "DONE" end
    return launch(actor,record)
end

function Work.hasCargo(actor)
    local record = job()
    if not record then return false end
    local npc = carrier(actor)
    if not npc or EmberRoutesProbeJava.carrierId(npc) ~= record.npcId then return true end
    local ids, inspected = {}, 0
    for _, id in ipairs(record.items) do ids[id] = true end
    local function scan(container, depth)
        if depth > 16 then return true end -- Fail closed before destructive commands.
        local items = container:getItems()
        for i = 0, items:size()-1 do
            inspected = inspected+1
            if inspected > 4096 then return true end
            local item = items:get(i)
            if ids[item:getID()] then return true end
            if item.getInventory and item:getInventory() and scan(item:getInventory(), depth+1) then return true end
        end
        return false
    end
    return scan(npc:getInventory(), 0)
end

function Work.prepareRemoval(actor)
    if not job() then return true end
    if Work.hasCargo(actor) then return false end
    Work.pause("REMOVE")
    log("TASK_CANCELLED npc removal explicitly requested; no task cargo on NPC")
    Store.clear(npcId)
    return true
end

local function create(actor)
    if Work.busy() then return "BUSY" end
    local data = Store.route(npcId)
    local previous = job()
    if previous then
        if previous.state ~= "DONE" then return "TASK_EXISTS_RESUME_OR_CLEAR" end
        if Work.hasCargo(actor) then return "CARGO_RETAINED_RESUME_FIRST" end
    end
    local source, reason = Registry.resolve(data.source, "take", "local-world")
    if not source then return reason end
    local destination
    destination, reason = Registry.resolve(data.destination, "put", "local-world")
    if not destination then return reason end
    if source.container == destination.container then return "SAME_CONTAINER" end
    local npc = carrier(actor)
    if not npc then return "CARRIER_UNAVAILABLE" end
    local reserved=0
    local items, planReason = Policy.planExplicit(source.container, function(item)
        if not Work.eligible(item) or not Registry.accepts(destination,item) then return false end
        if Store.owner(item:getID()) then reserved=reserved+1 return false end
        return true
    end)
    if not items then return planReason=="NO_ELIGIBLE_ITEMS" and reserved>0 and "ITEM_RESERVED" or planReason end
    local record = { id=Registry.id(), npcId=EmberRoutesProbeJava.carrierId(npc), source=data.source,
        destination=data.destination, items=items, state="PAUSED", reason="CREATED", delivered=0,
        format=1, kind="EXPLICIT_TRANSFER", scopeId="local-world", executor="ENTITY" }
    local result = launch(actor, record)
    -- Launch validates ownership, cleanup and queue availability synchronously.
    -- Publish only after acceptance; no action ticks run inside this intent call.
    if Work.busy() then
        Store.publish(record)
        if previous then log("REPLACED_COMPLETED previous=" .. previous.id .. " next=" .. record.id) end
    elseif not previous then
        local token=Store.claim(record)
        if token then Store.publish(record) setState(record,"PAUSED",result) end
    end
    return result
end

local function report()
    local record = job()
    local data = Store.route(npcId)
    log("ROUTE source=" .. tostring(data.source) .. " destination=" .. tostring(data.destination))
    if not record then return "NO_TASK" end
    log("REPORT task=" .. record.id .. " npc=" .. record.npcId .. " source=" .. record.source
        .. " destination=" .. record.destination .. " state=" .. record.state .. " reason=" .. record.reason)
    local npc = carrier(getSpecificPlayer(0))
    local source, destination = endpoints(record)
    local index, indexReason
    if npc and source and destination then
        index, indexReason = View.index({source.container, npc:getInventory(), destination.container})
    end
    for _, id in ipairs(record.items) do
        local location = "UNAVAILABLE"
        if index then
            local _, position, reason = View.find(index, id)
            location = position and ({"SOURCE", "NPC", "DESTINATION"})[position] or reason
        elseif indexReason then location = indexReason
        end
        log("ITEM task=" .. record.id .. " item=" .. id .. " location=" .. location)
    end
    return record.state .. " " .. record.delivered .. "/" .. #record.items .. " " .. record.reason
end

local function execute(actor, command, object, container)
    if not Probe.ready or not Probe.hasJava() or isClient() or isServer() then return "DRIVER_UNAVAILABLE" end
    if command == "report" then return report() end
    if command == "pause" then Work.pause("USER") return "PAUSED" end
    if command == "run" then return create(actor) end
    if command == "resume" then
        if Work.busy() then return "BUSY" end
        local record = job()
        if not record then return "NO_TASK" end
        if record.state == "DONE" then return "DONE" end
        return launch(actor, record)
    end
    if command == "clear" then
        Work.pause("CLEAR")
        if Work.hasCargo(actor) then return "CARGO_RETAINED_RESUME_FIRST" end
        local record = job()
        if record and not carrier(actor) then return "CARRIER_REQUIRED_TO_CLEAR" end
        Store.clear(npcId)
        return "TASK_CLEARED"
    end
    if command == "source" or command == "destination" then
        local result=Registry.select(actor,object,command,container)
        if string.find(result,"^SELECTED") then Store.route(npcId)[command]=Registry.data()[command] end
        return result
    end
    local result = Registry.tag(actor, object, command)
    if Work.busy() then
        local valid, reason = validate(Work.context)
        if not valid then Work.pause(reason) end
    end
    return result
end

function Work.execute(actor, command, object, container)
    local ok, result = pcall(execute, actor, command, object, container)
    if not ok then Work.pause("ERROR") log("ERROR " .. tostring(result)) result = "ERROR" end
    log("INTENT command=" .. command .. " result=" .. tostring(result))
    say(actor, result)
    return result
end

local function nextStep(context)
    local root, record = context.npc:getInventory(), context.job
    local previousPhase=record.phase
    local selected, item, where, delivered, problem = nil, nil, nil, 0, nil
    if not context.scan then context.scan=View.scan({context.source.container,root,context.destination.container}) end
    local index,indexReason=context.scan:step(32)
    if not index then
        if indexReason=="INVENTORY_CHANGED" then context.scan=nil return nil,"SCAN_PENDING" end
        return nil,indexReason
    end
    context.scan=nil
    if record.producer then
        local selection,count,reason=Batch.choose(context,index)
        delivered=count
        if selection then selected,item,where=selection.id,selection.item,selection.where else problem=reason end
    else
    for _, id in ipairs(record.items) do
        local candidate, location, reason = View.find(index, id)
        if not candidate then
            if reason ~= "ITEM_MISSING" then return nil, reason .. " item=" .. id end
            problem = reason .. " item=" .. id
        elseif location == 3 then delivered = delivered+1
        elseif not selected or location == 2 then
            selected, item, where = id, candidate, location
        end
    end
    end
    if record.delivered~=delivered or record.phase~=previousPhase then
        record.delivered=delivered Signals.changed(record.npcId)
    end
    if record.producer and not selected then return nil,problem end
    if problem and where ~= 2 then return nil, problem end
    if not selected then return nil, "DONE" end
    if not item then return nil,"ITEM_MISSING" end
    if not Work.eligible(item) then return nil, "ITEM_PROTECTED item=" .. selected end
    if not Registry.accepts(context.destination,item) then return nil,"FILTER_REJECTED item=" .. selected end
    if not Producers.transfer(context,item,where==1 and context.source.container or root,
        where==1 and root or context.destination.container) then return nil,"PRODUCER_RULE_CHANGED" end
    if not context.destination.container:hasRoomFor(context.npc, item) then return nil, "DESTINATION_FULL" end
    local reserved,reserveReason=Store.capacity(context.token,selected,record.destination,
        item:getUnequippedWeight(),context.destination.container:getFreeCapacity(context.npc))
    if not reserved then return nil,reserveReason end
    local endpoint = where == 2 and context.destination or context.source
    if not Transfer.reachable(context.npc, endpoint) then return Transfer.move(context, endpoint) end
    if where == 1 and not root:hasRoomFor(context.npc, item) then return nil, "NPC_INVENTORY_FULL" end
    log("TRANSFER task=" .. record.id .. " item=" .. selected .. " phase=" .. (where == 1 and "TAKE" or "DELIVER"))
    return Transfer.item(context, item, where == 1 and context.source.container or root,
        where == 1 and root or context.destination.container, endpoint)
end

local function tick()
    local context = Work.context
    if not context then return end
    local time = getTimestampMs()
    if time < Work.nextTick then return end
    Work.nextTick = time+100
    local valid, reason = validate(context)
    if not valid then Work.pause(reason) return end
    if not Work.step then
        local step, why = nextStep(context)
        if not step then
            if why == "DONE" then
                Work.context = nil
                setState(context.job, "DONE", "ALL_ORIGINAL_IDS_AT_DESTINATION")
                Store.finish(context.job)
                if not context.job.producer then say(context.actor, "DONE " .. #context.job.items) end
            elseif why=="CAPACITY_RESERVED" then
                if context.job.reason~=why then context.job.reason=why log("WAIT task="..context.job.id.." reason="..why) end
            elseif why~="SCAN_PENDING" then Work.pause(why) end
            return
        end
        if context.job.reason=="CAPACITY_RESERVED" then context.job.reason="EXECUTING" end
        Work.step, Work.startedAt = step, time
        local state, detail = step.start()
        if state == "FAILED" then Work.pause(detail) return end
    end
    if time-Work.startedAt >= (Work.step.timeout or 60000) then Work.pause("STEP_TIMEOUT") return end
    local state, detail = Work.step.poll()
    if state == "PASSED" then Work.step = nil
    elseif state == "FAILED" then Work.pause(detail) end
end

function Work.tick()
    if not Work.busy() then return end
    local ok, err = pcall(tick)
    if not ok then Work.pause("ERROR") log("ERROR " .. tostring(err)) end
end

function Work.reset()
    Work.pause("WORLD_RESET")
    Work.context, Work.step, Work.nextTick = nil, nil, 0
end

return Work
end
return Factory
