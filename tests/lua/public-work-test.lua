local checks=0
local function check(v,s) checks=checks+1 assert(v,s) end
local root={} local serial=0 local now=0 local allowed=true local accepting=true
local workers={'alice','bob'} local busy={} local calls={} local records={} local offers={} local cargo={}
local recipe={recipe={getName=function() return 'saw' end},id='saw',name='Saw',product='Base.Plank',yield=3,surface=false}
local actor={getUsername=function() return 'owner' end,isRecipeKnown=function() return true end,isDead=function() return false end}
local entry={id='s'}
dofile('tests/lua/membership-fixture.lua')(function() if allowed then return entry end end,workers)
local function npc(id) return {id=id,getX=function() return 1 end,getY=function() return 1 end,getZ=function() return 0 end,
 getCharacterActions=function() return {isEmpty=function() return true end} end,
 getBodyDamage=function() return {getOverallBodyHealth=function() return 100 end} end} end
local manual={}
local handles={alice=npc('alice'),bob=npc('bob')}
local studyTargets={}
package.loaded['EmberRoutesProbe/Boot']={ready=true,runtimeReady=true,hasJava=function() return true end,
    idleStudy=function(id,_,target) if target then studyTargets[id]=target end end}
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
package.loaded['EmberRoutesProbe/BusinessJobs']={records=function() return craftRecords end,crafts=function() return {} end,flush=function() end}
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
package.loaded['EmberRoutesProbe/SettlementMembership']={query=function() return {'crate'} end}
local Public=require 'EmberRoutesProbe/PublicWork'
local rawCreate=Public.create local requestTokens={}
Public.create=function(a,s,r,n,surface,label,preferences)
 if not requestTokens[label] or not root.publicWork then requestTokens[label]=Public.requestId() end
 return rawCreate(a,s,r,n,surface,requestTokens[label],preferences)
end
local function tick() now=now+require('EmberRoutesProbe/TickConfig').discoveryMs+1 Public.tick() end
local status,order=Public.create(actor,'s','saw',4,nil,'once')
check(status=='ORDER_CREATED' and root.publicWork.orders[order].npcId==nil,'unclaimed demand does not name an NPC')
check(Public.orders('s')[1].target==6,'requested finished count rounds to complete native batches')
check(Public.create(actor,'s','saw',7,nil,'once')=='REQUEST_CONFLICT','idempotency token cannot change demand')
local snapshot=Public.orders('s') snapshot[1].quantity=99
check(root.publicWork.orders[order].quantity==4,'order snapshots are detached')
check(Public.setPriority(actor,'s','alice','crafting',1)=='PRIORITY_SAVED','per-worker priority saved')
check(Public.setPriorities(actor,'s','alice',{crafting=0,hauling=0},0)=='PRIORITY_CHANGED','stale settings revision is rejected')
tick() check(#calls==0,'NPC without known recipe cannot claim even at highest priority')
check(studyTargets.alice and studyTargets.alice.recipeId=='saw' and studyTargets.alice.knowledge[1]=='saw',
    'missing knowledge publishes a personal study target without claiming the public order')
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
-- More than the old total-history cap: each unclaimed cancellation retires;
-- small intent receipts reject expired submissions rather than recreating them.
root={} busy={} cargo={} records={} craftRecords={} workers={}
local oldest,latest,lastOrder
for i=1,300 do
 local token=Public.requestId() oldest=oldest or token latest=token
 local status,id=rawCreate(actor,'s','saw',1,nil,token)
 assert(status=='ORDER_CREATED') lastOrder=id
 assert(Public.command(actor,'s',id,root.publicWork.orders[id].revision,'return')=='ORDER_UPDATED')
 assert(Public.retireSettled(8)==1)
end
check(#Public.orders('s')==0 and #root.publicWork.requests==128,'300 settled orders leave no history and bounded receipts')
check(rawCreate(actor,'s','saw',1,nil,oldest)=='REQUEST_EXPIRED','evicted request is rejected instead of duplicating completed demand')
local result,retried=rawCreate(actor,'s','saw',1,nil,latest)
check(result=='ORDER_CREATED' and retried==lastOrder and #Public.orders('s')==0,'recent completed request is acknowledged without work')
check(rawCreate(actor,'s','saw',2,nil,latest)=='REQUEST_CONFLICT','completed receipt still rejects changed demand')
local pendingToken=Public.requestId() local _,pendingId=rawCreate(actor,'s','saw',1,nil,pendingToken)
for _=1,129 do Public.requestId() end
local repeated,repeatedId=rawCreate(actor,'s','saw',1,nil,pendingToken)
check(repeated=='ORDER_CREATED' and repeatedId==pendingId,'active order retry survives receipt eviction')
-- Capacity is a worker property: a failed weak candidate must not cool down
-- the shared demand for a stronger worker.
root={} busy={} cargo={} records={} craftRecords={} calls={} offers={} workers={'alice'}
package.loaded['EmberRoutesProbe/ProductionChain'].new=function(_,n)
 return {step=function() if n.id=='alice' then return nil,'CAPACITY_UNAVAILABLE' end return {nodes={}} end,cancel=function() end}
end
local _,capacityOrder=Public.create(actor,'s','saw',1,nil,'capacity')
tick() tick()
check(root.publicWork.orders[capacityOrder].state=='WAITING' and not root.publicWork.orders[capacityOrder].jobId and #calls==0,
 'capacity rejection keeps public demand unclaimed and waiting')
workers={'bob'} tick() tick()
check(#calls==1 and calls[1].npc=='bob' and calls[1].orderId==capacityOrder,
 'stronger worker may claim the same demand before weak-worker retry expires')
-- A provider exception closes public admission only; it must not strand active
-- body controllers or disable the save authority.
root={} busy={} cargo={} records={} craftRecords={} calls={} offers={} workers={'alice'} known.alice=true
Public.prepareRecovery()
local driver=package.loaded['EmberRoutesProbe/Driver'] local oldBind=driver.bindId local binds=0
driver.bindId=function(...) binds=binds+1 return oldBind(...) end
local business=package.loaded['EmberRoutesProbe/BusinessJobs'] local oldRecords,oldFlush=business.records,business.flush
local scans,flushes=0,0
business.records=function(...) scans=scans+1 return oldRecords(...) end
business.flush=function(...) flushes=flushes+1 return oldFlush(...) end
tick()
check(binds==1,'ordinary decision uses just-computed worker eligibility once')
check(scans==0,'unlinked/empty orders do not build a complete crafting index')
check(Public.retireSettled(8)==0 and flushes==0,'no public orders means no redundant business flush in public retirement')
driver.bindId=oldBind business.records,business.flush=oldRecords,oldFlush
-- No craft orders must not skip releasing a finished hauling offer.
local Directory=require 'EmberRoutesProbe/TaskDirectory' local originalNew=Directory.new local released=0
Directory.new=function(...)
 local directory=originalNew(...) local release=directory.release
 directory.release=function(self,...) released=released+1 return release(self,...) end
 return directory
end
root={} busy={} cargo={} records={} craftRecords={} calls={} offers={alice={source='source',items={1}}}
tick() check(#calls==1 and calls[1].kind=='haul','hauling can run without public crafting orders')
records.alice={id=calls[1].jobId,state='DONE'} busy.alice=nil
Public.retireSettled(8)
check(released>0,'empty craft order cleanup still releases completed hauling offers')
Directory.new=originalNew
-- P3.5: public planning may observe through an idle native action, but must
-- stop that owner's leisure before a real claim/production is submitted.
root={} busy={} cargo={} records={} craftRecords={} calls={} offers={} workers={'alice'} known.alice=true
package.loaded['EmberRoutesProbe/ProductionChain'].new=function() return {step=function() return {nodes={}} end,cancel=function() end} end
local boot=package.loaded['EmberRoutesProbe/Boot'] local interrupted=0 local probing=true
boot.careBlocksWork=function() return probing end
boot.careProbeWork=function() return probing end
boot.leisureWorkReady=function() interrupted=interrupted+1 end
handles.alice.getCharacterActions=function() return {isEmpty=function() return not probing end} end
Public.create(actor,'s','saw',1,nil,'leisure-preempt') tick() tick()
check(interrupted>0 and #calls==0,'idle native action remains observable; ready work requests stop without claiming')
probing=false tick() tick()
check(#calls==1,'work claims only after personal leisure has stopped and released its body')
boot.careBlocksWork=nil boot.careProbeWork=nil boot.leisureWorkReady=nil
-- A fully planned candidate can still lose a resource at real admission.
-- Failure must cool this NPC/offer instead of cancelling leisure every round.
root={} busy={} cargo={} records={} craftRecords={} calls={} offers={} workers={'alice'}
local production=package.loaded['EmberRoutesProbe/Production']
local originalExecute=production.execute local failedStarts=0
production.execute=function() failedStarts=failedStarts+1 return 'RESOURCE_CHANGED' end
boot.leisureWorkState=function() end
Public.create(actor,'s','saw',1,nil,'admission-failure') tick() tick()
check(failedStarts==1,'actual admission failure observed once')
for i=1,5 do tick() end
check(failedStarts==1,'failed NPC/offer is backed off while world evidence is unchanged')
production.execute=originalExecute boot.leisureWorkState=nil
root={} busy={} cargo={} records={} craftRecords={} calls={} offers={} workers={'alice'}
local logistics=package.loaded['EmberRoutesProbe/LogisticsService']
local oldOffer=logistics.publicOffer local discoveries=0
logistics.publicOffer=function(...) discoveries=discoveries+1 return oldOffer(...) end
for _=1,35 do tick() end
check(discoveries<30,'quiet idle workers stop polling providers after the bounded no-work window')
Public.create(actor,'s','saw',1,nil,'wake-idle') tick() tick()
check(#calls==1,'new order wakes a dormant worker without waiting for fallback')
logistics.publicOffer=oldOffer

-- Dynamic Provider Registration Protocol
local discoveredCooking=0 local claimedCooking=0 local reconciledCooking=0
local cookingProvider={
    category='cooking',
    defaultPriority=2,
    discover=function(env)
        discoveredCooking=discoveredCooking+1
        if env.npcId=='alice' and env.priority>0 then
            local offer=env.upsertOffer('cook:pot',1,'cooking',env.entry.id)
            if offer and not offer.jobId then
                env.candidates[#env.candidates+1]={key=offer.key,revision=offer.revision,category='cooking',allowed=true,score=10}
            end
        end
    end,
    claim=function(selected,npcId,jobId,env)
        claimedCooking=claimedCooking+1
        calls[#calls+1]={kind='cook',npc=npcId,jobId=jobId}
        return 'QUEUED'
    end,
    reconcile=function()
        reconciledCooking=reconciledCooking+1
    end
}
check(Public.registerProvider(cookingProvider),'provider registration succeeds')
local cats=Public.categories()
local hasCooking=false for _,c in ipairs(cats) do if c=='cooking' then hasCooking=true end end
check(hasCooking,'registered category appears in Public.categories()')
local pAlice=Public.priorities('alice')
check(pAlice.cooking==2,'unconfigured worker inherits provider default priority')
local pRes=Public.setPriority(actor,'s','alice','cooking',4)
check(pRes=='PRIORITY_SAVED','setPriority supports dynamic provider category')
check(Public.priorities('alice').cooking==4,'saved category priority is reflected')
root={} busy={} cargo={} records={} craftRecords={} calls={} offers={} workers={'alice'}
tick()
check(reconciledCooking>0,'provider reconcile is invoked on tick')
check(discoveredCooking>0 and claimedCooking==1 and calls[#calls].kind=='cook',
    'provider discover and claim are executed for registered category')

-- Associated preparation demand uses the same bounded receipts and survives
-- parent pause without being mistaken for a new independent player request.
workers={'alice'} root={} busy={} cargo={} records={} craftRecords={}
Public.prepareRecovery()
local parent={id='food-parent',category='cooking',recipeId='food-root',settlementId='s',
    name='Meal',product='Base.Meal',quantity=1,target=1,delivered=0,sequence=1,revision=1,state='WAITING',requestId='parent'}
root.publicWork.orders[parent.id]=parent root.publicWork.sequence=1
actor.isRecipeKnown=function() return false end
local result,childId=Public.createPrerequisite(actor,parent.id,{recipeId='saw',requested=3})
check(result=='ORDER_CREATED' and root.publicWork.orders[childId].parentOrderId==parent.id,
    'NPC-known predecessor reuses the public order store without requiring player recipe knowledge')
local _,sameChild=Public.createPrerequisite(actor,parent.id,{recipeId='saw',requested=3})
check(sameChild==childId and root.publicWork.sequence==2,'repeated planning joins its active predecessor instead of duplicating demand')
parent.state='PAUSED'
check(not require('EmberRoutesProbe/CookingOrders').parentAllows(root.publicWork.orders[childId]),
    'paused parent prevents an unclaimed associated order from starting')
check(Public.createPrerequisite(actor,parent.id,{recipeId='saw',requested=3})=='TASK_CHANGED',
    'paused requests cannot create more predecessor work')
actor.isRecipeKnown=function() return true end
workers={'alice'} root={} busy={} cargo={} records={} craftRecords={}
package.loaded['EmberRoutesProbe/ProductionChain'].new=function() error('provider fixture failure') end
Public.create(actor,'s','saw',1,nil,'fault') tick()
check(package.loaded['EmberRoutesProbe/Boot'].runtimeReady,'provider failure does not disable existing body/save runtime')
local available,why=Public.available()
check(not available and why=='DISPATCH_BLOCKED','provider failure blocks further public mutation without retries')

-- Delivery composes with the existing hauling provider; it cannot replace logistics.
local delivery=require 'EmberRoutesProbe/DeliveryService'
local oldDiscover,oldClaim,oldAdvance=delivery.discover,delivery.claim,delivery.advance
local discovered,advanced=false,false
local provider=Public.provider('hauling')
delivery.discover=function(env) discovered=true env.candidates[#env.candidates+1]={delivery=true} end
delivery.claim=function() return 'DELIVERY_CLAIM_MARKER' end
delivery.advance=function() advanced=true end
offers.alice={source='box',items={17}}
local candidates={}
provider.discover({actor=actor,npc=handles.alice,entry=entry,candidates=candidates})
check(discovered and #candidates==2 and candidates[1].delivery and candidates[2].intent.source=='box',
    'same hauling provider contributes delivery and existing logistics offers')
check(provider.claim({delivery=true},'alice','job',{})=='DELIVERY_CLAIM_MARKER','delivery selected through existing provider claim')
provider.advance({}) check(advanced,'shared coordinator advances retained delivery responsibility')
delivery.discover,delivery.claim,delivery.advance=oldDiscover,oldClaim,oldAdvance
print('PASS '..checks..' public dispatch/priority/claim/recovery checks; native bodies mocked')
