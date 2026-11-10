-- P0 pilot: low needs degrade first, forced self-care second (HAUL only).
-- Run from the repo root: lua tests/lua/p1-pilot-lowneeds-haul-test.lua
-- Dispatch-side demotion only: a warn-band NPC's HAUL drops one tier.
-- SelfCare enter/leave/workEnter thresholds are pinned unchanged below.
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local checks=0
local function check(v,s) checks=checks+1 assert(v,s) end

-- ---- NeedsPolicy: warn levels and untouched forced-care thresholds ----
-- Canonical home for the enter pins: the two sleep pilots used to repeat
-- the hunger-just-below-enter and satisfied-needs pins verbatim.
local Policy=require 'EmberRoutesProbe/SelfCare/NeedsPolicy'
local offers={EAT=true,DRINK=true,REST=true,SLEEP=true}
local safe={safe=true}
local working={safe=true,isWorking=true}
check(Policy.warned(nil)==false,'missing sample is not a warning')
check(Policy.warned({})==false,'missing need fields are not a warning')
check(Policy.warned({hunger=0.14,fatigue=0.10})==false,'hunger just below warn is not warned')
check(Policy.warned({hunger=0.15,fatigue=0.10})==true,'hunger at warn is warned')
check(Policy.warned({hunger=0.05,fatigue=0.49})==false,'fatigue just below warn is not warned')
check(Policy.warned({hunger=0.05,fatigue=0.50})==true,'fatigue at warn is warned')
check(Policy.warned({hunger=0.30,fatigue=0.10})==true,'hunger past enter is still warned')
check(Policy.choose({hunger=0.15,thirst=0.05,fatigue=0.10,endurance=0.90},nil,safe,offers)==nil,
    'warn-level hunger alone never forces self-care')
check(Policy.choose({hunger=0.24,thirst=0.05,fatigue=0.10,endurance=0.90},nil,safe,offers)==nil,
    'hunger just below enter does not force EAT')
check(Policy.choose({hunger=0.30,thirst=0.05,fatigue=0.10,endurance=0.90},nil,safe,offers)=='EAT',
    'hunger enter threshold still forces EAT')
check(Policy.choose({hunger=0.40,thirst=0.05,fatigue=0.10,endurance=0.90},nil,working,offers)==nil,
    'working hunger below workEnter still does not force EAT')
check(Policy.choose({hunger=0.51,thirst=0.05,fatigue=0.10,endurance=0.90},nil,working,offers)=='EAT',
    'working hunger workEnter threshold still forces EAT')
check(Policy.choose({hunger=0.05,thirst=0.05,fatigue=0.60,endurance=0.90},nil,safe,offers)==nil,
    'warn-level fatigue alone never forces self-care')
check(Policy.choose({hunger=0.05,thirst=0.05,fatigue=0.71,endurance=0.90},nil,safe,offers)=='SLEEP',
    'fatigue enter threshold still forces SLEEP')
check(Policy.choose({hunger=0.05,thirst=0.05,fatigue=0.80,endurance=0.90},nil,working,offers)==nil,
    'working fatigue below workEnter still does not force SLEEP')
check(Policy.choose({hunger=0.05,thirst=0.05,fatigue=0.86,endurance=0.90},nil,working,offers)=='SLEEP',
    'working fatigue workEnter threshold still forces SLEEP')
check(Policy.choose({hunger=0.05,thirst=0.21,fatigue=0.10,endurance=0.90},nil,safe,offers)=='DRINK',
    'thirst enter threshold untouched (no warn level for DRINK)')
check(Policy.choose({hunger=0.05,thirst=0.05,fatigue=0.10,endurance=0.20},nil,safe,offers)=='REST',
    'endurance enter threshold untouched (no warn level for REST)')
check(Policy.choose({hunger=0.05,thirst=0.05,fatigue=0.10,endurance=0.90},nil,safe,offers)==nil,
    'satisfied needs choose nothing (the sleep entry condition)')

-- ---- Dispatch fixture (minimal public-work-test shape, one worker) ----
local root={} local serial=0 local now=0 local allowed=true local accepting=true
local workers={'alice'} local busy={} local calls={} local records={} local offersHaul={} local cargo={}
local samples={}
local recipe={recipe={getName=function() return 'saw' end},id='saw',name='Saw',product='Base.Plank',yield=3,surface=false}
local actor={getUsername=function() return 'owner' end,getX=function() return 1 end,getY=function() return 1 end,isRecipeKnown=function() return true end,isDead=function() return false end}
local entry={id='s'}
local membershipRows=dofile('tests/lua/membership-fixture.lua')(function() if allowed then return entry end end,workers)
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
package.loaded['EmberRoutesProbe/Logistics/LogisticsService']={publicOffer=function(_,_,n) return offersHaul[n.id] end,
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
-- Controllable needs sample per worker; a nil sample models unreadable stats.
package.loaded['EmberRoutesProbe/SelfCare/NeedsObserver']={sample=function(_,id) return samples[id] end}
local Public=require 'EmberRoutesProbe/Work/PublicWork'
local function tick() now=now+require('EmberRoutesProbe/Kernel/TickConfig').discoveryMs+1 Public.tick() end
local normal={hunger=0.05,thirst=0.05,fatigue=0.10,endurance=0.90}
local hungry={hunger=0.20,thirst=0.05,fatigue=0.10,endurance=0.90}
local tired={hunger=0.05,thirst=0.05,fatigue=0.60,endurance=0.90}
-- One fresh world per scenario; priorities are re-saved (revision 0) each time.
local function scenario(sample,priorities,wantCraft,wantHaul)
    root={} busy={} cargo={} records={} craftRecords={} calls={} offersHaul={} workers={'alice'}
    samples.alice=sample
    -- Initialise the order store for the fresh world before touching
    -- priorities (production create() does this first; this fixture calls
    -- setPriorities first instead).
    Public.prepareRecovery()
    check(Public.setPriorities(actor,'s','alice',priorities,0)=='PRIORITY_SAVED','pilot priorities saved')
    if wantCraft then
        check(Public.create(actor,'s','saw',1,nil,Public.requestId())=='ORDER_CREATED','pilot craft order created')
    end
    if wantHaul then offersHaul.alice={source='in',destination='out',items={123},producer='LOGISTICS',settlementId='s'} end
    local before=#calls
    for _=1,12 do if #calls>before then break end tick() end
    check(#calls==before+1,'exactly one claim is made')
    return calls[#calls]
end

-- Normal NPC, HAUL tier 1 vs CRAFT tier 2: HAUL wins (baseline behaviour).
local claimed=scenario(normal,{crafting=2,hauling=1},true,true)
check(claimed.kind=='haul','normal NPC claims HAUL at tier 1 over tier-2 CRAFT')
-- Warned by hunger: HAUL drops to tier 2, where CRAFT (score > 0) beats HAUL (score 0).
claimed=scenario(hungry,{crafting=2,hauling=1},true,true)
check(claimed.kind=='craft','hungry warn-band NPC claims CRAFT instead of demoted HAUL')
check(Public.priorities('alice').hauling==1,'warn demotion never writes stored priorities')
-- Warned by fatigue alone: same demotion, no hunger involved.
claimed=scenario(tired,{crafting=2,hauling=1},true,true)
check(claimed.kind=='craft','tired warn-band NPC claims CRAFT instead of demoted HAUL')
-- Warned NPC, HAUL only: demotion is not a block, HAUL still runs.
claimed=scenario(hungry,{crafting=2,hauling=1},false,true)
check(claimed.kind=='haul','warned NPC still hauls when nothing else competes')
-- Warned NPC, CRAFT only: non-HAUL work is unaffected by the pilot.
claimed=scenario(hungry,{crafting=2,hauling=1},true,false)
check(claimed.kind=='craft','warned NPC claims CRAFT unaffected when no HAUL competes')
-- Warned NPC, HAUL already at the lowest tier: no further demotion, HAUL still runs.
claimed=scenario(hungry,{crafting=2,hauling=4},false,true)
check(claimed.kind=='haul','warned NPC with HAUL already at tier 4 still hauls')
-- Unreadable sample fails open: no demotion, HAUL at tier 1 wins as normal.
claimed=scenario(nil,{crafting=2,hauling=1},true,true)
check(claimed.kind=='haul','unreadable needs sample fails open to normal HAUL dispatch')
print('PASS '..checks..' low-needs HAUL pilot checks; SelfCare thresholds unchanged')
