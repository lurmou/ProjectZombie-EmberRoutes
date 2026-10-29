-- Real shared admission/Jobs/Claims; native objects remain the existing host fixture.
local Policy=require 'EmberRoutesProbe/CookingPolicy'
local Record=require 'EmberRoutesProbe/CookingRecord'
local JobStore=require 'EmberRoutesProbe/JobStore'
local Budget=require 'EmberRoutesProbe/CookingBudget'
local checks=0
local function check(v,message) checks=checks+1 assert(v,message) end
local function near(a,b) return math.abs(a-b)<0.000001 end
local rows={
    a={npcId='a',settlementId='base',factionId='f',context='SETTLEMENT'},
    b={npcId='b',settlementId='base',factionId='f',context='FOLLOW'},
    c={npcId='c',settlementId='base',factionId='f',context='RETURN'},
    d={npcId='d',settlementId='base',factionId='f',retired=true},
    e={npcId='e',settlementId='elsewhere',factionId='f'},
}
check(Policy.population(rows,'base','f')==3,'away members remain; confirmed retired excluded')
rows.b.pendingCommand={kind='TRANSFER',settlementId='elsewhere'}
check(Policy.population(rows,'base','f')==3,'pending transfer still counts old committed base exactly once')
rows.b.settlementId='elsewhere'
check(Policy.population(rows,'base','f')==2,'committed migration changes supply population')
local demand=assert(Policy.demand(1,0,0,0,false))
local batch=assert(Policy.batch(demand,0.5))
check(near(batch.quota,0.5) and near(batch.minimumOverrun,0.2),'one person can start one indivisible native batch')
local small=assert(Policy.demand(1,0.2,0,0,true))
check(not Policy.batch(small,0.5),'do not open oversized second pot once minimum reserve exists')
check(not Policy.demand(1,0/0,0,0,false),'unknown/NaN supply cannot grant work')
check(assert(Policy.demand(0,0,0,0,true)).gap==0,'no population stops new work')
local root={} local jobs=assert(JobStore.open(root))
local quota=assert(Budget.open(root,jobs))
local function job(id,npc,target,amount)
    return assert(Record.new(id,npc,'base','Soup','AUTO','policy:base',target or 0.3,amount or 0.3))
end
local function snapshot(n,ready,min)
    local v=assert(quota:view('base'))
    return {scopeId='base',stamp=v.stamp,complete=true,population=n or 2,ready=ready or 0,
        minimum=min or 0.1,active=false}
end
local before=snapshot()
check(quota:reserve(job('cook-a','a'),before),'first cook receives finite quota')
check(not quota:reserve(job('cook-b','b'),before),'same-frame contender cannot use old supply stamp')
check(not quota:reserve(job('cook-a','a'),snapshot()),'duplicate request does not create/replay job')
local v=assert(quota:view('base'))
check(near(v.blocked,0.3) and v.pending==0,'unconfirmed output retains quota but is not edible or predicted food')
local fresh=snapshot() fresh.complete=false
check(not quota:reserve(job('cook-b','b'),fresh),'unloaded/incomplete observation is not zero stock')
check(quota:reserve(job('cook-b','b'),snapshot()),'second cook can cover different remaining deficit')
check(not quota:reserve(job('cook-c','c'),snapshot()),'two reserved batches prevent third full-deficit claim')
local saved=assert(jobs:get('cook-a'))
local p=Record.copy(saved.payload) p.expected=0.3
check(jobs:update(saved.id,saved.revision,{payload=p}),'verified prediction stays in existing job')
v=assert(quota:view('base'))
check(near(v.pending,0.3) and near(v.blocked,0.3),'prediction and unknown quota have distinct accounting')
local reopened=assert(JobStore.open(root))
local after=assert(Budget.open(root,reopened)):view('base')
check(after.stamp==v.stamp and near(after.pending,v.pending) and near(after.blocked,v.blocked),
    'save/reopen derives exactly same allocations from Jobs without second ledger')
-- Resource and attempt invariants use actual record shape.
local cook=job('effect','chef')
cook.payload.assets={{id=201,fullType='Base.Pot',custody='HELD',raw=0,effective=0},
    {id=202,fullType='Base.Carrot',custody='HELD',raw=0.1,effective=0.1}}
cook.payload.claims={'item:201','item:202'}
check(Record.valid(cook),'retained originals have matching declarations')
local attempt=assert(Record.begin(cook,'ADD',{201,202}))
local committing=assert(Record.committing(attempt,attempt.payload.attempt.id))
check(committing.effects=='UNKNOWN' and committing.payload.attempt.state=='COMMITTING',
    'persist intent before native effect; interrupted commit cannot be called known')
check(not Record.begin(committing,'ADD',{201,202}),'unfinished commit cannot auto-replay with another attempt')
check(not Record.committing(committing,committing.payload.attempt.id),'duplicate complete cannot enter commit twice')
local unsafe=Record.copy(committing) unsafe.effects='KNOWN'
check(not Record.valid(unsafe),'cannot clear unknown flag without effect receipt')
local dup=Record.copy(cook) dup.payload.claims={'item:201','item:201'}
check(not Record.valid(dup),'duplicate declaration rejected')
local hole=Record.copy(cook) hole.payload.assets[4]=hole.payload.assets[2]
check(not Record.valid(hole),'sparse item manifests rejected')
local orphan=Record.copy(cook) orphan.payload.claims={'item:201'}
check(not Record.valid(orphan),'held ingredient cannot disappear from declarations')
local terminal=Record.copy(committing) terminal.state='DONE' terminal.payload.phase='SETTLED'
check(not Record.valid(terminal),'unknown or retained originals forbid terminal job')
local receipt={attemptId=committing.payload.attempt.id,observed=true,baseBeforeId=201,baseAfterId=201,
    ingredientId=202,baseKnown=true,beforeAmount=0.1,afterAmount=0.05}
local applied=assert(Record.confirm(committing,receipt.attemptId,receipt))
check(Record.transition(committing,applied),'observed partial ingredient consumption can resolve unknown effect')
check(not Record.confirm(applied,receipt.attemptId,receipt),'duplicate receipt cannot complete effect twice')
local noEffect=Record.copy(receipt) noEffect.afterAmount=noEffect.beforeAmount
check(not Record.confirm(committing,receipt.attemptId,noEffect),'unchanged native ingredient is not completion evidence')
local stale=Record.copy(receipt) stale.attemptId='old:1'
check(not Record.confirm(committing,receipt.attemptId,stale),'other attempt receipt cannot resolve this operation')
local rewritten=Record.copy(applied) rewritten.payload.attempt.receipt.afterAmount=0.01
check(not Record.transition(applied,rewritten),'accepted historical receipt cannot be rewritten')
local lost=Record.copy(committing) lost.payload.assets={} lost.payload.claims={} lost.payload.attempt.itemIds={}
check(not Record.transition(committing,lost),'unknown effect cannot discard its original responsibility')
local reprice=Record.copy(applied) reprice.payload.quota=0.4
check(not Record.transition(applied,reprice),'admitted quota cannot grow behind other cooks')
local cycle={} cycle.self=cycle
check(not pcall(Record.copy,cycle),'cyclic native-like data fails bounded copy rather than recursing forever')
local hot=job('stove','chef')
hot.payload.claims={'cooking:stove:1'} hot.obligations.furnace=true
hot.payload.duty={id='duty:1',siteKey='cooking:stove:1',ownerId='chef',revision=1,
    originalActive=false,openedByJob=true,state='STOP_REQUIRED'}
local off=assert(Record.begin(hot,'TOGGLE',{}))
off=assert(Record.committing(off,off.payload.attempt.id))
off=assert(Record.confirm(off,off.payload.attempt.id,{attemptId=off.payload.attempt.id,observed=true,
    siteKey='cooking:stove:1',expectedActive=false,actualActive=false,controlled=true}))
local cleared=Record.copy(off) cleared.payload.duty=nil cleared.payload.claims={} cleared.obligations={}
cleared.state='DONE' cleared.payload.phase='SETTLED'
check(Record.valid(cleared),'verified shutdown receipt survives clearing furnace obligation')
-- A delivered output enters shared ready stock and leaves its old in-progress amount.
saved=assert(jobs:get('cook-a')) p=Record.copy(saved.payload)
p.assets={{id=701,fullType='Base.PotOfSoupRecipe',custody='DELIVERED',role='OUTPUT',effective=0.3}}
check(jobs:update(saved.id,saved.revision,{payload=p}),'delivery publishes original identity and actual amount')
v=assert(quota:view('base'))
check(v.pending==0 and near(v.blocked,0.3),'delivered meal is not counted in both shared S and old P')
-- Raw depletion and effective meal coverage must never be confused.
function instanceof(value,kind) return kind=='Food' and value.food==true end
local Food=require 'EmberRoutesProbe/CookingFood'
local function dish(raw,effective)
    local item={food=true}
    function item:getID() return 77 end
    function item:getFullType() return 'Base.PotOfSoupRecipe' end
    function item:getHungChange() return -raw end
    function item:getHungerChange() return -effective end
    function item:getBaseHunger() return -0.4 end
    function item:isCooked() return true end
    function item:isCookable() return true end
    function item:isRotten() return false end
    function item:isBurnt() return false end
    function item:isPoison() return false end
    function item:getPoisonPower() return 0 end
    function item:isTainted() return false end
    function item:isbDangerousUncooked() return true end
    function item:isFrozen() return false end
    function item:isSpice() return false end
    function item:getRequireInHandOrInventory() return nil end
    return item
end
local half=dish(0.2,0.26)
local food=assert(Food.read(half))
check(food.ready and near(food.effective,0.26) and near(food.raw,0.2),'half cooked pot counts native effective value once')
function half:isPoison() return true end
check(not assert(Food.read(half)).ready,'positive hunger contribution does not authorize unsafe food')
local frozen=dish(0.2,0.26) function frozen:isFrozen() return true end
check(not assert(Food.read(frozen)).ready,'frozen food not silently counted as directly edible')
local spice=dish(0.1,0.13) function spice:isSpice() return true end
check(not assert(Food.read(spice)).ready,'cooked spice does not become a completed meal')
local missing=dish(0.1,0.13) missing.getHungerChange=nil
check(Food.read(missing)==nil,'missing native effective amount stays unknown, not zero')
-- Production integration: all providers contend in one existing LaborStore.
local f=dofile('tests/lua/multi-worker-test.lua')
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Store=require 'EmberRoutesProbe/LaborStore'
local sharedJobs=require('EmberRoutesProbe/TaskJobs').current()
Store.data()
local a=job('foundation-a',f.a.id)
local b=job('foundation-b',f.b.id)
check(sharedJobs:create(a) and sharedJobs:create(b),'cooking stores ordinary durable Jobs')
local ta=assert(Store.claimCooking(a))
local tb=assert(Store.claimCooking(b))
local original=Record.copy(a)
original.payload.assets={{id=987001,fullType='Base.Pot',custody='HELD'}}
original.payload.claims={'item:987001'}
local ok,nextJob,nextToken=Store.replaceCooking(a,ta,original)
check(ok,'original acquired through existing shared claims')
a,ta=nextJob,nextToken
check(Store.owner(987001).taskId==a.id,'other production sees same item owner')
local rejected=Record.copy(a) rejected.payload.quota=0.4
rejected.payload.assets={{id=987002,fullType='Base.Pot',custody='HELD'}} rejected.payload.claims={'item:987002'}
check(not Store.replaceCooking(a,ta,rejected),'durable transition refusal rejects replacement claims')
check(Store.owner(987001).taskId==a.id and not Store.owner(987002) and Store.validCooking(a,ta),
    'failed publish restores old original and token without leaking new claim')
local conflict=Record.copy(b)
conflict.payload.assets={{id=987001,fullType='Base.Pot',custody='HELD'}}
conflict.payload.claims={'item:987001'}
check(not Store.replaceCooking(b,tb,conflict),'other cook cannot steal retained pot')
check(#sharedJobs:get(b.id).payload.claims==0 and Store.owner(987001).taskId==a.id,
    'claim conflict changes neither durable declaration nor old owner')
local prepared=assert(Record.begin(a,'TRANSFER',{987001}))
local good,ja,t1=Store.replaceCooking(a,ta,prepared)
check(good and not Store.validCooking(a,ta),'new attempt fences old token and revision')
a,ta=ja,t1
local unsafeCommit=assert(Record.committing(a,a.payload.attempt.id))
good,ja,t1=Store.replaceCooking(a,ta,unsafeCommit)
check(good,'unknown commit persists in same Job and retains original')
a,ta=ja,t1
check(not Store.finishCooking(a,ta),'unknown original cannot be released')
check(Store.owner(987001).taskId==a.id,'failed finish keeps shared original protected')
-- Rebuild only LaborStore cache, not durable Jobs or other provider data.
package.loaded['EmberRoutesProbe/LaborStore']=nil
local loadedStore=require 'EmberRoutesProbe/LaborStore'
check(loadedStore.owner(987001).taskId==a.id,'load restores unknown cooking claims before any new allocation')
check(not loadedStore.validCooking(a,ta),'old in-memory token cannot operate after world claim rebuild')
local reserved=Record.copy(sharedJobs:get(b.id))
reserved.payload.claims={'cooking:capacity:'..b.id}
reserved.payload.capacity={endpointId='foundation-cold',amount=4} reserved.obligations.storage=true
local refreshed=assert(loadedStore.claimCooking(sharedJobs:get(b.id)))
local capacityOK,capacityJob,capacityToken=loadedStore.replaceCooking(sharedJobs:get(b.id),refreshed,reserved)
check(capacityOK and loadedStore.availableCapacity('foundation-cold',6)==2,
    'a durable batch promise shares the existing hauling space budget')
check(loadedStore.availableCooking(capacityJob,capacityToken,'foundation-cold',3)==3,
    'overfull cold storage never invents free space by refunding a clamped promise')
package.loaded['EmberRoutesProbe/LaborStore']=nil
local restored=require 'EmberRoutesProbe/LaborStore'
check(restored.availableCapacity('foundation-cold',6)==2,
    'saved cooking promises rebuild before another worker can reserve the destination')
print('PASS cooking foundation '..checks..' boundary assertions; no native cooking executed')
