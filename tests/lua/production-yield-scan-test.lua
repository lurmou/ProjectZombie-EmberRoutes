-- Yield scan wiring: Production.tickPending must take its 1s asset-free scan
-- from the Java kernel bridge (productionYieldIds), not from a Lua loop.
-- Reuse the established native-craft substitute, not a second item/recipe model.
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;" .. package.path
local f=dofile('tests/lua/craft-probe-test.lua')
local Yield=require 'EmberRoutesProbe/Crafting/ProductionYield'
local Production=require 'EmberRoutesProbe/Crafting/Production'
local checks=0
local function check(v,label) assert(v,label) checks=checks+1 end
f.Probe.controlledExecution=true
f.Probe.activityContext=nil
f.fresh(3)
-- Drive one manual job to its asset-free suspended state, as in
-- activity-craft-yield-test.lua: run 9, yield after the first unit.
assert(f.Craft.execute(f.actor,'run',nil,f.npc.id,true,{recipeId=f.recipe.key,quantity=9,chain=true,nonPreemptive=true})=='QUEUED')
for _=1,1500 do f.tick(true) if f.nativeCalls()==1 then break end end
local manualId=f.Craft.record(f.npc.id).id
local Resume=require 'EmberRoutesProbe/Runtime/TaskResume'
local m=require('EmberRoutesProbe/Settlement/MembershipService').view(f.npc.id)
f.Probe.activityContext=function() return {eventId='manual-party',settlementId=f.entry.id,
    commandEpoch=Resume.epoch(f.npc.id),membershipRevision=m.revision} end
for _=1,1500 do f.tick(true) if not f.Work.busy(f.npc.id) then break end end
local manual=f.Craft.record(f.npc.id)
check(manual.id==manualId and not manual.released and Yield.assetFree(manual),'manual goal stays in the same asset-free suspended Job')
-- Count bridge scans: the fixture host model stands in for the Java kernel.
local scanCalls=0
local realScan=assert(EmberRoutesProbeJava.productionYieldIds,'fixture bridge lacks productionYieldIds')
EmberRoutesProbeJava.productionYieldIds=function(crafts) scanCalls=scanCalls+1 return realScan(crafts) end
-- Gathering active: scan runs, resume is blocked by the activity context.
Production.tickPending()
check(scanCalls>=1,'yield scan goes through the bridge')
check(Yield.assetFree(manual) and f.nativeCalls()==1,'active gathering prevents automatic work resume')
-- No bridge entry: scan is empty, no resume, no error. (Production.execute
-- refuses without Java anyway, so the empty scan is behaviour-identical.)
f.Probe.activityContext=nil
EmberRoutesProbeJava.productionYieldIds=nil
local callsBefore=scanCalls
for _=1,200 do Production.tickPending() f.tick(true) if manual.released then break end end
check(not manual.released,'missing bridge entry cannot resume')
check(scanCalls==callsBefore,'missing bridge entry is not called')
-- Bridge error: pcall contains it, the round is skipped, no resume, no error.
EmberRoutesProbeJava.productionYieldIds=function() error('boom') end
for _=1,200 do Production.tickPending() f.tick(true) if manual.released then break end end
check(not manual.released,'bridge error cannot resume')
-- Bridge restored: the same job resumes exactly the remaining two units.
EmberRoutesProbeJava.productionYieldIds=realScan
for _=1,2500 do Production.tickPending() f.tick(true) if manual.released then break end end
check(manual.id==manualId and manual.released and manual.state=='DONE' and f.nativeCalls()==3,
    'original manual Job resumes exactly the remaining two units: '..tostring(manual.state)..'/'..tostring(manual.reason)..' calls='..tostring(f.nativeCalls()))
check(Production.status(manual).delivered==9,'manual original-goal progress is not lost or counted twice')
print('production-yield-scan: '..checks..' PASS (native craft/inventory substitutes; no game run)')
