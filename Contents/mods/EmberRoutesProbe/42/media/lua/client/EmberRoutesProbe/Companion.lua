local Probe=require "EmberRoutesProbe/Boot"
local Driver=require "EmberRoutesProbe/Driver"
local Factory=require "EmberRoutesProbe/CompanionAgent"
local Schedule=require "EmberRoutesProbe/LaborSchedule"
local Companion={}
local agents,schedule={},Schedule.new()
local function selected(id)
    return id or Driver.selected(getSpecificPlayer(0))
end
local function agent(id)
    id=selected(id)
    if not agents[id] then agents[id]=Factory.new() end
    return agents[id],id
end
local function enroll(worker,id)
    if worker.binding then schedule:add(id) else schedule:remove(id) end
end
function Companion.execute(actor,command)
    local binding=Driver.bind(actor)
    local worker,id=agent(binding and binding.id)
    worker.execute(actor,command) enroll(worker,id)
end
function Companion.cancel(reason,id)
    id=selected(id) local worker=agents[id]
    if worker then worker.cancel(reason) schedule:remove(id) end
end
function Companion.cancelAll(reason)
    for id,worker in pairs(agents) do worker.cancel(reason) schedule:remove(id) end
end
function Companion.exportState(id)
    local worker=agent(id) return worker.exportState()
end
function Companion.restoreState(actor,data)
    local worker,id=agent(data.id)
    local result=worker.restoreState(actor,data) enroll(worker,id) return result
end
function Companion.report() local worker=agent() return worker.report() end
function Companion.tick()
    schedule:step(4,function(id)
        local worker=agents[id] worker.tick() enroll(worker,id)
    end)
end
function Companion.reset()
    Companion.cancelAll("WORLD_RESET") agents,schedule={},Schedule.new()
end
-- Read-only compatibility for existing diagnostic consumers.
setmetatable(Companion,{__index=function(_,key) local worker=agent() return worker[key] end})
Probe.cancelCompanion,Probe.tickCompanion,Probe.resetCompanion=Companion.cancel,Companion.tick,Companion.reset
Probe.cancelEveryCompanion=Companion.cancelAll
return Companion
