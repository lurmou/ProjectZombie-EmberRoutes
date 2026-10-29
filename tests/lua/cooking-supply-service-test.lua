-- Shared-cache, ownership and admission boundaries over real Jobs/Claims/Index.
local f=dofile('tests/lua/cooking-supply-test.lua')
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Store=require 'EmberRoutesProbe/LaborStore'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Service=require 'EmberRoutesProbe/CookingSupplyService'
local Jobs=require('EmberRoutesProbe/TaskJobs').current()
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
Registry.configure(f.f.actor,f.box,f.config,f.box.container,'STORAGE')
local root=Registry.data()
root.npcMembership={format=1,byNpc={}}
for i=1,6 do root.npcMembership.byNpc['meal-'..i]={npcId='meal-'..i,
    settlementId=f.entry.id,factionId=f.entry.factionId,context=i==2 and 'FOLLOW' or 'SETTLEMENT'} end
local now,hours=1000,1
local budget={scan=1}
check(Service.observe(f.entry,now,hours,budget)==nil and budget.scan==0,'partial shared scan never grants zero stock')
local another={scan=8}
check(Service.observe(f.entry,now,hours,another)==nil and another.scan==8,'same-frame second chef shares cursor without another pump')
local function observed()
    for _=1,100 do
        now=now+50
        local row,why=Service.observe(f.entry,now,hours,{scan=8})
        if row then return row end
        assert(why=='SUPPLY_NOT_OBSERVED' or why=='SUPPLY_CHANGED',tostring(why))
    end
    error('shared meal observation did not finish')
end
local snapshot=observed()
check(snapshot.population==6 and math.abs(snapshot.ready-.78)<.000001 and snapshot.demand.active,
    'all formal members count, including away follower; stock uses actual remaining fullness')
local untouched={scan=8} local cached=assert(Service.observe(f.entry,now,hours,untouched))
check(untouched.scan==8 and cached~=snapshot,'cache shares observations but gives callers detached values')
snapshot.ready=100 snapshot.population=0
local job=assert(Record.new('service-first','service-chef',f.entry.id,'Soup','AUTO','policy:'..f.entry.id,1.02,1.02))
check(Service.reserve(f.entry,job,snapshot,.075,now,hours),'admission uses authoritative cached stock/population, not mutated caller values')
local competitor=assert(Record.new('service-second','service-other',f.entry.id,'Soup','AUTO','policy:'..f.entry.id,1.02,1.02))
check(not Service.reserve(f.entry,competitor,cached,.075,now,hours),'same-gap second claim cannot reuse the old observation')
local covered=observed()
check(covered.demand.gap==0 and math.abs(covered.demand.blocked-1.02)<.000001,'same Job reservation blocks duplicate batch without inventing edible stock')
-- A different task can claim a still-visible original without a container event.
local held=assert(Record.new('service-claim','service-custodian',f.entry.id,'Soup','REQUEST','request:test',.1,.1))
held.payload.assets={{id=f.whole:getID(),fullType=f.whole:getFullType(),custody='SOURCE',role='INPUT'}}
held.payload.claims={'item:'..f.whole:getID()}
assert(Jobs:create(held)) local token=assert(Store.claimCooking(Jobs:get(held.id)))
check(not Service.reserve(f.entry,competitor,covered,.075,now,hours),'a newly claimed original fences previous stock without waiting for inventory events')
local restricted=observed()
check(math.abs(restricted.ready-.26)<.000001,'claimed original is excluded from available reserve')
local released=Record.copy(Jobs:get(held.id)) released.payload.assets[1].custody='RETURNED' released.payload.claims={}
assert(Store.replaceCooking(Jobs:get(held.id),token,released))
check(math.abs(observed().ready-.78)<.000001,'released original invalidates cached partial stock')
root.npcMembership.byNpc['meal-2'].retired=true
check(assert(Service.observe(f.entry,now,hours,{scan=8})).population==5,'confirmed retirement immediately changes demand without rescan')
hours=hours+1/30 now=now+50
check(Service.observe(f.entry,now,hours,{scan=1})==nil,'fast-forward game time expires food facts even before wall-clock TTL')
observed() now=now+2000
check(Service.observe(f.entry,now,hours,{scan=1})==nil,'wall-clock fallback also invalidates silent power or spoilage changes')
print('PASS shared cooking observation/admission boundaries; native world mocked, game NOT RUN')
