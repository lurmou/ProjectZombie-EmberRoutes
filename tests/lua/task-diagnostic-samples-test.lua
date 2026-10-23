local f=dofile('tests/lua/persistence-samples-test.lua')
local npc,Samples=f.npc,f.Samples
local checks,key,serial=0,nil,0
local function check(value,message) checks=checks+1 assert(value,message) end
local actor={Say=function() end,isDead=function() return false end}
local Probe={ready=true,controlledExecution=true,hasJava=function() return true end}
package.loaded['EmberRoutesProbe/Boot']=Probe
package.loaded['EmberRoutesProbe/Actions']={isBusy=function() return false end,
    cleanupForHaul=function(body,cap) assert(body==npc and cap.current()) return true end}
package.loaded['EmberRoutesProbe/Companion']={}
package.loaded['EmberRoutesProbe/Haul']={}
Probe.cleanupHaul=function(body,cap) assert(body==npc and cap.current()) return true end
function isClient() return false end function isServer() return false end
local root={}
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
Registry.data=function() return root end
Registry.id=function() serial=serial+1 return 'sample-job-'..serial end
local actions={isEmpty=function() return true end}
function npc:getCharacterActions() return actions end
EmberRoutesProbeJava={controlledCarrier=function() return npc end,carrierFor=function() return npc end,
    carrierId=function() return 'npc-2' end,carrierPresent=function() return true end,
    acquireBodyControl=function(body,job,generation) assert(not key) key=job..generation return key end,
    bodyStopMask=function(body,k) return k==key and 0 or -1 end,
    stopWithControl=function(body,k) assert(k==key) return true end,
    releaseBodyControl=function(body,k) assert(k==key) key=nil return true end,
    freezeBodyControl=function() return true end,thawBodyControl=function() return true end,retireBodyControl=function() return true end,
    stopCarrier=function() error('sample used legacy stop') end}
ISTimedActionQueue={queues={},clear=function() end}
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Persistence=require 'EmberRoutesProbe/Persistence'
Runtime.begin()
local function drain()
    for _=1,30 do Runtime.current():step() if not Runtime.current():owns('npc-2') then return end end
    error('sample body did not drain')
end
local marker=npc:getModData().EmberRoutesPersistenceSample
check(Persistence.execute(actor,'sample')=='QUEUED' and npc:getModData().EmberRoutesPersistenceSample==marker,'sample request has no early mutation') drain()
check(Samples.evidence(npc,'npc-2').effects=='KNOWN' and key==nil,'exact sample evidence closes controlled one-shot')
local pencil=npc:getPrimaryHandItem()
npc.root:Remove(pencil)
check(Persistence.execute(actor,'sample')=='QUEUED','existing sample is inspected after grant') drain()
check(root.diagnosticRecovery.byNpc['npc-2'] and key==nil,'missing original sample creates durable recovery obligation')
check(Persistence.execute(actor,'sample')~='QUEUED','sample cannot silently regenerate originals')
npc.damage.health=75
check(Persistence.execute(actor,'recover')=='QUEUED','health diagnostic may run without erasing unknown items') drain()
check(npc.damage.health==100 and root.diagnosticRecovery.byNpc['npc-2'] and key==nil,'health recovery preserves original obligation')
check(Persistence.execute(actor,'clearsample')=='QUEUED','explicit cleanup may attempt retained sample') drain()
check(npc:getModData().EmberRoutesPersistenceSample==marker,'failed cleanup preserves marker')
npc.root.items[#npc.root.items+1]=pencil pencil.container=npc.root
check(Persistence.execute(actor,'clearsample')=='QUEUED','same original can be explicitly reconciled') drain()
check(not npc:getModData().EmberRoutesPersistenceSample and not root.diagnosticRecovery.byNpc['npc-2'] and key==nil,'verified cleanup removes only its recovery record')
print('PASS '..checks..' controlled persistence sample checks; engine mocked')
