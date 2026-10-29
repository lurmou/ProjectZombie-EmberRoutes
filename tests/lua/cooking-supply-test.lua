-- Real registered endpoints, permission checks and invalidation; food reads are host doubles.
local f=dofile('tests/lua/multi-worker-test.lua')
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Filter=require 'EmberRoutesProbe/StorageFilter'
local Index=require 'EmberRoutesProbe/MealSupplyIndex'
local Facilities=require 'EmberRoutesProbe/CookingFacilities'
local checks=0
local function check(v,m) checks=checks+1 assert(v,m) end
local previous=instanceof
function instanceof(value,kind)
    if kind=='Food' and value.food then return true end
    if kind=='IsoStove' and value.stove then return true end
    return previous(value,kind)
end
local actor=f.actor actor.x=1004.5
function actor:getIndex() return 0 end
local entry=assert(Ledger.commit(actor,nil,'Meals',{x=1000,y=0,w=40,h=10}))
local box=f.fixture.object(1004)
local powered,cold=true,true
function box.container:isFridge() return cold end
function box.container:isFreezer() return false end
function box.container:isPowered() return powered end
function box.container:getTemperature() return powered and 0.2 or 1 end
local config=Filter.new() config.types['Base.PotOfSoupRecipe']=true
check(Registry.configure(actor,box,config,box.container,'STORAGE')=='FILTER_CONFIGURED','register actual shared food storage')
local function food(amount)
    local item=f.fixture.item('Base.PotOfSoupRecipe',box.container)
    item.food=true
    function item:getHungChange() return -amount end
    function item:getHungerChange() return -amount*1.3 end
    function item:getBaseHunger() return -0.4 end
    function item:isRotten() return false end
    function item:isBurnt() return false end
    function item:isPoison() return false end
    function item:getPoisonPower() return 0 end
    function item:isTainted() return false end
    function item:isCooked() return true end
    function item:isCookable() return true end
    function item:isbDangerousUncooked() return true end
    function item:isFrozen() return false end
    function item:isSpice() return false end
    function item:getRequireInHandOrInventory() return nil end
    return item
end
local half=food(0.2) local whole=food(0.4)
local boxId=Registry.metadata(box,box.container).id
box.stove=true
local microwave=false
function box:isMicrowave() return microwave end
function box:isBroken() return false end
function box:Activated() return false end
local stove=assert(Facilities.stove(assert(Registry.resolve(boxId,'put','local-world'))))
check(stove.siteKey=='cooking:'..boxId and stove.powered and not stove.active,
    'stove facts retain stable endpoint identity without activating anything')
microwave=true
check(not Facilities.stove(assert(Registry.resolve(boxId,'put','local-world'))),'microwave cannot enter ordinary stove adapter')
microwave=false
local function finish(scan)
    for _=1,100 do local done,why=scan:step(8) assert(done~=nil,why) if done then return scan:result() end end
    error('bounded test scan did not finish')
end
local scan=assert(Index.new(entry,function() return 123 end))
check(scan:result()==nil,'partial scan is never confirmed zero meals')
local result=assert(finish(scan))
check(result.complete and math.abs(result.ready-0.78)<0.000001 and result.items==2,
    'two different pot sizes aggregate native remaining hunger instead of counting two meals')
powered=false
local warm=assert(finish(assert(Index.new(entry))))
check(warm.complete and warm.ready==0,'unpowered fridge does not count as effective cold meal reserve')
powered=true cold=false
local named=assert(finish(assert(Index.new(entry))))
check(named.complete and named.ready==0,'powered ordinary box is not refrigeration')
cold=true
-- Invalidating while cursor is alive cancels that snapshot, never adds its old partial count.
local changed=assert(Index.new(entry)) changed:step(1)
for _,listener in ipairs(Registry.inventoryListeners) do listener(boxId) end
local ok,reason=changed:step(1)
check(ok==nil and reason=='SUPPLY_CHANGED','mid-scan inventory notification fences stale observations')
-- Unobservable permitted inventory is unknown, not a valid zero-food result.
local resolve=Registry.resolve
function Registry.resolve(id,intent,scope)
    if id==boxId then return nil,'CONTAINER_UNLOADED' end
    return resolve(id,intent,scope)
end
local unknown=assert(finish(assert(Index.new(entry))))
check(not unknown.complete and unknown.ready==nil,'unloaded shared pantry cannot trigger zero-stock refill')
Registry.resolve=resolve
local private=Filter.copy(config) private.private=true
Registry.configure(actor,box,private,box.container,'STORAGE')
local hidden=assert(finish(assert(Index.new(entry))))
check(hidden.complete and hidden.ready==0,'private food is not read or counted as public supply')
check(half:getContainer()==box.container and whole:getContainer()==box.container,
    'every supply query leaves original food in its real container')
print('PASS cooking supply '..checks..' boundary assertions; native food mocked')
return {f=f,entry=entry,box=box,boxId=boxId,config=config,half=half,whole=whole,
    power=function(value) powered=value end}
