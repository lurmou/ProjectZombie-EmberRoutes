-- P0 pilot: NPC sleep (cross-game Factorio §1.3). An NPC with no pending
-- work and no over-threshold need skips the provider discovery pass and
-- only rechecks wake conditions at 1Hz; a new order, a need crossing its
-- (unchanged) enter threshold, or 15s without a full pass wakes it.
-- Run from the repo root: lua tests/lua/p1-pilot-npc-sleep-work-test.lua
-- Fixture is the p1-pilot-lowneeds-haul dispatch shape (one worker), plus
-- a real LaborSignals watch/changed bus (order creation must wake sleepers
-- through the production signal path) and per-provider discover counters.
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local checks=0
local function check(v,s) checks=checks+1 assert(v,s) end

-- NeedsPolicy enter pins live in tests/lua/p1-pilot-lowneeds-haul-test.lua
-- (canonical home). The sleep pilot must never move these: sleep wakes on
-- choose(), it does not re-threshold it. Only the enter pins were repeated
-- here; the warn band is pinned by p1-pilot-lowneeds-haul-test.lua.

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
-- Real watch/changed bus (production shape): order creation must wake a
-- sleeping NPC through Signals.changed, not only through the stamp.
local signalWatchers={}
package.loaded['EmberRoutesProbe/Work/LaborSignals']={changed=function(id)
    for _,w in ipairs(signalWatchers) do w(id) end
end,watch=function(f) signalWatchers[#signalWatchers+1]=f end}
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
local hungry={hunger=0.30,thirst=0.05,fatigue=0.10,endurance=0.90} -- over the EAT enter threshold
-- Per-provider discover counters. The sleep proof is that these stop
-- growing while the NPC sleeps and grow again on wake.
local discoverCalls={hauling=0,crafting=0}
for _,cat in ipairs({'hauling','crafting'}) do
    local p=Public.provider(cat)
    local orig=p.discover
    p.discover=function(env) discoverCalls[cat]=discoverCalls[cat]+1 return orig(env) end
end
local function discovers() return discoverCalls.hauling+discoverCalls.crafting end
-- One fresh world; priorities are re-saved (revision 0) each time.
local function fresh(sample)
    root={} busy={} cargo={} records={} craftRecords={} calls={} offersHaul={} workers={'alice'}
    samples.alice=sample
    -- Initialise the order store for the fresh world before touching
    -- priorities (production create() does this first; this fixture calls
    -- setPriorities first instead).
    Public.prepareRecovery()
    check(Public.setPriorities(actor,'s','alice',{crafting=2,hauling=1},0)=='PRIORITY_SAVED','pilot priorities saved')
end
local function fallAsleep()
    for _=1,4 do tick() end
    check(Public.sleeping('alice')~=nil,'NPC falls asleep with no work and satisfied needs')
end

-- Baseline: a fresh awake NPC still claims work normally.
fresh(normal)
check(Public.create(actor,'s','saw',1,nil,Public.requestId())=='ORDER_CREATED','baseline order created')
local before=#calls
for _=1,12 do if #calls>before then break end tick() end
check(#calls==before+1,'awake NPC still claims work normally')

-- Sleep entry + skip: no further discovery passes while quiet.
fresh(normal)
fallAsleep()
local base=discovers()
for _=1,10 do tick() end
check(discovers()==base,'sleeping NPC runs no further discovery passes over 10 ticks')
check(Public.sleeping('alice')~=nil,'NPC is still asleep after quiet ticks')
check(#calls==0,'sleeping NPC claims nothing while quiet')

-- Wake on new work: order creation (signal + catalog stamp) wakes the
-- sleeper, discovery runs, and the order is claimed.
check(Public.create(actor,'s','saw',1,nil,Public.requestId())=='ORDER_CREATED','wake order created')
local d0=discovers()
for _=1,4 do if discovers()>d0 then break end tick() end
check(discovers()>d0,'new order wakes the sleeper: discovery runs within 4 ticks')
before=#calls
for _=1,12 do if #calls>before then break end tick() end
check(#calls==before+1,'woken NPC claims the new order')
check(Public.sleeping('alice')==nil,'claiming NPC is awake')

-- Wake on need: hunger crossing its enter threshold wakes the sleeper,
-- and it does not re-sleep while hungry.
fresh(normal)
fallAsleep()
samples.alice=hungry
d0=discovers()
for _=1,3 do if discovers()>d0 then break end tick() end
check(discovers()>d0,'need crossing its threshold wakes the sleeper within 3 ticks')
check(Public.sleeping('alice')==nil,'need-woken NPC is awake, not re-slept while hungry')

-- 15s cap: no full discovery pass for ~10s of quiet sleep, then the cap
-- runs one anyway, and the NPC re-sleeps after it finds nothing.
fresh(normal)
fallAsleep()
d0=discovers()
for _=1,20 do tick() end
check(discovers()==d0,'no full discovery pass in the first ~10s of quiet sleep')
for _=1,20 do tick() end
check(discovers()>d0,'the 15s cap runs a full discovery pass even with no wake event')
check(Public.sleeping('alice')~=nil,'NPC re-sleeps after the cap pass finds nothing')

-- Long sleep still wakes on need: past the old 10s idle threshold the
-- pilot sleep (not the 15s IdleDiscovery sleep) still governs, and the
-- recheck stays 1Hz (not the backoff ladder). Hunger is set ~20s after
-- entry -- mid-window for the old 15s sleep, far from its expiry -- so a
-- need crossing wakes within 3 ticks only if the pilot recheck runs.
fresh(normal)
fallAsleep()
for _=1,40 do tick() end
check(Public.sleeping('alice')~=nil,'NPC is still asleep after ~20s of quiet sleep')
samples.alice=hungry
d0=discovers()
for _=1,3 do if discovers()>d0 then break end tick() end
check(discovers()>d0,'need wakes the sleeper within 3 ticks even after ~20s of quiet sleep')
check(Public.sleeping('alice')==nil,'long-sleeping NPC is awake, not re-slept while hungry')

-- Unreadable sample fails open: never sleeps, discovery keeps running.
fresh(nil)
d0=discovers()
for _=1,8 do tick() end
check(Public.sleeping('alice')==nil,'unreadable sample never sleeps')
check(discovers()>d0,'unreadable sample still runs discovery (fail open)')
print('PASS '..checks..' NPC sleep dispatch checks; SelfCare thresholds unchanged')
