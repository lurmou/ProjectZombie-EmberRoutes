-- Installed ISHandcraftAction, shared real Jobs/Claims; engine entities/fluids mocked.
local f=dofile('tests/lua/cooking-actions-test.lua')
local checkCount=0 local function check(v,m) checkCount=checkCount+1 assert(v,m) end
local root,npc=f.root,f.npc
local function list(values)
    local result=f.list(values or {})
    function result:add(value) self[#self+1]=value end
    return result
end
ArrayList={new=function() return list() end}
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Context=require 'EmberRoutesProbe/CookingContext'
local Store=require 'EmberRoutesProbe/LaborStore'
local Fluids=require 'EmberRoutesProbe/CraftFluids'
local Stations=require 'EmberRoutesProbe/CraftStations'
local Actions=require 'EmberRoutesProbe/CookingActions'
local Jobs=require('EmberRoutesProbe/TaskJobs').current()
ResourceType={Item='Item',Fluid='Fluid'} ComponentType={CraftBench='CraftBench'}
CharacterTrait={ALL_THUMBS='allthumbs'} DebugType={CraftLogic='CraftLogic'}
function npc:hasTrait() return false end function npc:isWearingAwkwardGloves() return false end
function npc:isRecipeKnown() return self.known~=false end
function log() end function showDebugInfoInChat() end
function convertToPZNetTable(v) return v end
function ISBaseTimedAction:forceStop() self:stop() end
function ISBaseTimedAction:setOverrideHandModels() end
local game='D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/'
dofile(game..'shared/Entity/TimedActions/ISHandcraftAction.lua')
package.loaded['Entity/TimedActions/ISHandcraftAction']=true
local sampleCount,releaseCount=0,0
local function milkContainer(volume,capacity)
    local c={parts={{kind='CowMilk',amount=volume}},capacity=capacity or 10}
    function c:getAmount() local n=0 for _,p in ipairs(self.parts) do n=n+p.amount end return n end
    function c:getCapacity() return self.capacity end
    function c:createFluidSample()
        sampleCount=sampleCount+1 local parts={}
        local total=self:getAmount()
        for _,p in ipairs(self.parts) do if p.amount>0 then parts[#parts+1]={kind=p.kind,amount=p.amount} end end
        return {size=function() return #parts end,
            getFluid=function(_,i) return {getFluidTypeString=function() return parts[i+1].kind end} end,
            getPercentage=function(_,i) return parts[i+1].amount/total end,
            getFluidInstance=function() error('unexposed native FluidInstance must never be called') end,
            release=function() releaseCount=releaseCount+1 end}
    end
    function c:remove(n)
        local ratio=(self:getAmount()-n)/self:getAmount()
        for _,p in ipairs(self.parts) do p.amount=p.amount*ratio end
    end
    return c
end
local parent={index=0} local fluid={index=1,parent=parent}
parent.child=fluid
for _,io in ipairs({parent,fluid}) do
    function io:getResourceType() return self==parent and 'Item' or 'Fluid' end
    function io:getAmount() return self==parent and 1 or 5 end
    function io:getIntAmount() return self:getAmount() end
    function io:getOriginalLine() return self==parent and 'item 1 [*]' or '-fluid 5.0 [CowMilk;SheepMilk] mode:mixture' end
    function io:isVariableAmount() return false end
    function io:isKeep() return self==parent end function io:isDestroy() return false end
    function io:hasParentScript() return self.parent~=nil end function io:getParentScript() return self.parent end
    function io:hasConsumeFromItem() return self.child~=nil end function io:getConsumeFromItemScript() return self.child end
    function io:hasCreateToItem() return false end function io:isAutomationOnly() return false end
    function io:isWorn() return false end function io:isApplyOnTick() return false end
    function io:getFluidMatchMode() return 'mixture' end
    function io:canUseItem(item) return item:getFluidContainer()~=nil end
    function io:isFluidMatch(c)
        for _,part in ipairs(c.parts) do if part.kind~='CowMilk' and part.kind~='SheepMilk' then return false end end
        return true
    end
end
local product={getFullName=function() return 'Base.Butter' end,getActualWeight=function() return 1 end}
local output={getResourceType=function() return 'Item' end,getIntAmount=function() return 1 end,
    getOriginalLine=function() return 'item 1 Base.Butter' end,getChance=function() return 1 end,
    isVariableAmount=function() return false end,isApplyOnTick=function() return false end,
    hasCreateToItem=function() return false end,getPossibleResultItems=function() return list({product}) end}
local recipe={}
function recipe:getInputs() return list({parent,fluid}) end function recipe:getOutputs() return list({output}) end
function recipe:getIndexForIO(io) return io.index end
function recipe:getIOForIndex(i) return i==0 and parent or fluid end
function recipe:getName() return 'churn_butter' end function recipe:getTranslationName() return 'Butter' end
function recipe:getTime() return 500 end function recipe:getTimedActionScript() end
function recipe:isCanWalk() return false end function recipe:isAnySurfaceCraft() return false end
function recipe:isInHandCraftCraft() return false end function recipe:requiresSpecificWorkstation() return true end
function recipe:isBuildableRecipe() return false end function recipe:hasOnTickInputs() return false end
function recipe:hasOnTickOutputs() return false end function recipe:getRequiredSkills() return list() end
function recipe:getRequiredSkillCount() return 0 end
function getScriptManager() return {getCraftRecipe=function(_,id) return id=='Base.churn_butter' and recipe end} end
EmberRoutesProbeJava.recipeHasCallbacks=function() return recipe.callback==true end
EmberRoutesProbeJava.recipeHasSpecialOutputs=function() return false end
local square={objects=list()}
function square:getX() return 1 end function square:getY() return 1 end function square:getZ() return 0 end
function square:getObjects() return self.objects end
function getCell() return {getGridSquare=function() return square end} end
local bench={getRecipes=function() return list({recipe}) end}
local object={mod={}}
function object:getModData() return self.mod end function object:getSquare() return square end
function object:getComponent(kind) return kind=='CraftBench' and bench end
function object:getUsingPlayer() return self.user end
function object:isUsingPlayer(p) return self.user==p end function object:setUsingPlayer(p) self.user=p end
square.objects:add(object)
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local permitted=true
Ledger.view=function(actor,id)
    if actor==f.fixture.actor and id=='kitchen' and permitted then return {id=id,areas={{x=0,y=0,w=10,h=10}}} end
end
local commits=0 local mode
HandcraftLogic={new=function(body)
    local logic={manual={},outputs=list(),consumed=list()}
    function logic:isCharacterInRangeOfWorkbench() return body.far~=true end
    function logic:setContainers() end function logic:setRecipe(r) self.recipe=r end
    function logic:setTargetVariableInputRatio() end function logic:setManualSelectInputs() end
    function logic:clearManualInputs() self.manual={} end
    function logic:setManualInputsFor(io,items) self.manual[io]=items return true end
    function logic:canPerformCurrentRecipe() return self.manual[parent]~=nil end
    function logic:getModelHandOne() end function logic:getModelHandTwo() end
    local data={getAllInputItems=function() return logic.manual[parent] or list() end,
        getDataForInputScript=function(_,io) return {getAppliedItemsCount=function() return (logic.manual[io] or list()):size() end,
            hasAppliedItem=function(_,value) return (logic.manual[io] or list()):contains(value) end} end,
        getAllConsumedItems=function() return logic.consumed end,luaCallOnCreate=function() end,processDestroyAndUsedItems=function() end}
    function logic:getRecipeData() return data end
    function logic:getCreatedOutputItems(target) for _,value in ipairs(self.outputs) do target:add(value) end end
    function logic:performCurrentRecipe()
        local container=self.manual[parent]:get(0)
        local owner=assert(Store.owner(container.id))
        local durable=assert(Jobs:peek(owner.taskId))
        assert(durable.effects=='UNKNOWN' and durable.payload.attempt.state=='COMMITTING','native effect requires durable barrier')
        commits=commits+1
        container.fluid:remove(mode=='wrong-volume' and 4 or 5)
        local butter=f.item('Base.Butter',true) root:Remove(butter) self.outputs:add(butter)
        if mode=='throw-after-output' then root.items[#root.items+1]=butter butter.container=root error('native partial completion') end
        return true
    end
    return logic
end}
_G.Actions={addOrDropItem=function(_,item)
    if mode=='drop' then
        item.world={getSquare=function() return square end,getWorldObjectIndex=function() return 0 end}
        function item:getWorldItem() return self.world end
    else root.items[#root.items+1]=item item.container=root end
end}
local function setup(volume)
    mode=nil object.user=nil object.mod.EmberRoutesCraftOccupancy=nil npc.known=true npc.far=false permitted=true
    local item=f.item('Mod.MilkCarrier',false) item.fluid=milkContainer(volume or 6)
    function item:getFluidContainer() return self.fluid end
    local c=f.context({item}) c.actor=f.fixture.actor
    c.body.snapshot=function() return {available=true,nativeStopped=f.queued()==nil} end
    return c,item
end
local function leaf(c,item) return Actions.craft(c,1,'Base.churn_butter',{{slot=0,item=item,id=item.id}},object) end
local c,milk=setup()
local action=assert(leaf(c,milk))
check(action.run()=='Running' and object.user==npc,'native UsingPlayer is acquired before first native validity check')
local native=f.queued() native:start() native:perform()
check(action.run()=='Success' and c.job.payload.attempt.state=='APPLIED',
    'installed handcraft confirm: '..tostring(c.reason)..' / '..tostring(native.failure)..' / '..tostring(c.job.payload.attempt.state))
check(milk.fluid:getAmount()==1 and milk:getContainer()==root and Store.owner(milk.id),'milk is consumed inside the retained original carrier')
check(not object.user and not c.job.payload.station,'normal completion clears physical occupancy before logical station claim')
local ref=assert(Record.outputReference(c.job,1,1))
check(Record.resolveOutput(c.job,ref).fullType=='Base.Butter','observed Butter original becomes the next step output')
local replay=assert(leaf(c,milk)) check(replay.run()=='Success' and commits==1,'known replay does not churn another batch')
check(not Actions.craft(c,1,'Base.churn_butter',{{slot=99,item=milk,id=milk.id}},object),
    'known replay cannot reinterpret the original input as a different IO slot')
local wrong,wrongMilk=setup() local bad=assert(leaf(wrong,wrongMilk)) assert(bad.run()=='Running')
f.queued():start() mode='wrong-volume' f.queued():perform()
check(wrong.job.effects=='UNKNOWN' and wrong.job.payload.attempt.state=='UNKNOWN','wrong native depletion does not confirm expected five litres')
check(#wrong.job.payload.assets==2 and Store.owner(wrong.job.payload.assets[2].id),'unexpected result still claims the actual output')
local nonce=wrong.job.payload.station.leaseId
check(Stations.release(wrong,true,nonce) and not object.user and wrong.job.payload.station.state=='RELEASED',
    'unknown effects can clear proven native occupancy while retaining logical station responsibility')
-- Avoid reusing a retained physical station in subsequent independent fixtures.
object.mod.EmberRoutesCraftProbeBenchId=nil
local cancelled,cancelMilk=setup() local cancel=assert(leaf(cancelled,cancelMilk)) assert(cancel.run()=='Running')
local controller={inspect=function() return {state='STOPPING',npcId=npc.id,jobId=cancelled.job.id} end,
    bodySnapshot=function() return {available=true,nativeStopped=f.queued()==nil} end,stopBody=function() return true end}
local stop=Context.stopAdapter(cancelled,controller,function() return {} end)
check(stop.requestStop('REVOKED') and f.queued()==nil,'session revoke clears the owned action through existing stop protocol')
local stopped=stop.observeStop()
check(stopped.bodyStopped and stop.persistEffects(stopped) and not object.user,'proven session stop clears UsingPlayer without relying on action completion')
check(cancelled.job.effects=='KNOWN' and cancelled.job.payload.attempt.state=='ABORTED' and cancelMilk.fluid:getAmount()==6,
    'pre-effect revoke leaves original fluid untouched and records a known cancellation')
local short,shortMilk=setup(2.5)
check(not leaf(short,shortMilk) and not object.user,'insufficient single carrier cannot acquire or start the workstation')
local held,heldMilk=setup() local pending=assert(leaf(held,heldMilk))
local heldNonce=held.job.payload.station.leaseId
local player={id='player'} object.user=player
check(Stations.release(held,true,heldNonce) and object.user==player,
    'releasing an unused reservation does not clear a player who arrived first')
object.user=nil
local moved,movedMilk=setup() local unstarted=assert(leaf(moved,movedMilk))
local movedNonce=moved.job.payload.station.leaseId
square.objects[1]=nil
check(Stations.release(moved,true,movedNonce) and not moved.job.payload.station,
    'a never-acquired reservation can settle after its furniture disappears')
square.objects[1]=object
local stale,staleMilk=setup() local oldLeaf=assert(leaf(stale,staleMilk)) assert(oldLeaf.run()=='Running')
local oldNonce=stale.job.payload.station.leaseId
object.mod.EmberRoutesCraftOccupancy={leaseId='successor',npcId=npc.id,jobId='next-job'}
check(not Stations.release(stale,true,oldNonce) and object.user==npc,'old cleanup cannot clear successor marker even for the same NPC')
f.queue(nil) object.mod.EmberRoutesCraftProbeBenchId=nil
local dropped,droppedMilk=setup() local vanished=assert(leaf(dropped,droppedMilk)) assert(vanished.run()=='Running')
f.queue(nil) -- Engine/session interruption bypassed action.stop entirely.
local droppedController={inspect=function() return {state='STOPPING',npcId=npc.id,jobId=dropped.job.id} end,
    bodySnapshot=function() return {available=true,nativeStopped=true} end,stopBody=function() return true end}
local droppedStop=Context.stopAdapter(dropped,droppedController,function() return {} end)
assert(droppedStop.requestStop('NATIVE_QUEUE_DROPPED'))
check(droppedStop.persistEffects(droppedStop.observeStop()) and not object.user
    and dropped.job.payload.attempt.state=='ABORTED','session stop settles unchanged input even when action.stop never ran')
local mix=milkContainer(4) mix.parts={{kind='CowMilk',amount=4},{kind='SheepMilk',amount=2}}
local before=assert(Fluids.read(mix)) mix:remove(5)
check(Fluids.consumed(before,assert(Fluids.read(mix)),5),'native proportional mixed milk removal is accepted')
mix.parts={{kind='CowMilk',amount=1}}
check(not Fluids.consumed(before,assert(Fluids.read(mix)),5),'same leftover total with changed mixture is not consumption proof')
local unknown,unknownMilk=setup() npc.known=false
check(not leaf(unknown,unknownMilk) and not object.user,'actual NPC recipe knowledge remains mandatory')
local failed,failedMilk=setup() local failure=assert(leaf(failed,failedMilk)) assert(failure.run()=='Running')
f.queued():start() mode='throw-after-output' f.queued():perform()
check(failed.job.effects=='UNKNOWN' and #failed.job.payload.assets==2,'native exception after producing an original retains output and blocks replay')
check(failure.run()=='Failure' and failed.job.payload.attempt.state=='UNKNOWN','partial native result never becomes a fresh attempt')
object.mod.EmberRoutesCraftProbeBenchId=nil
local ground,groundMilk=setup() local spill=assert(leaf(ground,groundMilk)) assert(spill.run()=='Running')
f.queued():start() mode='drop' f.queued():perform()
check(ground.job.effects=='UNKNOWN' and ground.job.payload.assets[2].custody=='WORLD'
    and Store.owner(ground.job.payload.assets[2].id),'dropped output remains an owned actual world original, never a successful inventory delivery')
check(sampleCount==releaseCount,'all pooled native fluid samples are released')
print('PASS '..checkCount..' workstation/compound-fluid checks; installed craft Lua, fake engine; gameplay NOT RUN')
return {f=f,npc=npc,root=root,object=object,recipe=recipe,parent=parent,milkContainer=milkContainer,
    commits=function() return commits end,mode=function(value) mode=value end}
