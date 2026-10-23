local checks=0
local function check(v,s) checks=checks+1 assert(v,s) end
local root={} local serial=0 local now=0 local allowed=true local accepting=true
local workers={'alice','bob'} local busy={} local calls={} local records={} local offers={} local cargo={}
local recipe={recipe={},id='saw',name='Saw',product='Base.Plank',yield=3,surface=false}
local actor={getUsername=function() return 'owner' end,isRecipeKnown=function() return true end,isDead=function() return false end}
local entry={id='s'}
local function npc(id) return {id=id,getX=function() return 1 end,getY=function() return 1 end,
 getCharacterActions=function() return {isEmpty=function() return true end} end,
 getBodyDamage=function() return {getOverallBodyHealth=function() return 100 end} end} end
local manual={}
local handles={alice=npc('alice'),bob=npc('bob')}
package.loaded['EmberRoutesProbe/Boot']={ready=true,runtimeReady=true,hasJava=function() return true end}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,id=function() serial=serial+1 return 'id-'..serial end}
package.loaded['EmberRoutesProbe/SettlementLedger']={view=function() if allowed then return entry end return nil,'ACCESS_DENIED' end,at=function() return {entry} end}
package.loaded['EmberRoutesProbe/SettlementGeometry']={inside=function() return true end}
package.loaded['EmberRoutesProbe/Driver']={bindId=function(_,id) return {handle=handles[id]} end}
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return {accepting=function() return accepting end,
 status=function(_,id,job) return busy[id] and {jobId=job} or nil end} end}
package.loaded['EmberRoutesProbe/Work']={busy=function(id) return busy[id] end,hasCargo=function(_,id) return cargo[id] end,
 record=function(id) return records[id] end,
 resumeFor=function(_,id) records[id].reason='RESUMED' calls[#calls+1]={kind='resume',npc=id} return 'QUEUED' end,
 allowAutomation=function(id) manual[id]=nil end,
 assign=function(_,id,intent) if manual[id] then return 'MANUAL_OVERRIDE' end busy[id]=true calls[#calls+1]={kind='haul',npc=id,jobId=intent.jobId} return 'QUEUED' end}
package.loaded['EmberRoutesProbe/Companion']={exportState=function() return {mode='HOLD'} end}
local known={alice=false,bob=true}
package.loaded['EmberRoutesProbe/ProductionRecipe']={read=function() return recipe end,inspect=function(_,n)
 if known[n.id] then return recipe end return nil,'NPC_RECIPE_UNKNOWN' end}
package.loaded['EmberRoutesProbe/CraftSurfaces']={resolve=function() return {} end}
package.loaded['EmberRoutesProbe/LaborSignals']={changed=function() end}
package.loaded['EmberRoutesProbe/Log']={write=function() end}
local craftRecords={}
package.loaded['EmberRoutesProbe/BusinessJobs']={records=function() return craftRecords end,crafts=function() return {} end}
package.loaded['EmberRoutesProbe/ProductionChain']={new=function() return {step=function() return {nodes={}} end,cancel=function() end} end}
package.loaded['EmberRoutesProbe/Production']={execute=function(_,_,_,id,o)
 busy[id]=true calls[#calls+1]={kind='craft',npc=id,jobId=o.taskId,orderId=o.orderId}
 craftRecords[o.taskId]={id=o.taskId,npcId=id,state='RUNNING',orderId=o.orderId}
 return 'QUEUED' end}
local recoveryPrepared=0
package.loaded['EmberRoutesProbe/LogisticsService']={publicOffer=function(_,_,n) return offers[n.id] end,
 preparePublic=function() recoveryPrepared=recoveryPrepared+1 return true end}
function isClient() return false end function isServer() return false end
function getTimestampMs() return now end function getSpecificPlayer() return actor end
EmberRoutesProbeJava={workerCount=function() return #workers end,workerIdAt=function(i) return workers[i+1] end}
local Public=require 'EmberRoutesProbe/PublicWork'
local function tick() now=now+201 Public.tick() end
local status,order=Public.create(actor,'s','saw',4,nil,'once')
check(status=='ORDER_CREATED' and root.publicWork.orders[order].npcId==nil,'unclaimed demand does not name an NPC')
check(Public.orders('s')[1].target==6,'requested finished count rounds to complete native batches')
check(Public.create(actor,'s','saw',7,nil,'once')=='REQUEST_CONFLICT','idempotency token cannot change demand')
local snapshot=Public.orders('s') snapshot[1].quantity=99
check(root.publicWork.orders[order].quantity==4,'order snapshots are detached')
check(Public.setPriority(actor,'s','alice','crafting',1)=='PRIORITY_SAVED','per-worker priority saved')
check(Public.setPriorities(actor,'s','alice',{crafting=0,hauling=0},0)=='PRIORITY_CHANGED','stale settings revision is rejected')
tick() check(#calls==0,'NPC without known recipe cannot claim even at highest priority')
tick() tick() tick() check(#calls==1 and calls[1].npc=='bob','other capable idle NPC claims the public order')
known.alice=true tick() tick()
check(#calls==1,'two workers never execute the same claimed order')
check(root.publicWork.orders[order].jobId==calls[1].jobId,'claim links stable Order and independent Job')
accepting=false
local _,second=Public.create(actor,'s','saw',1,nil,'second')
tick() check(#calls==1 and not root.publicWork.orders[second].jobId,'save admission barrier prevents new claims')
accepting=true
check(Public.command(actor,'s',second,0,'return')=='TASK_CHANGED','stale unclaimed command is rejected')
local revision=root.publicWork.orders[second].revision
check(Public.command(actor,'s',second,revision,'stop')=='ORDER_UPDATED','unclaimed demand can pause')
tick() tick() check(#calls==1,'paused demand is not claimed')
revision=root.publicWork.orders[second].revision
check(Public.command(actor,'s',second,revision,'return')=='ORDER_UPDATED','unclaimed demand can cancel without an executor')
check(Public.command(actor,'s',second,revision+1,'resume')=='TASK_CHANGED','cancelled demand cannot revive')
check(Public.saveRule(actor,'s','saw',50,12,nil)=='RULE_SAVED','stock policy uses a fixed finished-item refill count')
local rule=Public.rule('s','Base.Plank') check(rule.minimum==50 and rule.batch==12 and not rule.npcId,'policy has no fixed worker')
check(Public.saveRule(actor,'s','saw',0,12,nil)=='RULE_DISABLED','stock policy can disable without deleting history')
allowed=false check(Public.create(actor,'s','saw',1,nil,'denied')=='ACCESS_DENIED','scope permission is rechecked') allowed=true
-- Owned cargo recovery bypasses fresh-work cargo exclusion, never user pauses.
busy.bob=nil workers={'alice'} cargo.alice=true
records.alice={id='held-haul',state='PAUSED',reason='LOAD_RECOVERY',producer='LOGISTICS',settlementId='s'}
tick() check(recoveryPrepared==1 and calls[#calls].kind=='resume','loaded haul resumes its own original cargo before public discovery')
records.alice.reason='USER' local before=#calls tick()
check(#calls==before,'explicit user pause is never automatically resumed')
records.alice.reason='LOAD_RECOVERY' records.alice.controlUncertain=true tick()
check(#calls==before,'unknown effects never automatically resume')
-- Selector semantics are independent of discovery order and exclude priority 0.
local Selector=require 'EmberRoutesProbe/WorkSelector'
local options={{key='a',category='crafting',allowed=true,score=100},{key='b',category='hauling',allowed=true,score=0}}
check(Selector.choose(options,{crafting=4,hauling=1}).key=='b','work priority outranks business score')
check(Selector.choose(options,{crafting=0,hauling=0})==nil,'disabled categories never enter arbitration')
local d=require('EmberRoutesProbe/TaskDirectory').new()
d:upsert('clean:tile',1,'cleaning','s')
check(d:claim('clean:tile',1,'alice','job-a'),'stable target offer can be claimed')
check(not d:claim('clean:tile',1,'bob','job-b'),'competing worker cannot double claim')
check(not d:release('clean:tile','job-a',{effects='UNKNOWN',obligationsCleared=true}),'unknown effects retain ownership')
check(not d:release('clean:tile','job-a',{effects='KNOWN',obligationsCleared=false}),'outstanding obligations retain ownership')
check(d:release('clean:tile','job-a',{effects='KNOWN',obligationsCleared=true}),'confirmed settled obligation releases offer')
d:upsert('guard:post',1,'guarding','s')
check(d:claim('guard:post',1,'alice','watch-a'),'continuous post has one current owner')
d:withdraw('guard:post')
check(not d:claim('guard:post',1,'bob','watch-b'),'withdrawal does not silently transfer a staffed post')
check(not d:release('guard:post','watch-a',{effects='KNOWN',obligationsCleared=false}),'leaving a tree does not end ongoing post responsibility')
-- Clean world switch rebuilds only transient discovery, retaining old world data.
local previous=root root={} records={} craftRecords={} cargo={} busy={} workers={}
tick() check(previous.publicWork.orders[order].jobId~=nil and root.publicWork.sequence==0,'world switch preserves old facts and resets transient discovery')
-- An unavailable craft never reserves an NPC; a lower ordinary job remains possible.
workers={'alice'} known.alice=true
package.loaded['EmberRoutesProbe/ProductionChain'].new=function() return {step=function() return nil,'MATERIALS_UNAVAILABLE' end,cancel=function() end} end
Public.setPriorities(actor,'s','alice',{crafting=1,hauling=2},0)
Public.create(actor,'s','saw',1,nil,'missing-materials')
tick() tick()
check(#calls==before and Public.orders('s')[1].jobId==nil,'read-only missing-material evaluation creates no execution job')
manual.alice=true
offers.alice={source='in',destination='out',items={123},producer='LOGISTICS',settlementId='s'}
tick() check(calls[#calls].kind=='haul','missing materials and an ended manual override do not block ordinary hauling after HOLD')
offers={} busy={} workers={}
for _,o in pairs(root.publicWork.orders) do o.state='CANCELLED' end
local physical,complete=50,true local watches=0
package.loaded['EmberRoutesProbe/WarehouseIndex']={watch=function() watches=watches+1 return function() watches=watches-1 end end,
 candidates=function() return {state='READY',complete=complete,knownCount=physical} end,refresh=function() end}
package.loaded['EmberRoutesProbe/SettlementMembership']={query=function() return {'crate'} end}
Public.saveRule(actor,'s','saw',50,12,nil)
tick() local total=#Public.orders('s')
check(total==1,'stock at threshold causes no refill; reservations are not subtracted')
physical=49 complete=false now=now+1000 tick()
check(#Public.orders('s')==total,'incomplete inventory never triggers refill')
complete=true now=now+1000 tick()
check(#Public.orders('s')==total+1 and Public.orders('s')[2].quantity==12,'below threshold creates fixed batch, not shortage quantity')
now=now+1000 tick()
check(#Public.orders('s')==total+1,'one active stock order suppresses duplicate refill')
Public.saveRule(actor,'s','saw',0,12,nil) tick()
check(watches==0 and #Public.orders('s')==total+1,'disabling policy releases inventory watch without removing its order')
check(package.loaded['EmberRoutesProbe/Boot'].runtimeReady,'normal dispatch has no hidden backend fault')
-- A provider exception closes public admission only; it must not strand active
-- body controllers or disable the save authority.
workers={'alice'} root={} busy={} cargo={} records={} craftRecords={}
package.loaded['EmberRoutesProbe/ProductionChain'].new=function() error('provider fixture failure') end
Public.create(actor,'s','saw',1,nil,'fault') tick()
check(package.loaded['EmberRoutesProbe/Boot'].runtimeReady,'provider failure does not disable existing body/save runtime')
local available,why=Public.available()
check(not available and why=='DISPATCH_BLOCKED','provider failure blocks further public mutation without retries')

print('PASS '..checks..' public dispatch/priority/claim/recovery checks; native bodies mocked')
