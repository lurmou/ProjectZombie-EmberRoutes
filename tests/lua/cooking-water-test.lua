-- Installed ISTakeWaterAction; Jobs/claims/receipts real, world/fluid effects mocked.
local f=dofile('tests/lua/cooking-actions-test.lua')
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
local Record=require 'EmberRoutesProbe/CookingRecord'
local Context=require 'EmberRoutesProbe/CookingContext'
local Store=require 'EmberRoutesProbe/LaborStore'
local Facilities=require 'EmberRoutesProbe/SettlementFacilities'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Transfer=require 'EmberRoutesProbe/WorkTransfer'
local Fluids=require 'EmberRoutesProbe/CraftFluids'
local originalInstance=instanceof
function instanceof(value,kind)
    if kind=='IsoWorldInventoryObject' or kind=='IsoThumpable' then return false end
    return originalInstance(value,kind)
end
Fluid={Water='Water'}
IsoFlagType={water='water',solidfloor='solidfloor'}
luautils={stringStarts=function(value,prefix) return string.sub(value,1,#prefix)==prefix end}
function sendItemStats() end
function f.root:setDrawDirty() end
function f.npc:getFreeInventoryCapacity() return 20 end
function f.npc:hasFullInventory() return false end
function f.npc:isEquippedClothing() return false end
function f.npc:playSound() end function f.npc:faceThisObject() end function f.npc:reportEvent() end
function f.npc:isSecondaryHandItem() return true end
function ISBaseTimedAction:getJobDelta() return self.delta or 0 end
function ISBaseTimedAction:setAnimVariable() end function ISBaseTimedAction:setOverrideHandModels() end
dofile('D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/shared/TimedActions/ISTakeWaterAction.lua')
package.loaded['TimedActions/ISTakeWaterAction']=true
Transfer.reachable=function() return true end
local permitted=true local row={version=1,slots={}} local squares={}
local entry={id='kitchen',areas={{x=0,y=0,w=10,h=10}}}
Ledger.view=function() return permitted and entry or nil end
Facilities.watch=function() return row end Facilities.pending=function() return false end
function getCell() return {getGridSquare=function(_,x) return squares[x] end} end
local calls=0 local throwAfter=false
local function fluid(amount,capacity)
    return {amount=amount,capacity=capacity or 10,kind='Water',
        getAmount=function(self) return self.amount end,getCapacity=function(self) return self.capacity end,
        isPureFluid=function(self,kind) return self.kind==kind end}
end
local function source(x,amount)
    local water=fluid(amount) local object={mod={},fluid=water}
    local square={getX=function() return x end,getY=function() return 1 end,getZ=function() return 0 end}
    square.objects=f.list({object}) function square:getObjects() return self.objects end
    squares[x]=square
    function object:getSquare() return square end function object:getModData() return self.mod end
    function object:getFluidContainer() return self.fluid end function object:getFluidAmount() return water.amount end
    function object:getFluidCapacity() return water.capacity end function object:hasFluid() return water.amount>0 end
    function object:getUsesExternalWaterSource() return self.external==true end
    function object:getPrimaryFluid() return water.kind end function object:isTaintedWater() return false end
    function object:getProperties() return {has=function() return false end,get=function() end} end
    function object:getSprite() return {getName=function() return 'test_tap' end} end
    function object:transferFluidTo(target,amount)
        calls=calls+1
        local owner=assert(Store.owner(target.itemId))
        local job=require('EmberRoutesProbe/TaskJobs').current():peek(owner.taskId)
        assert(job.effects=='UNKNOWN' and job.payload.attempt.state=='COMMITTING','durable progressive barrier')
        local n=math.min(amount,water.amount,target.capacity-target.amount)
        water.amount=water.amount-n target.amount=target.amount+n
        if throwAfter then error('partial native water failure') end
    end
    return object
end
local function setup(amount)
    permitted=true throwAfter=false row.version=row.version+1
    local pot=f.item('Base.Pot',false) pot.fluid=fluid(amount or 0) pot.fluid.itemId=pot.id
    function pot:getFluidContainer() return self.fluid end function pot:isEquipped() return false end
    function pot:setBeingFilled(v) self.beingFilled=v end function pot:getName() return 'Pot' end
    function pot:getFillFromTapSound() end function pot:getPourType() return 'pot' end
    function pot:getStaticModel() return 'Pot' end function pot:syncItemFields() end
    local c=f.context({pot}) c.actor=f.fixture.actor c.entry=entry c.items={[pot.id]=pot}
    c.body.stop=function() return true end
    c.body.snapshot=function() return {available=true,nativeStopped=f.queued()==nil} end
    return c,pot
end
local Water=require 'EmberRoutesProbe/CookingWater'
local Sources=require 'EmberRoutesProbe/CookingWaterSources'
local c,pot=setup() local tap=source(1,5)
local leaf=assert(Water.take(c,1,pot,tap)) assert(leaf.run()=='Running')
local action=f.queued() action:start() action.delta=.4 action:update()
check(pot.fluid.amount==2 and c.job.effects=='UNKNOWN' and c.job.payload.sequence==1,'native update creates real partial progress inside one durable attempt')
local revision=c.job.revision action.delta=.6 action:update()
check(pot.fluid.amount==3 and c.job.revision==revision and leaf.run()=='Running','progress does not create per-frame Jobs or fail because its effect is in flight')
action:complete() action:perform()
local result=leaf.run()
check(result=='Success' and pot.fluid.amount==5 and c.job.payload.attempt.receipt.added==5
    and c.job.payload.attempt.receipt.exhausted and not c.job.payload.waterSource,'empty source settles measured five-unit increment and releases only its source claim: '
        ..tostring(result)..' '..tostring(c.reason)..' '..tostring(c.job.payload.attempt.state)..' '..pot.fluid.amount)
local count=calls check(assert(Water.take(c,1,pot,tap)).run()=='Success' and calls==count,'known receipt replay never fills again')
local partial,vessel=setup() local second=source(2,8)
local fill=assert(Water.take(partial,1,vessel,second)) assert(fill.run()=='Running')
local native=f.queued() native:start() native.delta=.25 native:update()
local controller={inspect=function() return {state='STOPPING',npcId=partial.job.npcId,jobId=partial.job.id} end,
    bodySnapshot=function() return {available=true,nativeStopped=f.queued()==nil} end,stopBody=function() return true end}
local stop=Context.stopAdapter(partial,controller,function() return {} end)
assert(stop.requestStop('REVOKED')) local fact=stop.observeStop() assert(stop.persistEffects(fact))
check(fact.bodyStopped and fact.effects=='KNOWN','partial classification reaches the controller stop/save evidence, not only the business Job')
check(vessel.fluid.amount==2 and partial.job.effects=='KNOWN' and partial.job.payload.attempt.receipt.partial
    and partial.job.state=='SUSPENDED' and Store.owner(vessel.id),'controlled stop retains observed partial water and original custody')
partial.stopping=nil partial.body={current=function() return true end,retained=function() return true end,
    add=function(a) f.queue(a) return true end,clear=function() if f.queued() then f.queued():stop() end return true end,
    snapshot=function() return {available=true,nativeStopped=f.queued()==nil} end}
local nextSource=source(3,10)
local more=assert(Water.take(partial,2,vessel,nextSource)) assert(more.run()=='Running')
check(f.queued().startUsedAmount==2 and f.queued().waterUnit==8,'new native constructor plans from actual residual water, not the old full request')
f.queued():complete() f.queued():perform() assert(more.run()=='Success')
check(vessel.fluid.amount==10,'resumed fill keeps prior water without duplicating it')
local chain,bigPot=setup() local first,last=source(4,3),source(5,10)
row.slots={{object=first},{object=last}}
local recipe={hasMinimumWater=function(_,item) return item.fluid.amount/item.fluid.capacity>=.9 end}
local ensure=Water.ensure(chain,recipe,bigPot)
for _=1,100 do
    chain.budget={scan=2,paths=1,nodes=8}
    local state=ensure.run()
    local pending=f.queued()
    if pending then pending:start() pending:complete() pending:perform() end
    if state=='Success' then break end
    assert(state=='Running',tostring(chain.reason))
end
check(bigPot.fluid.amount==10 and first.fluid.amount==0 and last.fluid.amount==3 and chain.job.payload.sequence==2,
    'source exhaustion relocates to the next shared candidate and resumes the same pot')
local mixed,mixedPot=setup() mixedPot.fluid.amount=1 mixedPot.fluid.kind='Bleach'
check(not Water.take(mixed,1,mixedPot,last),'a mixed/dirty pot is never silently drained or diluted')
last.external=true
check(not Sources.read(chain.actor,'kitchen',last),'unproven external-plumbing purification is not assumed to be pure water')
last.external=false
local raced,racedPot=setup() local dry,nextTap=source(7,2),source(8,10)
row.slots={{object=dry},{object=nextTap}}
local continuation=Water.ensure(raced,recipe,racedPot) local drained=false
for _=1,100 do
    raced.budget={scan=2,paths=1,nodes=8}
    local state=continuation.run() local pending=f.queued()
    if pending then
        if not drained then dry.fluid.amount=0 drained=true end
        if pending:isValid() then pending:start() pending:complete() pending:perform() else pending:stop() end
    end
    if state=='Success' then break end assert(state=='Running',tostring(raced.reason))
end
check(racedPot.fluid.amount==10 and raced.job.payload.sequence==2,'a source drained before its first effect also relocates instead of retrying the dry tap')
local bad,badPot=setup() local broken=source(6,5)
local errorLeaf=assert(Water.take(bad,1,badPot,broken)) assert(errorLeaf.run()=='Running')
throwAfter=true f.queued().delta=.2 f.queued():update()
check(bad.job.effects=='UNKNOWN' and bad.job.payload.attempt.state=='UNKNOWN' and badPot.fluid.amount==1,
    'exception after a partial native write leaves unknown responsibility without rolling back liquid')
check(assert(Water.take(bad,1,badPot,broken)).run()=='Failure' and Store.owner(badPot.id),
    'unknown progressive operation cannot be replayed and keeps the actual pot claimed')
print('PASS '..checks..' progressive-water checks; installed native action, mocked world; game NOT RUN')
return {f=f,setup=setup,source=source,row=row,Water=Water}
