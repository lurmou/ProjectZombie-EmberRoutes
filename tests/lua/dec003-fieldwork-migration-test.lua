-- Lua host parity, not Java/bridge/game execution. Old implementation is test-only.
local Jobs=require 'EmberRoutesProbe/Kernel/JobStore'
local Claims=require 'EmberRoutesProbe/Kernel/LaborClaims'
local checks=0
local function check(v,m) checks=checks+1 assert(v,m) end
local function copy(v) if type(v)~='table' then return v end local r={} for k,x in pairs(v) do r[k]=copy(x) end return r end
local function equal(a,b)
    if type(a)~=type(b) then return false end if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end return true
end
local function setup(old)
    EmberRoutesProbeJava=nil
    local root={} local jobs=assert(Jobs.open(root))
    local st={root=root,claims=Claims.new(),tokens={},fieldTokens={},published=true}
    local S={} local specs={} local context local location='npc' local custody={id='tool',state='HELD'}
    root.toolCustody={format=1,byId={tool=custody}}
    local function alloc(r,id) r.nextClaimSeq=(r.nextClaimSeq or 0)+1 return id..':c'..r.nextClaimSeq end
    local function clean(id) st.tokens[id]=nil st.fieldTokens[id]=nil end
    function S.data() st.published=true return root end
    function S.getToken(id) return st.claims.tokensByTaskId[id] end
    function S.hasTaskClaims(id) return st.claims.tokensByTaskId[id]~=nil end
    function S.resourceOwner(k) return st.claims.owners[k] end
    function S.releaseCapacity(t) return st.claims:releaseCapacity(t) end
    function S.custodyByItem() return custody end
    function S.assignToolUse(_,id) custody.activeJobId=id return true end
    function S.releaseCustody() custody.released=true return true end
    function S.validToolUse() return true end
    local item={getID=function() return 11 end,getFullType=function() return 'Base.Log' end,
        getUnequippedWeight=function() return 2 end,getIsCraftingConsumed=function() return false end}
    local tool={getID=function() return 22 end}
    local function container(where)
        local c={hasRoomFor=function() return true end,getFreeCapacity=function() return 10 end}
        function c:getItems() return {size=function() return location==where and 1 or 0 end,
            get=function() return item end,contains=function(_,i) return i==item and location==where end} end
        function c:getFirstEvalRecurse(f) if f(tool) then return tool end end
        return c
    end
    local inv,dest=container('npc'),container('stock')
    function item:getContainer() return location=='npc' and inv or dest end
    local npc={getInventory=function() return inv end,isDead=function() return false end}
    local actor={isDead=function() return false end}
    local endpoint={id='stock',container=dest}
    local runtime={accepting=function() return true end,owns=function() return false end,
        submit=function(_,spec) specs[#specs+1]=spec return spec end,status=function() return nil end,
        inspect=function() return {state='REJECTED',reason='HOST_REJECT'} end}
    package.loaded['EmberRoutesProbe/Runtime/TaskJobs']={current=function() return jobs end}
    package.loaded['EmberRoutesProbe/Work/LaborStore']=S
    package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return root end,id=function() return 'attempt' end,
        inventoryChanged=function() end,revalidate=function() return true end,accepts=function() return true end,
        logistics=function() return 'STORAGE' end}
    package.loaded['EmberRoutesProbe/Runtime/TaskRuntime']={current=function() return runtime end}
    package.loaded['EmberRoutesProbe/Runtime/Driver']={bindId=function() return {handle=npc} end,valid=function() return true end}
    package.loaded['EmberRoutesProbe/Kernel/Boot']={}
    package.loaded['EmberRoutesProbe/Work/LaborSignals']={changed=function() end}
    package.loaded['EmberRoutesProbe/Settlement/MembershipService']={view=function() return nil end}
    package.loaded['EmberRoutesProbe/Field/FieldSpatial']={}
    package.loaded['EmberRoutesProbe/Crafting/CraftSupply']={returnRoute=function() return {step=function() return endpoint,true end} end}
    package.loaded['EmberRoutesProbe/Work/WorkTransfer']={reachable=function() return true end}
    package.loaded['EmberRoutesProbe/Work/LaborProducers']={eligible=function() return true end}
    package.loaded['TimedActions/ISInventoryTransferAction']=true
    package.loaded['TimedActions/ISGrabItemAction']=true
    package.loaded['EmberRoutesProbe/Field/FieldActions']={new=function(c,hooks)
        return {run=function()
            assert(hooks.valid()) location='stock'
            local ok=hooks.observe(true,true) return ok and 'Success' or 'Failure'
        end,settle=function() return true end}
    end}
    package.loaded['EmberRoutesProbe/Runtime/TaskBusinessStop']={new=function(options) return options end}
    for _,m in ipairs({'FieldWork','FieldContext','FieldSession','FieldCargo','FieldWorkflow','FieldSupplies'}) do
        package.loaded['EmberRoutesProbe/'..m]=nil
    end
    require('EmberRoutesProbe/Work/LaborDomainAdapters').install(S,st,function(_,j) return assert(j.claimId) end,clean,function() return true end)
    if old then
        -- Frozen HEAD 7a36667 FIELD replace; oracle only, no production fallback.
        function S.replaceField(j,t,p)
            if not S.validField(j,t) or not require('EmberRoutesProbe/Field/FieldRecord').valid(p) then return false,'FIELD_JOB_CHANGED' end
            local before=j.payload.claims
            local ok,why=st.claims:replace(t,p.payload.claims) if not ok then return false,why end
            ok,why=jobs:update(j.id,j.revision,{state=p.state,effects=p.effects,obligations=p.obligations,payload=p.payload})
            if not ok then assert(st.claims:replace(t,before)) return false,why end
            return true,jobs:get(j.id)
        end
    else
        st.bridge=dofile('tests/lua/fixtures/dec003-field-kernel-host.lua')
        st.bridge.install(st,alloc,clean)
        require('EmberRoutesProbe/Work/LaborJobCommit').install(S,st,alloc,clean)
    end
    if old then package.loaded['EmberRoutesProbe/Field/FieldCargo']=dofile('tests/lua/fixtures/dec003-pre-kernel-fieldcargo.lua') end
    local F=old and dofile('tests/lua/fixtures/dec003-pre-kernel-fieldwork.lua') or require 'EmberRoutesProbe/Field/FieldWork'
    local def={category='lumberjack',claim=function()
        return {kind='TREE',x=1,y=1,z=0,identity='tree',toolSupply={requirements={
            {role='axe',itemId=22,custodyId='tool',containerId='warehouse'}}}},{'field:tree'}
    end,step=function(c)
        context=c
        if not c.job.payload.attempt then
            assert(c.change(function(j)
                j.payload.attempt={id='attempt',kind='CHOP',state='APPLIED'}
                j.payload.assets={{id=11,fullType='Base.Log',custody='HELD'}}
                j.payload.claims[#j.payload.claims+1]='item:11'
            end))
        end
        return 'Success'
    end}
    local provider=F.provider(def)
    local function claim()
        check(provider.claim({key='offer'},'npc','field',{actor=actor,entry={id='scope'}})=='QUEUED','provider claim')
        return specs[#specs]
    end
    local function getContext()
        -- c is captured through the real context factory; keep domain admission out of native host proof.
        return context
    end
    local Context=require 'EmberRoutesProbe/Field/FieldContext'
    local original=Context.new
    Context.new=function(...)
        local c=original(...) if c then context=c c.valid=function() return c.same() end end return c
    end
    local function snap()
        local owners={} for k,t in pairs(st.claims.owners) do owners[k]={id=t.taskId,claimId=t.claimId} end
        local caps={} for k,b in pairs(st.claims.capacity) do
            caps[k]={} for id,e in pairs(b.entries) do caps[k][id]={amount=e.amount,items=copy(e.items)} end
        end
        return copy({job=jobs:get('field'),claims=owners,capacity=caps,custody=custody,location=location})
    end
    local body={snapshot=function() return {nativeStopped=true} end,stop=function() return true end,clear=function() return true end}
    return {F=F,S=S,J=jobs,st=st,claim=claim,c=getContext,snap=snap,body=body,specs=specs,custody=custody}
end
getTimestampMs=function() return 1000 end
local function main(old)
    local t=setup(old) local spec=t.claim() local out={created=t.snap()}
    check(out.created.job.revision==1 and out.created.job.state=='PREPARING','created revision/state')
    check(spec.start(t.body),'start') out.running=t.snap()
    check(t.J:get('field').revision==2,'start revision')
    -- PREPARE -> WORK through actual FieldSupplies, then output -> cargo through actual Workflow.
    spec.tick() local c=t.c() c.nextTick=0 spec.tick() out.work=t.snap()
    check(c.job.payload.phase=='DELIVER' and c.job.payload.toolSupply==nil,'tool supply/workflow policy')
    c.nextTick=0 spec.tick() out.reserved=t.snap()
    check(c.job.payload.capacity.itemId==11 and out.reserved.capacity.stock.field.items[11]==2,'carried item capacity promise')
    c.nextTick=0 spec.tick() out.delivered=t.snap()
    check(out.delivered.location=='stock' and not c.job.payload.capacity,'real cargo host observation releases capacity')
    c.nextTick=0 spec.tick() out.settling=t.snap()
    check(c.job.state=='SETTLING','workflow settling')
    local stop=spec.stopAdapter({},{} ) check(stop.persist({bodyStopped=true}),'stop persist') out.done=t.snap()
    check(c.job.state=='DONE' and c.job.payload.phase=='SETTLED' and not c.job.payload.toolSupply
        and #c.job.payload.claims==0 and not next(c.job.obligations),'terminal shape')
    check(not next(out.done.claims) and not next(out.done.capacity),'claims/capacity empty')
    check(t.S.finishField(c.job) and t.custody.activeJobId==nil,'terminal custody cleanup after kernel') out.finished=t.snap()
    return out
end
local old,new=main(true),main(false)
for k,v in pairs(old) do check(equal(v,new[k]),'old/kernel parity '..k) end
-- Stale c.change retains the prior job and owners; no proposed addition is published.
for _,legacy in ipairs({true,false}) do
    local t=setup(legacy) t.claim() local c=t.c()
    check(c.change(function(j) j.payload.reason='NEW_REVISION' end),'advance revision')
    local stale=copy(c.job) stale.revision=stale.revision-1 c.job=stale
    local before=t.snap()
    check(not c.change(function(j) j.payload.claims[#j.payload.claims+1]='item:99' end)
        and equal(before,t.snap()) and not t.st.claims.owners['item:99'],'stale session no partial publish')
end
-- Same-fact re-claim failure after create: actual rollback custody + mutate/cancel.
for _,legacy in ipairs({true,false}) do
    local t=setup(legacy) t.S.claimField=function() return nil,'INJECTED' end
    local p=t.F.provider({category='cleaning',claim=function() return {kind='STAIN',x=0,y=0,z=0,identity='x'},{'target:x'} end})
    check(p.claim({key='offer'},'npc','field',{actor={},entry={id='scope'}})=='FIELD_RESOURCE_RESERVED','claim token compensation')
    check(t.J:get('field').state=='CANCELLED' and t.J:get('field').revision==3,'claim failure two revisions')
end
-- Published prepareRecovery UNKNOWN commits once; repeated invocation is idempotent.
for _,legacy in ipairs({true,false}) do
    local t=setup(legacy) local spec=t.claim() assert(spec.start(t.body)) local c=t.c()
    assert(c.change(function(j) j.payload.attempt={id='a',kind='CHOP',state='PREPARED',dispatched=true} end))
    t.F.prepareRecovery() local before=t.snap()
    check(before.job.state=='RECONCILE_REQUIRED' and before.job.effects=='UNKNOWN'
        and before.job.payload.attempt.state=='UNKNOWN','published recovery UNKNOWN')
    t.F.prepareRecovery() check(equal(before,t.snap()),'recovery idempotent')
end
-- Preserve both suspended start transitions and both stop transitions.
local t=setup(false) local spec=t.claim() local c=t.c()
assert(c.change(function(j) j.state='SUSPENDED' end)) local rev=c.job.revision
check(spec.start(t.body) and c.job.revision==rev+2,'suspended -> preparing -> running revisions')
-- Explicit rejected runtime and session abandon cancellation entrances use kernel cancel.
t=setup(false)
local rejection=t.F.provider({category='cleaning',claim=function() return {kind='STAIN',x=0,y=0,z=0,identity='x'},{'target:x'} end})
assert(rejection.claim({key='offer'},'npc','field',{actor={},entry={id='scope'}})=='QUEUED')
local retired local remove=t.J.removeSettled
t.J.removeSettled=function(self,id,rev) retired=self:get(id) return remove(self,id,rev) end
t.F.advance({now=1000})
check(retired.state=='CANCELLED' and retired.revision==3 and not t.J:get('field'),'advance rejection uses mutate/cancel then external retirement')
t=setup(false) spec=t.claim() c=t.c() assert(spec.start(t.body))
c.abandon=true
check(spec.stopAdapter({},{}).persist({bodyStopped=true}) and c.job.state=='CANCELLED','session abandon via kernel cancel')
-- Inject CAS refusal after additions: host model single restore; no second publication.
t=setup(false) t.claim() c=t.c() local before=t.snap() local update=t.J.update
t.J.update=function() return false,'INJECTED_REJECT' end
check(not c.change(function(j) j.payload.claims[#j.payload.claims+1]='item:99' end)
    and c.reason=='TASK_WRITE_FAILURE' and equal(before,t.snap()),'CAS rejection rollback')
t.J.update=update
-- A race after the Lua same() admission reaches the kernel stale guard.
t=setup(false) t.claim() c=t.c() before=t.snap()
local mutate=t.S.mutateJob
t.S.mutateJob=function(...)
    local j=t.J:get('field') assert(t.J:update(j.id,j.revision,{payload=j.payload}))
    return mutate(...)
end
check(not c.change(function(j) j.payload.claims[#j.payload.claims+1]='item:99' end)
    and c.reason=='STALE_REVISION' and t.J:get('field').revision==before.job.revision+1
    and equal(before.claims,t.snap().claims) and not t.st.claims.owners['item:99'],'kernel stale rejection after admission')
t.S.mutateJob=mutate
-- Custody release precedes terminal CAS, deliberately not compensated on failure.
t=setup(false) spec=t.claim() c=t.c() assert(spec.start(t.body)) c.abandon=true
t.custody.state='RESERVED' local cancel=t.J.cancel
local terminalAttempts=0
t.J.cancel=function() terminalAttempts=terminalAttempts+1 return false,'INJECTED_TERMINAL_REJECT' end
check(not spec.stopAdapter({},{}).persist({bodyStopped=true}) and terminalAttempts==1
    and t.J:get('field').state=='SETTLING' and t.J:get('field').payload.toolSupply~=nil
    and t.custody.state=='HELD','terminal failure keeps visible custody release; reload required')
t.J.cancel=cancel
-- Pre-publication restore aliases Registry root: evidence of hard-stopped commit path.
local recovery=require 'EmberRoutesProbe/Field/FieldJobRecovery'
local revision=t.J:get('field').revision
recovery.restore({current=t.st.root,rebuilt=t.st.claims,hasConflict=function() return true end,rebuiltField={}})
check(t.J:get('field').effects=='UNKNOWN' and t.J:get('field').revision==revision,'OPEN pre-publication UNKNOWN write reaches root without revision')
-- Fail closed: never use old oracle as fallback.
t=setup(false) EmberRoutesProbeJava=nil
local p=t.F.provider({category='cleaning',claim=function() return {kind='STAIN',x=0,y=0,z=0,identity='x'},{} end})
check(p.claim({key='offer'},'npc','field',{actor={},entry={id='scope'}})=='KERNEL_UNAVAILABLE' and not t.J:get('field'),'missing bridge rejects create')
print('PASS '..checks..' FIELD_WORK host checks; Java, game, disk reload, performance UNVERIFIED')
