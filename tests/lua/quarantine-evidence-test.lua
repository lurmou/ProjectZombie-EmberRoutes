-- Evidence facts only; no PZ disk codec or native game execution is exercised.
package.path='./Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;./Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;'..package.path
local E=require 'EmberRoutesProbe/QuarantineEvidence'
local count=0
local function check(value,message) count=count+1 assert(value,message) end
local function eq(a,b,message) check(a==b,message..' expected='..tostring(b)..' actual='..tostring(a)) end
local facts={participants={'A','B'},conflicts={['item:1']=true},nested={before=2,after=1,verified=false}}
local saved,report=E.snapshot(facts)
check(report.complete,'Nested facts are complete')
eq(saved.participants[2],'B','Array retained')
eq(saved.conflicts['item:1'],true,'Set retained')
eq(saved.nested.verified,false,'False retained')
facts.participants[1]='changed'
eq(saved.participants[1],'A','Caller mutation is detached')
saved.nested.before=99
eq(facts.nested.before,2,'Internal mutation does not affect caller')
local numericKeys,numericReport=E.snapshot({[-1.5]='coordinate fact'})
check(numericReport.complete,'Finite numeric keys supported by installed codec remain legal')
eq(numericKeys[-1.5],'coordinate fact','Negative/fractional fact keys retained')
local invalid={
    {'function',function() end},
    {'thread',coroutine.create(function() end)},
    {'userdata',io.stdout},
    {'metatable',setmetatable({safe=1},{})},
    {'token',{taskId='A',generation=1,claimId='A:c1',resources={}}},
    {'nan',0/0}, {'infinity',math.huge}
}
local cycle={};cycle.self=cycle
invalid[#invalid+1]={'cycle',cycle}
invalid[#invalid+1]={'boolean key',{[true]='not supported by installed codec'}}
local deep={};local cursor=deep
for i=1,E.MAX_DEPTH+2 do cursor.child={} cursor=cursor.child end
invalid[#invalid+1]={'depth',deep}
local many={}
for i=1,E.MAX_TABLE_ENTRIES+1 do many[i]=i end
invalid[#invalid+1]={'table entries',many}
local nodes={}
for i=1,16 do nodes[i]={} for j=1,1024 do nodes[i][j]=j end end
invalid[#invalid+1]={'nodes',nodes}
local strings={}
for i=1,8 do strings[i]=string.rep('x',E.MAX_STRING_LENGTH) end
invalid[#invalid+1]={'string bytes',strings}
invalid[#invalid+1]={'string length',string.rep('x',E.MAX_STRING_LENGTH+1)}
for _,case in ipairs(invalid) do
    local partial,r=E.snapshot({good={jobId='A'},bad=case[2]})
    check(not r.complete,'Reject '..case[1])
    check(#r.errors>0 and type(r.errors[1].path)=='string','Diagnostic path for '..case[1])
    check(#r.errors<=E.MAX_ERRORS,'Bounded diagnostics for '..case[1])
    -- Global budgets may exhaust before another sibling is visited.
    if case[1]=='function' then eq(partial.good.jobId,'A','Safe sibling preserved') end
end
local shared={value=1}
local aliases,aliasReport=E.snapshot({a=shared,b=shared})
check(aliasReport.complete,'Repeated reference without a cycle is legal')
check(aliases.a~=aliases.b and aliases.a~=shared,'Repeated references copied independently')
local errors={}
for i=1,64 do errors[i]=function() end end
local _,bounded=E.snapshot(errors)
eq(#bounded.errors,E.MAX_ERRORS,'Diagnostic list is capped')
check(bounded.omittedErrors>0,'Excess diagnostics counted without storing raw values')

local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local function boot(world)
    Registry.data=function() return world end
    for _,name in ipairs({'TaskJobs','BusinessJobs','LaborStore'}) do package.loaded['EmberRoutesProbe/'..name]=nil end
    local s=require('EmberRoutesProbe/LaborStore');s.data();return s
end
local function worldWithItem(item)
    local world={containers={},taskJobs={format=1,byId={}}}
    local s=boot(world);local c=s.claimsInstance()
    local t=c:acquireNew('evidence-job',1,{'item:'..item})
    check(c:reserve(t,'evidence-bin',item,3,100),'Reserve protected capacity')
    return world,s,c,t
end
local world,s,c,t=worldWithItem(27001)
local input={participants={'A','B'},conflicts={['item:27001']=true}}
check(s.quarantineResource('item:27001','FACTS',input),'Valid quarantine succeeds')
input.participants[1]='changed'
eq(world.quarantineResources['item:27001'].evidence.participants[1],'A','Creation stores detached evidence')
local read,readReport=s.quarantineRecord('item:27001')
check(readReport.complete,'Read snapshot is complete')
read.evidence.participants[1]='changed-read'
read.evidenceReport.complete=false
eq(world.quarantineResources['item:27001'].evidence.participants[1],'A','Read cannot modify internal evidence')
check(world.quarantineResources['item:27001'].evidenceReport.complete,'Read cannot corrupt internal report')

for i,case in ipairs(invalid) do
    local w,store,kernel,token=worldWithItem(27100+i)
    local key='item:'..(27100+i)
    local ok=store.quarantineResource(key,'INVALID',{good='retained',bad=case[2]})
    check(ok,'Invalid creation evidence still protects original: '..case[1])
    eq(store.resourceOwner(key).kind,'SYSTEM_QUARANTINE','System ownership retained')
    check(not w.quarantineResources[key].evidenceReport.complete,'Incomplete marker persisted')
    local revision=kernel.revision
    local record=w.quarantineResources[key]
    local released,why,diagnostic=store.unquarantineResource(key,{reason='ATTEMPT',evidence={clean=true}})
    check(not released and why=='QUARANTINE_EVIDENCE_INCOMPLETE','Clean new evidence cannot override incomplete creation')
    check(diagnostic and not diagnostic.complete,'Rejected release returns safe diagnostic facts')
    diagnostic.complete=true
    check(not record.evidenceReport.complete,'Caller cannot repair completeness by mutating returned report')
    eq(kernel.revision,revision,'Failed release does not change claims revision')
    eq(kernel.capacity['evidence-bin'].total,3,'Failed release retains capacity')
    eq(w.quarantineResources[key],record,'Failed release retains persistent record')
    eq(record.status,'ACTIVE','Failed release never enters RESOLVING')
    eq(store.resourceOwner(key).kind,'SYSTEM_QUARANTINE','Rejected release retains system owner')
    eq(w.quarantineAudit,nil,'Failed release writes no success audit')
end

-- Check both evidence argument forms and a real persistent Job revision.
world={containers={},taskJobs={format=1,byId={}}}
s=boot(world);c=s.claimsInstance()
check(s.createClaimedJob({id='durable',npcId='npc',providerType='CRAFT',scopeId='local-world',
    revision=1,state='PREPARING',effects='KNOWN',obligations={asset=true},
    payload={format=4,sequence=0,recipeId='Base.MakeAxe',target=1,produced=0,materials={{id=27300}},
	tools={},outputs={},claims={'item:27300'},reservation={key='evidence-bin',items={[27300]=3},free=100}}}),
    'Create real CRAFT Job through authority')
check(require('EmberRoutesProbe/TaskJobs').current():update('durable',1,
    {state='RECONCILE_REQUIRED',effects='UNKNOWN'}),'Record durable reconciliation responsibility')
check(s.quarantineResource('item:27300','VALID',{proof=true}),'Valid original evidence')
for _,case in ipairs(invalid) do
    local rev=c.revision
    local ok=s.unquarantineResource('item:27300',{evidence={bad=case[2]}})
    check(not ok,'Invalid nested release evidence rejected: '..case[1])
    check(not s.unquarantineResource('item:27300',{reason='ATTEMPT'},{bad=case[2]}),
	'Invalid explicit release evidence rejected: '..case[1])
    eq(c.revision,rev,'Invalid incoming evidence leaves claims unchanged')
    eq(world.taskJobs.byId.durable.revision,2,'Persistent Job revision unchanged')
    check(world.taskJobs.byId.durable.obligations.asset,'Persistent responsibility unchanged')
end
local explicit={proof={observed=true}}
local removedRecord=world.quarantineResources['item:27300']
check(s.unquarantineResource('item:27300',{reason='VERIFIED'},explicit),'Normal release succeeds')
explicit.proof.observed=false
eq(world.quarantineAudit['item:27300'].evidence.proof.observed,true,'Completed audit detached from caller')
removedRecord.resolvingEvidence.proof.observed=false
eq(world.quarantineAudit['item:27300'].evidence.proof.observed,true,'Old internal intent cannot modify completed history')
local audit=s.quarantineAuditRecord('item:27300')
audit.evidence.proof.observed=false
eq(world.quarantineAudit['item:27300'].evidence.proof.observed,true,'Audit reader cannot change history')

-- RESOLVING recovery snapshots the newly derived interrupted evidence. Existing
-- completed historical audit entries must remain byte-for-byte/table untouched.
local original={nested={proof='before'},bad=function() end}
local historical={evidence={untouched='historical',bad=function() end}}
world={containers={},taskJobs={format=1,byId={}},quarantineAudit={old=historical},quarantineResources={
    ['item:27400']={status='RESOLVING',originalTaskId='A',originalClaimId='A:c1',capacityKey='recover-bin',
	capacityItemId=27400,capacityAmount=3,resolvingEvidence=original,resolution={reason='interrupted'}}}}
s=boot(world)
original.nested.proof='changed'
local q=world.quarantineResources['item:27400']
eq(q.interruptedEvidence.nested.proof,'before','Recovery detaches interrupted evidence')
check(not q.interruptedEvidenceReport.complete,'Recovery preserves incompleteness')
eq(q.status,'ACTIVE','Recovery retains quarantine')
check(not s.unquarantineResource('item:27400','ATTEMPT'),'Incomplete interrupted evidence blocks release')
eq(s.claimsInstance().capacity['recover-bin'].total,3,'Recovery retains capacity')
eq(world.quarantineAudit.old,historical,'Historical audit was not migrated')
local historyView,historyReport=s.quarantineAuditRecord('old')
check(not historyReport.complete,'Invalid legacy audit is diagnosed on read')
eq(historyView.evidence.untouched,'historical','Safe legacy audit facts remain inspectable')
eq(world.quarantineAudit.old,historical,'Read-only diagnosis does not migrate history')
local legacy={good='old',bad=function() end}
world={containers={},taskJobs={format=1,byId={}},quarantineResources={['item:27401']={status='ACTIVE',evidence=legacy}}}
s=boot(world)
eq(world.quarantineResources['item:27401'].evidence,legacy,'Legacy active evidence is not rewritten on boot')
check(not s.unquarantineResource('item:27401','ATTEMPT'),'Invalid legacy evidence cannot authorize release')
eq(world.quarantineResources['item:27401'].evidence,legacy,'Rejection does not clean legacy evidence')
world,s,c,t=worldWithItem(27402)
check(s.quarantineResource('item:27402','INCOMPLETE',{safe='kept',bad=cycle}),'Create incomplete record')
local detached,worldReport=E.snapshot(world)
check(worldReport.complete,'Partial evidence plus its diagnostic report is serializable')
s=boot(detached)
check(not s.unquarantineResource('item:27402',{evidence={verified=true}}),'Cold boot cannot launder incomplete evidence')
eq(s.claimsInstance().capacity['evidence-bin'].total,3,'Cold boot retains incomplete-record capacity')
local qAfter=detached.quarantineResources['item:27402']
local _,resnapshot=E.snapshot(qAfter.evidence,qAfter.evidenceReport)
check(not resnapshot.complete and resnapshot.recordedIncomplete,'Repeated snapshots preserve incompleteness')
check(s.quarantineResource('item:27402','REPEATED',{clean='new facts'}),'Repeated quarantine remains protective')
check(not s.unquarantineResource('item:27402',{evidence={verified=true}}),
    'Repeated quarantine with clean input cannot erase prior incomplete evidence')
local repeated=detached.quarantineResources['item:27402']
eq(repeated.evidenceEvents.events[1].evidence.safe,'kept','Repeated quarantine preserves prior safe facts')
eq(repeated.evidence.clean,'new facts','Repeated quarantine preserves new safe facts')
world,s,c,t=worldWithItem(27403)
check(s.quarantineResource('item:27403','PENDING',{proof=true}),'Create pending-resolution fixture')
local pending=world.quarantineResources['item:27403']
pending.status='RESOLVING'
pending.resolvingEvidence={bad=function() end}
check(not s.unquarantineResource('item:27403',{evidence={clean=true}}),'New input cannot overwrite incomplete pending evidence')
eq(pending.status,'RESOLVING','Failed gate leaves existing pending status unchanged')
eq(c.capacity['evidence-bin'].total,3,'Pending evidence rejection retains capacity')

-- F1: internal event wrappers must not consume the caller's payload depth budget.
world,s,c,t=worldWithItem(28000)
local deepest={proof=true};local branch=deepest
for i=1,E.MAX_DEPTH do branch.child={} branch=branch.child end
check(select(2,E.snapshot(deepest)).complete,'Fixture reaches the legal payload depth')
for i=1,20 do
    check(s.quarantineResource('item:28000','REPEAT',deepest),'Protect repeated quarantine '..i)
    check(world.quarantineResources['item:28000'].evidenceReport.complete,'Legal repeat stays complete '..i)
end
local view,viewReport=s.quarantineRecord('item:28000')
check(viewReport.complete,'Reading event history does not consume payload depth')
eq(#view.evidenceEvents.events,20,'Fixed-level history keeps all twenty events')
view.evidenceEvents.events[1].evidence.proof=false
check(world.quarantineResources['item:28000'].evidenceEvents.events[1].evidence.proof,'Event read is detached')
local retained=s.quarantineRecord('item:28000')
world={containers={},taskJobs={format=1,byId={}},quarantineResources={['item:28000']=retained}}
s=boot(world)
eq(s.claimsInstance().capacity['evidence-bin'].total,3,'Twenty-event reload preserves capacity')
check(s.unquarantineResource('item:28000','VERIFIED'),'Twenty healthy events still allow normal release')
local archive,archiveReport=s.quarantineAuditRecord('item:28000')
check(archiveReport.complete,'Completed history can be read at full payload depth')
eq(#archive.evidenceEvents.events,20,'Completion preserves detached event history')
retained.evidenceEvents.events[1].evidence.proof=false
check(archive.evidenceEvents.events[1].evidence.proof,'Removed internal record cannot alter completed history')

world,s,c,t=worldWithItem(28001)
for i=1,E.MAX_EVENTS do check(s.quarantineResource('item:28001','LIMIT',{event=i}),'Append bounded event') end
check(world.quarantineResources['item:28001'].evidenceReport.complete,'History is complete at its exact limit')
check(s.quarantineResource('item:28001','LIMIT',{event=E.MAX_EVENTS+1}),'History overflow still protects original')
local limited=world.quarantineResources['item:28001']
check(not limited.evidenceReport.complete,'Overflow is explicitly incomplete')
eq(#limited.evidenceEvents.events,E.MAX_EVENTS,'Stored event count remains bounded')
eq(limited.evidenceEvents.omittedEvents,1,'Overflow count is explicit')
check(not s.unquarantineResource('item:28001','ATTEMPT'),'Overflow cannot silently discard unresolved history')

world={containers={},taskJobs={format=1,byId={}}};s=boot(world);c=s.claimsInstance()
check(s.createClaimedJob({id='duplicate-add',npcId='npc',providerType='CRAFT',scopeId='local-world',
    revision=1,state='PREPARING',effects='KNOWN',obligations={},payload={format=4,sequence=0,
	recipeId='Base.MakeAxe',target=1,produced=0,materials={{id=28200}},tools={},outputs={},claims={'item:28200'}}}),
    'Create duplicate-add fixture through authority')
local jobs=require('EmberRoutesProbe/TaskJobs').current()
local proposal=jobs:get('duplicate-add').payload
proposal.materials[#proposal.materials+1]={id=28201};proposal.claims[#proposal.claims+1]='item:28201'
local duplicateKeys={} for i=1,9 do duplicateKeys[i]='item:28201' end
local update=jobs.update;local reachedCAS=false
jobs.update=function() reachedCAS=true return false,'FORCED_CAS_FAILURE' end
local accepted,why=s.mutateJob('duplicate-add',1,proposal,{addKeys=duplicateKeys})
jobs.update=update
check(not accepted and why=='RESOURCE_DUPLICATED','Duplicate addKeys rejected explicitly')
check(not reachedCAS,'Duplicate input rejected before CAS')
eq(c.owners['item:28201'],nil,'Duplicate input acquires no new resource')
eq(world.quarantineResources['item:28201'],nil,'Duplicate input creates no repeated quarantine')
eq(jobs:get('duplicate-add').revision,1,'Duplicate input preserves Job revision')

local ordinary,ordinaryReport=E.snapshot({kind='SYSTEM_QUARANTINE',note='historical diagnostic fact'})
check(ordinaryReport.complete and ordinary.kind=='SYSTEM_QUARANTINE','Kind string alone is not a runtime token')
local _,systemOwner=c:quarantine('item:28200')
check(not select(2,E.snapshot(systemOwner)).complete,'Actual SYSTEM_QUARANTINE owner remains rejected')

-- Identity collision annotation must preserve incompleteness in old evidence.
world={nextClaimSeq=100,containers={},taskJobs={format=1,byId={}},quarantineResources={
    ['item:28400']={status='ACTIVE',originalTaskId='other-task',originalClaimId='collision-task:c1',
	evidence={safe='kept',bad=function() end}}}}
world.taskJobs.byId['collision-task']={id='collision-task',npcId='npc-collision',providerType='CRAFT',
    scopeId='local-world',revision=1,state='RUNNING',effects='KNOWN',obligations={},claimId='collision-task:c1',
    payload={format=4,sequence=0,recipeId='Base.MakeAxe',target=1,produced=0,materials={{id=28401}},
	tools={},outputs={},claims={'item:28401'}}}
s=boot(world)
local conflicted=world.quarantineResources['item:28400']
eq(conflicted.evidence.safe,'kept','Collision annotation retains old safe evidence')
check(not conflicted.evidenceReport.complete,'Collision annotation preserves incomplete status')
check(conflicted.evidence.identityCollisions['collision-task']~=nil,'Collision participants still recorded')
eq(s.getToken('collision-task'),nil,'Colliding task does not obtain a token')
check(not s.unquarantineResource('item:28400','ATTEMPT'),'Collision cannot erase old evidence failure')
eq(s.resourceOwner('item:28400').kind,'SYSTEM_QUARANTINE','Combined failure keeps system ownership')
print('PASS '..count..' Evidence snapshot/creation/release/recovery/read-only checks; PZ disk save NOT RUN')
