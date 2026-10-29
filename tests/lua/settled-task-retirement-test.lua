local root={} local active={} local held={}
local n=0 local function check(v,label) n=n+1 assert(v,label) end
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}
package.loaded['EmberRoutesProbe/LaborSignals']={watch=function() end}
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return {
 accepting=function() return true end,status=function(_,npc,id) return active[id] end} end}
package.loaded['EmberRoutesProbe/LaborStore']={hasTaskClaims=function(id) return held[id] end}
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Business=require 'EmberRoutesProbe/BusinessJobs'
local function craft(id)
 local r={id=id,npcId='npc',format=3,state='RUNNING',generation=1,settlementId='s',
  produced=0,delivered=0,target=3,materials={},tools={},outputs={},held={}}
 assert(Business.publishCraft(r)) return r
end
local function finish(r) r.state='DONE' r.released=true r.produced=3 r.delivered=3 Business.flush() end
local r=craft('first')
local originalObligations=root.taskJobs.byId[r.id].obligations
Business.flush()
check(root.taskJobs.byId[r.id].obligations==originalObligations,'unchanged responsibility table is not rebuilt on every flush')
originalObligations.extra=true Business.flush()
check(root.taskJobs.byId[r.id].obligations~=originalObligations and not root.taskJobs.byId[r.id].obligations.extra,
 'modified responsibility shape is normalized rather than blindly reused')
check(not Business.retire(r.id),'running task retained') finish(r)
active[r.id]={state='STOPPING'} check(not Business.retire(r.id),'body stop still pending retains completed work') active[r.id]=nil
held[r.id]=true check(not Business.retire(r.id),'physical or capacity claims prevent retirement') held[r.id]=nil
r.uncertain=true Business.flush() check(not Business.retire(r.id),'unknown native effects retained')
r.uncertain=nil Business.flush()
root.executionSave={state='BLOCKED',byNpc={}}
check(not Business.retire(r.id),'save barrier prevents deletion')
root.executionSave={state='CAPTURED',byNpc={npc={jobId=r.id}}}
local next=craft('next')
check(Business.retire(r.id) and Business.crafts().npc==next and not root.executionSave.byNpc.npc,
 'retiring predecessor preserves successor and clears obsolete save reference')
check(not Jobs.current():get(r.id) and #Jobs.current():forNpc('npc')==1,'store and NPC indexes agree after retirement')
check(not Jobs.current():update(r.id,1,{state='RUNNING'}),'late update cannot revive erased work')
finish(next)
root.publicWork={orders={o={jobId=next.id}}}
check(not Business.retire(next.id),'public link cannot be orphaned by generic cleanup')
check(Business.retire(next.id,'o'),'public owner can retire its confirmed settled job') root.publicWork.orders={}
local care=require('EmberRoutesProbe/SelfCareRecord').create('care','npc')
check(Jobs.current():create(care),'persistent personal routine created')
r=craft('resume') finish(r)
care=Jobs.current():get('care') care.payload.resume={jobId=r.id,state='STOP_CONFIRMED'}
assert(Jobs.current():update(care.id,care.revision,{payload=care.payload}))
check(not Business.retire(r.id),'uncompleted personal restore relation retained')
care=Jobs.current():get('care') care.payload.resume.state='RESTORE_QUEUED'
assert(Jobs.current():update(care.id,care.revision,{payload=care.payload}))
check(Business.retire(r.id) and Jobs.current():get('care').payload.resume.state=='RESTORED',
 'completed restored work discharges late observation without deleting personal custody')
local h={id='haul',npcId='other',kind='EXPLICIT_TRANSFER',format=1,state='DONE',items={},generation=1}
check(Business.publishHaul(h) and Business.retire(h.id) and not Business.hauls().tasks[h.id],'settled hauling retires too')
for i=1,600 do local row=craft('cycle-'..i) finish(row) assert(Business.retire(row.id)) end
check(#Jobs.current():forNpc('npc')==1 and Jobs.current():get('care')~=nil,'600 completed jobs do not exhaust capacity or erase personal routine')
local reopened=assert(require('EmberRoutesProbe/JobStore').open(root))
check(#reopened:forNpc('npc')==1 and not reopened:get('cycle-600'),'save-table reopen contains only unresolved/recurring work')
print('PASS '..n..' settled-task lifecycle checks; native effects mocked')
