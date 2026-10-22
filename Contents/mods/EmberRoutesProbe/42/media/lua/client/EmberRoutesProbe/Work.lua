-- Selection is UI state. Execution contexts are keyed by stable NPC identity.
local Probe=require "EmberRoutesProbe/Boot"
local Driver=require "EmberRoutesProbe/Driver"
local Factory=require "EmberRoutesProbe/WorkAgent"
local Schedule=require "EmberRoutesProbe/LaborSchedule"
local Store=require "EmberRoutesProbe/LaborStore"
local Signals=require "EmberRoutesProbe/LaborSignals"
local Work={}
local agents,handles,schedule,suspended={},{},Schedule.new(),{}
local executors={}
local function retained(id)
    for _,executor in pairs(executors) do if executor.retains(id) then return true end end
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
function Work.record(id) return Store.record(selected(nil,id)) end
function Work.lastCompleted(id) return Store.recent(selected(nil,id)) end
function Work.execute(actor,command,object,container)
    local worker,id=agent(actor)
    if (command=="run" or command=="resume" or command=="clear") and (nativeExecutor(id) or retained(id)) then return "OTHER_TASK_RETAINED" end
    if command=="pause" then Work.pause("USER",id) end
    if command=="run" or command=="resume" or command=="pause" or command=="clear" then suspended[id]=true end
    local result=worker.execute(actor,command,object,container)
    Signals.changed(id)
    if worker.busy() then schedule:add(id) else schedule:remove(id) end
    return result
end
function Work.busy(id)
    id=selected(nil,id) local worker=agents[id]
    return nativeExecutor(id)~=nil or (worker and worker.busy() or false)
end
function Work.pause(reason,id)
    local key=selected(nil,id) local worker=agents[key]
    if reason=="USER" or reason=="STOP" or reason=="MOVE" or reason=="REMOVE" or reason=="COMPANION_ORDER"
        or reason=="ACTION_ORDER" or reason=="HAUL_ORDER" or reason=="PERSISTENCE_SAMPLE" then suspended[key]=true end
    if worker then worker.pause(reason) schedule:remove(key) end
    for _,executor in pairs(executors) do executor.pause(reason,key) end
    schedule:remove(key)
    Signals.changed(key)
end
function Work.allowAutomation(id) suspended[id]=nil end
function Work.automationAllowed(id) return not suspended[id] and not retained(id) and not nativeExecutor(id) end
function Work.assign(actor,id,intent)
    if retained(id) or nativeExecutor(id) then return "OTHER_TASK_RETAINED" end
    if suspended[id] then return "MANUAL_OVERRIDE" end
    local worker=agent(actor,id)
    local ok,result=pcall(worker.assign,actor,intent)
    if not ok then worker.pause("ERROR") return "ERROR" end
    if worker.busy() then schedule:add(id) end
    return result
end
function Work.resumeFor(actor,id)
    if retained(id) or nativeExecutor(id) then return "OTHER_TASK_RETAINED" end
    local worker=agent(actor,id)
    local ok,result=pcall(worker.resume,actor)
    if not ok then worker.pause("ERROR") return "ERROR" end
    if worker.busy() then schedule:add(id) end
    return result
end
function Work.discardAutomatic(actor,id)
    local record=Store.record(id)
    if not record or record.producer~="LOGISTICS" or Work.busy(id) or Work.hasCargo(actor,id) then return false end
    Store.clear(id) return true
end
function Work.pauseAll(reason)
    for id,worker in pairs(agents) do worker.pause(reason) schedule:remove(id) end
    for _,executor in pairs(executors) do executor.pauseAll(reason) end
end
function Work.hasCargo(actor,id)
    local worker,key=agent(actor,id) return retained(key) or worker.hasCargo(actor)
end
function Work.prepareRemoval(actor,id)
    local worker,key=agent(actor,id) if retained(key) then return false end return worker.prepareRemoval(actor)
end
function Work.tick()
    schedule:step(4,function(id)
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
Probe.tickWork,Probe.cancelWork,Probe.resetWork,Probe.workHasCargo=Work.tick,Work.pause,Work.reset,Work.hasCargo
Probe.pauseAllWork=Work.pauseAll
return Work
