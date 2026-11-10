-- Selection is UI state. Execution contexts are keyed by stable NPC identity.
local Probe=require "EmberRoutesProbe/Kernel/Boot"
local Driver=require "EmberRoutesProbe/Runtime/Driver"
local Factory=require "EmberRoutesProbe/Work/WorkAgent"
local Schedule=require "EmberRoutesProbe/Work/LaborSchedule"
local Store=require "EmberRoutesProbe/Work/LaborStore"
local Signals=require "EmberRoutesProbe/Work/LaborSignals"
local Runtime=require 'EmberRoutesProbe/Runtime/TaskRuntime'
local TaskResume=require 'EmberRoutesProbe/Runtime/TaskResume'
local Reasons=TaskResume.Reasons
local Work={}
local agents,handles,schedule,suspended={},{},Schedule.new(),{}
local executors={}
local function retained(id,exceptKind)
    for kind,executor in pairs(executors) do if kind~=exceptKind and executor.retains(id) then return true end end
    return false
end
local function nativeExecutor(id)
    for _,executor in pairs(executors) do if executor.busy(id) then return executor end end
end
-- Optional native-action probes share this scheduler and all worker lifecycle gates.
function Work.registerExecutor(kind,executor)
    assert(not executors[kind],"EXECUTOR_ALREADY_REGISTERED") executors[kind]=executor
end
function Work.wake(id) schedule:add(id) end
local function selected(actor,id)
    if id then return id end
    if EmberRoutesProbeJava.selectedId then return EmberRoutesProbeJava.selectedId() end
    local binding=Driver.bind(actor or getSpecificPlayer(0))
    if binding then
        local known=handles[binding.handle]
        if known and known~=binding.id then return known end
        handles[binding.handle]=binding.id
    end
    return Driver.selected(actor or getSpecificPlayer(0))
end
local function agent(actor,id)
    id=selected(actor,id)
    if not agents[id] then agents[id]=Factory.new(id) end
    return agents[id],id
end
-- One guard shape for the three care invalidations below (C2/C3/C4). It only
-- converges how the Probe presence check is written; Work.execute and
-- Work.taskCommand keep their own preconditions and call order.
local function invalidateCare(id,reason)
    if Probe.invalidateCare then Probe.invalidateCare(id,reason) end
end
function Work.record(id) return Store.record(selected(nil,id)) end
function Work.lastCompleted(id) return Store.recent(selected(nil,id)) end
function Work.stopAdapter(id,controller,ticket)
    local worker=agents[id]
    if not worker then return nil,'NO_ACTIVE_TRANSFER' end
    return worker.stopAdapter(controller,ticket)
end
function Work.execute(actor,command,object,container)
    local worker,id=agent(actor)
    local runtime=Runtime.current()
    if command=='clear' and runtime and runtime:owns(id) then
        worker.pause('CLEAR') return 'PAUSE_BEFORE_CLEAR'
    end
    if (command=="run" or command=="resume" or command=="clear") and (nativeExecutor(id) or retained(id)) then return "OTHER_TASK_RETAINED" end
    if command=="pause" then Work.pause(Reasons.USER,id) end
    if command=="run" or command=="resume" or command=="pause" or command=="clear" then suspended[id]=true end
    local result=worker.execute(actor,command,object,container)
    if (command=='run' or command=='resume' or command=='clear')
        and (result=='QUEUED' or result=='STARTED' or result=='TASK_CLEARED') then
        invalidateCare(id,Reasons.WORK_COMMAND)
    end
    Signals.changed(id)
    if worker.busy() then schedule:add(id) else schedule:remove(id) end
    return result
end
function Work.executing(id)
    id=selected(nil,id) local worker=agents[id]
    return nativeExecutor(id)~=nil or (worker and worker.busy() or false)
end
function Work.busy(id)
    id=selected(nil,id)
    local runtime=Runtime.current()
    return Work.executing(id) or (runtime and runtime:owns(id) or false)
end
function Work.pause(reason,id)
    local key=selected(nil,id) local worker=agents[key]
    if reason==Reasons.USER or reason==Reasons.STOP or reason==Reasons.MOVE or reason==Reasons.REMOVE or reason==Reasons.COMPANION_ORDER
        or reason==Reasons.ACTION_ORDER or reason==Reasons.HAUL_ORDER or reason==Reasons.PERSISTENCE_SAMPLE then
        suspended[key]=true
        invalidateCare(key,reason)
        if Probe.cancelReservation then Probe.cancelReservation(key,reason) end
    end
    if worker then worker.pause(reason) schedule:remove(key) end
    for _,executor in pairs(executors) do executor.pause(reason,key) end
    schedule:remove(key)
    Signals.changed(key)
end
function Work.allowAutomation(id) suspended[id]=nil end
function Work.automationAllowed(id)
    local allowed=not require('EmberRoutesProbe/Activity/ActivityAttendance').blocksOrdinary(id)
    -- Let the original logistics owner resume its retained finite task. The
    -- selector sees that record and never treats this as permission for a new one.
    if not allowed then local current=Work.record(id) allowed=current~=nil and current.state~='DONE' end
    return allowed
        and not (Probe.careBlocksWork and Probe.careBlocksWork(id)) and not suspended[id]
        and not retained(id) and not nativeExecutor(id) and not Work.busy(id)
end
function Work.assign(actor,id,intent)
    if retained(id) or nativeExecutor(id) then return "OTHER_TASK_RETAINED" end
    if suspended[id] then return "MANUAL_OVERRIDE" end
    local worker=agent(actor,id)
    local ok,result=pcall(worker.assign,actor,intent)
    if not ok then worker.pause("ERROR") return "ERROR" end
    if worker.busy() then schedule:add(id) end
    return result
end
-- Recovery deliberately does NOT check suspended[id] or automationAllowed,
-- unlike Work.assign (which returns 'MANUAL_OVERRIDE' for suspended).
-- Recovery paths depend on a paused NPC still being resumable:
--   MembershipRuntime.recover resumes any PAUSED record (no manualPaused /
--     suspended check), including a user-paused one;
--   DeliveryService.advance resumes system-paused deliveries (e.g. a
--     HAUL_ORDER pause sets suspended but not manualPaused, which its
--     `not r.manualPaused` gate does not exclude);
--   TaskPersistence.candidate (TRANSFER) resumes a DELIVERY record on
--     load with no manualPaused check;
--   HaulingProvider.blocksDecision resumes a retained LOGISTICS haul
--     (gated on manualPaused only).
-- Whether automationAllowed belongs here is open: callers check it today
-- (LogisticsService.advance, PublicWork.eligible); adding it here would
-- change every recovery path at once, so it stays a caller-side check.
function Work.resumeFor(actor,id)
    if retained(id) or nativeExecutor(id) then return "OTHER_TASK_RETAINED" end
    local worker=agent(actor,id)
    local ok,result=pcall(worker.resume,actor,true)
    if not ok then worker.pause("ERROR") return "ERROR" end
    if worker.busy() then schedule:add(id) end
    return result
end
-- Explicit stable Job identity; never falls back to the player's selected NPC.
function Work.taskCommand(actor,id,jobId,generation,command)
    local r=Store.record(id)
    if not r or r.id~=jobId or r.generation~=generation then return 'TASK_CHANGED' end
    if r.state=='DONE' then return 'DONE' end
    if command=='stop' then Work.pause('USER',id) return 'STOP_REQUESTED' end
    if command~='resume' then return 'INVALID_COMMAND' end
    if Probe.isPublicDispatch() and r.producer=='LOGISTICS' then
        local entry,why=require('EmberRoutesProbe/Settlement/SettlementLedger').view(actor,r.settlementId)
        if not entry then return why end
        if not require('EmberRoutesProbe/Logistics/LogisticsService').preparePublic(actor,entry,true) then return 'LOGISTICS_STOPPED' end
    end
    if retained(id) or nativeExecutor(id) then return 'OTHER_TASK_RETAINED' end
    local worker=agent(actor,id)
    local ok,result=pcall(worker.resume,actor,false)
    if not ok then worker.pause('ERROR') return 'ERROR' end
    if (result=='QUEUED' or result=='STARTED') then invalidateCare(id,Reasons.WORK_COMMAND) end
    if worker.busy() then schedule:add(id) end
    Signals.changed(id)
    return result
end
function Work.discardAutomatic(actor,id)
    local record=Store.record(id)
    if not record or record.producer~="LOGISTICS" or Work.busy(id) or Work.hasCargo(actor,id) then return false end
    return Store.clear(id)
end
-- No invalidateCare here: a world reset drops careCommandEpochs with the
-- Registry.data() root-table switch, and Service.reset clears the rows.
-- Per-NPC invalidation is not the reset mechanism.
function Work.pauseAll(reason)
    for id,worker in pairs(agents) do worker.pause(reason) schedule:remove(id) end
    for _,executor in pairs(executors) do executor.pauseAll(reason) end
end
function Work.hasCargo(actor,id,exceptKind)
    local worker,key=agent(actor,id) return retained(key,exceptKind) or worker.hasCargo(actor)
end
function Work.prepareRemoval(actor,id)
    local worker,key=agent(actor,id)
    if Probe.careRemovalReady and not Probe.careRemovalReady(key) then return false end
    local runtime=Runtime.current()
    if runtime and runtime:owns(key) then Work.pause('REMOVE',key) return false end
    if retained(key) then return false end return worker.prepareRemoval(actor)
end
function Work.tick()
    schedule:step(4,function(id)
        local runtime=Runtime.current()
        if runtime and runtime:owns(id) then return end
        local executor=nativeExecutor(id)
        local worker=agents[id]
        if executor then executor.tick(id) elseif worker then worker.tick() end
        if not Work.busy(id) then schedule:remove(id) end
    end)
end
function Work.reset()
    Work.pauseAll("WORLD_RESET")
    for _,executor in pairs(executors) do executor.reset() end
    agents,handles,schedule,suspended={},{},Schedule.new(),{}
end
Probe.tickWork=Work.tick
if Probe.registerCancel then Probe.registerCancel("Work", Work.pause) end
if Probe.registerReset then Probe.registerReset("Work", Work.reset) end
Probe.pauseAllWork=Work.pauseAll
return Work
