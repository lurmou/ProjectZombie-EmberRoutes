-- P0 pilot 1/15: emergency short-circuit (RimWorld): decide returns before
-- the provider scan when the NPC needs medical care, is extremely
-- hungry/thirsty, or is severely injured. SelfCare's MEDICAL handling and
-- the ordinary enter thresholds are pinned unchanged below.
-- Run from the repo root: lua tests/lua/p1-pilot-emergency-shortcircuit-test.lua
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local checks=0
local function check(v,s) checks=checks+1 assert(v,s) end

-- ---- NeedsPolicy: emergency predicates and untouched SelfCare semantics ----
local Policy=require 'EmberRoutesProbe/SelfCare/NeedsPolicy'
check(Policy.EMERGENCY.HUNGER==0.90,'emergency hunger threshold pinned at 0.90')
check(Policy.EMERGENCY.THIRST==0.90,'emergency thirst threshold pinned at 0.90')
check(Policy.EMERGENCY.HEALTH==50,'emergency health threshold pinned at 50')
check(Policy.medicalEmergency(nil)==false,'no medical facts is not a medical emergency')
check(Policy.medicalEmergency({})==false,'empty medical facts is not a medical emergency')
check(Policy.medicalEmergency({needsCare=false})==false,'needsCare false is not a medical emergency')
check(Policy.medicalEmergency({needsCare=true})==true,'needsCare true is a medical emergency')
check(Policy.medicalEmergency({needsCare=true,deep=true,health=100})==true,'needsCare true with deep wound is a medical emergency')
check(Policy.extremeNeed(nil)==false,'missing sample is not an extreme need')
check(Policy.extremeNeed({})==false,'missing need fields are not an extreme need')
check(Policy.extremeNeed({hunger=0.89,thirst=0.05})==false,'hunger just below emergency is not extreme')
check(Policy.extremeNeed({hunger=0.90,thirst=0.05})==true,'hunger at emergency is extreme')
check(Policy.extremeNeed({hunger=0.95,thirst=0.05})==true,'hunger past emergency is extreme')
check(Policy.extremeNeed({hunger=0.05,thirst=0.89})==false,'thirst just below emergency is not extreme')
check(Policy.extremeNeed({hunger=0.05,thirst=0.90})==true,'thirst at emergency is extreme')
check(Policy.extremeNeed({hunger=0/0,thirst=0.05})==false,'NaN hunger is not an extreme need')
check(Policy.severeInjury(nil)==false,'no medical facts is not a severe injury')
check(Policy.severeInjury({})==false,'empty medical facts is not a severe injury')
check(Policy.severeInjury({needsCare=false,deep=false,health=100})==false,'healthy facts are not a severe injury')
check(Policy.severeInjury({needsCare=false,deep=true,health=100})==true,'deep wound is a severe injury')
check(Policy.severeInjury({needsCare=false,deep=false,health=50})==true,'health at emergency line is a severe injury')
check(Policy.severeInjury({needsCare=false,deep=false,health=51})==false,'health just above emergency line is not a severe injury')
check(Policy.severeInjury({needsCare=false,deep=false,health=0})==true,'health at zero is a severe injury')
check(Policy.severeInjury({needsCare=false,deep=false,health=0/0})==false,'NaN health is not a severe injury')
-- SelfCare MEDICAL semantics untouched: needsCare + MEDICAL offered wins,
-- without the offer it does not, and the EAT enter threshold is unchanged.
local safe={safe=true}
local medicalSample={hunger=0.05,thirst=0.05,fatigue=0.10,endurance=0.90,medical={needsCare=true}}
check(Policy.choose(medicalSample,nil,safe,{MEDICAL=true,EAT=true,DRINK=true,REST=true})=='MEDICAL',
    'SelfCare still chooses MEDICAL when care is needed and offered')
check(Policy.choose(medicalSample,nil,safe,{EAT=true,DRINK=true,REST=true})==nil,
    'SelfCare still does not choose MEDICAL when it is not offered')
local hungrySample={hunger=0.30,thirst=0.05,fatigue=0.10,endurance=0.90}
check(Policy.choose(hungrySample,nil,safe,{EAT=true,DRINK=true,REST=true})=='EAT',
    'EAT enter threshold still forces EAT')
check(Policy.warned({hunger=0.15,fatigue=0.10})==true,'warn level unchanged')

-- ---- Dispatch fixture (minimal public-work-test shape, one worker) ----
local root={} local serial=0 local now=0 local allowed=true local accepting=true
local workers={'alice'} local busy={} local calls={} local records={} local offersHaul={} local cargo={}
local samples={} local medicalFacts={}
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
-- Controllable needs sample and last-observed medical facts per worker.
-- canWork stays healthy in every scenario: eligibility passes, so only the
-- decide-level short-circuit can block a claim (the canWork-cache window
-- the pilot closes). A nil sample models unreadable stats, nil facts model
-- SelfCare not having observed this NPC yet.
package.loaded['EmberRoutesProbe/SelfCare/NeedsObserver']={sample=function(_,id) return samples[id] end}
package.loaded['EmberRoutesProbe/SelfCare/MedicalCare']={lastFacts=function(id) return medicalFacts[id] end}
local Public=require 'EmberRoutesProbe/Work/PublicWork'
local function tick() now=now+require('EmberRoutesProbe/Kernel/TickConfig').discoveryMs+1 Public.tick() end
local normal={hunger=0.05,thirst=0.05,fatigue=0.10,endurance=0.90}
-- One fresh world per scenario; priorities are re-saved (revision 0) each time.
-- Both providers hold work in every scenario: maximum dispatch pressure, so
-- a missing claim can only mean the short-circuit fired.
local function setup(sample,medical)
    root={} busy={} cargo={} records={} craftRecords={} calls={} offersHaul={} workers={'alice'}
    samples.alice=sample medicalFacts.alice=medical
    Public.prepareRecovery()
    check(Public.setPriorities(actor,'s','alice',{crafting=2,hauling=1},0)=='PRIORITY_SAVED','pilot priorities saved')
    check(Public.create(actor,'s','saw',1,nil,Public.requestId())=='ORDER_CREATED','pilot craft order created')
    offersHaul.alice={source='in',destination='out',items={123},producer='LOGISTICS',settlementId='s'}
end
local function scenarioClaim(sample,medical)
    setup(sample,medical)
    local before=#calls
    for _=1,12 do if #calls>before then break end tick() end
    check(#calls==before+1,'exactly one claim is made')
    return calls[#calls]
end
local function scenarioNoClaim(sample,medical)
    setup(sample,medical)
    local before=#calls
    for _=1,12 do tick() end
    check(#calls==before,'no claim is made while the short-circuit holds')
end

-- Baseline: normal NPC claims HAUL at tier 1 over tier-2 CRAFT.
local claimed=scenarioClaim(normal,nil)
check(claimed.kind=='haul','normal NPC claims HAUL at tier 1 over tier-2 CRAFT')
-- 1. MEDICAL: needsCare short-circuits, no provider scan, no claim.
scenarioNoClaim(normal,{needsCare=true,deep=false,health=100,bleeding=false})
-- 2. Extreme hunger short-circuits, no claim.
scenarioNoClaim({hunger=0.90,thirst=0.05,fatigue=0.10,endurance=0.90},nil)
-- 2. Extreme thirst short-circuits, no claim.
scenarioNoClaim({hunger=0.05,thirst=0.95,fatigue=0.10,endurance=0.90},nil)
-- 3. Severe injury: deep wound short-circuits even with full health.
scenarioNoClaim(normal,{needsCare=false,deep=true,health=100,bleeding=false})
-- 3. Severe injury: diffuse damage at the health line short-circuits.
scenarioNoClaim(normal,{needsCare=false,deep=false,health=50,bleeding=false})
-- Boundaries: just below each line, dispatch proceeds unchanged. Hunger
-- 0.89 is still warn-band, so the older low-needs pilot demotes HAUL and
-- CRAFT wins -- the short-circuit is what is absent, not dispatch itself.
claimed=scenarioClaim({hunger=0.89,thirst=0.05,fatigue=0.10,endurance=0.90},nil)
check(claimed.kind=='craft','hunger just below emergency falls through to warn demotion, not the short-circuit')
claimed=scenarioClaim({hunger=0.05,thirst=0.89,fatigue=0.10,endurance=0.90},nil)
check(claimed.kind=='haul','thirst just below emergency still hauls')
claimed=scenarioClaim(normal,{needsCare=false,deep=false,health=51,bleeding=false})
check(claimed.kind=='haul','health just above emergency line still hauls')
-- Fail open: unreadable sample and no medical observation still dispatch.
claimed=scenarioClaim(nil,nil)
check(claimed.kind=='haul','unreadable sample with no medical facts fails open to normal HAUL dispatch')
-- Healthy facts (no care, no deep wound, full health) do not short-circuit.
claimed=scenarioClaim(normal,{needsCare=false,deep=false,health=100,bleeding=false})
check(claimed.kind=='haul','healthy medical facts do not short-circuit dispatch')
-- Recovery: after an emergency scenario the same NPC dispatches again.
scenarioNoClaim({hunger=0.95,thirst=0.05,fatigue=0.10,endurance=0.90},nil)
claimed=scenarioClaim(normal,nil)
check(claimed.kind=='haul','NPC dispatches again once the emergency clears')
print('PASS '..checks..' emergency short-circuit checks; SelfCare MEDICAL semantics unchanged')
