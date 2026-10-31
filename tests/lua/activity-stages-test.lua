-- Pure finite protocol; no native actions or effects are simulated as success.
local S=require 'EmberRoutesProbe/ActivityStages'
local checks=0
local function check(v,m) assert(v,m) checks=checks+1 end
local function clone(t) if type(t)~='table' then return t end local r={} for k,v in pairs(t) do r[k]=clone(v) end return r end
local function definition(mode,optional)
    return {id='talk',roleBehaviorIds={speaker='SPEAK',listener='LISTEN'},completionRule=mode,
        durationGameMinutes=10,timeoutGameMinutes=20,requiredReceipts={'speaker','listener'},optional=optional or false,
        timeoutPolicy=optional and 'SKIP' or 'INCOMPLETE'}
end
local ref={worldId='w',eventId='e',controlEpoch=1,stageEpoch=1}
local actors={a={jobId='ja',participantEpoch=1,roleId='speaker'},b={jobId='jb',participantEpoch=1,roleId='listener'}}
local function begin(mode,optional)
    local p=assert(S.plan({definition(mode,optional)})) return assert(S.begin(p,1,ref,actors,1)),p
end
local function msg(r,npc,status)
    local m=clone(r.scope) local a=r.actors[npc]
    m.npcId=npc m.jobId=a.jobId m.participantEpoch=a.participantEpoch m.actionAttemptId='attempt:'..npc
    m.status=status or 'SUCCEEDED' m.bodyStopped=true m.effectsKnown=true return m
end
check(not S.plan({definition('BOGUS')}),'unknown completion rules are rejected')
local raw=definition('BOTH') raw.timeoutPolicy='SKIP'
check(not S.plan({raw}),'required stages cannot skip on timeout')
raw=definition('BOTH')
check(not S.plan({raw,raw}),'stage ids must be unique')
local r,p=begin('BOTH')
check(not S.supports(p,{SPEAK=true}) and S.supports(p,{SPEAK=true,LISTEN=true}) and not S.supports(nil,{}),'native capability availability is explicit')
p[1].roles.speaker='CHANGED' actors.a.jobId='changed'
check(r.spec.roles.speaker=='SPEAK' and r.actors.a.jobId=='ja','stage freezes definition and participant bindings') actors.a.jobId='ja'
local m=msg(r,'a')
check(not S.record(r,m),'unissued callbacks cannot become receipts')
assert(S.issue(r,m))
for _,key in ipairs({'worldId','eventId','controlEpoch','stageEpoch','participantEpoch','jobId','actionAttemptId'}) do
    local stale=clone(m) stale[key]=type(m[key])=='number' and m[key]+1 or m[key]..':old'
    check(not S.record(r,stale),'stale '..key..' is fenced')
end
assert(S.record(r,m)) assert(S.record(r,m))
check(S.evaluate(r,1.18)=='WAIT','duration alone cannot satisfy BOTH')
local b=msg(r,'b') assert(S.issue(r,b)) assert(S.record(r,b))
check(S.evaluate(r,1.05)=='WAIT' and S.evaluate(r,1.18)=='COMPLETED','BOTH requires duration and every required participant receipt')
assert(S.requestEnd(r,'COMPLETED',1.18))
check(not S.finish(r,1.18),'results alone cannot close a stage before exits')
assert(S.exit(r,m)) assert(S.exit(r,m))
check(r.exitCount==1,'duplicate cleanup does not advance twice')
local unknown=clone(b) unknown.status='UNKNOWN' unknown.effectsKnown=false unknown.bodyStopped=false
assert(S.record(r,unknown))
check(not S.exit(r,b) and not S.finish(r,1.2),'unknown action effects hold cleanup')
check(not S.record(r,b),'unknown outcomes require explicit owner reconciliation')
b.reconciled=true assert(S.record(r,b)) assert(S.exit(r,b)) assert(S.finish(r,1.2))
check(S.valid(r) and r.outcome=='COMPLETED' and not S.record(r,b),'closed stages reject late callbacks')
local nextDef=definition('RECEIPTS') nextDef.id='second'
local two=assert(S.plan({definition('BOTH'),nextDef})) local nextRef=clone(ref) nextRef.stageEpoch=2
local pending=clone(r) pending.state='CLOSING'
check(not S.begin(two,2,nextRef,actors,1.2,pending),'next stage waits for full predecessor closure')
check(S.begin(two,2,nextRef,actors,1.2,r)~=nil,'closed predecessor permits one forward stage transition')
local added=clone(actors) added.c={jobId='jc',participantEpoch=1,roleId='listener'}
check(not S.begin(two,2,nextRef,added,1.2,r),'late admission requires an explicit stage boundary policy')
local missing=clone(actors) missing.a=nil
check(not S.begin(two,2,nextRef,missing,1.2,r),'required participants cannot disappear from the denominator')
local timeout=begin('RECEIPTS')
check(S.evaluate(timeout,1.4)=='INCOMPLETE','required timeout is incomplete, never success')
local optional=begin('RECEIPTS',true)
check(S.evaluate(optional,1.4)=='SKIPPED','optional timeout remains a distinct skipped outcome')
assert(S.requestEnd(optional,'SKIPPED',1.4))
for npc in pairs(optional.actors) do assert(S.exit(optional,msg(optional,npc))) end
assert(S.finish(optional,1.4)) check(optional.outcome=='SKIPPED','skipped phase does not earn a completed outcome')
local duration=begin('DURATION')
check(S.evaluate(duration,1.18)=='COMPLETED','duration-only phases do not invent action receipts')
local failed=begin('RECEIPTS') local f=msg(failed,'a','FAILED') assert(S.issue(failed,f)) assert(S.record(failed,f))
check(S.evaluate(failed,1.01)=='FAILED','required actor failure ends the stage incomplete')
local forged=clone(f) forged.status='SUCCEEDED' forged.reconciled=true
check(not S.record(failed,forged),'reconciliation flag cannot overwrite a known failure')
local max={}
for i=1,256 do max['npc'..i]={jobId='job'..i,participantEpoch=1,roleId=i==1 and 'speaker' or 'listener'} end
check(S.begin(assert(S.plan({definition('BOTH')})),1,ref,max,1)~=nil,'the finite actor bound admits 256 members')
max.extra={jobId='extra',participantEpoch=1,roleId='listener'}
check(not S.begin(assert(S.plan({definition('BOTH')})),1,ref,max,1),'actor count is bounded')
print('activity stages: '..checks..' checks (pure receipt protocol; native actions unverified)')
