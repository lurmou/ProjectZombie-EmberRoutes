local Store=require 'EmberRoutesProbe/JobStore'
local n=0 local function check(ok,label) n=n+1 assert(ok,label) end
local root={} local store=assert(Store.open(root))
local function job(key) return {id=key,npcId='a',providerType='craft',scopeId='s',revision=1,state='PREPARING',
    effects='KNOWN',obligations={},payload={step=1}} end
local a=job('one')
check(store:create(a),'create independent Job') a.payload.step=9
check(store:get('one').payload.step==1,'caller cannot mutate durable fact')
check(store:create(job('two')) and #store:forNpc('a')==2,'NPC is secondary index and can retain multiple Jobs')
check(not store:create(job('one')),'duplicate stable identity rejected')
local rows=store:forNpc('a') rows[1].payload.step=99
check(store:get('one').payload.step==1,'read models detached')
check(store:update('one',1,{state='RUNNING'}),'start accepted')
check(not store:update('one',1,{state='STOPPING'}),'stale revision cannot mutate task')
check(not store:update('one',2,{state='DONE'}),'cannot bypass settling')
check(store:update('one',2,{state='STOPPING',obligations={cargo=11}}),'stop retains cargo obligation')
check(store:update('one',3,{state='SUSPENDED'}),'suspend leaves original Job')
store=assert(Store.open(root))
check(store:get('one').state=='SUSPENDED' and store:get('one').obligations.cargo==11,'reopen reconstructs index without dropping obligations')
check(store:update('one',4,{state='SETTLING',effects='UNKNOWN'}),'unknown effects retained')
check(not store:update('one',5,{state='DONE'}),'cannot finalize unknown effects or outstanding obligation')
check(store:update('one',5,{effects='KNOWN',obligations={}}),'explicit reconciled facts accepted')
check(store:update('one',6,{state='DONE'}),'verified settlement terminates')
check(not store:update('one',7,{state='PREPARING'}),'terminal Job cannot replay')
check(not store:update('two',1,{npcId='b'}),'assignment cannot silently change owner')
local bad=job('bad') bad.payload.callback=function() end
check(not store:create(bad) and not store:get('bad'),'native closures never persist')
bad=job('bad') bad.payload.loop=bad.payload
check(not store:create(bad),'cycles rejected without publishing')
local old={craftProbes={format=1,byNpc={a={id='old'}}}}
local api,reason=Store.open(old)
check(not api and reason=='LEGACY_TASK_RESET_REQUIRED' and old.craftProbes.byNpc.a.id=='old' and not old.taskJobs,
    'no compatibility: old task blocks initialization without deletion or conversion')
check(not Store.open({taskJobs={format=2,byId={}}}),'future schema fails closed')
check(not Store.open({taskJobs=true}) and not Store.open({taskJobs=false}) and not Store.open({craftProbes=true}),'malformed roots fail without overwriting data')
print('PASS '..n..' independent Job store checks; persistence table only, game/save codec NOT RUN')
