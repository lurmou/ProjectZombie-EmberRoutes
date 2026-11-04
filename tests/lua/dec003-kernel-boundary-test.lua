-- Host tests only admission/dispatch + real Lua record validity, NOT Java parity.
local Contracts=require 'EmberRoutesProbe/JobContracts'
assert(Contracts.register('DEC003_TEST',{validate=function() return true end}))
local Jobs=require 'EmberRoutesProbe/JobStore'
local Commit=require 'EmberRoutesProbe/LaborJobCommit'
local Kernel=require 'EmberRoutesProbe/LaborKernelAvailability'
local n=0
local function check(v,label) n=n+1 assert(v,label) end
local root={}
local jobs=assert(Jobs.open(root))
local function draft(id,state)
    return {id=id,npcId=id,providerType='DEC003_TEST',scopeId=id,revision=1,
        state=state or 'PREPARING',effects='KNOWN',obligations={},payload={claims={}}}
end
for _,state in ipairs({'PREPARING','RUNNING','STOPPING','SUSPENDED','SETTLING','RECONCILE_REQUIRED'}) do
    local j=draft(state) assert(jobs:create(j))
    -- Seed each valid state via its normal state graph.
    local rev=1
    local paths={RUNNING={'RUNNING'},STOPPING={'RUNNING','STOPPING'},SUSPENDED={'SUSPENDED'},
        SETTLING={'SETTLING'},RECONCILE_REQUIRED={'RECONCILE_REQUIRED'}}
    for _,s in ipairs(paths[state] or {}) do local ok,r=jobs:update(j.id,rev,{state=s}) assert(ok,r) rev=r end
    local ok,r=jobs:cancel(j.id,rev,{state='CANCELLED',payload={claims={}}})
    check(ok and r==rev+1 and jobs:get(j.id).state=='CANCELLED','cancel '..state)
end
local j=draft('blocked') j.obligations={original=true} assert(jobs:create(j))
local ok,why=jobs:cancel(j.id,1,{state='CANCELLED'})
check(not ok and why=='CANCEL_BLOCKED_OBLIGATIONS','cancel obligations blocked')
check(jobs:get(j.id).revision==1,'cancel rejection retains revision')
j=draft('unknown') assert(jobs:create(j));assert(jobs:update(j.id,1,{effects='UNKNOWN'}))
ok,why=jobs:cancel(j.id,2,{state='CANCELLED'})
check(not ok and why=='CANCEL_BLOCKED_EFFECTS_UNKNOWN','unknown effects blocked')
j=draft('claims') j.payload.claims={'item:9'} assert(jobs:create(j))
ok,why=jobs:cancel(j.id,1,{state='CANCELLED'})
check(not ok and why=='CANCEL_BLOCKED_CLAIMS','claims blocked')
-- Real persistent personal contract forbids deletion. No SELF_CARE domain migrated.
check(not jobs:removeSettled('blocked',1),'live deletion blocked')
local personal=draft('personal') personal.providerType='SELF_CARE'
assert(jobs:create(personal))
assert(jobs:cancel('personal',1,{state='CANCELLED'}))
check(not jobs:removeSettled('personal',2),'persistent personal never deleted')
local done=draft('done') assert(jobs:create(done))
assert(jobs:update('done',1,{state='SETTLING'}))
check(jobs:update('done',2,{state='DONE'}),'normal DONE validity')
local calls={}
local Store={data=function() error('must refuse before data access') end}
Commit.install(Store,{},function() error('must not allocate') end,function() end)
EmberRoutesProbeJava=nil
for _,method in ipairs({'mutateJob','createClaimedJob','cancelJob'}) do
    ok,why=Store[method]('x',1,{}, {})
    check(not ok and why=='KERNEL_UNAVAILABLE',method..' unavailable')
end
EmberRoutesProbeJava={laborMutate=function(...) calls.mutate={...} return {ok=true,result=2} end,
    laborCreate=function(...) calls.create={...} return {ok=true,result='x'} end,
    laborCancel=function(...) calls.cancel={...} return {ok=false,result='TASK_WRITE_FAILURE',evidence='CANCEL_BLOCKED_CLAIMS'} end}
package.loaded['EmberRoutesProbe/TaskJobs']={current=function() return jobs end}
Store.data=function() end
local state={}
Commit.install(Store,state,function() end,function() end)
check(Store.mutateJob('x',1,{claims={}},{}),'mutate bridge dispatch')
check(Store.createClaimedJob(draft('x')),'create bridge dispatch')
ok,why=Store.cancelJob('x',1,{claims={}}, {})
check(not ok and why=='TASK_WRITE_FAILURE' and calls.cancel,'cancel bridge dispatch')
EmberRoutesProbeJava.laborMutate=function() error('bridge throw') end
ok,why=Store.mutateJob('x',1,{claims={}}, {})
check(not ok and why=='TASK_WRITE_FAILURE','bridge exception converted')
EmberRoutesProbeJava.laborCancel=nil
check(not Kernel.validate() and Kernel.diagnosis=='MISSING_JAVA_ENTRY:laborCancel','partial bridge unavailable')
print('PASS '..n..' DEC003 Lua boundary checks; Java NOT RUN')
