-- Pins the PublicWork kernel paths that call into one labor domain: world
-- reset, order command, settled-order retirement and the eligibility
-- retained checks. Observed through guard results, call order and the real
-- providers' effects, so it holds whether the kernel names the domain or
-- reaches it through a provider hook. Domain services are recording stubs.
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;"..package.path
local trace={}
local function rec(s) trace[#trace+1]=s end
local function check(v,msg) if not v then error(msg,2) end end
local function stub(name,t) package.loaded['EmberRoutesProbe/'..name]=t or {} return package.loaded['EmberRoutesProbe/'..name] end

local clock=1000
function getTimestampMs() return clock end
local root={}
local orders,rules,requests,priorities={},{},{},{}
local store={orders=orders,rules=rules,requests=requests,priorities=priorities,sequence=0}
local ids=0
stub('Warehouse/ContainerRegistry',{data=function() return root end,id=function() ids=ids+1 return 'id'..ids end})
local view={entry={id='s',revision=1}}
stub('Settlement/SettlementLedger',{view=function() if view.reason then return nil,view.reason end return view.entry end})
stub('Settlement/SettlementGeometry',{inside=function() return true end})
local npc={getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end,
    getCharacterActions=function() rec('actions') return {isEmpty=function() return true end} end}
stub('Runtime/Driver',{bindId=function() rec('bind') return {handle=npc} end,suspended=function() return false end})
local runtime={accepting=function() return true end,status=function() return nil end}
stub('Runtime/TaskRuntime',{current=function() return runtime end})
stub('Work/Work',{busy=function() rec('busy') return false end,hasCargo=function() return false end,
    record=function() return nil end,allowAutomation=function() end,assign=function() return 'QUEUED' end})
stub('Settlement/Companion') stub('Crafting/Production') stub('Crafting/ProductionRecipe') stub('Crafting/CraftSurfaces')
stub('Crafting/CraftStations') stub('Work/WorkSelector')
local signals=0
stub('Work/LaborSignals',{changed=function() signals=signals+1 end})
local dirOps={}
local directory={withdraw=function(_,k) dirOps[#dirOps+1]='withdraw '..k end,
    release=function(_,k) dirOps[#dirOps+1]='release '..k return true end,
    upsert=function() return nil end,claim=function() return false end}
stub('Kernel/TaskDirectory',{new=function() return directory end})
stub('Work/OrderStore',{load=function(r) r.publicWork=store return store end})
stub('Work/OrderQuery',{invalidate=function() end,priorities=function(id) return priorities[id] or {revision=0} end,
    orderIds=function() return {} end,firstLiveByProduct=function() return {} end})
stub('Kernel/Log',{write=function() end})
local studies=0
local Probe=stub('Kernel/Boot',{ready=true,runtimeReady=true,hasJava=function() return true end,
    invalidateStudy=function() studies=studies+1 end})
stub('Runtime/TaskJobs',{current=function() return {ordinaryCount=function() return 0 end,forNpc=function() return {} end} end})
stub('Kernel/JobStore',{LIMIT=100})
stub('Kernel/DispatchMetrics',{new=function() return {claims=0,record=function() end,snapshot=function() end} end})
stub('Runtime/PlanningWake',{revision=function() return 0 end,changed=function() return false end,capture=function() return {} end})
-- TickConfig stub must list every field PublicWork reads: the dispatcher
-- takes wake/backoff/reservation/social cadences from the same table.
-- Timing-sensitive fields keep production values: the reservation must
-- outlive the 100ms promote gap below, and the social round gates the
-- leisure-ready throttle the promoted path exercises.
stub('Kernel/TickConfig',{discoveryMs=1,discoveryIdleMs=1,precheckMs=1,wakeMs=1,
    discoveryWakeMs=1,reconcileMs=1,stockMs=1,backoffMs={1,1,1},
    reservationExpiryMs=15000,socialRoundMs=1500,workerRemoteMs=1,workerRemoteRadius=1})
stub('Kernel/RuntimeMetrics',{active=function() return false end})
local gate={field=true}
stub('Kernel/RuntimeGate',{isSinglePlayer=function() return true end,hasFieldOperations=function() return gate.field end})
local idleDue=false -- true lets a decision reach discovery (section 6)
stub('Work/IdleDiscovery',{new=function() return {clear=function() end,due=function() return idleDue end,empty=function() end} end})
local cookCalls={}
stub('Cooking/CookingOrders',{describe=function() return nil end,parentAllows=function() return true end,
    command=function(o,action) cookCalls[#cookCalls+1]={o=o,action=action} return 'COOK_RESULT' end})
stub('Logistics/DeliveryService',{discover=function() end,advance=function() end,hasWork=function() return false end})
stub('Logistics/LogisticsService',{publicOffer=function() return nil end})
stub('Field/ToolReturnService',{canInterrupt=function() return false end})
stub('Field/ToolReturnProvider',{category='toolReturn',defaultPriority=4,discover=function() end,claim=function() return 'X','ROLLED_BACK' end})
stub('Field/FieldDemand',{advance=function() end})
local retainedNow={cooking=false,field=false}
stub('Cooking/CookingService',{retained=function() rec('cooking.retained') return retainedNow.cooking end,
    reconcile=function() end,hasWork=function() return false end,advance=function() end})
stub('Field/FieldWork',{retained=function() rec('field.retained') return retainedNow.field end})
local jobs={canRetire={},records={},retired={}}
stub('Work/BusinessJobs',{crafts=function() rec('crafts') return {} end,
    canRetire=function(id) return jobs.canRetire[id]==true end,
    record=function(id) return jobs.records[id] end,
    retire=function(id,orderId) jobs.retired[#jobs.retired+1]=id..'>'..orderId return true end})
stub('Activity/ActivityAttendance',{blocksOrdinary=function() return false end})
stub('SelfCare/HealthAssessment',{canWork=function() rec('canWork') return true end})
stub('Settlement/MembershipService',{check=function() rec('members') return {allowed=true} end,
    entry=function() return {id='s',revision=1} end})
stub('Warehouse/WarehouseIndex',{refresh=function() end})
EmberRoutesProbeJava={carrierActive=true,workerCount=function() return 1 end,workerIdAt=function() return 'w1' end}
function getSpecificPlayer() return {isDead=function() return false end,getX=function() return 0 end,getY=function() return 0 end} end

-- Real providers whose kernel coupling is under test. Reset spies wrap the
-- provider fields, so they see every caller that looks the field up.
local Crafting=require 'EmberRoutesProbe/Crafting/CraftingProvider'
local Hauling=require 'EmberRoutesProbe/Hauling/HaulingProvider'
for name,p in pairs({crafting=Crafting,hauling=Hauling}) do
    local raw=p.reset p.reset=function() rec(name..'.reset') return raw() end
end
local Public=require 'EmberRoutesProbe/Work/PublicWork'
local function generation(id) -- planGenerations[id] as seen by CraftingProvider.waiting
    local o={id=id,state='WAITING'}
    for g=0,8 do if Crafting.waiting(o,{order=o,generation=g}) then return g end end
end

-- 1. World reset: crafting then hauling, once each, only when the root changes.
Public.prepareRecovery()
trace={}
Crafting.evaluations():put('n1',{orderId='o1',request={cancel=function() end}}) Crafting.bumpGeneration('o1')
Hauling.claim({key='haul:1',intent={}},'n1','j1',{directory=directory,actor={}})
check(Hauling.hasWork() and Crafting.evaluations():size()==1 and generation('o1')==1,'reset fixture armed')
Public.prepareRecovery()
check(#trace==0,'same world root runs no provider reset')
root={}
Public.prepareRecovery()
check(table.concat(trace,',')=='crafting.reset,hauling.reset','world swap resets crafting then hauling once: '..table.concat(trace,','))
check(not Hauling.hasWork() and Crafting.evaluations():size()==0 and generation('o1')==0,'reset effects cleared provider state')

-- 2. Order command guards and the craft/cooking split.
local function order(id,t)
    local o={id=id,requestId='q'..id,settlementId='s',revision=1,state='WAITING',sequence=1}
    for k,v in pairs(t or {}) do o[k]=v end
    orders[id]=o return o
end
local function reset() dirOps,cookCalls,signals,studies={},{},0,0 end
reset() view.reason='LEDGER_DENIED' order('c1')
check(Public.command({}, 's','c1',1,'stop')=='LEDGER_DENIED' and orders.c1.state=='WAITING','ledger guard runs first')
view.reason=nil
local k1=order('k1',{category='cooking',jobId='kj',npcId='n'})
check(Public.command({},'s','k1',2,'stop')=='TASK_CHANGED' and #cookCalls==0,'cooking revision guard precedes cooking command')
check(Public.command({},'s','k1',1,'stop')=='COOK_RESULT','cooking order with a job goes to the cooking command')
check(#cookCalls==1 and cookCalls[1].o==k1 and cookCalls[1].action=='stop','cooking command receives the order and action')
check(#dirOps==0 and signals==0 and studies==0 and k1.revision==1,'kernel adds no craft effects to a cooking command')
reset() order('c2',{jobId='cj',npcId='n'})
check(Public.command({},'s','c2',1,'stop')=='ORDER_ALREADY_CLAIMED' and generation('c2')==0,'claimed craft order refused')
order('c3',{state='DONE'})
check(Public.command({},'s','c3',1,'stop')=='TASK_CHANGED' and generation('c3')==0,'settled craft order refused')
local c4=order('c4')
check(Public.command({},'s','c4',1,'resume')=='INVALID_COMMAND' and c4.revision==1 and generation('c4')==0,'resume of a waiting order is invalid')
check(#dirOps==0 and signals==0 and #cookCalls==0,'refused craft commands have no effects')
check(Public.command({},'s','c4',1,'stop')=='ORDER_UPDATED' and c4.state=='PAUSED' and c4.revision==2,'stop pauses')
check(table.concat(dirOps,',')=='withdraw craft:c4' and generation('c4')==1 and signals==1 and studies==1,'stop withdraws, bumps the plan generation once, signals')
reset()
check(Public.command({},'s','c4',2,'resume')=='ORDER_UPDATED' and c4.state=='WAITING' and #dirOps==0 and generation('c4')==2,'resume waits again')
reset()
check(Public.command({},'s','c4',3,'return')=='ORDER_UPDATED' and c4.state=='CANCELLED' and table.concat(dirOps,',')=='withdraw craft:c4','return cancels and withdraws')
check(#cookCalls==0,'craft commands never reach the cooking command')
for id in pairs(orders) do orders[id]=nil end

-- 3. Settled-order retirement.
reset()
order('rA',{state='CANCELLED'}) order('rB',{state='DONE'})
order('rC',{category='cooking',state='DONE'}) order('rD',{category='cooking',state='CANCELLED'})
order('rE',{category='cooking',state='WAITING'})
order('rF',{state='DONE',jobId='jF',npcId='n'}) jobs.canRetire.jF=true jobs.records.jF={state='DONE'}
order('rG',{state='DONE',craftProgress={settledJobId='jG'}})
order('rH',{state='DONE',craftProgress={settledJobId='jH'}}) jobs.records.jH={state='DONE'}
for _,id in ipairs({'rA','rC','rF','rG','rH'}) do Crafting.bumpGeneration(id) end
local count=Public.retireSettled(100)
local retired,kept={},{}
for _,id in ipairs({'rA','rB','rC','rD','rE','rF','rG','rH'}) do
    if orders[id] then kept[#kept+1]=id else retired[#retired+1]=id end
end
check(count==5 and table.concat(retired,',')=='rA,rC,rD,rF,rG','retired set: '..table.concat(retired,','))
check(table.concat(kept,',')=='rB,rE,rH','kept set: '..table.concat(kept,','))
check(table.concat(jobs.retired,',')=='jF>rF','claimed order retires its exact job')
local ops={} for _,op in ipairs(dirOps) do ops[op]=(ops[op] or 0)+1 end
for _,id in ipairs(retired) do
    check(ops['release craft:'..id]==1 and ops['withdraw craft:'..id]==1,'retired order releases and withdraws its offer: '..id)
    check(generation(id)==0,'retired order drops its plan generation: '..id)
end
for i=1,#dirOps,2 do check(dirOps[i]:sub(1,8)=='release ' and dirOps[i+1]=='withdraw '..dirOps[i]:sub(9),'release precedes withdraw') end
check(#dirOps==10 and generation('rH')==1,'kept orders keep their offer and generation')
for _,id in ipairs(retired) do
    local found for _,r in ipairs(requests) do if r.orderId==id then found=true end end
    check(found,'retired order keeps an idempotency receipt: '..id)
end
for id in pairs(orders) do orders[id]=nil end

-- 4. Eligibility: cooking retained, then field retained, before the craft
-- record, whether or not field operations are open.
local function decision()
    trace={} clock=clock+1000 Public.tick()
    local list={} -- the field check may be evaluated once per field provider
    for _,s in ipairs(trace) do if s~=list[#list] then list[#list+1]=s end end
    return table.concat(list,',')
end
local head='bind,busy,'
retainedNow.cooking,retainedNow.field=true,false
check(decision()==head..'cooking.retained','cooking retained stops eligibility first')
retainedNow.cooking,retainedNow.field=false,true
check(decision()==head..'cooking.retained,field.retained','field retained stops eligibility after cooking')
gate.field=false
check(decision()==head..'cooking.retained,field.retained','field retained applies with field operations closed')
gate.field=true retainedNow.field=false
local got=decision()
check(got:sub(1,#head+#'cooking.retained,field.retained,crafts')==head..'cooking.retained,field.retained,crafts',
    'unretained worker reaches the craft record: '..got)
-- 5. Priority validation: crafting and hauling are required, other keys are
-- checked only when present, unknown keys are kept, unknown categories refused.
local function setAll(values) return Public.setPriorities({},'s','w1',values,(priorities.w1 or {revision=0}).revision) end
check(setAll({hauling=1})=='INVALID_PRIORITY','crafting priority is required')
check(setAll({crafting=1})=='INVALID_PRIORITY','hauling priority is required')
check(setAll({crafting=1,hauling=5})=='INVALID_PRIORITY','required priority range checked')
check(setAll({crafting=1,hauling=1,cooking=1.5})=='INVALID_PRIORITY','optional priority checked when present')
check(setAll({crafting=0,hauling=4,cooking=2,custom=3})=='PRIORITY_SAVED','valid priorities save')
local saved=priorities.w1
check(saved.crafting==0 and saved.hauling==4 and saved.cooking==2 and saved.custom==3 and saved.revision==1,'saved projection keeps every key')
check(Public.setPriority({},'s','w1','custom',1)=='INVALID_PRIORITY','unregistered category refused')
check(Public.setPriority({},'s','w1','hauling',7)=='INVALID_PRIORITY','single priority range checked')
check(Public.setPriority({},'s','w1','hauling',2)=='PRIORITY_SAVED','registered required category saves alone')

-- 6. Claim failure settlement through the real dispatch paths: a direct
-- decision and a promoted care-probe reservation both reach claimSelected,
-- which releases the offer only on a rollback declaration. Real directory.
local saved=package.loaded['EmberRoutesProbe/Kernel/TaskDirectory']
package.loaded['EmberRoutesProbe/Kernel/TaskDirectory']=nil
local real=require('EmberRoutesProbe/Kernel/TaskDirectory').new()
package.loaded['EmberRoutesProbe/Kernel/TaskDirectory']=saved
for _,op in ipairs({'upsert','claim','release','withdraw','isWithdrawn'}) do
    directory[op]=function(_,...) return real[op](real,...) end
end
package.loaded['EmberRoutesProbe/Work/WorkSelector'].choose=function(candidates)
    for _,c in ipairs(candidates) do if c.allowed~=false then return c end end
end
local logs={}
package.loaded['EmberRoutesProbe/Kernel/Log'].write=function(_,line) logs[#logs+1]=line end
EmberRoutesProbeJava.workerIdAt=function() return 'w9' end
priorities.w9={revision=0,claimprobe=1}
idleDue=true
local probing=false
Probe.careProbeWork=function() return probing end
local key,category,declare,claims='probe:0','claimprobe',nil,{}
check(Public.registerProvider({category='claimprobe',
    discover=function(env)
        local offer=env.upsertOffer(key,1,category)
        if offer and not offer.jobId then
            env.candidates[#env.candidates+1]={key=key,revision=1,category=category,allowed=true,score=1}
        end
    end,
    claim=function(_,npcId,jobId) claims[#claims+1]=npcId..'/'..jobId return 'PROBE_REFUSED',declare end}),
    'claim probe registers')
local function allocated(k) return (real:upsert(k,1,category,'s') or {}).jobId end
local function logged(k)
    for _,line in ipairs(logs) do if line:find('offer='..k..' ',1,true) then return line end end
end
local function dispatch(name,promoted,cat,declaration)
    key,category,declare,logs='probe:'..name,cat or 'claimprobe',declaration,{}
    local before=#claims
    clock=clock+20000 -- past the 8 s offer cooldown and the 15 s worker backoff
    if promoted then
        probing=true Public.tick() probing=false
        check(Public.hasReservation('w9') and #claims==before and allocated(key),name..': probing worker reserves the offer')
        clock=clock+100 Public.tick()
        check(not Public.hasReservation('w9'),name..': reservation promoted')
    else
        Public.tick()
    end
    for _,line in ipairs(logs) do check(not line:find('WORKER_FAULT',1,true),name..': '..line) end
    check(logged(key),name..': claim reached the dispatcher log')
    return #claims-before,logged(key)
end
local calls,line=dispatch('direct-declared',false,nil,'ROLLED_BACK')
check(calls==1 and allocated(key)==nil and not line:find('OFFER_RETAINED',1,true),'declared rollback releases the offer')
calls,line=dispatch('direct-undeclared',false,nil,nil)
local job=line:match(' job=(%S+)')
check(calls==1 and job and allocated(key)==job,'undeclared failure keeps the offer allocated to its Job')
check(line:find('OFFER_RETAINED reason=CLAIM_ROLLBACK_UNDECLARED',1,true),'undeclared failure is diagnosed: '..line)
calls,line=dispatch('direct-providerless',false,'unregistered',nil)
check(calls==0 and allocated(key)==nil and line:find('result=nil',1,true),'offer of no registered provider is released by the dispatcher')
calls,line=dispatch('promoted-declared',true,nil,'ROLLED_BACK')
check(calls==1 and allocated(key)==nil and not line:find('OFFER_RETAINED',1,true),'promoted declared rollback releases the offer')
calls,line=dispatch('promoted-undeclared',true,nil,nil)
job=line:match(' job=(%S+)')
check(calls==1 and job and allocated(key)==job and line:find('OFFER_RETAINED reason=CLAIM_ROLLBACK_UNDECLARED',1,true),
    'promoted undeclared failure keeps and diagnoses the offer')
print('PASS public-work kernel hook paths')
