-- Current controlled Companion/TaskRuntime/Persistence chain. Native cleanup,
-- snapshot codec and disk receipt are explicit fakes; no legacy free-body calls.
local world=dofile('tests/lua/task-companion-runtime-test.lua')
local actor,npc,Probe=world.actor,world.bodies.a,world.probe
local Companion=world.companion
local root=world.root()
root.format=2 root.nextClaimSeq=0
root.obligations=require('EmberRoutesProbe/Kernel/ObligationLedger').fresh()
Probe.enabled=true Probe.isPublicDispatch=function() return false end
Probe.unavailableCode=function() return 'DRIVER_UNAVAILABLE' end
function actor:getCurrentSquare() return {} end
local currentActor=actor
function getSpecificPlayer() return currentActor end
local multiplayer=false
function isClient() return multiplayer end function isServer() return false end
local count,captures,restores,reports,worldSaves=0,0,0,0,0
local function check(ok,message) count=count+1 assert(ok,message) end
local frozen,paused,cleanupFails,cleanupThrows,captureFails,delayedStop=false,false,false,false,false,false
local diskNonce,restoreResult=nil,'CHECKPOINT_RESTORED'
local blocked={} local property={id='same-original',state={condition=73}}
local bridge=EmberRoutesProbeJava
if ERLaborTestBridge then for k,v in pairs(ERLaborTestBridge) do bridge[k]=v end end
local nativeStop=bridge.stopWithControl
bridge.stopWithControl=function(body,key)
    if delayedStop then return true end
    return nativeStop(body,key)
end
bridge.workerCount=function() return 1 end bridge.workerIdAt=function() return 'a' end
bridge.freezeBodyControl=function() frozen=true return true end
bridge.thawBodyControl=function() if world.keys().a then return false end frozen=false return true end
bridge.saveBodyReady=function(id,body) return id=='a' and body==npc and frozen and not world.keys().a end
bridge.captureCheckpointFor=function(id,mode,hasHome,x,y,z)
    check(id=='a' and frozen and paused and not world.keys().a,'capture only after freeze, stopped body and business admission barrier')
    captures=captures+1
    return captureFails and 'CHECKPOINT_BLOCKED injected' or 'CHECKPOINT_SAVED'
end
bridge.armSaveReceipt=function() return true end
bridge.verifySaveReceipt=function() return diskNonce==root.executionSave.id end
bridge.blockAllCheckpoints=function(reason) blocked[#blocked+1]=reason return 'CHECKPOINT_BLOCKED' end
bridge.restoreCheckpointFor=function(id)
    check(id=='a','restore uses stable NPC identity') restores=restores+1 return restoreResult
end
bridge.reportCheckpoint=function() reports=reports+1 return 'CHECKPOINT_REPORT' end
local cleanupProperty=property
package.loaded['EmberRoutesProbe/Runtime/Actions']={cleanupForHaul=function(body,capability)
    check(body==npc and capability.current() and capability.clear(),'cleanup requires frozen idle capability')
    check(not capability.move and not capability.add and not capability.stop,'cleanup cannot dispatch or force-stop')
    if cleanupThrows then error('injected cleanup exception') end
    check(cleanupProperty==property and property.state.condition==73,'unrelated original identity and instance state retained')
    return not cleanupFails
end}
package.loaded['EmberRoutesProbe/Hauling/Haul']={fixtures={},cleanup=function(body,capability)
    return body==npc and capability.current()
end}
-- No jobs in these domains in this fixture; retain their explicit boot hooks.
package.loaded['EmberRoutesProbe/Crafting/CraftProbe']={prepareRecovery=function() end}
package.loaded['EmberRoutesProbe/Field/FieldWork']={prepareRecovery=function() return true end}
package.loaded['EmberRoutesProbe/Activity/ActivityParticipant']={prepareRecovery=function() return true end}
package.loaded['EmberRoutesProbe/Activity/ActivityService']={finishScenes=function() end}
Probe.beforeStockSave=function() paused=true end
Probe.afterStockSave=function() paused=false end
local craftResult
Probe.afterCraftSave=function(results) craftResult=results or false end
local Persistence=require 'EmberRoutesProbe/Runtime/Persistence'
local Save=require 'EmberRoutesProbe/Runtime/TaskPersistence'
Save.load()
world.select('a')
check(Companion.debugExecute(actor,'follow'),'follow submits through controlled runtime') world.tick(3)
local intent=Companion.exportState('a')
check(intent.mode=='FOLLOW' and world.keys().a,'follow owns actual controlled session')
check(Persistence.save():find('^CHECKPOINT_SAVED') and captures==1,'normal save captures stopped follow')
local receipt=root.executionSave local saved=receipt.byNpc.a
check(saved.kind=='COMPANION' and saved.intent.jobId==intent.jobId and saved.intent.mode=='FOLLOW'
    and saved.effects=='KNOWN' and saved.persisted and saved.bodyStopped,'snapshot retains same Job intent and stop evidence')
check(frozen and paused and not world.keys().a,'OnSave does not resume follow')
diskNonce=receipt.id
Persistence.tick() world.tick(3)
check(not frozen and not paused and Companion.exportState('a').jobId==intent.jobId
    and Companion.exportState('a').mode=='FOLLOW','verified receipt restores exact follow Job on later tick')
check(craftResult and craftResult.a=='CHECKPOINT_SAVED','craft continuation receives per-NPC capture result')
local function recoverBarrier()
    cleanupFails=false cleanupThrows=false captureFails=false delayedStop=false
    -- Simulate a fresh native/Lua host after a blocked save; persisted root is retained.
    -- A blocked runtime is never thawed by merely changing a fake cleanup flag.
    require('EmberRoutesProbe/Runtime/TaskRuntime').reset()
    world.keys().a=nil frozen=false
    require('EmberRoutesProbe/Runtime/TaskRuntime').begin()
    Save.reset() Save.load()
    world.tick(8)
end
cleanupFails=true
check(Persistence.save()=='CHECKPOINT_BLOCKED' and root.executionSave.state=='BLOCKED','cleanup refusal blocks checkpoint')
check(craftResult==false and cleanupProperty==property,'blocked save disarms continuation without destroying original')
recoverBarrier()
check(Persistence.save():find('^CHECKPOINT_SAVED'),'explicitly resolved cleanup permits subsequent capture')
-- Captured ModData alone is not a disk receipt.
diskNonce=nil Persistence.tick()
check(frozen and paused and root.executionSave.state=='BLOCKED','missing disk receipt cannot reopen admission')
recoverBarrier()
cleanupThrows=true
check(Persistence.save()=='CHECKPOINT_BLOCKED' and root.executionSave.state=='BLOCKED','cleanup exception poisons snapshot')
recoverBarrier()
captureFails=true
check(Persistence.save()=='CHECKPOINT_BLOCKED' and root.executionSave.state=='BLOCKED','native capture failure remains blocked')
recoverBarrier()
-- Automatic restore waits for local actor/driver readiness, then attempts once.
root.executionSave=nil
Probe.restorePending=true currentActor=nil Persistence.tick()
check(restores==0 and Probe.restorePending,'restore waits for real local actor')
currentActor=actor Probe.ready=false Persistence.tick()
check(restores==0 and Probe.restorePending,'restore waits for ready driver')
Probe.ready=true Persistence.tick() Persistence.tick()
check(restores==1 and not Probe.restorePending,'one automatic restore per successful snapshot')
-- Only unloaded-tile refusals are retried, with a bounded cadence.
restoreResult='RESTORE_TILE_UNAVAILABLE' Probe.restorePending=true
local priorRestores=restores
Persistence.tick()
check(restores==priorRestores+1,'unloaded tile gets initial restore attempt')
for _=1,8 do world.tick(3) Persistence.tick() end
check(restores==priorRestores+3 and not Probe.restorePending,'automatic tile retry is bounded to three attempts')
Persistence.execute(actor,'restore')
check(restores==priorRestores+4,'manual restore remains available after bounded automatic retry')
restoreResult='CHECKPOINT_RESTORED'
local mode=Companion.exportState('a').mode
Persistence.execute(actor,'report')
check(reports==1 and Companion.exportState('a').mode==mode,'report leaves current intent untouched')
-- Saveworld now prepares asynchronously; native save must wait for stop proof.
function save(characters)
    assert(characters==true) worldSaves=worldSaves+1
    check(Persistence.save():find('^CHECKPOINT_SAVED'),'native OnSave reaches same controlled barrier')
    diskNonce=root.executionSave.id
end
check(Persistence.execute(actor,'saveworld')=='WORLD_SAVE_PREPARING' and worldSaves==0,'world save queues preparation before native write')
world.tick(12) Persistence.tick()
check(worldSaves==1,'native world save invoked after preparation')
Persistence.tick() world.tick(3)
multiplayer=true Persistence.execute(actor,'saveworld')
check(worldSaves==1,'existing multiplayer guard prevents local world write') multiplayer=false
local before=captures
Probe.enabled=false Persistence.save() Probe.enabled=true
check(captures==before,'disabled probe cannot capture or poison checkpoint')
-- A native stop request is not stop evidence.
recoverBarrier()
check(Companion.debugExecute(actor,'follow'),'follow can start after explicit barrier reset') world.tick(4)
delayedStop=true
check(Persistence.save()=='CHECKPOINT_BLOCKED' and world.keys().a and frozen,'unconfirmed physical stop retains control and blocks save')
check(root.executionSave.byNpc.a.bodyStopped==false and root.executionSave.byNpc.a.effects=='UNKNOWN',
    'failed stop is preserved as unknown rather than clean snapshot')
print('PASS '..count..' controlled persistence orchestration checks; native/disk mocked')
