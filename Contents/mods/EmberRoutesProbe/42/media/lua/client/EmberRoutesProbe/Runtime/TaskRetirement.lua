-- Retire settled facts only after normal executors have returned from callbacks.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Runtime=require 'EmberRoutesProbe/Runtime/TaskRuntime'
local Probe=require 'EmberRoutesProbe/Kernel/Boot'
local Signals=require 'EmberRoutesProbe/Work/LaborSignals'
local Config=require 'EmberRoutesProbe/Kernel/TickConfig'
local Log=require 'EmberRoutesProbe/Kernel/Log'
local Service={}
local world,nextTick,nextSweep,fault,dirty=nil,0,0,nil,true
local Public,Jobs
local function retire()
    Public=Public or require 'EmberRoutesProbe/Work/PublicWork'
    Jobs=Jobs or require 'EmberRoutesProbe/Work/BusinessJobs'
    Public.retireSettled(8)
    if Jobs.retireSettled(8)>0 then Signals.changed() end
    require('EmberRoutesProbe/Cooking/CookingProvider').retire(8)
end
if Signals.watch then Signals.watch(function() dirty=true end) end
function Service.tick()
    local now=getTimestampMs() if now<nextTick then return end
    local root=Registry.data()
    if root~=world then world,nextSweep,fault,dirty=root,0,nil,true end
    if not dirty and now<nextSweep then return end
    local runtime=Runtime.current()
    if not Probe.ready or not Probe.runtimeReady or not runtime or not runtime:accepting()
        or root.executionSave and root.executionSave.state=='BLOCKED' then return end
    nextTick=now+Config.retirementMs nextSweep=now+Config.retirementFallbackMs dirty=false
    local ok,reason=pcall(retire)
    if not ok and fault~=tostring(reason) then
        fault=tostring(reason) Log.write('TASK_RETIREMENT',fault)
    end
end
function Service.install() Probe.tickRetirement=Service.tick end
return Service
