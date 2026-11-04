-- DEC-003 BusinessJobs migration: last domain, kernel-routed resume only.
-- Production change is only BusinessJobs.retire routing the SELF_CARE resume
-- write through SelfCareCommit.update (kernel mutate); removeSettled stays
-- the single explicitly-listed kernel-external retirement primitive.
-- Host bridge model only; NOT Java execution, NOT in-game proof.
local JobStore=require 'EmberRoutesProbe/JobStore'
local Claims=require 'EmberRoutesProbe/LaborClaims'
local Record=require 'EmberRoutesProbe/SelfCareRecord'
local n=0 local function check(v,m) n=n+1 assert(v,m) end
local root={} local jobs=assert(JobStore.open(root))
local st={root=root,claims=Claims.new(),tokens={},personalTokens={}}
local held={}
local S={}
function S.data() return root end
function S.getToken(id) return st.claims.tokensByTaskId[id] or st.tokens[id] or st.personalTokens[id] end
function S.hasTaskClaims(id) return held[id] end
function S.claimPersonal() return nil,'NO_CLAIM' end
local function alloc(r,id) r.nextClaimSeq=(r.nextClaimSeq or 0)+1 return id..':c'..r.nextClaimSeq end
local function identity(r,j,id) if not j.claimId then j.claimId=alloc(r,id) end return j.claimId end
local function clean(id) st.tokens[id]=nil st.personalTokens[id]=nil st.claims.tokensByTaskId[id]=nil end
local function stub(name,value) package.loaded['EmberRoutesProbe/'..name]=value end
stub('ContainerRegistry',{data=function() return root end})
stub('TaskJobs',{current=function() return jobs end})
stub('LaborStore',S)
stub('TaskRuntime',{current=function() return {
    accepting=function() return true end,status=function() return nil end} end})
stub('Hauling/HaulManifest',{valid=function() return true end,claimItemIds=function() return {} end})
stub('TaskResume',{pending=function() return true end})
for _,name in ipairs({'SelfCareCommit','BusinessJobs'}) do package.loaded['EmberRoutesProbe/'..name]=nil end
require 'EmberRoutesProbe/LaborDomainAdapters'.install(S,st,identity,clean,function() return true end)
local host=dofile('tests/lua/fixtures/dec003-activity-kernel-host.lua')
host.install(st,alloc,clean)
require 'EmberRoutesProbe/LaborJobCommit'.install(S,st,alloc,clean)
EmberRoutesProbeJava.workerCount=function() return 1 end
EmberRoutesProbeJava.workerIdAt=function() return 'a' end
local Business=require 'EmberRoutesProbe/BusinessJobs'
local SelfCareCommit=require 'EmberRoutesProbe/SelfCareCommit'
-- Settle a CRAFT job through the ordinary JobStore transitions. Format 3 is
-- admission-only for retirement (BuiltinJobContracts), so no full production
-- record is needed; canRetire's format-4 production check does not apply.
local function craft(id,npcId)
    local job={id=id,npcId=npcId,providerType='CRAFT',scopeId='local-world',revision=1,
        state='PREPARING',effects='KNOWN',obligations={},
        payload={format=3,state='RUNNING',released=false,claims={}}}
    check(jobs:create(job),'create '..id)
    for _,state in ipairs({'RUNNING','SETTLING','DONE'}) do
        local cur=jobs:get(id) local p=cur.payload p.state=state
        if state=='DONE' then p.released=true end
        check(jobs:update(id,cur.revision,{state=state,payload=p}),id..' -> '..state)
    end
    local done=jobs:get(id)
    check(done.state=='DONE' and done.payload.state=='DONE' and done.payload.released,'settled '..id)
    return done
end
local function care(id,npcId,resume)
    local job=Record.create(id,npcId)
    check(jobs:create(job),'create personal '..id)
    if resume then
        local cur=jobs:get(id) cur.payload.resume=resume
        check(jobs:update(id,cur.revision,{payload=cur.payload}),'resume queued '..id)
    end
    return jobs:get(id)
end
-- Main chain: settled CRAFT + one RESTORE_QUEUED SELF_CARE resume.
local target=craft('craft-1','npc')
local personal=care('care','npc',{jobId='craft-1',state='RESTORE_QUEUED'})
local beforeRev=personal.revision
root.executionSave={byNpc={npc={jobId='craft-1'}}}
check(Business.canRetire('craft-1'),'canRetire main chain')
check(Business.retire('craft-1'),'retire main chain')
local after=jobs:get('care')
check(after.payload.resume.state=='RESTORED','resume becomes RESTORED')
check(after.revision==beforeRev+1,'resume revision +1, one kernel mutate')
check(jobs:get('craft-1')==nil,'target envelope gone')
check(root.executionSave.byNpc.npc==nil,'save receipt cleared (root table, not a revisioned commit)')
check(not Business.retire('craft-1'),'second pass is a no-op')
check(jobs:get('care').revision==after.revision,'second pass writes nothing')
-- canRetire == false writes nothing: claims held on a settled job.
local blocked=craft('craft-blocked','npc2')
held['craft-blocked']=true
check(not Business.canRetire('craft-blocked'),'claims block retirement')
check(not Business.retire('craft-blocked'),'blocked retire false')
check(jobs:get('craft-blocked')~=nil,'blocked target retained')
held['craft-blocked']=nil
-- Terminal refusal through the kernel path, not a direct JobStore write:
-- a DONE personal job must be refused by JobStore CAS inside laborMutate.
local terminalCare=care('care-term','npc3')
for _,state in ipairs({'SETTLING','DONE'}) do
    local cur=jobs:get('care-term')
    check(jobs:update('care-term',cur.revision,{state=state}),'terminal care -> '..state)
end
local termRev=jobs:get('care-term').revision
local ok,why,evidence=SelfCareCommit.update('care-term',termRev,{payload=jobs:get('care-term').payload})
check(not ok,'terminal personal update refused')
-- Real Java returns TASK_WRITE_FAILURE with JOB_TERMINAL as evidence
-- (LaborCommitKernel.java:175); the host model drops that evidence, so
-- this test proves refusal through the kernel path, not code preservation.
check(why=='TASK_WRITE_FAILURE','terminal refusal code is TASK_WRITE_FAILURE, got '..tostring(why))
check(evidence==nil or evidence=='JOB_TERMINAL','terminal evidence is JOB_TERMINAL when carried, got '..tostring(evidence))
check(jobs:get('care-term').revision==termRev,'terminal job unchanged')
-- Stale-revision failure: a concurrent winner bumps the personal revision
-- inside mutateJob, so the resume commit fails STALE and retire must stop
-- before removeSettled; the target stays and the resume stays queued.
local staleTarget=craft('craft-stale','npc4')
local staleCare=care('care-stale','npc4',{jobId='craft-stale',state='RESTORE_QUEUED'})
local realMutate=S.mutateJob local bumped=false
S.mutateJob=function(id,rev,p,m)
    if not bumped then
        bumped=true
        local cur=jobs:get('care-stale')
        check(jobs:update('care-stale',cur.revision,{payload=cur.payload}),'concurrent winner bumps personal revision')
    end
    return realMutate(id,rev,p,m)
end
check(not Business.retire('craft-stale'),'stale resume stops retirement')
check(jobs:get('craft-stale')~=nil,'stale target retained')
check(jobs:get('care-stale').payload.resume.state=='RESTORE_QUEUED','stale resume still queued, not falsely RESTORED')
S.mutateJob=realMutate
-- Batch path: a settled job with no personal resume retires via retireSettled.
craft('craft-batch','npc5')
check(Business.retireSettled(10)>=1,'retireSettled retires settled jobs')
check(jobs:get('craft-batch')==nil,'batch target gone')
print('PASS '..n..' businessjobs migration checks; bridge model only')
