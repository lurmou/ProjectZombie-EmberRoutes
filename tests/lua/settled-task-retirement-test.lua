-- Settled-task retirement gates on format=4 direct Job envelopes.
-- e8b30c0 retired BusinessJobs.publishCraft/flush: a craft job is now created
-- as a format=4 PRODUCTION envelope in the JobStore (PREPARING, then RUNNING)
-- and settled by the same two-step SETTLING -> DONE commit Production uses.
-- The flush obligations-normalization assertions are deleted with flush.
-- The personal-restore gates are dropped too: current canRetire only blocks on
-- a restore ref whose epoch is current (TaskResume.pending), and retire()
-- discharges a RESTORE_QUEUED ref through SelfCareCommit.update, which needs
-- the Java labor kernel (laborMutate/create/cancel) this host test does not
-- provide. The personal routine itself stays for the capacity checks below.
local root={} local active={} local held={}
local n=0 local function check(v,label) n=n+1 assert(v,label) end
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return root end}
package.loaded['EmberRoutesProbe/Work/LaborSignals']={watch=function() end}
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime']={current=function() return {
 accepting=function() return true end,status=function(_,npc,id) return active[id] end} end}
package.loaded['EmberRoutesProbe/Work/LaborStore']={hasTaskClaims=function(id) return held[id] end}
local Jobs=require 'EmberRoutesProbe/Runtime/TaskJobs'
local Business=require 'EmberRoutesProbe/Work/BusinessJobs'
local function craft(id)
 local r={id=id,npcId='npc',format=4,executor='PRODUCTION',state='RUNNING',generation=1,sequence=1,settlementId='s',
  produced=0,delivered=0,target=3,materials={},tools={},outputs={},claims={},
  requester='fixture',recipeId='fixture',signature='fixture',product='Base.Plank',recipeName='fixture',
  phase='COLLECTING',released=false,requested=3,unitYield=3}
 assert(Jobs.current():create({id=id,npcId='npc',providerType='CRAFT',scopeId='s',
  revision=1,state='PREPARING',effects='KNOWN',obligations={},payload=r}))
 assert(Jobs.current():update(id,1,{state='RUNNING'}))
 return r
end
local function finish(r)
 local job=Jobs.current():get(r.id)
 local p=job.payload p.state='DONE' p.released=true p.produced=3 p.delivered=3
 assert(Jobs.current():update(r.id,job.revision,{state='SETTLING',payload=p}))
 job=Jobs.current():get(r.id)
 assert(Jobs.current():update(r.id,job.revision,{state='DONE',payload=job.payload}))
end
local r=craft('first')
check(not Business.retire(r.id),'running task retained') finish(r)
active[r.id]={state='STOPPING'} check(not Business.retire(r.id),'body stop still pending retains completed work') active[r.id]=nil
held[r.id]=true check(not Business.retire(r.id),'physical or capacity claims prevent retirement') held[r.id]=nil
-- Unknown effects on a settled payload: the plain uncertain flag cannot coexist
-- with released (record contract), so the gate is exercised through
-- controlUncertain, written with the store's recovery write.
local settled=Jobs.current():get(r.id) local payload=settled.payload payload.controlUncertain=true
assert(Jobs.current():adopt(r.id,{payload=payload}))
check(not Business.retire(r.id),'unknown native effects retained')
payload.controlUncertain=nil
assert(Jobs.current():adopt(r.id,{payload=payload}))
root.executionSave={state='BLOCKED',byNpc={}}
check(not Business.retire(r.id),'save barrier prevents deletion')
root.executionSave={state='CAPTURED',byNpc={npc={jobId=r.id}}}
local next=craft('next')
check(Business.retire(r.id) and Business.crafts().npc.id==next.id and not root.executionSave.byNpc.npc,
 'retiring predecessor preserves successor and clears obsolete save reference')
check(not Jobs.current():get(r.id) and #Jobs.current():forNpc('npc')==1,'store and NPC indexes agree after retirement')
check(not Jobs.current():update(r.id,1,{state='RUNNING'}),'late update cannot revive erased work')
finish(next)
root.publicWork={orders={o={jobId=next.id}}}
check(not Business.retire(next.id),'public link cannot be orphaned by generic cleanup')
check(Business.retire(next.id,'o'),'public owner can retire its confirmed settled job') root.publicWork.orders={}
local care=require('EmberRoutesProbe/SelfCare/SelfCareRecord').create('care','npc')
check(Jobs.current():create(care),'persistent personal routine created')
local h={id='haul',npcId='other',kind='EXPLICIT_TRANSFER',format=1,state='DONE',items={},generation=1,source='fixture-source',destination='fixture-target'}
for i=1,600 do local row=craft('cycle-'..i) finish(row) assert(Business.retire(row.id)) end
check(#Jobs.current():forNpc('npc')==1 and Jobs.current():get('care')~=nil,'600 completed jobs do not exhaust capacity or erase personal routine')
local reopened=assert(require('EmberRoutesProbe/Kernel/JobStore').open(root))
check(#reopened:forNpc('npc')==1 and not reopened:get('cycle-600'),'save-table reopen contains only unresolved/recurring work')
print('PASS '..n..' settled-task lifecycle checks; native effects mocked')
