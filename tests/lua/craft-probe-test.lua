-- Format=4 Production fixture (rebuilt 2026-11-11).
-- Shared by tests/lua/activity-craft-yield-test.lua, production-three-batch-test.lua
-- and task-production-runtime-test.lua, which dofile this file for `f`.
--
-- e8b30c0 retired the legacy craft stratum (the format<=2 executor inside
-- CraftProbe, BusinessJobs.publishCraft/flush, the legacy recipe path) and
-- Production's direct (non-TaskRuntime) execution mode. This fixture therefore
-- drives the real format=4 Production through the TaskRuntime controlled path:
-- f.Craft is the real CraftProbe facade, f.Work/f.Store are the real modules,
-- and f.tick steps the Runtime so Production contexts advance. Job create /
-- commit go through LaborStore.createClaimedJob/mutateJob, which require the
-- labor kernel entries, so the fixture installs the dec003 Lua host model
-- (tests/lua/fixtures/dec003-craft-kernel-host.lua) against the real JobStore
-- and LaborClaims. There is no 'STARTED' anymore: Production.execute returns 'QUEUED' and the job starts
-- on the next Runtime step, so the dependent tests assert 'QUEUED' (call
-- adaptation only; every scenario assertion survives unchanged).
-- f.Probe.controlledExecution must stay true while a test runs; the old
-- uncontrolled value has no production meaning since the direct mode is gone.
--
-- Recipe under test: Base.SawLogs, one Base.Log + one kept Base.Saw2 yields
-- three Base.Plank per native effect (quantity 9 = three commits).
-- Installed ISHandcraftAction/ActionManager Lua; native bodies, inventories
-- and queue are fakes. Exercises effect fencing/recovery, not animation,
-- Java crafting or physical save durability. No game run.
local clock,serial,nativeCalls=0,0,0
local function list(t)
    t=t or {}
    function t:size() return #self end
    function t:get(i) return self[i+1] end
    function t:add(value) self[#self+1]=value end
    function t:contains(value) for _,v in ipairs(self) do if v==value then return true end end return false end
    function t:isEmpty() return #self==0 end
    return t
end
ArrayList={new=function() return list() end}
local function container()
    local c={items=list(),capacity=100}
    function c:getItems() return self.items end
    function c:contains(item) return self.items:contains(item) end
    function c:getCapacityWeight() local n=0 for _,v in ipairs(self.items) do n=n+v:getUnequippedWeight() end return n end
    function c:getFreeCapacity() return self.capacity-self:getCapacityWeight() end
    function c:getEffectiveCapacity() return self.capacity end
    function c:hasRoomFor(_,v) return self:getCapacityWeight()+v:getUnequippedWeight()<=self.capacity end
    function c:AddItem(item) self.items:add(item) item.container=self return item end
    function c:Remove(item) for i,v in ipairs(self.items) do if v==item then table.remove(self.items,i) item.container=nil return end end end
    return c
end
local function item(kind)
    serial=serial+1 local value={id=serial,kind=kind,condition=10,sharpness=1,mod={}}
    function value:getID() return self.id end
    function value:getFullType() return self.kind end
    function value:getCategory() return "Normal" end
    function value:getContainer() return self.container end
    function value:getCondition() return self.condition end
    function value:getSharpness() return self.sharpness end
    function value:getActualWeight() return self.weight or 1 end
    function value:getUnequippedWeight() return self.weight or 1 end
    function value:getIsCraftingConsumed() return false end
    function value:isEquipped() return self.equipped==true end
    function value:isFavorite() return self.favorite==true end
    function value:setJobDelta() end
    function value:setJobType() end
    function value:getModData() return self.mod end
    return value
end
local square={objects=list()}
function square:getX() return 0 end
function square:getY() return 0 end
function square:getZ() return 0 end
function square:getObjects() return self.objects end
function square:canReachTo() return true end
function square:AddWorldInventoryItem(value) self.dropped=value end
local function character(id)
    local body={id=id,root=container(),actions=list(),known=true,skill=2}
    function body:getInventory() return self.root end
    function body:getMaxWeight() return self.maxWeight or 100 end
    function body:getInventoryWeight() return self.root:getCapacityWeight() end
    function body:getCharacterActions() return self.actions end
    function body:getCurrentSquare() return square end
    function body:getX() return self.x or 0.5 end function body:getY() return 0.5 end function body:getZ() return 0 end
    function body:isDead() return false end
    function body:getUsername() return self.id end
    function body:getFullName() return self.id end
    function body:isRecipeKnown() return self.known end
    function body:learnRecipe() self.known=true end
    function body:getPerkLevel() return self.skill end
    function body:getBodyDamage()
        local part={HasInjury=function() return false end,bandaged=function() return false end,
            bleeding=function() return false end,deepWounded=function() return false end,
            haveBullet=function() return false end,haveGlass=function() return false end,
            getFractureTime=function() return 0 end,getBandageLife=function() return 0 end}
        return {getOverallBodyHealth=function() return 100 end,
            getBodyParts=function() return list({part}) end}
    end
    function body:hasTrait() return false end function body:isWearingAwkwardGloves() return false end
    function body:isTimedActionInstant() return false end
    function body:Say(text) self.speech=text end
    return body
end
local actor,npc=character("local-owner"),character("craft-npc")
-- Base.SawLogs: one consumable log (slot 0) plus one kept saw (slot 1).
local function chainItem(kind)
    return {getFullName=function() return kind end,getDisplayName=function() return kind end,
        getActualWeight=function() return 1 end}
end
local function sawIO(kind,keep,slot)
    local io={kind=kind,keep=keep,index=slot}
    function io:getResourceType() return "Item" end
    function io:isVariableAmount() return false end
    function io:getIntAmount() return 1 end
    function io:isKeep() return self.keep end
    function io:canUseItem(value) return value.kind==self.kind end
    function io:getPossibleInputItems() return list({chainItem(self.kind)}) end
    function io:getOriginalLine() return tostring(self.index)..':'..tostring(self.keep)..':1' end
    function io:isUsesPartialItem() return false end
    function io:hasCreateToItem() return false end
    function io:hasConsumeFromItem() return false end
    function io:isAutomationOnly() return false end
    function io:isWorn() return false end
    function io:isApplyOnTick() return false end
    function io:isDestroy() return not self.keep end
    function io:isAcceptsAnyItem() return false end
    return io
end
local logInput=sawIO('Base.Log',false,0)
local sawInput=sawIO('Base.Saw2',true,1)
local outputItem=chainItem('Base.Plank')
local output={}
function output:getPossibleResultItems() return list({outputItem}) end
function output:getResourceType() return "Item" end
function output:getIntAmount() return 3 end
function output:isVariableAmount() return false end
function output:getChance() return 1 end
function output:isApplyOnTick() return false end
function output:hasCreateToItem() return false end
function output:getOriginalLine() return 'item 3 Base.Plank' end
local recipe={key='Base.SawLogs'}
function recipe:getName() return "Base.SawLogs" end
function recipe:getTranslationName() return "Base.SawLogs" end
function recipe:getCategory() return "Carpentry" end
function recipe:getInputs() return list({logInput,sawInput}) end
function recipe:getOutputs() return list({output}) end
function recipe:getRequiredSkillCount() return 0 end
function recipe:getRequiredSkill() return nil end
function recipe:getRequiredSkills() return list({}) end
function recipe:getIndexForIO(input) return input.index end
function recipe:getIOForIndex(index) return index==0 and logInput or (index==1 and sawInput or nil) end
function recipe:isAnySurfaceCraft() return false end
function recipe:isInHandCraftCraft() return true end
function recipe:requiresSpecificWorkstation() return false end
function recipe:getTimedActionScript() return nil end
function recipe:isCanWalk() return false end
function recipe:getTime() return 1 end
function recipe:isBuildableRecipe() return false end
function recipe:hasOnTickInputs() return false end
function recipe:hasOnTickOutputs() return false end
local object={mod={}}
function object:isGenericCraftingSurface() return self.invalid~=true end
function npc:canUseAsGenericCraftingSurface(target) return target:isGenericCraftingSurface() end
function object:getSquare() return square end
function object:getModData() return self.mod end
function object:getUsingPlayer() return self.occupant end
function object:isUsingPlayer(value) return self.occupant==value end
function object:setUsingPlayer(value) self.occupant=value end
square.objects[1]=object
ResourceType={Item="Item"} ComponentType={CraftBench="CraftBench"} Perks={Carving="Carving"}
CharacterTrait={ALL_THUMBS="allthumbs"} DebugType={CraftLogic=1}
function getScriptManager() return {getCraftRecipe=function(_,id)
        if id=='Base.SawLogs' then return recipe end return nil end,
    getAllCraftRecipes=function() return list({recipe}) end} end
function getCell() return {getGridSquare=function(x) return square end} end
function getTimestampMs() return clock end
function getText(key,value) return key.." "..tostring(value or "") end
function getTextOrNull() return nil end
function getSpecificPlayer() return actor end
function isClient() return false end function isServer() return false end
function log() end function showDebugInfoInChat() end function sendAddItemToContainer() end
function convertToPZNetTable(value) return value end
local saved,queued,mode={},nil,nil
local logs={}
-- The stub Boot the production modules require. Controlled execution is the
-- only execution mode left, so controlledExecution stays true; the dependent
-- tests no longer switch it off.
local Probe={ready=true,controlledExecution=true,failureCode="NOT_STARTED",
    hasJava=function() return true end,unavailableCode=function() return "NOT_READY" end}
function Probe.isPublicDispatch() return Probe.publicDispatch==true end
package.loaded["EmberRoutesProbe/Kernel/Boot"]=Probe
package.loaded["EmberRoutesProbe/Kernel/Log"]={write=function(_,text) logs[#logs+1]=text end}
local boxes={}
local function storage(id,x,kind)
    local endpoint={id=id,container=container(),
        filter={format=1,enabled=true,private=false,priority=3,groups={},types={[kind]=true}}}
    endpoint.object={}
    local sq={getX=function() return x end,getY=function() return 0 end,getZ=function() return 0 end}
    function endpoint.object:getSquare() return sq end
    boxes[id]=endpoint return endpoint
end
local materials=storage("materials",4,"Base.Log")
local tools=storage("tools",8,"Base.Saw2")
local products=storage("products",12,"Base.Plank")
local registry={listeners={},inventoryListeners={},data=function() return saved end,
    id=function() serial=serial+1 return "uuid-"..serial end}
function registry.resolve(id)
    local endpoint=boxes[id]
    if endpoint and not endpoint.private then return endpoint end
    return nil,"CONTAINER_PRIVATE"
end
function registry.revalidate(endpoint) return registry.resolve(endpoint.id) end
function registry.filter(target) for _,endpoint in pairs(boxes) do if endpoint.object==target then return endpoint.filter end end end
function registry.accepts(endpoint,value) return not endpoint.private and endpoint.filter.types[value.kind]==true end
function registry.logistics(endpoint) return endpoint.role or "STORAGE" end
function registry.inventoryChanged() for _,listener in ipairs(registry.inventoryListeners) do listener() end end
package.loaded["EmberRoutesProbe/Warehouse/ContainerRegistry"]=registry
local entry={id="home",areas={{x=0,y=0,w=30,h=2}}}
dofile('tests/lua/membership-fixture.lua')(function() if not entry.denied then return entry end end,{npc.id})
package.loaded["EmberRoutesProbe/Settlement/SettlementLedger"]={
    listeners={},
    get=function() return entry end,at=function() return {entry} end,
    view=function() if entry.denied then return nil,"ACCESS_DENIED" end return entry end}
package.loaded["EmberRoutesProbe/Settlement/SettlementMembership"]={query=function() return {"materials","tools","products"} end}
package.loaded["EmberRoutesProbe/Work/WorkTransfer"]={
    reachable=function(body,endpoint) return math.abs(body:getX()-endpoint.object:getSquare():getX()-0.5)<=1.6 end,
    move=function(context,endpoint) return {start=function() context.npc.x=endpoint.object:getSquare():getX()+0.5 end,poll=function() return "PASSED" end} end}
package.loaded["EmberRoutesProbe/Work/WorkAgent"]={new=function() return {
    busy=function() return false end,pause=function() end,hasCargo=function() return false end,
    prepareRemoval=function() return true end,assign=function() return "ASSIGNED" end,execute=function() return "IGNORED" end,
    resume=function() return "RESUMED" end,tick=function() end} end}
-- Labor kernel host stand-in (TEST ONLY Lua model, the same one the dec003
-- migration tests use): ProductionJobs.create/commit go through
-- LaborStore.createClaimedJob/mutateJob, which require the Java labor
-- kernel entries laborCreate/laborMutate/laborCancel. The host implements
-- them against the real JobStore and LaborClaims. It replaces the bridge
-- table, so the body-control entries below are merged onto it instead of
-- replacing it. Its install arguments are unused by the labor functions
-- (they run on the arguments LaborJobCommit passes), so none are given.
dofile('tests/lua/fixtures/dec003-craft-kernel-host.lua').install()
-- Default body-control bridge for the controlled path. task-production-runtime
-- overrides the control-key functions with its own strict stubs after dofile.
local bridge={selectedId=function() return npc.id end,carrierFor=function() return npc end,
    carrierId=function(body) return body.id end,carrierActive=function() return true end,carrierPresent=function() return true end,
    stopCarrier=function() return true end,
    acquireBodyControl=function(body,job,generation) return 'control:'..tostring(job)..':'..tostring(generation) end,
    bodyStopMask=function(body,key) return body.actions:isEmpty() and 0 or 4 end,
    stopWithControl=function() return true end,releaseBodyControl=function() return true end,
    retireBodyControl=function() return true end,freezeBodyControl=function() return true end,
    thawBodyControl=function() return true end,controlledCarrier=function() return npc end,
    motionResult=function(body) return body.motion or 'STOPPED' end,
    followWithControl=function(body,key,actor,rank) body.motion='FOLLOW_ACTIVE' return 'FOLLOW_STARTED' end,
    moveWithControl=function(body,key,actor,x,y,z) body.x=x body.motion='REACHED' return 'MOVE_REQUESTED' end,
    workerCount=function() return 1 end,workerIdAt=function() return npc.id end,
    recipeHasCallbacks=function(value) return value.callbacks==true end,
    recipeHasSpecialOutputs=function(value) return value.specialOutput==true end,
    recipeKey=function(r) return r.key end,
    -- TEST ONLY Lua host model of the Java kernel entry productionYieldIds:
    -- same pure filter+sort contract as ProductionYieldScan.yieldIds, so the
    -- yield-scan tests exercise the bridge path without the real bridge.
    productionYieldIds=function(crafts)
        local Yield=require 'EmberRoutesProbe/Crafting/ProductionYield'
        local ids={}
        for id,r in pairs(crafts) do if Yield.assetFree(r) then ids[#ids+1]=id end end
        table.sort(ids)
        return ids
    end}
for k,v in pairs(bridge) do EmberRoutesProbeJava[k]=v end
local function dequeue(action) if queued==action then queued=nil npc.actions[1]=nil end end
ISBaseTimedAction={}
function ISBaseTimedAction:derive() return setmetatable({},{__index=self}) end
function ISBaseTimedAction.new(class,body) return setmetatable({character=body},{__index=class}) end
function ISBaseTimedAction.stop(action) dequeue(action) end
function ISBaseTimedAction.perform(action) dequeue(action) end
function ISBaseTimedAction:forceStop() self:stop() end
function ISBaseTimedAction:setOverrideHandModels() end
package.loaded["TimedActions/ISBaseTimedAction"]=true
ISTimedActionQueue={queues={}}
function ISTimedActionQueue.add(action)
    assert(not queued,"probe never queues competing native actions") queued=action npc.actions[1]=action
    if action.start then action:start() else action:startActionAnim() end
end
function ISTimedActionQueue.hasAction(action) return action~=nil and queued==action end
function ISTimedActionQueue.clear() if queued then local old=queued old:stop() dequeue(old) end end
ISInventoryTransferAction={}
function ISInventoryTransferAction:new(body,value,from,to)
    local action={character=body}
    function action:isValid() return true end function action:startActionAnim() self.selectedContainer=from end
    function action:stop() dequeue(self) end
    function action:perform() from:Remove(value) to:AddItem(value) dequeue(self) end
    return action
end
package.loaded["TimedActions/ISInventoryTransferAction"]=true
Events={OnProcessAction={Add=function() end},OnContainerUpdate={Add=function() end},
    OnInitGlobalModData={Add=function() end},OnNewGame={Add=function() end},
    OnGameStart={Add=function() end},OnServerStarted={Add=function() end},
    OnTick={Add=function() end},OnPreMapLoad={Add=function() end},OnSave={Add=function() end},
    OnTickEvenPaused={Add=function() end}}
dofile('D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/shared/ActionManager.lua')
dofile('D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/shared/Entity/TimedActions/ISHandcraftAction.lua')
package.loaded["Entity/TimedActions/ISHandcraftAction"]=true
ISInventoryPage={dirtyUI=function() end}
HandcraftLogic={new=function(body)
    local logic={manual={},outputs=list(),consumed=list()}
    function logic:setContainers() end function logic:setRecipe(value) self.recipe=value end
    function logic:setTargetVariableInputRatio() end function logic:setManualSelectInputs() end
    function logic:clearManualInputs() self.manual={} end
    function logic:setManualInputsFor(io,items) self.manual[io]=items return true end
    function logic:canPerformCurrentRecipe()
        if queued and queued.craftRecipe and queued.craftStarted then return false end
        for _,io in ipairs(self.recipe:getInputs()) do
            local items=self.manual[io]
            if not items or items:size()~=io:getIntAmount() then return false end
            for _,value in ipairs(items) do if value.container~=body.root or not io:canUseItem(value,body) then return false end end
        end
        return true
    end
    function logic:getModelHandOne() end function logic:getModelHandTwo() end
    local recipeData={}
    function recipeData:getAllInputItems()
        local values=list() for _,items in pairs(logic.manual) do for _,value in ipairs(items) do values:add(value) end end return values
    end
    function recipeData:getDataForInputScript(io)
        return {getAppliedItemsCount=function() return #(logic.manual[io] or {}) end,
            hasAppliedItem=function(_,value) return logic.manual[io] and logic.manual[io]:contains(value) or false end}
    end
    function recipeData:getAllConsumedItems() return logic.consumed end
    function recipeData:luaCallOnCreate() end
    function recipeData:processDestroyAndUsedItems()
        for io,values in pairs(logic.manual) do if io:isKeep() then
            for _,value in ipairs(values) do value.condition=value.condition-1 end
        end end
    end
    function logic:getRecipeData() return recipeData end
    function logic:getCreatedOutputItems(target) for _,value in ipairs(self.outputs) do target:add(value) end end
    function logic:performCurrentRecipe()
        nativeCalls=nativeCalls+1
        for io,values in pairs(self.manual) do if not io:isKeep() then
            for _,value in ipairs(values) do body.root:Remove(value) self.consumed:add(value) end
        end end
        if mode=='consume_error' then error('injected exception after consumption') end
        for _,io in ipairs(self.recipe:getOutputs()) do
            for i=1,io:getIntAmount() do self.outputs:add(item(io:getPossibleResultItems():get(0):getFullName())) end
        end
        return true
    end
    return logic
end}
local Work=require "EmberRoutesProbe/Work/Work"
function Probe.cancelAll(reason,id) Work.pause(reason,id) end
local Craft=require "EmberRoutesProbe/Crafting/CraftProbe"
local Store=require "EmberRoutesProbe/Work/LaborStore"
local Runtime=require "EmberRoutesProbe/Runtime/TaskRuntime"
local function fresh(n)
    Work.reset() logs={} saved={} object.mod={} object.occupant=nil object.invalid=false entry.denied=false
    actor.root=container() npc.root=container() actor.known=true npc.known=true npc.skill=2 npc.x=0.5 npc.motion=nil queued=nil npc.actions=list()
    mode=nil nativeCalls=0 square.dropped=nil
    for _,endpoint in pairs(boxes) do endpoint.container=container() endpoint.private=false endpoint.role="STORAGE" end
    materials.filter.types={['Base.Log']=true} tools.filter.types={['Base.Saw2']=true} products.filter.types={['Base.Plank']=true}
    local log
    for i=1,n or 1 do log=materials.container:AddItem(item('Base.Log')) end
    local saw=tools.container:AddItem(item('Base.Saw2'))
    actor.root:AddItem(item('Base.Log')) actor.root:AddItem(item('Base.Saw2'))
    return log,saw
end
-- Poison access: new orders must never read the player's inventory, even as a fallback.
function actor:getInventory() error("PLAYER_INVENTORY_TOUCHED") end
local function tick(effect)
    clock=clock+110 Work.tick()
    local runtime=Runtime.current()
    if runtime then runtime:step() end
    if effect and queued then queued:perform() end
end
-- Fail fast if the saw-log profile stops satisfying the format=4 executor.
local spec=assert(require('EmberRoutesProbe/Crafting/ProductionRecipe').read('Base.SawLogs'),'saw-log recipe profile unreadable')
assert(spec.yield==3 and spec.product=='Base.Plank' and spec.surface==false and spec.station==false,'saw-log profile mismatch')
return {Probe=Probe,Work=Work,Craft=Craft,Store=Store,actor=actor,npc=npc,registry=registry,
    fresh=fresh,recipe=recipe,entry=entry,materials=materials,tools=tools,products=products,tick=tick,
    queued=function() return queued end,nativeCalls=function() return nativeCalls end,
    setMode=function(value) mode=value end,object=object,item=item}
