-- Real production Boot + TaskRuntime; engine/body/ledger boundaries are mocked.
local checks,bootCalls,starts=0,0,0
local function check(v,m) checks=checks+1 assert(v,m) end
local callbacks={}
Events={}
for _,name in ipairs({'OnGameStart','OnServerStarted','OnTick','OnTickEvenPaused','OnPreMapLoad','OnSave'}) do
    Events[name]={Add=function(fn) callbacks[name]=fn end}
end
package.loaded['EmberRoutesProbe/Build']={version='activation',prefix='TEST'}
local logs={}
package.loaded['EmberRoutesProbe/Log']={write=function(kind,message) logs[#logs+1]=kind..' '..message end}
function getText(key) return key end
SandboxVars={EmberRoutes={CarrierProbe=true}}
local function stub() end
local bridge={begin=function() bootCalls=bootCalls+1 return 'READY' end,version=function() return 'activation' end}
for _,name in ipairs({'command','tick','reset','clearForSave','actionCarrier','carrierActive','carrierPresent','motionResult',
    'stopCarrier','controlledCarrier','carrierId','retirementTick','saveCheckpoint','restoreCheckpoint','blockCheckpoint',
    'reportCheckpoint','checkpointMode','checkpointHasHome','checkpointHomeX','checkpointHomeY','checkpointHomeZ',
    'commandFor','carrierFor','selectedId','spawnAdditional','selectCarrier','workerCount','workerIdAt','saveCheckpointFor',
    'blockAllCheckpoints','captureCheckpointFor','saveBodyReady','armSaveReceipt','verifySaveReceipt','restoreCheckpointFor',
    'acquireBodyControl','releaseBodyControl','moveWithControl','stopWithControl','bodyStopMask','ownedCarrierId','freezeBodyControl',
    'thawBodyControl','retireBodyControl','removeIdleCarrier','reposeWithControl','reposeAtWithControl'}) do bridge[name]=stub end
EmberRoutesProbeJava=bridge
local Probe=dofile('Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Boot.lua')
package.loaded['EmberRoutesProbe/Boot']=Probe
check(Probe.controlledExecution==true,'production defaults to complete controlled path')
local required={'captureCheckpointFor','saveBodyReady','armSaveReceipt','verifySaveReceipt','restoreCheckpointFor',
    'acquireBodyControl','releaseBodyControl','moveWithControl','stopWithControl','bodyStopMask','ownedCarrierId','freezeBodyControl',
    'thawBodyControl','retireBodyControl','removeIdleCarrier','reposeWithControl','reposeAtWithControl'}
for _,name in ipairs(required) do
    local original=bridge[name] bridge[name]=nil
    local before=bootCalls callbacks.OnGameStart()
    check(not Probe.ready and not Probe.restorePending and bootCalls==before and Probe.failureCode=='MISSING_JAVA',
        'incomplete bridge cannot begin: '..name)
    bridge[name]=original
end
callbacks.OnGameStart()
check(not Probe.ready and Probe.failureCode=='RUNTIME_MODULES_MISSING','missing Lua consumers cannot silently enable partial execution')

local world,loaded,order={},false,{}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return world end}
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
Probe.prepareTaskRecovery=function() loaded=true order[#order+1]='claims' end
Probe.beginTasks=function() check(loaded,'claims prepared before runtime begin') order[#order+1]='begin' Runtime.begin() end
Probe.tickTasks=Runtime.tick Probe.resetTasks=Runtime.reset
Probe.beforeStockSave=stub Probe.afterStockSave=stub Probe.resetStock=stub
local saved,legacy=0,0
Probe.savePersistentCarrier=function() saved=saved+1 end
bridge.clearForSave=function() legacy=legacy+1 end
local body,key,present={},nil,true
bridge.carrierPresent=function(expected) return present and expected==body end
bridge.reset=function() present=false key=nil return 'ABSENT' end
bridge.carrierId=function() return 'npc-a' end
bridge.acquireBodyControl=function(_,job,generation) assert(not key) key=job..generation return key end
bridge.bodyStopMask=function(_,k) return key==k and 0 or -1 end
bridge.releaseBodyControl=function(_,k) assert(key==k) key=nil return true end
bridge.stopWithControl=function(_,k) return k==key end
bridge.retireBodyControl=function() return true end
ISTimedActionQueue={queues={},clear=stub}
callbacks.OnGameStart()
check(Probe.ready and order[1]=='claims' and order[2]=='begin' and Runtime.current(),'complete startup creates ready controlled runtime')
check(logs[#logs]:find('controlledExecution=true')~=nil,'activation is visible in boot diagnostics')
local owned
local runtime=Runtime.current()
local handle=assert(runtime:submit({npcId='npc-a',jobId='original-job',kind='TEST',binding={id='npc-a',handle=body},
    validate=function() return loaded end,start=function(cap) owned=cap starts=starts+1 return true end,
    tick=stub,finished=function() return false end,persistFailure=function() return true end,
    stopAdapter=function(controller,ticket)
        return require('EmberRoutesProbe/TaskBusinessStop').new({controller=controller,ticket=ticket,npc=body,
            npcId='npc-a',jobId='original-job',same=function() return true end,
            pause=function() return owned.clear() end,effects=function() return 'KNOWN' end,persist=function() return true end})
    end}))
check(starts==0,'startup and submit never execute business synchronously')
callbacks.OnTickEvenPaused() check(starts==0,'paused tick cannot acquire/execute new tasks')
callbacks.OnTick() callbacks.OnTick()
check(starts==1 and runtime:inspect(handle).state=='ACTIVE' and key,'normal Boot tick grants and runs real runtime')
callbacks.OnSave()
check(saved==1 and legacy==0,'production save delegates to unified persistence instead of legacy removal')

local prepare=Probe.prepareTaskRecovery
Probe.prepareTaskRecovery=function() error('invalid retained claim') end
callbacks.OnPreMapLoad() -- Retires old capabilities before trying another load.
check(not owned.current() and not owned.clear(),'world reset fences late callbacks from the old owner')
local before=#order
local nativeBegin=bridge.begin
bridge.begin=function() return 'RESET_REQUIRED old body disposal pending' end
callbacks.OnGameStart()
check(Probe.ready and not Probe.runtimeReady and not Runtime.current(),'native cleanup availability does not authorize task execution')
check(#order==before and not Probe.restorePending,'old-body disposal cannot normalize claims or restore new jobs')
bridge.begin=nativeBegin
callbacks.OnGameStart()
check(not Probe.ready and not Probe.restorePending and Probe.failureCode=='RECOVERY_RECORDS_INVALID',
    'invalid claims block startup instead of allowing new work')
check(#order==before and not Runtime.current(),'failure cannot begin or grant a runtime even if its hook exists')
Probe.prepareTaskRecovery=prepare
SandboxVars.EmberRoutes.CarrierProbe=false
callbacks.OnGameStart()
check(Probe.enabled==false and #order==before,'disabled probe does not normalize/rewrite saved business records')
check(not Runtime.current(),'disabled probe cannot dispatch through the enabled production path')
print('PASS '..checks..' default activation/startup checks; game runtime/body boundaries mocked')
