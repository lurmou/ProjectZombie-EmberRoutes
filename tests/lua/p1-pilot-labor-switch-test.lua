-- P0 pilot: per-NPC labor switches (Dwarf Fortress hard gate, not a weight).
-- Run from the repo root: lua5.1 tests/lua/p1-pilot-labor-switch-test.lua
-- Member record carries laborSwitches (stored false = off; missing key =
-- on, so pre-pilot rows read as all-on). decide never discovers a
-- switched-off provider for that NPC, whatever its priority or score;
-- switching a labor off pauses the NPC's current task of that kind through
-- Work.pause, and leaves other labors alone. A reservation made before the
-- switch is dropped instead of claimed.
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local checks=0
local function check(v,s) checks=checks+1 assert(v,s) end

-- ================= Part A: MembershipService member record =================
local rootA={}
local actorA={}
local jobsByNpc={}
local jobService={visitNpc=function(self,id,fn) for _,j in ipairs(jobsByNpc[id] or {}) do fn(j) end end}
local pauseCalls={}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return rootA end,
    id=function() return 'id-a' end}
package.loaded['EmberRoutesProbe/Settlement/SettlementLedger']={data=function() return {factionId='f1'} end,
    authorized=function(a) return a==actorA end}
package.loaded['EmberRoutesProbe/Settlement/MembershipPolicy']={evaluate=function() return {allowed=true} end}
package.loaded['EmberRoutesProbe/Work/LaborSignals']={changed=function() end}
package.loaded['EmberRoutesProbe/Runtime/TaskJobs']={current=function() return jobService end}
package.loaded['EmberRoutesProbe/Work/Work']={pause=function(reason,id) pauseCalls[#pauseCalls+1]={reason=reason,id=id} end}
local Membership=require 'EmberRoutesProbe/Settlement/MembershipService'
local function rev(id) return rootA.npcMembership.byNpc[id].revision end
check(Membership.newWorld()==true,'fresh world creates membership store')
check(Membership.register('alice')==true,'alice registers')
check(Membership.register('bob')==true,'bob registers')
local sw=Membership.laborSwitches('alice')
local n=0 for _ in pairs(sw) do n=n+1 end
check(n==8,'fresh member carries all 8 labor switches')
for _,cat in ipairs({'crafting','hauling','cooking','cleaning','farming','lumberjack','forager','toolReturn'}) do
    check(sw[cat]==true,'fresh member has '..cat..' on')
end
check(Membership.laborSwitches('ghost')==nil,'unknown member has no switches')
check(Membership.laborAllowed('alice','hauling')==true,'fresh member may haul')
check(Membership.laborAllowed('ghost','hauling')==true,'unknown member fails open')
check(Membership.laborAllowed('alice','smithing')==true,'unknown category fails open')
check(Membership.laborAllowed('alice',nil)==true,'nil category fails open')
-- Switch HAUL off: effective off, other labors on, stored key is false only.
check(Membership.setLaborSwitch(actorA,'alice','hauling',false,1)=='LABOR_SWITCH_SAVED','HAUL switched off')
check(Membership.laborAllowed('alice','hauling')==false,'HAUL reads back off')
check(Membership.laborAllowed('alice','cooking')==true,'COOKING stays on')
check(rootA.npcMembership.byNpc.alice.laborSwitches.hauling==false,'off is stored as false')
check(rev('alice')==2,'switch-off bumps the revision')
-- Switch HAUL back on: the stored key is deleted, not stored true.
check(Membership.setLaborSwitch(actorA,'alice','hauling',true,2)=='LABOR_SWITCH_SAVED','HAUL switched back on')
check(Membership.laborAllowed('alice','hauling')==true,'HAUL reads back on')
check((rootA.npcMembership.byNpc.alice.laborSwitches or {}).hauling==nil,'on deletes the stored key')
-- Rejections: providerType key, unknown trade, non-boolean, stale revision,
-- unauthorized actor, unknown member. None bumps the revision.
local r=rev('alice')
check(Membership.setLaborSwitch(actorA,'alice','HAUL',false,r)=='LABOR_SWITCH_CATEGORY_INVALID','providerType HAUL is not a category key')
check(Membership.setLaborSwitch(actorA,'alice','smithing',false,r)=='LABOR_SWITCH_CATEGORY_INVALID','unknown trade rejected')
check(Membership.setLaborSwitch(actorA,'alice','hauling','false',r)=='LABOR_SWITCH_INVALID','string enabled rejected')
check(Membership.setLaborSwitch(actorA,'alice','hauling',nil,r)=='LABOR_SWITCH_INVALID','nil enabled rejected')
check(Membership.setLaborSwitch(actorA,'alice','hauling',false,r+99)=='STALE_MEMBERSHIP','stale revision rejected')
check(Membership.setLaborSwitch({},'alice','hauling',false,r)=='ACCESS_DENIED','unauthorized actor rejected')
check(Membership.setLaborSwitch(actorA,'ghost','hauling',false,1)=='NO_MEMBERSHIP','unknown member rejected')
check(rev('alice')==r,'rejected writes never bump the revision')
-- Pause on switch-off: only the switched-off kind, only while its Job runs.
local function setJobs(id,jobs) jobsByNpc[id]=jobs end
local function pauses() return #pauseCalls end
setJobs('alice',{{providerType='HAUL',state='RUNNING',payload={}}})
check(Membership.setLaborSwitch(actorA,'alice','hauling',false,rev('alice'))=='LABOR_SWITCH_SAVED','HAUL off pauses the running haul')
check(pauses()==1 and pauseCalls[1].reason=='USER' and pauseCalls[1].id=='alice','pause runs once, USER reason, for alice')
-- Already off: a second off-write saves but does not pause again.
check(Membership.setLaborSwitch(actorA,'alice','hauling',false,rev('alice'))=='LABOR_SWITCH_SAVED','HAUL off again still saves')
check(pauses()==1,'already-off switch does not pause again')
check(Membership.setLaborSwitch(actorA,'alice','hauling',true,rev('alice'))=='LABOR_SWITCH_SAVED','HAUL back on')
-- Other labor running: switching HAUL off leaves it alone.
setJobs('bob',{{providerType='COOKING',state='RUNNING',payload={}}})
check(Membership.setLaborSwitch(actorA,'bob','hauling',false,rev('bob'))=='LABOR_SWITCH_SAVED','HAUL off with a cooking job running')
check(pauses()==1,'cooking job is not paused by a HAUL switch-off')
check(Membership.setLaborSwitch(actorA,'bob','cooking',false,rev('bob'))=='LABOR_SWITCH_SAVED','COOKING off pauses the cooking job')
check(pauses()==2 and pauseCalls[2].id=='bob','cooking pause runs for bob')
-- Shared FIELD_WORK kind resolves through the payload category.
setJobs('alice',{{providerType='FIELD_WORK',state='RUNNING',payload={category='farming'}}})
check(Membership.setLaborSwitch(actorA,'alice','cleaning',false,rev('alice'))=='LABOR_SWITCH_SAVED','CLEANING off with a farming job running')
check(pauses()==2,'farming job is not paused by a CLEANING switch-off')
check(Membership.setLaborSwitch(actorA,'alice','farming',false,rev('alice'))=='LABOR_SWITCH_SAVED','FARMING off pauses the farming job')
check(pauses()==3,'farming pause runs')
-- Terminal jobs and non-labor jobs never pause.
setJobs('alice',{{providerType='HAUL',state='DONE',payload={}}})
check(Membership.setLaborSwitch(actorA,'alice','hauling',false,rev('alice'))=='LABOR_SWITCH_SAVED','HAUL off with a DONE haul')
check(pauses()==3,'DONE job is not paused')
setJobs('alice',{{providerType='SELF_CARE',state='RUNNING',payload={}}})
check(Membership.setLaborSwitch(actorA,'alice','cooking',false,rev('alice'))=='LABOR_SWITCH_SAVED','COOKING off with a self-care job running')
check(pauses()==3,'self-care job is not paused')
-- Stored rows validate: non-boolean value or unknown key fails load.
rootA.npcMembership.byNpc.bad={npcId='bad',factionId='f1',context='WAIT',revision=1,laborSwitches={hauling='off'}}
local ok,why=Membership.load()
check(ok==false and why=='MEMBERSHIP_FORMAT_INVALID','string switch value fails load')
rootA.npcMembership.byNpc.bad.laborSwitches={smithing=false}
ok,why=Membership.load()
check(ok==false and why=='MEMBERSHIP_FORMAT_INVALID','unknown switch key fails load')
rootA.npcMembership.byNpc.bad.laborSwitches={hauling=false}
ok,why=Membership.load()
check(ok==true,'stored off switch loads')
rootA.npcMembership.byNpc.bad=nil
-- Old rows without the table load and read as all-on.
rootA.npcMembership.byNpc.old={npcId='old',factionId='f1',context='WAIT',revision=1}
check(Membership.load()==true,'pre-pilot row without a switch table loads')
check(Membership.laborAllowed('old','hauling')==true,'pre-pilot row reads as all-on')
rootA.npcMembership.byNpc.old=nil
-- view() carries a detached copy of the switches.
local view=Membership.view('alice')
check(view.laborSwitches.farming==false,'view carries the stored switches')
view.laborSwitches.farming=true
check(Membership.laborAllowed('alice','farming')==false,'mutating the view never touches the stored row')

-- ============ Part B: decide hard gate + reservation gate ============
-- Minimal public-work-test shape, one worker. Fake HAUL/COOKING providers
-- (re-registered over the real ones in this process only) offer one
-- candidate each with a controllable score; claim just records the call.
local root={} local serial=0 local now=0 local allowed=true local accepting=true
local workers={'alice'} local busy={} local calls={} local records={} local cargo={}
local scores={hauling=0,cooking=0}
local switches={}
local probing={}
local recipe={recipe={getName=function() return 'saw' end},id='saw',name='Saw',product='Base.Plank',yield=3,surface=false}
local actor={getUsername=function() return 'owner' end,getX=function() return 1 end,getY=function() return 1 end,isRecipeKnown=function() return true end,isDead=function() return false end}
local entry={id='s'}
local membershipRows=dofile('tests/lua/membership-fixture.lua')(function() if allowed then return entry end end,workers)
-- Part A stubbed TaskJobs for the pause checks; Part B runs the real
-- JobStore against the fixture root (same as the priority-matrix test),
-- so the stub must not leak across.
package.loaded['EmberRoutesProbe/Runtime/TaskJobs']=nil
package.loaded['EmberRoutesProbe/Settlement/MembershipService'].laborAllowed=function(id,cat)
    return not (switches[id] and switches[id][cat]==false)
end
local function npc(id) return {id=id,getX=function() return 1 end,getY=function() return 1 end,getZ=function() return 0 end,
 getCharacterActions=function() return {isEmpty=function() return true end} end,
 getBodyDamage=function() return {getOverallBodyHealth=function() return 100 end} end} end
local handles={alice=npc('alice')}
local healthy=true
package.loaded['EmberRoutesProbe/SelfCare/HealthAssessment']={canWork=function() return healthy,'HEALTH_NEEDS_CARE' end}
package.loaded['EmberRoutesProbe/Kernel/Boot']={ready=true,runtimeReady=true,hasJava=function() return true end,
    idleStudy=function() end,careProbeWork=function(id) return probing[id] end,
    leisureWorkReady=function() end}
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
package.loaded['EmberRoutesProbe/Work/LaborStore']={custodyForNpc=function() return {} end,custodyEntries=function() return {} end,hasCustody=function() return false end}
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
local function scenario(orderPriorities,off,haulScore,cookScore,wantCraft)
    root={} busy={} cargo={} records={} craftRecords={} calls={} workers={'alice'}
    scores.hauling=haulScore scores.cooking=cookScore switches.alice=off probing.alice=nil
    Public.prepareRecovery()
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

-- Baseline: HAUL tier 1 beats COOKING tier 2.
local claimed=scenario({crafting=2,hauling=1,cooking=2},nil,0,5,false)
check(claimed and claimed.kind=='hauling','baseline: tier-1 HAUL wins over tier-2 COOKING')
-- HAUL switched off: tier-1 HAUL is never dispatched, COOKING runs instead.
claimed=scenario({crafting=2,hauling=1,cooking=2},{hauling=false},0,5,false)
check(claimed and claimed.kind=='cooking','HAUL off: tier-1 HAUL never dispatched; COOKING runs')
-- Both off: nothing is claimed.
claimed=scenario({crafting=2,hauling=1,cooking=1},{hauling=false,cooking=false},0,5,false)
check(claimed==nil,'both trades off: no job is dispatched')
-- Other trades unaffected: CRAFT tier 1 still wins with HAUL off.
claimed=scenario({crafting=1,hauling=1,cooking=2},{hauling=false},0,5,true)
check(claimed and claimed.kind=='craft','HAUL off: non-pilot CRAFT tier 1 still wins')
-- A reservation made before the switch still holds: flip HAUL off while the
-- HAUL offer is reserved under a care probe, and the reservation is dropped
-- instead of claimed (no 15s freeze, no HAUL dispatch).
root={} busy={} cargo={} records={} craftRecords={} calls={} workers={'alice'}
scores.hauling=0 scores.cooking=5 switches.alice=nil probing.alice=true
Public.prepareRecovery()
check(Public.setPriorities(actor,'s','alice',{crafting=2,hauling=1,cooking=2},0)=='PRIORITY_SAVED','reservation priorities saved')
local before=#calls
for _=1,6 do tick() end
check(#calls==before,'care probe reserves instead of claiming')
switches.alice={hauling=false} probing.alice=nil
for _=1,12 do if #calls>before then break end tick() end
claimed=calls[#calls]
check(claimed and claimed.kind=='cooking','reserved HAUL is dropped after the switch; COOKING runs next')
print('PASS '..checks..' labor-switch pilot checks')
