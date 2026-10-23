-- Real Actions/Haul/TaskRuntime/TaskPersistence, mocked native body and disk boundary.
local f=dofile('tests/lua/task-diagnostics-runtime-test.lua')
local npc,actor=f.f.npc,f.f.actor
local Probe=f.f.ctx.Probe
local Actions,Haul=f.f.ctx.Actions,f.f.Haul
local root=f.root
function getSpecificPlayer() return actor end
local checks,captures,nonce=0,0,nil
local function check(v,m) checks=checks+1 assert(v,m) end
package.loaded['EmberRoutesProbe/CraftProbe']={prepareRecovery=function() end,record=function() end}
package.loaded['EmberRoutesProbe/LaborStore']={data=function() end,record=function() end}
package.loaded['EmberRoutesProbe/Companion']={exportState=function() return {mode='HOLD',id='npc-a'} end}
local bridge=EmberRoutesProbeJava
bridge.workerCount=function() return 1 end bridge.workerIdAt=function() return 'npc-a' end
local frozen=false
local freeze,thaw=bridge.freezeBodyControl,bridge.thawBodyControl
bridge.freezeBodyControl=function() frozen=true return freeze() end
bridge.thawBodyControl=function() local ok=thaw() if ok then frozen=false end return ok end
bridge.saveBodyReady=function(id,body) return frozen and id=='npc-a' and body==npc and npc.actions:isEmpty() end
bridge.captureCheckpointFor=function()
    check(not Actions.fixtures and #Haul.fixtures==0,'actual temporary fixture owners cleaned before capture')
    captures=captures+1 return 'CHECKPOINT_SAVED'
end
bridge.armSaveReceipt=function() nonce=root.executionSave.id return true end
bridge.verifySaveReceipt=function() return nonce==root.executionSave.id end
bridge.blockAllCheckpoints=function() return 'CHECKPOINT_BLOCKED' end
local Save=require 'EmberRoutesProbe/TaskPersistence'
Save.load()
local property=npc:getInventory():AddItem('Base.Pencil')
property:getModData().PersistenceOriginal='retain-on-save'
check(Actions.execute(actor,'suite')=='QUEUED','real active diagnostic requested') f.tick(3)
check(Actions.isBusy(),'real batch active at OnSave')
check(string.find(Save.capture(),'^CHECKPOINT_SAVED'),'one-shot controlled stop can save after physical observations agree')
check(property:getContainer()==npc:getInventory() and property:getModData().PersistenceOriginal=='retain-on-save',
    'save cleanup retains unrelated/persistent originals')
check(not Actions.isBusy() and frozen,'no diagnostic restart from save callback')
Save.tick(actor) f.tick(4)
check(not frozen and not Actions.fixtures and property:getContainer()==npc:getInventory(),'later live recovery opens admission without recreating diagnostic assets')
check(Actions.execute(actor,'prepare')=='QUEUED','second actual diagnostic fixture requested') f.drain()
local cargo=Actions.fixtures.cargo
npc:getInventory():Remove(cargo)
check(Actions.execute(actor,'eat')=='QUEUED','missing original reaches existing diagnostic evidence provider') f.drain()
local old=root.diagnosticRecovery.byNpc['npc-a']
check(old and old.ids[1],'unknown diagnostic original IDs recorded')
local prior=captures
check(Save.capture()=='CHECKPOINT_BLOCKED' and captures==prior,'save refuses missing-original fixture cleanup')
check(Actions.fixtures and root.diagnosticRecovery.byNpc['npc-a']==old and property:getContainer()==npc:getInventory(),
    'failed cleanup preserves unresolved receipt and all surviving originals')
print('PASS '..checks..' actual diagnostic save checks; native body/disk effects mocked')
