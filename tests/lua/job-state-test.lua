-- JobState registry: one vocabulary, one terminal test. Callers never compare
-- job state strings themselves; JobStore and every retained/settled check ask here.
local JobState=require 'EmberRoutesProbe/Kernel/JobState'
local n=0 local function check(ok,label) n=n+1 assert(ok,label) end
for _,state in ipairs({'PREPARING','RUNNING','STOPPING','SUSPENDED','SETTLING','RECONCILE_REQUIRED'}) do
    check(JobState.isValid(state),state..' is a known job state')
    check(not JobState.isTerminal(state),state..' is not terminal')
end
for _,state in ipairs({'DONE','CANCELLED'}) do
    check(JobState.isValid(state),state..' is a known job state')
    check(JobState.isTerminal(state),state..' is terminal')
end
-- Unknown, missing or foreign-machine states are never terminal: a PAUSED
-- order/record or a mistyped value must not read as a finished job.
for _,state in ipairs({'PAUSED','WAITING','COMPLETED','FAILED','REJECTED','',123,true}) do
    check(not JobState.isValid(state),'unknown state rejected: '..tostring(state))
    check(not JobState.isTerminal(state),'unknown state is not terminal: '..tostring(state))
end
check(not JobState.isTerminal(nil),'nil state is not terminal')
check(not JobState.isValid(nil),'nil state is not valid')
-- JobStore itself answers through the registry: an unknown state is refused
-- at creation, and a terminal job refuses further updates.
local Store=require 'EmberRoutesProbe/Kernel/JobStore'
local root={} local store=assert(Store.open(root))
local function job(key,state) return {id=key,npcId='a',providerType='craft',scopeId='s',revision=1,
    state=state,effects='KNOWN',obligations={},payload={step=1}} end
local bad=job('bad','PAUSED')
check(not store:create(bad) and not store:get('bad'),'PAUSED is not a JobStore state')
check(store:create(job('one','PREPARING')),'create accepted')
check(store:update('one',1,{state='SETTLING'}) and store:update('one',2,{state='DONE'}),'settle accepted')
check(not store:update('one',3,{state='RUNNING'}),'terminal job cannot replay through the registry')
check(store:removeSettled('one',3),'terminal job retires')
print('PASS '..n..' JobState registry checks; game/save codec NOT RUN')
