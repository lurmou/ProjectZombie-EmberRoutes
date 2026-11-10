-- P0 pilot: per-NPC x provider priority matrix (HAUL + COOKING first).
-- Run from the repo root: lua5.1 tests/lua/p1-pilot-priority-matrix-test.lua
-- Member record carries workPriorities (1-4, 0 = blank = never do, unset =
-- no override, effective default 3). decide overlays explicitly stored
-- HAUL/COOKING levels on the OrderStore priorities, discovers all eligible
-- providers in one pass ordered by (priority asc, registration order), and
-- picks one job by global utility choose. One decide dispatches at most one
-- job: the queue is never drained (the RimWorld "finish this priority
-- before the next" shape is not copied).
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local checks=0
local function check(v,s) checks=checks+1 assert(v,s) end

-- ================= Part A: MembershipService member record =================
local rootA={}
local actorA={}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return rootA end,
    id=function() return 'id-a' end}
package.loaded['EmberRoutesProbe/Settlement/SettlementLedger']={data=function() return {factionId='f1'} end,
    authorized=function(a) return a==actorA end}
package.loaded['EmberRoutesProbe/Settlement/MembershipPolicy']={evaluate=function() return {allowed=true} end}
package.loaded['EmberRoutesProbe/Work/LaborSignals']={changed=function() end}
local Membership=require 'EmberRoutesProbe/Settlement/MembershipService'
check(Membership.newWorld()==true,'fresh world creates membership store')
check(Membership.register('alice')==true,'alice registers')
local eff=Membership.workPriorities('alice')
check(eff.hauling==3 and eff.cooking==3,'fresh member defaults to 3 for both pilot trades')
check(Membership.workPriorityOverrides('alice')==nil,'fresh member stores no overrides')
check(Membership.workPriorities('ghost')==nil,'unknown member has no priorities')
-- Set HAUL 1: effective 1, stored override, revision bumped.
check(Membership.setWorkPriority(actorA,'alice','hauling',1,1)=='WORK_PRIORITY_SAVED','HAUL set to 1')
eff=Membership.workPriorities('alice')
check(eff.hauling==1 and eff.cooking==3,'HAUL 1 leaves COOKING at default 3')
local ov=Membership.workPriorityOverrides('alice')
check(ov.hauling==1 and ov.cooking==nil,'only the explicitly set key is an override')
-- Blank (0) means never do: COOKING 0.
check(Membership.setWorkPriority(actorA,'alice','cooking',0,2)=='WORK_PRIORITY_SAVED','COOKING set to blank (0)')
eff=Membership.workPriorities('alice')
check(eff.hauling==1 and eff.cooking==0,'blank COOKING reads back as 0, not the default')
-- Clearing a key returns it to "no override" (effective default again).
check(Membership.setWorkPriority(actorA,'alice','hauling',nil,3)=='WORK_PRIORITY_SAVED','clearing HAUL removes the override')
eff=Membership.workPriorities('alice')
check(eff.hauling==3 and eff.cooking==0,'cleared HAUL is default 3; blank COOKING stays 0')
-- Rejections: non-pilot category, out-of-range / non-integer / wrong type,
-- stale revision, unauthorized actor, unknown member. None bumps revision.
local rev=rootA.npcMembership.byNpc.alice.revision
check(Membership.setWorkPriority(actorA,'alice','crafting',1,rev)=='WORK_PRIORITY_CATEGORY_INVALID','non-pilot trade rejected')
check(Membership.setWorkPriority(actorA,'alice','hauling',5,rev)=='WORK_PRIORITY_INVALID','level 5 rejected')
check(Membership.setWorkPriority(actorA,'alice','hauling',1.5,rev)=='WORK_PRIORITY_INVALID','non-integer level rejected')
check(Membership.setWorkPriority(actorA,'alice','hauling','1',rev)=='WORK_PRIORITY_INVALID','string level rejected')
check(Membership.setWorkPriority(actorA,'alice','hauling',-1,rev)=='WORK_PRIORITY_INVALID','negative level rejected')
check(Membership.setWorkPriority(actorA,'alice','hauling',2,rev+99)=='STALE_MEMBERSHIP','stale revision rejected')
check(Membership.setWorkPriority({},'alice','hauling',2,rev)=='ACCESS_DENIED','unauthorized actor rejected')
check(Membership.setWorkPriority(actorA,'ghost','hauling',2,1)=='NO_MEMBERSHIP','unknown member rejected')
check(rootA.npcMembership.byNpc.alice.revision==rev,'rejected writes never bump the revision')
-- Stored rows validate: out-of-range value or non-pilot key fails load.
rootA.npcMembership.byNpc.bad={npcId='bad',factionId='f1',context='WAIT',revision=1,workPriorities={hauling=9}}
local ok,why=Membership.load()
check(ok==false and why=='MEMBERSHIP_FORMAT_INVALID','level 9 in a stored row fails load')
rootA.npcMembership.byNpc.bad.workPriorities={crafting=2}
ok,why=Membership.load()
check(ok==false and why=='MEMBERSHIP_FORMAT_INVALID','non-pilot key in a stored row fails load')
rootA.npcMembership.byNpc.bad=nil
check(Membership.load()==true,'load passes once the bad row is gone')
-- view() carries a detached copy of the matrix.
local view=Membership.view('alice')
check(view.workPriorities.cooking==0,'view carries the stored matrix')
view.workPriorities.cooking=99
check(Membership.workPriorities('alice').cooking==0,'mutating the view never touches the stored row')

-- ============ Part B: decide overlay + single-pass ordering ============
-- Minimal public-work-test shape, one worker. Fake HAUL/COOKING providers
-- (re-registered over the real ones in this process only) offer one
-- candidate each with a controllable score; claim just records the call.
-- The real CraftingProvider still runs, so a craft order exercises the
-- "other trades unchanged" cases.
local root={} local serial=0 local now=0 local allowed=true local accepting=true
local workers={'alice'} local busy={} local calls={} local records={} local cargo={}
local scores={hauling=0,cooking=0}
local overrides={}
local recipe={recipe={getName=function() return 'saw' end},id='saw',name='Saw',product='Base.Plank',yield=3,surface=false}
local actor={getUsername=function() return 'owner' end,getX=function() return 1 end,getY=function() return 1 end,isRecipeKnown=function() return true end,isDead=function() return false end}
local entry={id='s'}
local membershipRows=dofile('tests/lua/membership-fixture.lua')(function() if allowed then return entry end end,workers)
package.loaded['EmberRoutesProbe/Settlement/MembershipService'].workPriorityOverrides=function(id) return overrides[id] end
local function npc(id) return {id=id,getX=function() return 1 end,getY=function() return 1 end,getZ=function() return 0 end,
 getCharacterActions=function() return {isEmpty=function() return true end} end,
 getBodyDamage=function() return {getOverallBodyHealth=function() return 100 end} end} end
local handles={alice=npc('alice')}
local healthy=true
package.loaded['EmberRoutesProbe/SelfCare/HealthAssessment']={canWork=function() return healthy,'HEALTH_NEEDS_CARE' end}
package.loaded['EmberRoutesProbe/Kernel/Boot']={ready=true,runtimeReady=true,hasJava=function() return true end,
    idleStudy=function() end}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return root end,id=function() serial=serial+1 return 'id-'..serial end}
package.loaded['EmberRoutesProbe/Settlement/SettlementLedger']={view=function() if allowed then return entry end return nil,'ACCESS_DENIED' end,at=function() return {entry} end}
package.loaded['EmberRoutesProbe/Settlement/SettlementGeometry']={inside=function() return true end}
package.loaded['EmberRoutesProbe/Runtime/Driver']={bindId=function(_,id) return {handle=handles[id]} end,suspended=function() return false end}
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime']={current=function() return {accepting=function() return accepting end,
 status=function(_,id,job) return busy[id] and {jobId=job} or nil end} end}
package.loaded['EmberRoutesProbe/Work/Work']={busy=function(id) return busy[id] end,hasCargo=function(_,id) return cargo[id] end,
 record=function(id) return records[id] end,
 resumeFor=function(_,id) records[id].reason='RESUMED' calls[#calls+1]={kind='resume',npc=id} return 'QUEUED' end,
 allowAutomation=function(id) end,
 assign=function(_,id,intent) busy[id]=true calls[#calls+1]={kind='haul',npc=id,jobId=intent.jobId} return 'QUEUED' end}
package.loaded['EmberRoutesProbe/Settlement/Companion']={exportState=function() return {mode='HOLD'} end}
local known={alice=true}
package.loaded['EmberRoutesProbe/Crafting/ProductionRecipe']={read=function() return recipe end,inspect=function(_,n)
 if known[n.id] then return recipe end return nil,'NPC_RECIPE_UNKNOWN' end}
package.loaded['EmberRoutesProbe/Crafting/CraftSurfaces']={resolve=function() return {} end}
package.loaded['EmberRoutesProbe/Work/LaborSignals']={changed=function() end}
package.loaded['EmberRoutesProbe/Kernel/Log']={write=function() end}
local craftRecords={}
package.loaded['EmberRoutesProbe/Work/BusinessJobs']={records=function() return craftRecords end,crafts=function() return {} end,flush=function() end}
package.loaded['EmberRoutesProbe/Crafting/ProductionChain']={new=function() return {step=function() return {nodes={}} end,cancel=function() end} end}
package.loaded['EmberRoutesProbe/Crafting/Production']={execute=function(_,_,_,id,o)
 busy[id]=true calls[#calls+1]={kind='craft',npc=id,jobId=o.taskId,orderId=o.orderId}
 craftRecords[o.taskId]={id=o.taskId,npcId=id,state='RUNNING',orderId=o.orderId}
 return 'QUEUED' end}
package.loaded['EmberRoutesProbe/Logistics/LogisticsService']={publicOffer=function() return nil end,
 preparePublic=function() return true end}
function isClient() return false end function isServer() return false end
function getTimestampMs() return now end function getSpecificPlayer() return actor end
EmberRoutesProbeJava={workerCount=function() return #workers end,workerIdAt=function(i) return workers[i+1] end}
package.loaded['EmberRoutesProbe/Settlement/SettlementMembership']={query=function() return {'crate'} end}
package.loaded['EmberRoutesProbe/Work/LaborStore']={custodyForNpc=function() return {} end}
package.loaded['EmberRoutesProbe/Field/ToolReturnService']={canInterrupt=function() return false end,
 reconcile=function() end,returnResult=function() end,liveTask=function() end,
 forgetResult=function() error('no tracked tool return in dispatch-only fixture') end,
 startFor=function() error('unexpected tool return in dispatch-only fixture') end}
package.loaded['EmberRoutesProbe/Field/FieldDemand']={advance=function() end}
package.loaded['EmberRoutesProbe/Settlement/SettlementZones']={
    get=function() return {id='posted',settlementId='s',enabled=true} end,
    coveredZone=function() return true end,
    contains=function(_,x,y,z) return x>=0 and x<4 and y>=0 and y<4 and z==0 end}
package.loaded['EmberRoutesProbe/SelfCare/NeedsObserver']={sample=function() return {hunger=0.05,thirst=0.05,fatigue=0.10,endurance=0.90} end}
local Public=require 'EmberRoutesProbe/Work/PublicWork'
local function fakeProvider(category)
    return {category=category,defaultPriority=3,priorityRequired=category=='hauling',
        retained=function() return false end,
        discover=function(env)
            local offer=env.upsertOffer(category..':test',1,category,env.entry.id)
            if offer and not offer.jobId then
                env.candidates[#env.candidates+1]={key=category..':test',revision=1,category=category,
                    allowed=true,score=scores[category] or 0,npcId=env.npcId,scopeId=env.entry.id}
            end
        end,
        claim=function(selected,npcId,jobId)
            calls[#calls+1]={kind=selected.category,npc=npcId,jobId=jobId}
            return 'QUEUED'
        end}
end
check(Public.registerProvider(fakeProvider('hauling')),'fake HAUL provider registers')
check(Public.registerProvider(fakeProvider('cooking')),'fake COOKING provider registers')
local function tick() now=now+require('EmberRoutesProbe/Kernel/TickConfig').discoveryMs+1 Public.tick() end
-- One fresh world per scenario; priorities are re-saved (revision 0) each time.
local function scenario(orderPriorities,membership,haulScore,cookScore,wantCraft)
    root={} busy={} cargo={} records={} craftRecords={} calls={} workers={'alice'}
    scores.hauling=haulScore scores.cooking=cookScore overrides.alice=membership
    Public.prepareRecovery()
    -- A nil orderPriorities models "player never touched priorities": the
    -- fresh world has no saved set, so OrderQuery yields the default 3.
    if orderPriorities then
        check(Public.setPriorities(actor,'s','alice',orderPriorities,0)=='PRIORITY_SAVED','pilot priorities saved')
    end
    if wantCraft then
        check(Public.create(actor,'s','saw',1,nil,Public.requestId())=='ORDER_CREATED','pilot craft order created')
    end
    local before=#calls
    for _=1,12 do if #calls>before then break end tick() end
    check(#calls<=before+1,'one decide dispatches at most one job (queue never drained)')
    return calls[#calls]
end

-- Baseline, no membership overrides: HAUL tier 1 beats COOKING tier 2.
local claimed=scenario({crafting=2,hauling=1,cooking=2},nil,0,5,false)
check(claimed and claimed.kind=='hauling','baseline: tier-1 HAUL wins over tier-2 COOKING')
-- Membership override flips it: OrderStore says HAUL 2 / COOKING 2 (COOKING
-- would win on score 5 vs 0), but stored HAUL 1 wins.
claimed=scenario({crafting=2,hauling=2,cooking=2},{hauling=1},0,5,false)
check(claimed and claimed.kind=='hauling','membership HAUL 1 overrides OrderStore HAUL 2')
check(Public.priorities('alice').hauling==2,'overlay never writes the stored OrderStore priority')
-- Membership blank: HAUL 0 never runs even though OrderStore says tier 1.
claimed=scenario({crafting=2,hauling=1,cooking=2},{hauling=0},0,5,false)
check(claimed and claimed.kind=='cooking','blank HAUL (0) is never dispatched; COOKING runs')
-- Both pilot trades blank: nothing is claimed.
claimed=scenario({crafting=2,hauling=1,cooking=1},{hauling=0,cooking=0},0,5,false)
check(claimed==nil,'both pilot trades blank: no job is dispatched')
-- Same tier, utility decides: COOKING score 5 beats HAUL score 0 at tier 1.
claimed=scenario({crafting=2,hauling=1,cooking=1},nil,0,5,false)
check(claimed and claimed.kind=='cooking','same tier: higher-score COOKING wins by utility')
-- Same tier, utility decides the other way: HAUL score 7 beats COOKING 5.
claimed=scenario({crafting=2,hauling=1,cooking=1},nil,7,5,false)
check(claimed and claimed.kind=='hauling','same tier: higher-score HAUL wins by utility')
-- Default 3: no priorities saved for either pilot trade, both tier 3,
-- COOKING score 5 beats HAUL score 0 by utility.
claimed=scenario(nil,nil,0,5,false)
check(claimed and claimed.kind=='cooking','unset pilot trades run at default 3')
check(Public.priorities('alice').hauling==3 and Public.priorities('alice').cooking==3,'unset pilot trades read back as default 3')
-- Membership COOKING 1 beats OrderStore CRAFT 2 (cooking override works).
claimed=scenario({crafting=2,hauling=2,cooking=2},{cooking=1},0,5,false)
check(claimed and claimed.kind=='cooking','membership COOKING 1 overrides OrderStore COOKING 2')
-- Other trades unchanged: CRAFT tier 1 still beats tier-2 HAUL/COOKING,
-- and a membership HAUL 1 does not disturb CRAFT winning its own tier on
-- score (craft ~0.5 > haul 0).
claimed=scenario({crafting=1,hauling=2,cooking=2},nil,0,5,true)
check(claimed and claimed.kind=='craft','non-pilot CRAFT tier 1 still wins over tier-2 pilot trades')
claimed=scenario({crafting=1,hauling=2,cooking=2},{hauling=1},0,5,true)
check(claimed and claimed.kind=='craft','membership HAUL 1 does not disturb CRAFT winning its tier on score')
print('PASS '..checks..' priority-matrix pilot checks')
