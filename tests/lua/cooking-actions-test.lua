-- Actual installed add/toggle Lua with fake engine objects. Transfer port is a
-- double at its real transferItem effect boundary. No animation/gameplay claim.
local f=dofile('tests/lua/multi-worker-test.lua')
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Filter=require 'EmberRoutesProbe/StorageFilter'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Context=require 'EmberRoutesProbe/CookingContext'
local Store=require 'EmberRoutesProbe/LaborStore'
local Jobs=require('EmberRoutesProbe/TaskJobs').current()
local list=f.fixture.ctx.list local npc=f.a local root=npc:getInventory()
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
local previous=instanceof
function instanceof(v,kind)
    if not v then return false end
    if kind=='Food' then return v.food==true end
    if kind=='IsoStove' then return v.stove==true end
    return previous(v,kind)
end
local queued
ISTimedActionQueue.hasAction=function(a) return queued==a end
ISBaseTimedAction={}
function ISBaseTimedAction:derive() local t={} t.__index=t setmetatable(t,{__index=self}) return t end
function ISBaseTimedAction:new(character) return setmetatable({character=character},self) end
function ISBaseTimedAction:isValid() return true end
function ISBaseTimedAction:isValidStart() return true end
function ISBaseTimedAction:start() end
function ISBaseTimedAction:update() end
function ISBaseTimedAction:perform() queued=nil end
function ISBaseTimedAction:stop() queued=nil end
function ISBaseTimedAction:setActionAnim(anim) self.animation=anim end
package.loaded['TimedActions/ISBaseTimedAction']=true
ISInventoryPage={dirtyUI=function() end}
Perks={Cooking='Cooking'}
function npc:isTimedActionInstant() return false end
function npc:getPerkLevel() return 0 end
function npc:removeFromHands() end
function npc:getEmitter() return {playSoundImpl=function() return 0 end} end
function npc:getMaxWeight() return 100 end
function root:getEffectiveCapacity() return 150 end
function root:getCapacityWeight() return #self.items end
function root:contains(value) return self.items:contains(value) end
function getItemEvolvedRecipeName(v) return v end
function getItemDisplayName(v) return v end
function getItemFoodType() return 'Vegetables' end
function isItemFood() return true end
local game='D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/'
dofile(game..'shared/TimedActions/ISAddItemInRecipe.lua')
dofile(game..'shared/TimedActions/ISToggleStoveAction.lua')
package.loaded['TimedActions/ISAddItemInRecipe']=true
package.loaded['TimedActions/ISToggleStoveAction']=true
-- Retain the real native separation of perform and transferItem.
local transfers=0
function ISInventoryTransferAction:new(character,item,from,to)
    return {character=character,item=item,isValid=function() return true end,
        isValidStart=function() return true end,start=function() end,update=function() end,
        startActionAnim=function() end,stop=function() queued=nil end,
        transferItem=function(self,value)
            transfers=transfers+1 from:Remove(value) to.items[#to.items+1]=value value.container=to
        end,
        perform=function(self) self:checkQueueList() self:transferItem(self.item) queued=nil end}
end
local function item(kind,food,container)
    local value=f.fixture.item(kind,container or root)
    function value:getDisplayName() return self.kind end
    function value:getIsCraftingConsumed() return false end
    function value:setJobType() end
    function value:setJobDelta() end
    function value:getExtraItems() return self.extra end
    value.food=food value.raw=food and 0.2 or nil
    if food then
        function value:getHungChange() return -self.raw end
        function value:getHungerChange() return -self.raw end
        function value:getBaseHunger() return -self.raw end
        function value:isCooked() return self.cooked==true end
        function value:isCookable() return self.kind=='Base.PotOfSoupRecipe' end
        function value:getReplaceOnCooked() return self.replaceCooked end
        function value:getOnCooked() return self.onCooked end
        function value:isRotten() return false end
        function value:isBurnt() return false end
        function value:isPoison() return false end
        function value:getPoisonPower() return 0 end
        function value:isTainted() return false end
        function value:isbDangerousUncooked() return self.kind=='Base.PotOfSoupRecipe' end
        function value:isFrozen() return false end
        function value:isSpice() return self.spice==true end
        function value:getRequireInHandOrInventory() return nil end
        function value:getExtraItems() return self.extra end
        function value:getSpices() return self.spices end
        function value:getHeat() return 1 end
        function value:setHeat() end
        function value:isCustomName() return false end
        function value:getFoodType() return 'Soup' end
        function value:setName() end
    end
    return value
end
local serial=0
local function context(assets)
    serial=serial+1
    local j=assert(Record.new('native-cook-'..serial,npc.id,'kitchen','Soup','AUTO','policy:kitchen',0.3,0.3))
    for _,value in ipairs(assets or {}) do
        j.payload.assets[#j.payload.assets+1]={id=value:getID(),fullType=value:getFullType(),custody='HELD',role='INPUT'}
        j.payload.claims[#j.payload.claims+1]='item:'..value:getID()
    end
    assert(Jobs:create(j))
    local c={job=j,token=assert(Store.claimCooking(j)),npc=npc,valid=function() return true end,live=true,retained=true}
    c.body={current=function() return c.live end,retained=function() return c.retained end,
        add=function(action) queued=action return true end,
        clear=function() if queued then queued:stop() end return true end}
    return c
end
local additions=0 local throwAfterReplacement=false
local recipe={}
function recipe:getOriginalname() return 'Soup' end
function recipe:getUntranslatedName() return 'Soup' end
function recipe:getAddIngredientSound() return nil end
function recipe:getItemsCanBeUse(_,_,_) return {contains=function() return true end} end
function recipe:isItemUsableInRecipe() return true end
function recipe:isResultItem(v) return v.kind=='Base.PotOfSoupRecipe' end
function recipe:isSpiceAdded(base,ingredient) return base.spices and base.spices:contains(ingredient.kind) or false end
function recipe:addItem(base,ingredient)
    local owner=Store.owner(ingredient.id)
    local durable=owner and Jobs:peek(owner.taskId)
    assert(durable and durable.effects=='UNKNOWN' and durable.payload.attempt.state=='COMMITTING',
        'durable barrier must be published before entering vanilla irreversible method')
    additions=additions+1
    local result=base
    if not base.food then
        root:Remove(base) result=item('Base.PotOfSoupRecipe',true)
    end
    ingredient.raw=math.max(0,ingredient.raw-0.05)
    if ingredient.raw<0.01 then root:Remove(ingredient) end
    if ingredient.spice then result.spices=result.spices or list({}) result.spices[#result.spices+1]=ingredient.kind
    else result.extra=result.extra or list({}) result.extra[#result.extra+1]=ingredient.kind end
    if throwAfterReplacement then error('native failure after replacement') end
    return result
end
local A=require 'EmberRoutesProbe/CookingActions'
local Duty=require 'EmberRoutesProbe/CookingDuty'
local Inventory=require 'EmberRoutesProbe/CookingInventory'
local base,carrot=item('Base.Pot',false),item('Base.Carrot',true)
local c=context({base,carrot})
local add=assert(A.add(c,1,recipe,base,carrot))
check(c.job.payload.attempt.state=='PREPARED' and not queued,'preparing leaf persists intent but does not enqueue')
check(add.run()=='Running','first authorized run queues native add action')
local action=queued action:start()
check(action.animation=='Craft','presentation uses current native action and craft animation')
check(action:complete() and not action:complete(),'actual vanilla complete is fenced against duplicate add')
local result=action.baseItem action:perform()
check(add.run()=='Success' and additions==1 and carrot.raw<0.2,'native partial consumption and output require observed receipt')
check(Store.owner(result:getID()).taskId==c.job.id and not Store.owner(base:getID()),'replacement base retains new original and settles consumed base')
check(Inventory.asset(c.job,base:getID()).custody=='CONSUMED','old base remains auditable without recreation')
local outputRef=assert(Record.outputReference(c.job,1,1))
check(Record.resolveOutput(c.job,outputRef).id==result:getID(),
    'next step resolves the actual replacement original through its committed output reference')
local restored=Record.copy(c.job)
check(Record.resolveOutput(restored,outputRef).id==result:getID(),'output reference survives a detached saved-data copy')
local forgedRef=Record.copy(outputRef) forgedRef.attemptId='other-job:1'
check(not Record.resolveOutput(c.job,forgedRef),'a reference from another attempt cannot resolve by type or sequence alone')
local rewritten=Record.copy(c.job) rewritten.payload.bindings[1].outputIds[1]=base:getID()
check(not Record.transition(c.job,rewritten),'committed output binding cannot be rewritten to the old pot')
local removed=Record.copy(c.job) removed.payload.bindings=nil
check(not Record.transition(c.job,removed),'later updates cannot erase output history')
local sequence=c.job.payload.sequence
local replay=assert(A.add(c,1,recipe,base,carrot))
check(replay.run()=='Success' and c.job.payload.sequence==sequence and not queued and additions==1,'known attempt reconstructs result without replay')
local salt=item('Base.Salt',true) salt.spice=true salt.raw=0.055
local j=Record.copy(c.job) j.payload.assets[#j.payload.assets+1]={id=salt:getID(),fullType=salt.kind,custody='HELD'}
j.payload.claims[#j.payload.claims+1]='item:'..salt:getID() assert(Context.publish(c,j))
local seasoning=assert(A.add(c,2,recipe,result,salt)) assert(seasoning.run()=='Running')
assert(queued:complete()) queued:perform()
check(c.job.payload.spiceCount==1 and recipe:isSpiceAdded(result,salt),'real vanilla complete records partial spice use')
check(salt.raw>0 and not salt:getContainer() and Inventory.asset(c.job,salt.id).custody=='CONSUMED',
    'native final-use threshold may remove ingredient with positive raw remainder')
check(not A.add(c,3,recipe,result,salt),'same spice cannot be added a second time')
check(not A.add(c,1,recipe,base,carrot),'superseded sequence cannot replay after next ingredient')
check(#c.job.payload.bindings==2 and c.job.payload.bindings[2].attemptId==c.job.payload.attempt.id,
    'each observed add appends exactly one binding; replay appends none')
local p2,v2=item('Base.Pot',false),item('Base.Carrot',true)
local stopped=context({p2,v2}) local cancelled=assert(A.add(stopped,1,recipe,p2,v2))
assert(cancelled.run()=='Running') queued:stop()
check(stopped.job.payload.attempt.state=='ABORTED' and stopped.job.effects=='KNOWN' and v2.raw==0.2,
    'unchanged pre-effect cancellation records no-effect and keeps originals')
local p3,v3=item('Base.Pot',false),item('Base.Carrot',true)
local changed=context({p3,v3}) local external=assert(A.add(changed,1,recipe,p3,v3))
assert(external.run()=='Running') v3.raw=0.1 local old=additions
check(not queued:complete() and additions==old and changed.job.effects=='UNKNOWN','foreign depletion is isolated before another native mutation')
queued:stop()
local p4,v4=item('Base.Pot',false),item('Base.Carrot',true)
local failed=context({p4,v4}) local failure=assert(A.add(failed,1,recipe,p4,v4))
assert(failure.run()=='Running') throwAfterReplacement=true
check(not queued:complete() and failed.job.effects=='UNKNOWN','native throw after replacement cannot authorize replay')
throwAfterReplacement=false queued:stop()
local addedId
for _,asset in ipairs(failed.job.payload.assets) do if asset.id~=p4.id and asset.id~=v4.id then addedId=asset.id end end
check(addedId and Store.owner(addedId).taskId==failed.job.id and Store.owner(p4.id).taskId==failed.job.id,
    'even an exception retains observed new output and old unknown originals together')
check(not A.add(failed,2,recipe,p4,v4),'unknown operation cannot admit next effect')
local p5,v5=item('Base.Pot',false),item('Base.Carrot',true)
local oldBody=context({p5,v5}) local oldLeaf=assert(A.add(oldBody,1,recipe,p5,v5))
assert(oldLeaf.run()=='Running') local oldAction=queued oldBody.live=false
check(not oldAction:complete() and v5.raw==0.2,'stale body cannot enter native effect')
check(oldLeaf.halt() and oldBody.job.payload.attempt.state=='ABORTED','retained stopping capability cancels unchanged original without a second body')
-- Actual vanilla stove Toggle: one on, one off; original objects never recreated.
local actor=f.actor actor.x=1004.5
local stove=f.fixture.object(1004) stove.stove=true stove.active=false
local toggles=0
function stove:isMicrowave() return false end
function stove:isBroken() return false end
function stove:Activated() return self.active end
function stove:Toggle() toggles=toggles+1 self.active=not self.active end
function stove:PlayToggleSound() end
function stove:getObjectIndex() return 0 end
function stove.container:isPowered() return true end
local allowed=Filter.new() allowed.types['Base.PotOfSoupRecipe']=true
assert(Registry.configure(actor,stove,allowed,stove.container,'STORAGE')=='FILTER_CONFIGURED')
local endpoint=assert(Registry.resolve(Registry.metadata(stove,stove.container).id,'put','local-world'))
npc.x,npc.y=1004.5,0.5
local meal=item('Base.PotOfSoupRecipe',true)
local heat=context({meal})
assert(Duty.reserve(heat,endpoint))
local put=assert(A.transfer(heat,1,meal,endpoint,'PUT','STATION')) assert(put.run()=='Running')
local putAction=queued putAction:perform() putAction:perform()
check(transfers==1 and meal:getContainer()==stove.container and put.run()=='Success','one transferItem commit ignores duplicate native perform')
local on=assert(A.toggle(heat,2,endpoint,true)) assert(on.run()=='Running')
local onAction=queued assert(onAction:complete()) onAction:complete() onAction:perform()
check(stove.active and toggles==1 and heat.job.payload.duty.openedByJob,'vanilla Toggle runs once and persists activation ownership')
check(not A.toggle(heat,2,endpoint,false),'same sequence cannot reverse its stored switch intent')
local foreign=item('Base.Carrot',true,stove.container)
check(not A.toggle(heat,3,endpoint,false) and stove.active,'foreign contents block shutting down player work')
stove.container:Remove(foreign)
meal.cooked=true
check(Duty.observe(heat,endpoint).state=='STOP_REQUIRED','actual cooked food requests safe shutdown')
local off=assert(A.toggle(heat,3,endpoint,false)) assert(off.run()=='Running')
local offAction=queued assert(offAction:complete()) offAction:complete() offAction:perform()
check(not stove.active and toggles==2 and heat.job.payload.duty.shutdownObserved,'shutdown is observed and duplicate Toggle cannot relight')
check(not Duty.release(heat,endpoint),'shutdown alone does not release food still inside oven')
local take=assert(A.transfer(heat,4,meal,endpoint,'TAKE')) assert(take.run()=='Running') queued:perform()
check(take.run()=='Success' and meal:getContainer()==root and Duty.release(heat,endpoint),
    'unload original then release duty using retained shutdown evidence')
check(not Store.resourceOwner('cooking:'..endpoint.id) and Store.owner(meal.id).taskId==heat.job.id,
    'furnace released independently while original prepared meal remains owned')
local fridge=f.fixture.object(1005) actor.x=1005.5
local powered=true
function fridge.container:isFridge() return true end
function fridge.container:isFreezer() return false end
function fridge.container:isPowered() return powered end
function fridge.container:getTemperature() return powered and 0.2 or 1 end
assert(Registry.configure(actor,fridge,allowed,fridge.container,'STORAGE')=='FILTER_CONFIGURED')
local destination=assert(Registry.resolve(Registry.metadata(fridge,fridge.container).id,'put','local-world'))
local deliver=assert(A.transfer(heat,5,meal,destination,'PUT','DELIVERED')) assert(deliver.run()=='Running')
powered=false queued:perform()
check(meal:getContainer()==root and heat.job.payload.attempt.state=='ABORTED','power failure at commit leaves finished original owned on chef')
powered=true
local final=assert(A.transfer(heat,6,meal,destination,'PUT','DELIVERED')) assert(final.run()=='Running') queued:perform()
check(final.run()=='Success' and meal:getContainer()==fridge.container and not Store.owner(meal.id),
    'confirmed cold delivery releases same meal original, no recreate or replacement')
check(Inventory.asset(heat.job,meal.id).effective==0.2 and heat.job.payload.expected==0.2,
    'direct heating records actual cooked contribution before supply handoff')
local outageMeal=item('Base.PotOfSoupRecipe',true) local outage=context({outageMeal})
assert(Duty.reserve(outage,endpoint))
local load=assert(A.transfer(outage,1,outageMeal,endpoint,'PUT','STATION')) assert(load.run()=='Running') queued:perform()
local ignite=assert(A.toggle(outage,2,endpoint,true)) assert(ignite.run()=='Running') assert(queued:complete()) queued:perform()
stove.active=false -- Native power loss/player switch-off, not our own Toggle.
check(Duty.observe(outage,endpoint).state=='STOP_REQUIRED' and outage.job.payload.duty.shutdownObserved,
    'observed external OFF of owned stove permits safe unloading without relighting')
check(not A.toggle(outage,3,endpoint,true),'external OFF cannot restart an already owned cooking cycle')
local recover=assert(A.transfer(outage,3,outageMeal,endpoint,'TAKE')) assert(recover.run()=='Running') queued:perform()
check(Duty.release(outage,endpoint) and outageMeal:getContainer()==root,'known external shutdown still retains and returns unfinished food original')
print('PASS cooking actions '..checks..' checks; installed add/toggle Lua, fake engine objects; no gameplay run')
return {fixture=f,npc=npc,root=root,item=item,context=context,list=list,
    queued=function() return queued end,queue=function(action) queued=action end}
