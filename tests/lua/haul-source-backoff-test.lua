-- Real HaulAgent lifecycle with explicit storage/body hosts. No game or asset-transfer proof.
local now,checks,moves,claims,commits=100,0,0,0,0
local function check(v,m) checks=checks+1 assert(v,m) end
getTimestampMs=function() return now end
isClient=function() return false end isServer=function() return false end
local root,sourceInventory,destInventory={},{},{}
local actions={isEmpty=function() return true end}
local npc={getInventory=function() return root end,getCharacterActions=function() return actions end,
    getBodyDamage=function() return {getOverallBodyHealth=function() return 100 end} end}
local actor={isDead=function() return false end}
local source={id='source',container=sourceInventory} local destination={id='dest',container=destInventory}
function root:hasRoomFor() return true end function destInventory:getFreeCapacity() return 20 end
local item={getID=function() return 1 end,getUnequippedWeight=function() return 1 end}
local record={id='haul',npcId='npc',format=3,producer='LOGISTICS',scopeId='local-world',settlementId='base',
    source='source',destination='dest',generation=1,state='PAUSED',reason='LOAD_RECOVERY',manifest={{itemId=1,custodyState='UNCOLLECTED'}}}
local token={}
local Store={record=function() return record end,valid=function() return true end,
    claim=function() claims=claims+1 return token end,publish=function() return true end,
    pause=function() return token end,releaseCapacity=function() return true end,capacity=function() return true end}
package.loaded['EmberRoutesProbe/LaborStore']=Store
package.loaded['EmberRoutesProbe/ContainerRegistry']={resolve=function(id) return id=='source' and source or destination end,
    revalidate=function(ep) return ep end}
package.loaded['EmberRoutesProbe/Hauling/HaulManifest']={valid=function(r) return r==record end,
    pending=function(l) return l.custodyState=='UNCOLLECTED' end,claimItemIds=function() return {1} end}
package.loaded['EmberRoutesProbe/InventoryView']={scan=function() return {step=function() return {} end} end,
    find=function() return item,2 end}
package.loaded['EmberRoutesProbe/LaborProducers']={transfer=function() return true end,freeCarry=function() return 20 end}
package.loaded['EmberRoutesProbe/Driver']={bindId=function() return {id='npc',handle=npc} end}
package.loaded['EmberRoutesProbe/TaskRuntime']={}
package.loaded['EmberRoutesProbe/Hauling/HaulRouting']={accept=function() return true end}
package.loaded['EmberRoutesProbe/LaborSignals']={changed=function() end}
local Probe={ready=true,controlledExecution=false}
package.loaded['EmberRoutesProbe/Boot']=Probe
package.loaded['EmberRoutesProbe/Log']={write=function() end}
package.loaded['EmberRoutesProbe/DeliveryTarget']={}
package.loaded['EmberRoutesProbe/DisplayNames']={name=function() return 'Worker' end}
package.loaded['EmberRoutesProbe/Hauling/HaulJobs']={commit=function() commits=commits+1 return true end}
package.loaded['EmberRoutesProbe/HealthAssessment']={canWork=function() return true end}
ISTimedActionQueue={clear=function() end}
EmberRoutesProbeJava={carrierPresent=function() return true end,stopCarrier=function() end}
local failAtStart=false
package.loaded['EmberRoutesProbe/WorkTransfer']={reachable=function() return false end,move=function()
    return {start=function() moves=moves+1 if failAtStart then return 'FAILED','NO_WALKABLE_ADJACENT_TILE' end end,
        poll=function() return 'FAILED','PATH_FAILED' end}
end}
local agent=require('EmberRoutesProbe/Hauling/HaulAgent').new('npc')
check(agent.resume(actor)=='STARTED','retained job starts using the existing claim')
agent.tick()
check(record.state=='PAUSED' and record.reason=='ROUTING_WAIT' and not agent.busy(),'failed approach releases active execution')
check(record.pathBackoff.source==15100 and moves==1,'failed source has the existing 15-second backoff')
local beforeClaims,beforeCommits=claims,commits
for _=1,10 do now=now+100 check(agent.resume(actor)=='ROUTING_WAIT','cooldown rejects reacquiring the body') end
check(claims==beforeClaims and commits==beforeCommits and moves==1,'cooldown causes no claim/publication/movement churn')
check(record.manifest[1].custodyState=='UNCOLLECTED' and record.id=='haul','waiting retains the original job and uncollected responsibility')
-- A recovered record may carry only pathBackoff, without the diagnostic routingWait hint.
record.routingWait=nil
check(agent.resume(actor)=='STARTED','record without wait hint may enter ordinary source validation')
agent.tick()
check(record.state=='PAUSED' and moves==1 and record.routingWait.reason=='PATH_BACKOFF','source validation itself honours backoff before moving')
now=15100 failAtStart=true
check(agent.resume(actor)=='STARTED','expiry admits a fresh bounded attempt')
agent.tick()
check(moves==2 and record.pathBackoff.source==30100 and not agent.busy(),'failure before movement also backs off and releases execution')
print('PASS '..checks..' source backoff checks; real HaulAgent, native/storage hosts mocked')
