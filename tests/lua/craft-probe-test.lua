-- Installed ISHandcraftAction/ActionManager Lua; native bodies, inventories and queue are fakes.
-- Exercises effect fencing/recovery, not animation, Java crafting or physical save durability.
local checks,clock,serial,nativeCalls=0,0,0,0
local function check(value,message) checks=checks+1 assert(value,message) end
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
    function c:getCapacityWeight() return #self.items end
    function c:getFreeCapacity() return self.capacity-#self.items end
    function c:getEffectiveCapacity() return self.capacity end
    function c:hasRoomFor() return #self.items+1<=self.capacity end
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
    function value:getActualWeight() return 1 end
    function value:getUnequippedWeight() return 1 end
    function value:getIsCraftingConsumed() return false end -- new craft path need not set the legacy flag
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
    function body:getMaxWeight() return 100 end
    function body:getInventoryWeight() return self.root:getCapacityWeight() end
    function body:getCharacterActions() return self.actions end
    function body:getCurrentSquare() return square end
    function body:getX() return self.x or 0.5 end function body:getY() return 0.5 end function body:getZ() return 0 end
    function body:isDead() return false end
    function body:getUsername() return self.id end
    function body:isRecipeKnown() return self.known end
    function body:learnRecipe() self.known=true end
    function body:getPerkLevel() return self.skill end
    function body:getBodyDamage() return {getOverallBodyHealth=function() return 100 end} end
    function body:hasTrait() return false end function body:isWearingAwkwardGloves() return false end
    function body:isTimedActionInstant() return false end
    function body:Say(text) self.speech=text end
    return body
end
local actor,npc=character("local-owner"),character("craft-npc")
local materialInput={keep=false,index=9},toolInput
toolInput={keep=true,index=4}
for _,input in ipairs({materialInput,toolInput}) do
    function input:getResourceType() return "Item" end
    function input:isVariableAmount() return false end
    function input:getIntAmount() return 1 end
    function input:isKeep() return self.keep end
    function input:canUseItem(value) return self.keep and value.kind=="Base.KitchenKnife" and value.sharpness>0
        or (not self.keep and value.kind=="Base.SmallHandle") end
end
local outputItem={getFullName=function() return "Base.WoodenFork" end,getActualWeight=function() return 1 end}
local output={getPossibleResultItems=function() return list({outputItem}) end,getResourceType=function() return "Item" end,
    getIntAmount=function() return 1 end,isVariableAmount=function() return false end}
local recipe={}
function recipe:getName() return "CarveWoodenFork" end
function recipe:getInputs() return list({toolInput,materialInput}) end
function recipe:getOutputs() return list({output}) end
function recipe:getRequiredSkillCount() return 1 end
function recipe:needToBeLearn() return true end
function recipe:getRequiredSkill() return {getPerk=function() return "Carving" end,getLevel=function() return 2 end} end
function recipe:getIndexForIO(input) return input.index end
function recipe:getIOForIndex(index) return index==4 and toolInput or (index==9 and materialInput or nil) end
function recipe:isAnySurfaceCraft() return true end
function recipe:requiresSpecificWorkstation() return false end
function recipe:getTimedActionScript() return nil end
function recipe:isCanWalk() return false end
function recipe:getTime() return 1 end
function recipe:getTranslationName() return "Wooden Fork" end
local bench={getRecipes=function() return list({recipe}) end}
local object={mod={}}
function object:isGenericCraftingSurface() return self.invalid~=true end
function npc:canUseAsGenericCraftingSurface(target) return target:isGenericCraftingSurface() end
-- Ordinary table: no entity script or CraftBench component API at all.
function object:getSquare() return square end
function object:getModData() return self.mod end
function object:getUsingPlayer() return self.occupant end
function object:isUsingPlayer(value) return self.occupant==value end
function object:setUsingPlayer(value) self.occupant=value end
square.objects[1]=object
ResourceType={Item="Item"} ComponentType={CraftBench="CraftBench"} Perks={Carving="Carving"}
CharacterTrait={ALL_THUMBS="allthumbs"} DebugType={CraftLogic=1}
function getScriptManager() return {getCraftRecipe=function() return recipe end} end
function getCell() return {getGridSquare=function(x) return square end} end
function getTimestampMs() return clock end
function getText(key,value) return key.." "..tostring(value or "") end
function getSpecificPlayer() return actor end
function isClient() return false end function isServer() return false end
function log() end function showDebugInfoInChat() end function sendAddItemToContainer() end
function convertToPZNetTable(value) return value end
local saved,owners,queued,mode={}, {},nil,nil
local logs={}
local Probe={ready=true,hasJava=function() return true end,unavailableCode=function() return "NOT_READY" end}
package.loaded["EmberRoutesProbe/Boot"]=Probe
package.loaded["EmberRoutesProbe/Log"]={write=function(_,text) logs[#logs+1]=text end}
local boxes={}
local function storage(id,x,kind)
    local endpoint={id=id,container=container(),filter={groups={},types={[kind]=true}}}
    endpoint.object={}
    local sq={getX=function() return x end,getY=function() return 0 end,getZ=function() return 0 end}
    function endpoint.object:getSquare() return sq end
    boxes[id]=endpoint return endpoint
end
local materials=storage("materials",4,"Base.SmallHandle")
local tools=storage("tools",8,"Base.KitchenKnife")
local products=storage("products",12,"Base.WoodenFork")
local registry={listeners={},data=function() return saved end,id=function() serial=serial+1 return "uuid-"..serial end}
function registry.resolve(id)
    local endpoint=boxes[id]
    if endpoint and not endpoint.private then return endpoint end
    return nil,"CONTAINER_PRIVATE"
end
function registry.revalidate(endpoint) return registry.resolve(endpoint.id) end
function registry.filter(target) for _,endpoint in pairs(boxes) do if endpoint.object==target then return endpoint.filter end end end
function registry.accepts(endpoint,value) return not endpoint.private and endpoint.filter.types[value.kind]==true end
function registry.logistics(endpoint) return endpoint.role or "STORAGE" end
function registry.inventoryChanged() end
package.loaded["EmberRoutesProbe/ContainerRegistry"]=registry
local entry={id="home",areas={{x=0,y=0,w=30,h=2}}}
package.loaded["EmberRoutesProbe/SettlementLedger"]={
 listeners={},
 get=function() return entry end,at=function() return {entry} end,
 view=function() if entry.denied then return nil,"ACCESS_DENIED" end return entry end}
package.loaded["EmberRoutesProbe/SettlementMembership"]={query=function() return {"materials","tools","products"} end}
package.loaded["EmberRoutesProbe/StorageFilter"]={copy=function(v) return v end,
 describe=function(value) return {fullType=value.kind} end,classify=function() end}
package.loaded["EmberRoutesProbe/WorkTransfer"]={
 reachable=function(body,endpoint) return math.abs(body:getX()-endpoint.object:getSquare():getX()-0.5)<=1.6 end,
 move=function(context,endpoint) return {start=function() context.npc.x=endpoint.object:getSquare():getX()+0.5 end,poll=function() return "PASSED" end} end}

package.loaded["EmberRoutesProbe/WorkAgent"]={new=function() return {
    busy=function() return false end,pause=function() end,hasCargo=function() return false end,
    prepareRemoval=function() return true end,assign=function() return "ASSIGNED" end,execute=function() return "IGNORED" end,
    resume=function() return "RESUMED" end,tick=function() end} end}
EmberRoutesProbeJava={selectedId=function() return npc.id end,carrierFor=function() return npc end,
    carrierId=function(body) return body.id end,carrierActive=function() return true end,carrierPresent=function() return true end,stopCarrier=function() return true end}
local function dequeue(action) if queued==action then queued=nil npc.actions[1]=nil end end
ISBaseTimedAction={}
function ISBaseTimedAction:derive() return setmetatable({},{__index=self}) end
function ISBaseTimedAction.new(class,body) return setmetatable({character=body},{__index=class}) end
function ISBaseTimedAction.stop(action) dequeue(action) end
function ISBaseTimedAction.perform(action) dequeue(action) end
function ISBaseTimedAction:forceStop() self:stop() end
function ISBaseTimedAction:setOverrideHandModels() end
package.loaded["TimedActions/ISBaseTimedAction"]=true
ISTimedActionQueue={}
function ISTimedActionQueue.add(action)
    check(not queued,"probe never queues competing native actions") queued=action npc.actions[1]=action
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
Events={OnProcessAction={Add=function() end}}
dofile('D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/shared/ActionManager.lua')
dofile('D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/shared/Entity/TimedActions/ISHandcraftAction.lua')
package.loaded["Entity/TimedActions/ISHandcraftAction"]=true
ISInventoryPage={dirtyUI=function() end}
HandcraftLogic={new=function(body)
    local logic={manual={},outputs=list(),consumed=list()}
    function logic:setContainers() end function logic:setRecipe() end function logic:setTargetVariableInputRatio() end
    function logic:setManualSelectInputs() end function logic:clearManualInputs() self.manual={} end
    function logic:setManualInputsFor(input,items) self.manual[input]=items:get(0) return true end
    function logic:canPerformCurrentRecipe()
        -- Current JAR: itemGetQueuedAmount skips the current action only while
        -- craftStarted is false; once started, its own consumable is reserved.
        if queued and queued.craftRecipe and queued.craftStarted then return false end
        if mode=="recipe_rejected" then return false end
        local m,t=self.manual[materialInput],self.manual[toolInput]
        return m and t and m.container==body.root and t.container==body.root and toolInput:canUseItem(t)
    end
    function logic:getModelHandOne() end function logic:getModelHandTwo() end
    local recipeData={}
    function recipeData:getAllInputItems()
        local items=list({logic.manual[toolInput],logic.manual[materialInput]})
        if mode=="extra_input" then items:add(item("Base.WoodenSpoon")) end
        return items
    end
    function recipeData:getAllConsumedItems() return logic.consumed end
    function recipeData:luaCallOnCreate() end
    function recipeData:processDestroyAndUsedItems()
        local tool=logic.manual[toolInput] tool.condition=tool.condition-1 tool.sharpness=tool.sharpness-0.1
    end
    function logic:getRecipeData() return recipeData end
    function logic:getCreatedOutputItems(target) for _,v in ipairs(self.outputs) do target:add(v) end end
    function logic:performCurrentRecipe()
        nativeCalls=nativeCalls+1
        local material=self.manual[materialInput] body.root:Remove(material) self.consumed:add(material)
        if mode=="consume_error" then error("injected exception after consumption") end
        self.outputs:add(item("Base.WoodenFork"))
        if mode=="floor" then body.root.capacity=0 end
        return true
    end
    return logic
end}
local Work=require "EmberRoutesProbe/Work"
function Probe.cancelAll(reason,id) Work.pause(reason,id) end
local Craft=require "EmberRoutesProbe/CraftProbe"
local Store=require "EmberRoutesProbe/LaborStore"
local Adapter=require "EmberRoutesProbe/CraftRecipeAdapter"
local function fresh()
    Work.reset() logs={} saved={} owners={} object.mod={} object.occupant=nil object.invalid=false entry.denied=false
    actor.root=container() npc.root=container() actor.known=true npc.known=true npc.skill=2 npc.x=0.5 queued=nil npc.actions=list()
    mode=nil nativeCalls=0 square.dropped=nil
    for _,endpoint in pairs(boxes) do endpoint.container=container() endpoint.private=false endpoint.role="STORAGE" end
    local m=materials.container:AddItem(item("Base.SmallHandle")) local t=tools.container:AddItem(item("Base.KitchenKnife"))
    actor.root:AddItem(item("Base.SmallHandle")) actor.root:AddItem(item("Base.KitchenKnife"))
    return m,t
end
-- Poison access: new orders must never read the player's inventory, even as a fallback.
function actor:getInventory() error("PLAYER_INVENTORY_TOUCHED") end
local function tick(effect)
    clock=clock+110 Work.tick()
    if effect and queued then queued:perform() end
end
local function pump() for _=1,120 do tick(true) end end
local function toCraft()
    for _=1,120 do
        tick(false)
        if queued and queued.craftRecipe then return queued end
        if queued then queued:perform() end
    end
    error("craft action not reached")
end
local m,t=fresh()
check(Craft.execute(actor,"run",object)=="STARTED","classified storage plan starts")
check(Work.busy(npc.id) and not Work.automationAllowed(npc.id),"same shared worker arbiter")
local firstAction=toCraft()
check(firstAction.craftStarted and not firstAction.logic:canPerformCurrentRecipe(),"post-start planning sees its own queued reservation; execution must not use that result")
check(firstAction.craftBench==nil,"generic surface needs no CraftBench or chopping-block entity")
check(Store.owner(m.id) and Store.owner(t.id),"inputs visible to the sole logistics claims authority")
check(Work.assign(actor,npc.id,{})=="OTHER_TASK_RETAINED" and not Work.prepareRemoval(actor,npc.id),"other work and removal reject retained production")
firstAction:perform() pump()
local report=Craft.record(npc.id)
if report.state~="DONE" then for _,line in ipairs(logs) do print(line) end end
check(report.state=="DONE" and report.released and report.made,"normal classified production completes")
check(t.container==tools.container and t.condition==9 and m.container==nil,"same worn tool returns to its classified box")
check(products.container.items:size()==1 and products.container.items:get(0).id==report.outputIds[1],"original output delivered to matching category box")
check(actor.root.items:size()==2 and nativeCalls==1,"player inventory never read or changed")
firstAction:performRecipe() check(nativeCalls==1,"duplicate effect callback blocked")
check(not Store.owner(m.id) and not Store.owner(t.id) and not Store.owner(report.outputIds[1]),"claims released only after all deliveries")
check(object.occupant==nil and Work.prepareRemoval(actor,npc.id),"surface released and worker removable")

fresh() npc.skill=1
check(Craft.execute(actor,"run",object)=="NPC_SKILL_TOO_LOW","strict actual skill gate")
npc.skill=2 npc.known=false
check(Craft.execute(actor,"run",object)=="NPC_RECIPE_UNKNOWN","independent recipe knowledge")
check(Craft.execute(actor,"teach",object)=="RECIPE_TAUGHT","explicit teaching remains available")
actor.known=false check(Craft.execute(actor,"run",object)=="PLAYER_RECIPE_UNKNOWN","player recipe permission")
fresh() object.invalid=true
check(Craft.execute(actor,"run",object)=="CRAFT_SURFACE_REQUIRED","invalid generic surface rejected")
fresh() object.occupant=actor
check(Craft.execute(actor,"run",object)=="BENCH_OCCUPIED" and object.occupant==actor,"never steals occupancy")

m,t=fresh() materials.container:Remove(m)
Craft.execute(actor,"run",object) pump()
check(nativeCalls==0 and actor.root.items:size()==2 and not Craft.busy(npc.id),"empty category box never falls back to player-held matching materials")
m,t=fresh() tools.private=true Craft.execute(actor,"run",object) pump()
check(nativeCalls==0 and t.container==tools.container,"private tools excluded")
m,t=fresh() tools.role="EXCLUDED" Craft.execute(actor,"run",object) pump()
check(nativeCalls==0,"excluded logistics box not a production source")
m,t=fresh() t.sharpness=0 Craft.execute(actor,"run",object) pump()
check(nativeCalls==0,"native input validity rejects dull tools")
m,t=fresh() t.mod.EmberRoutesPersistenceSample=true Craft.execute(actor,"run",object) pump()
check(nativeCalls==0,"existing producer eligibility excludes protected diagnostic originals")

m,t=fresh() Craft.execute(actor,"run",object) local revoked=toCraft()
entry.denied=true revoked:perform() pump()
check(nativeCalls==0 and Craft.retains(npc.id),"permission revoked before effect prevents native consumption")
entry.denied=false Craft.execute(actor,"return") pump()
check(Craft.record(npc.id).released,"explicit recovery after restoring permission returns originals")

m,t=fresh() tools.container:Remove(t) npc.root:AddItem(t)
Craft.execute(actor,"run",object) pump()
check(t.container==tools.container and Craft.record(npc.id).toolFromNpc,"existing NPC tool also returns to its category storage")

m,t=fresh() Craft.execute(actor,"run",object) local interrupted=toCraft()
object.occupant=actor interrupted:perform() pump()
check(nativeCalls==0 and not Craft.record(npc.id).made and object.occupant==actor,"occupancy change cancels without clearing player's occupancy")
object.occupant=nil Craft.execute(actor,"return") pump()
if not Craft.record(npc.id).released then for _,line in ipairs(logs) do print(line) end end
check(m.container==materials.container and t.container==tools.container and Craft.record(npc.id).released,"cancelled originals returned through classification")

m,t=fresh() Craft.execute(actor,"run",object) local stale=toCraft()
Work.pauseAll("SAVE")
check(not Craft.busy(npc.id) and Craft.retains(npc.id) and object.occupant==nil,"save pauses while retaining shared claims")
Work.allowAutomation(npc.id) check(not Work.automationAllowed(npc.id),"automation enable cannot bypass pending assets")
stale:performRecipe() check(nativeCalls==0,"stale callback after save cannot commit")
Craft.reset()
check(Craft.record(npc.id).state=="PAUSED" and Store.owner(t.id),"reloading retains originals in global authority")
Craft.execute(actor,"return") pump()
check(m.container==materials.container and t.container==tools.container and nativeCalls==0,"recovery returns originals without crafting replay")

m,t=fresh() Craft.execute(actor,"run",object) local changed=toCraft()
npc.root:Remove(m) materials.container:AddItem(m) npc.root:AddItem(item("Base.SmallHandle"))
changed:perform() pump()
check(nativeCalls==0,"same-type replacement cannot substitute original")
Craft.execute(actor,"return") pump() check(Craft.record(npc.id).released,"original already in correct storage is safely recognized")

m,t=fresh() mode="consume_error" Craft.execute(actor,"run",object) toCraft():perform() pump()
check(Craft.record(npc.id).uncertain and nativeCalls==1 and not Work.prepareRemoval(actor,npc.id),"partial native failure retains blockers")
check(Craft.execute(actor,"run",object)=="RETURN_OR_RECONCILE_FIRST","uncertain commit cannot restart")
pump() check(nativeCalls==1,"no implicit retry after consumption exception")

m,t=fresh() mode="floor" Craft.execute(actor,"run",object) toCraft():perform() pump()
report=Craft.record(npc.id)
check(report.uncertain and #report.outputIds==1 and square.dropped and Store.owner(square.dropped.id),"native floor output ID is immediately claimed")
products.container:AddItem(square.dropped) Craft.execute(actor,"return") pump()
check(report.state=="DONE" and report.released and nativeCalls==1,"recovered original in category box resolves location without regeneration")

fresh() mode="extra_input" Craft.execute(actor,"run",object) pump()
check(nativeCalls==0 and not Craft.record(npc.id).made,"unselected third input cannot enter native effect")

m,t=fresh() Craft.execute(actor,"run",object) toCraft()
local other={format=1,id="foreign",npcId="other-npc",kind="EXPLICIT_TRANSFER",executor="ENTITY",scopeId="local-world",items={t.id},state="RUNNING"}
local token,why=Store.claim(other)
check(not token and why=="ITEM_RESERVED","ordinary logistics cannot claim crafting tool")
local sameNpc={id="same-npc",npcId=npc.id,items={9999},state="RUNNING"}
local sameToken,sameReason=Store.claim(sameNpc)
check(not sameToken and sameReason=="OTHER_TASK_RETAINED","authority rejects a second task on the same NPC even before executor hooks load")
check(not Store.publish(sameNpc),"direct publish cannot bypass the NPC ownership gate")
check(not Work.busy("other-npc"),"one production order does not monopolize other workers")

-- Loading native and logistics ownership conflicts is atomic and fail-closed.
Work.pauseAll("SAVE")
local rootWithConflict=saved
local conflicting={format=1,id="conflict",npcId="other-npc",kind="EXPLICIT_TRANSFER",executor="ENTITY",scopeId="local-world",items={t.id},state="PAUSED"}
rootWithConflict.labor.tasks.conflict=conflicting rootWithConflict.labor.byNpc["other-npc"]="conflict"
local freshRoot={} for key,value in pairs(rootWithConflict) do freshRoot[key]=value end saved=freshRoot
local ok=pcall(Store.data)
check(not ok,"load cannot publish double ownership across native production and logistics")
-- Restore the old root only to allow the fixture reset; this is not a runtime repair path.
saved=rootWithConflict rootWithConflict.labor.tasks.conflict=nil rootWithConflict.labor.byNpc["other-npc"]=nil

local Claims=require "EmberRoutesProbe/LaborClaims"
local claims=Claims.new()
local a=claims:acquire("a",1,{"item:1"}) local b=claims:acquire("b",1,{"item:3"})
local extended=claims:extend(a,{"item:2","item:3"})
check(not extended and not claims.owners["item:2"] and claims:valid(b,"item:3") and #a.resources==1,"failed output append leaves every ownership unchanged")
check(claims:extend(a,{"item:2"}) and claims:valid(a,"item:1") and claims:valid(a,"item:2"),"successful append retains inputs continuously")

fresh() mode="recipe_rejected" Craft.execute(actor,"run",object) pump()
check(Craft.record(npc.id).reason=="NATIVE_RECIPE_REJECTED" and nativeCalls==0,"native start rejection preserves a specific reason without consuming")
local rejectedLogs=0
for _,line in ipairs(logs) do
    if string.find(line,"ACTION_REJECTED kind=CRAFT",1,true) then
        rejectedLogs=rejectedLogs+1
        check(string.find(line,"phase=CRAFTING step=3",1,true) and string.find(line,"tool=Base.KitchenKnife",1,true),"rejection snapshot identifies step and original tool")
    end
end
check(rejectedLogs==1,"native refusal logs once instead of every validity check")

fresh() mode="extra_input" Craft.execute(actor,"run",object) pump()
check(Craft.record(npc.id).reason=="NATIVE_INPUT_SET_CHANGED" and nativeCalls==0,"unexpected input set has a distinct reason")

-- Same-session save continuation and explicit recovery retain the exact order and originals.
m,t=fresh() Craft.execute(actor,"run",object)
for _=1,120 do tick(true) if m.container==npc.root then break end end
check(m.container==npc.root and t.container==tools.container,"save boundary can fall between the two original input transfers")
Work.pauseAll("SAVE") Craft.afterSave({[npc.id]="CHECKPOINT_SAVED"}) Craft.tickPending() pump()
check(nativeCalls==1 and t.container==tools.container and Craft.record(npc.id).state=="DONE","continuation collects only the missing input and never retakes the held material")

m,t=fresh() Craft.execute(actor,"run",object) toCraft()
local savedOrder=Craft.record(npc.id).id
Work.pauseAll("SAVE") Craft.afterSave({[npc.id]="CHECKPOINT_SAVED"})
check(not Craft.busy(npc.id) and nativeCalls==0,"save callback never starts a replacement native action")
Craft.tickPending() pump()
check(Craft.record(npc.id).id==savedOrder and Craft.record(npc.id).state=="DONE" and nativeCalls==1,"successful save resumes the same order exactly once")
check(m.container==nil and t.container==tools.container and products.container.items:size()==1,"save continuation delivers originals and returns the same tool")

m,t=fresh() Craft.execute(actor,"run",object) toCraft():perform()
local originalOutput=Craft.record(npc.id).outputIds[1]
Work.pauseAll("SAVE") Craft.afterSave({[npc.id]="CHECKPOINT_SAVED"}) Craft.tickPending() pump()
check(nativeCalls==1 and Craft.record(npc.id).state=="DONE" and products.container.items:get(0).id==originalOutput,"saving after native commit resumes delivery without crafting again")

fresh() Craft.execute(actor,"run",object) toCraft() Work.pauseAll("SAVE")
Craft.afterSave(nil) Craft.tickPending() pump()
check(nativeCalls==0 and Craft.retains(npc.id) and not Craft.busy(npc.id),"failed checkpoint never schedules automatic continuation")
check(Craft.execute(actor,"resume")=="RESUME_STARTED","explicit continuation resolves the saved platform locator") pump()
check(nativeCalls==1 and Craft.record(npc.id).state=="DONE","explicit retry can complete after save failure")

fresh() Craft.execute(actor,"run",object) toCraft() Work.pauseAll("SAVE")
Craft.afterSave({[npc.id]="CHECKPOINT_SAVED"}) Work.pause("USER",npc.id) Craft.tickPending() pump()
check(nativeCalls==0 and Craft.record(npc.id).reason=="USER","a newer pause disarms scheduled continuation")
Craft.execute(actor,"resume") pump()
check(nativeCalls==1,"manual continuation remains available after deliberate pause")

fresh() Craft.execute(actor,"run",object) toCraft() Work.pauseAll("SAVE") Craft.reset()
check(Craft.execute(actor,"resume")=="RESUME_STARTED","reload can explicitly continue using only persisted identity and locator") pump()
check(nativeCalls==1 and Craft.record(npc.id).state=="DONE","reload continuation preserves input claims and avoids duplicate output")

m,t=fresh() Craft.execute(actor,"run",object) toCraft() Work.pause("USER",npc.id)
npc.root:Remove(m) npc.root:AddItem(item("Base.SmallHandle"))
Craft.execute(actor,"resume") pump()
check(nativeCalls==0 and Craft.record(npc.id).reason=="ITEM_MISSING" and Store.owner(m.id),"continue never substitutes another material of the same type")

fresh() mode="consume_error" Craft.execute(actor,"run",object) toCraft():perform() pump()
check(Craft.execute(actor,"resume")=="RECONCILE_REQUIRED" and nativeCalls==1,"uncertain native commit cannot be continued as a fresh craft")

-- Old 0.17.0 loans may only return what was already borrowed, never start new loans.
m,t=fresh() materials.container:Remove(m) tools.container:Remove(t) npc.root:AddItem(m) npc.root:AddItem(t)
saved.craftProbes={format=1,byNpc={[npc.id]={format=1,id="legacy-loan",npcId=npc.id,requester=actor.id,generation=1,
    state="PAUSED",phase="COLLECTING",benchId="legacy-surface",materialId=m.id,toolId=t.id,outputIds={},released=false}}}
function actor:getInventory() return self.root end -- Explicit legacy recovery is the sole compatibility exception.
Craft.reset()
check(Craft.execute(actor,"return")=="RETURN_STARTED","legacy loan has an explicit recovery path") pump()
check(m.container==actor.root and t.container==actor.root and Craft.record(npc.id).released,"upgrade preserves and returns previously borrowed originals")

-- Formal service uses the real craft kernel, explicit surfaces, scalar snapshots and signals.
function actor:getInventory() error("PLAYER_INVENTORY_TOUCHED_BY_FORMAL_SERVICE") end
EmberRoutesProbeJava.workerCount=function() return 1 end
EmberRoutesProbeJava.workerIdAt=function() return npc.id end
function npc:getFullName() return "Worker" end
local Service=require "EmberRoutesProbe/CraftingService"
local Signals=require "EmberRoutesProbe/LaborSignals"
m,t=fresh()
local platform=Service.selectSurface(actor,object)
check(platform and saved.craftSurfaces[platform.id],"normal platform selection persists only a stable locator")
local status=Service.status(actor,entry.id)
check(#status.workers==1 and status.surfaceId==platform.id and #status.surfaces==1,"formal service exposes same-settlement worker and chosen platform")
check(Service.command(actor,entry.id,npc.id,"run",platform.id)=="STARTED","formal service starts the verified single-unit recipe") pump()
check(nativeCalls==1 and Craft.record(npc.id).state=="DONE" and t.container==tools.container,"formal service reuses classification and native execution")
status=Service.status(actor,entry.id) status.workers[1].order.state="MUTATED"
check(Craft.record(npc.id).state=="DONE","UI scalar snapshot cannot modify the order")
local notices=0 local release=Service.watch(actor,entry.id,function() notices=notices+1 end)
Service.tick() check(notices==1,"visible crafting view receives initial dirty snapshot")
release() Signals.changed(npc.id) Service.tick()
check(notices==1,"released crafting watcher receives no hidden updates")
entry.denied=true
check(Service.command(actor,entry.id,npc.id,"run",platform.id)=="ACCESS_DENIED","formal commands revalidate settlement access")
entry.denied=false
check(Service.command(actor,entry.id,nil,"run",platform.id)=="NO_WORKER","formal API never falls back to another selected worker")

print("PASS classified native crafting: "..checks.." checks; installed Lua, fake engine/inventory/movement/save")

-- Generic item profile: real installed HandcraftAction, synthetic native recipe/inventory.
function recipe:isBuildableRecipe() return false end
function recipe:isInHandCraftCraft() return self.hand==true end
function recipe:isAnySurfaceCraft() return not self.hand end
function recipe:hasOnTickInputs() return false end function recipe:hasOnTickOutputs() return false end
function recipe:getRequiredSkills() return list({'Carving:2'}) end
function recipe:getInputs() return self.testInputs or list({toolInput,materialInput}) end
function recipe:getOutputs() return self.testOutputs or list({output}) end
function recipe:getIOForIndex(index)
    for _,io in ipairs(self:getInputs()) do if io.index==index then return io end end
end
EmberRoutesProbeJava.recipeHasCallbacks=function(value) return value.callbacks==true end
EmberRoutesProbeJava.recipeHasSpecialOutputs=function(value) return value.specialOutput==true end
local function profileInput(io)
    function io:isReplace() error('deprecated dummy API must not be used') end function io:hasCreateToItem() return false end
    function io:hasConsumeFromItem() return false end function io:isAutomationOnly() return false end
    function io:isWorn() return false end function io:isApplyOnTick() return false end
    function io:getPossibleInputItems() return list({outputItem}) end
    function io:isUsesPartialItem() return self.partial==true end
    function io:getOriginalLine() return tostring(self.index)..':'..tostring(self.keep)..':'..self:getIntAmount() end
    return io
end
profileInput(materialInput) profileInput(toolInput)
local function profileOutput(io)
    function io:getChance() return 1 end function io:isApplyOnTick() return false end
    function io:getOutputMapper() return nil end function io:isReplaceInput() error('deprecated dummy API must not be used') end
    function io:hasCreateToItem() return false end function io:isCreateUses() return true end -- actual JAR: true for all Item outputs
    function io:getOriginalLine() return 'item '..self:getIntAmount()..' Base.WoodenFork' end
    return io
end
profileOutput(output)
HandcraftLogic.new=function(body)
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
        if mode=='consume_error' then error('unknown generic commit') end
        for _,io in ipairs(self.recipe:getOutputs()) do
            for i=1,io:getIntAmount() do self.outputs:add(item(io:getPossibleResultItems():get(0):getFullName())) end
        end
        return true
    end
    return logic
end
local function runBatch(n,id) return Craft.execute(actor,'run',object,npc.id,true,{recipeId=id or 'Base.CarveWoodenFork',quantity=n}) end
local function pumpBatch()
    for i=1,1800 do tick(true) if not Work.busy(npc.id) then return end end error('generic operation budget exceeded')
end
m,t=fresh()
for i=1,2 do materials.container:AddItem(item('Base.SmallHandle')) end
check(runBatch(3)=='STARTED','generic parent order starts') pumpBatch()
local batch=Craft.record(npc.id)
check(batch.format==3 and batch.state=='DONE' and batch.target==3 and batch.produced==3 and batch.delivered==3,'generic counters follow committed output and verified delivery')
check(nativeCalls==3 and t.container==tools.container and t.condition==7,'three units reuse the same tool and return it once')
check(not Store.owner(t.id) and products.container:getItems():size()==3,'parent completion releases original tool and product claims')
check(runBatch(0)=='INVALID_QUANTITY' and runBatch(1.5)=='INVALID_QUANTITY','invalid quantities never create a new order')
recipe.callbacks=true check(runBatch(1)=='RECIPE_MECHANISM_UNSUPPORTED','unreviewed recipe callbacks are refused') recipe.callbacks=nil
materialInput.partial=true check(runBatch(1)=='RECIPE_MECHANISM_UNSUPPORTED','partial item resources are refused') materialInput.partial=nil
-- Non-square IO indexes, multiple consumable/tool types and two products per native effect.
local nails=profileInput({keep=false,index=11,getResourceType=materialInput.getResourceType,isVariableAmount=materialInput.isVariableAmount,
    getIntAmount=function() return 1 end,isKeep=materialInput.isKeep,canUseItem=function(_,value) return value.kind=='Base.Nails' end})
local hammer=profileInput({keep=true,index=15,getResourceType=toolInput.getResourceType,isVariableAmount=toolInput.isVariableAmount,
    getIntAmount=function() return 1 end,isKeep=toolInput.isKeep,canUseItem=function(_,value) return value.kind=='Base.Hammer' end})
local originalAmount=materialInput.getIntAmount
materialInput.getIntAmount=function() return 2 end
output.getIntAmount=function() return 2 end
recipe.testInputs=list({toolInput,nails,materialInput,hammer})
m,t=fresh() materials.filter.types['Base.Nails']=true tools.filter.types['Base.Hammer']=true
for i=1,3 do materials.container:AddItem(item('Base.SmallHandle')) end
for i=1,2 do materials.container:AddItem(item('Base.Nails')) end
local htool=tools.container:AddItem(item('Base.Hammer'))
check(runBatch(3,'Test.FixedMulti')=='STARTED','the same executor accepts a different fixed-item recipe profile')
pumpBatch() batch=Craft.record(npc.id)
check(batch.state=='DONE' and batch.requested==3 and batch.target==4 and batch.produced==4 and batch.delivered==4 and nativeCalls==2,'target rounds to complete native yield without a partial second effect')
check(t.condition==8 and htool.condition==8 and t.container==tools.container and htool.container==tools.container,'different catalysts remain constant across the order')
materialInput.getIntAmount=originalAmount output.getIntAmount=function() return 1 end recipe.testInputs=nil
-- Successful save, same parent, no replay after output creation.
m,t=fresh() materials.container:AddItem(item('Base.SmallHandle'))
check(runBatch(2)=='STARTED','save recovery sample starts')
for i=1,500 do tick(true) if Craft.record(npc.id).produced==1 then break end end
batch=Craft.record(npc.id) local parentId=batch.id
Work.pauseAll('SAVE') Craft.afterSave({[npc.id]='CHECKPOINT_SAVED 1'}) Probe.tickCrafting() pumpBatch()
check(batch.id==parentId and batch.state=='DONE' and nativeCalls==2 and batch.delivered==2,'save after creation resumes delivery and remaining units under the same parent')
-- Missing inputs retain the order; explicit retry can fill the remaining quantity.
m,t=fresh() check(runBatch(2)=='STARTED','missing second unit starts') pumpBatch()
batch=Craft.record(npc.id)
check(batch.state=='PAUSED' and batch.produced==1 and batch.delivered==1 and Store.owner(t.id),'missing later materials retain progress and catalyst claim')
materials.container:AddItem(item('Base.SmallHandle'))
check(Craft.execute(actor,'resume',nil,npc.id,true)=='RESUME_STARTED','explicit retry preserves parent identity') pumpBatch()
check(batch.state=='DONE' and batch.delivered==2 and nativeCalls==2,'refilled parent does not remake its completed first unit')
-- Unknown commit cannot be resumed or released by cancellation.
m,t=fresh() check(runBatch(2)=='STARTED','unknown commit sample starts') mode='consume_error' pumpBatch()
batch=Craft.record(npc.id)
check(batch.uncertain and nativeCalls==1 and Craft.execute(actor,'resume',nil,npc.id,true)=='RECONCILE_REQUIRED','unknown native commit is never replayed')
check(Craft.execute(actor,'return',nil,npc.id,true)=='RETURN_STARTED','known remaining originals can still be returned') mode=nil pumpBatch()
check(not batch.released and batch.state=='RECONCILE_REQUIRED' and nativeCalls==1,'return does not erase unresolved native commit')
print('PASS generic production and compatibility: '..checks..' checks; native Lua, fake recipe logic and inventory')
local Claims=require 'EmberRoutesProbe/LaborClaims'
local claims=Claims.new()
local ownerA=claims:acquire('a',1,{'tool','surface'})
local ownerB=claims:acquire('b',1,{'other-item'})
check(not claims:replace(ownerA,{'tool','other-item'}) and claims:valid(ownerA,'surface') and claims:valid(ownerB,'other-item'),
    'failed resource replacement leaves the complete old set and competing owner intact')
check(claims:replace(ownerA,{'tool','surface','fresh'}) and claims:valid(ownerA,'tool') and claims:valid(ownerA,'fresh'),
    'atomic batch transition keeps the original catalyst token')
-- Save while the input transfer is in flight, before native recipe commitment.
m,t=fresh() materials.container:AddItem(item('Base.SmallHandle'))
check(runBatch(2)=='STARTED','partial collection save sample starts')
for i=1,100 do tick(false) if queued then break end end
batch=Craft.record(npc.id) parentId=batch.id
Work.pauseAll('SAVE') Craft.afterSave({[npc.id]='CHECKPOINT_SAVED 1'}) Probe.tickCrafting() pumpBatch()
check(batch.id==parentId and batch.state=='DONE' and nativeCalls==2,'partial collection checkpoint resumes the same inputs without a replacement order')
-- A saved parent cannot resolve a missing original tool by taking an identical spare.
m,t=fresh() check(runBatch(2)=='STARTED','identity recovery sample starts') pumpBatch()
batch=Craft.record(npc.id) npc.root:Remove(t)
tools.container:AddItem(item('Base.KitchenKnife')) materials.container:AddItem(item('Base.SmallHandle'))
check(Craft.execute(actor,'resume',nil,npc.id,true)=='RESUME_STARTED','identity retry enters bounded scanning') pumpBatch()
check(batch.state=='PAUSED' and nativeCalls==1 and Store.owner(t.id),'missing catalyst identity blocks substitution and protects its claim')
-- Current requests are single player only, even if bypassing the UI.
local originalClient=isClient isClient=function() return true end
check(runBatch(1)=='SP_ONLY','generic command authority refuses MP callers') isClient=originalClient
print('PASS final production contracts: '..checks..' checks; no game engine run')

-- Real installed script IO shapes; native item/tag resolution and effects still mocked.
-- Run tools/recipe-coverage.py first. Missing/stale source profiles fail explicitly.
local profiles=dofile('build/qa/recipe-coverage.lua')
local Profile=require 'EmberRoutesProbe/ProductionRecipe'
for _,sample in ipairs(profiles) do
    local variants=1
    for _,input in ipairs(sample.inputs) do if not input.tag and #input.choices>1 then variants=2 end end
    for variant=1,variants do
        fresh()
        materials.container=container() tools.container=container() products.container=container()
        materials.filter.types={} tools.filter.types={} products.filter.types={}
        recipe.testInputs=list() recipe.testOutputs=list() recipe.hand=sample.hand
        function recipe:getTranslationName() return sample.id end
        function recipe:getName() return sample.id end
        function recipe:getRequiredSkillCount() return #sample.skills end
        function recipe:getRequiredSkill(index)
            local text=sample.skills[index+1]
            local perk,level=string.match(text,'([^:]+):(%d+)')
            return {getPerk=function() return perk end,getLevel=function() return tonumber(level) end}
        end
        function recipe:getRequiredSkills() return list(sample.skills) end
        local catalystItems={}
        for index,input in ipairs(sample.inputs) do
            -- Tags are symbolic test inventory, deliberately not presented as engine resolution.
            local kind=input.tag and ('Fixture.'..input.choices[1]) or input.choices[math.min(variant,#input.choices)]
            local io=profileInput({index=index,keep=input.keep})
            function io:getResourceType() return ResourceType.Item end
            function io:isVariableAmount() return false end
            function io:getIntAmount() return input.count end
            function io:isKeep() return input.keep end
            function io:canUseItem(value) return value.kind==kind end
            function io:getOriginalLine() return input.line end
            recipe.testInputs:add(io)
            local endpoint=input.keep and tools or materials
            endpoint.filter.types[kind]=true
            for i=1,input.count*(input.keep and 1 or 2) do
                local original=endpoint.container:AddItem(item(kind))
                if input.keep then catalystItems[#catalystItems+1]=original end
            end
        end
        for _,result in ipairs(sample.outputs) do
            local io=profileOutput({})
            function io:getResourceType() return ResourceType.Item end
            function io:isVariableAmount() return false end
            function io:getIntAmount() return result.count end
            function io:getOriginalLine() return result.line end
            function io:getPossibleResultItems()
                return list({{getFullName=function() return result.kind end,getActualWeight=function() return 1 end}})
            end
            recipe.testOutputs:add(io) products.filter.types[result.kind]=true
        end
        local spec=Profile.read(sample.id)
        check(spec and spec.surface==not sample.hand and spec.toolCount==#catalystItems,sample.id..' source profile parsed')
        if #sample.skills>0 then
            npc.skill=0
            check(Craft.execute(actor,'run',object,npc.id,true,{recipeId=sample.id,quantity=1})=='NPC_SKILL_TOO_LOW',sample.id..' actual source skill gate')
            npc.skill=2
        end
        npc.known=false
        check(Craft.execute(actor,'run',object,npc.id,true,{recipeId=sample.id,quantity=1})=='NPC_RECIPE_UNKNOWN',sample.id..' independent knowledge gate')
        npc.known=true
        local requested=spec.yield+1
        local target=object if sample.hand then target=nil end
        check(Craft.execute(actor,'run',target,npc.id,true,{recipeId=sample.id,quantity=requested})=='STARTED',sample.id..' starts shared executor')
        pumpBatch() local record=Craft.record(npc.id)
        check(record.state=='DONE' and nativeCalls==2 and record.target==spec.yield*2
            and record.produced==record.target and record.delivered==record.target,sample.id..' two complete batches and rounded primary count')
        check(products.container.items:size()==spec.outputCount*2,sample.id..' all primary and secondary outputs delivered')
        for _,original in ipairs(catalystItems) do
            check(original.container==tools.container and original.condition==8 and not Store.owner(original.id),sample.id..' original catalyst reused and returned')
        end
        for _,input in ipairs(record.materials) do check(not Store.owner(input.id),sample.id..' spent input released') end
        print('PASS source-derived '..sample.id..' variant '..variant..'; native item/tag resolution and effects mocked')
    end
end
print('PASS production with installed source coverage: '..checks..' checks; game NOT RUN')

-- The actual preview reuses the same candidate matcher without claiming or moving.
recipe.testInputs=nil recipe.testOutputs=nil recipe.hand=true
function recipe:getRequiredSkillCount() return 1 end
function recipe:getRequiredSkill()
    return {getPerk=function() return {getName=function() return 'Carving' end} end,getLevel=function() return 2 end}
end
function recipe:getRequiredSkills() return list({'Carving:2'}) end
local Preview=require 'EmberRoutesProbe/CraftingPreview'
local function finishPreview(request)
    for _=1,1500 do local result=request:step() if result then return result end end error('preview budget exceeded')
end
m,t=fresh() materials.filter.types['Base.SmallHandle']=true tools.filter.types['Base.KitchenKnife']=true
materials.container:AddItem(item('Base.SmallHandle')) materials.container:AddItem(item('Base.SmallHandle'))
local request=Preview.new(actor,entry.id,npc.id,'Base.CarveWoodenFork',3,nil)
local preview=finishPreview(request)
check(preview.state=='READY' and preview.counts[9].required==3 and preview.counts[4].required==1,'preview scales consumables but keeps one catalyst')
check(not Store.owner(m.id) and not Store.owner(t.id) and nativeCalls==0 and npc.root.items:size()==0,'preview never claims, takes, moves or crafts')
check(materials.container.items:size()==3 and tools.container.items:size()==1,'preview leaves all classified originals in place')
m,t=fresh() local oldResolve=registry.resolve
registry.resolve=function(id) if id=='products' then return nil,'CONTAINER_UNLOADED' end return oldResolve(id) end
preview=finishPreview(Preview.new(actor,entry.id,npc.id,'Base.CarveWoodenFork',3,nil))
check(preview.state=='UNKNOWN' and preview.partial and preview.counts[9].available==1,'missing stock plus unloaded coverage remains uncertain')
registry.resolve=oldResolve
request=Preview.new(actor,entry.id,npc.id,'Base.CarveWoodenFork',3,nil) request:cancel()
check(request:step()==nil,'cancelled request cannot publish a result')
preview=finishPreview(Preview.new(actor,entry.id,npc.id,'Base.CarveWoodenFork',9999,nil))
check(preview.state=='UNKNOWN' and preview.conditions[#preview.conditions]=='PREVIEW_LIMIT','large target does not create an unbounded matching job or false sufficient count')
recipe.hand=false
preview=finishPreview(Preview.new(actor,entry.id,npc.id,'Base.CarveWoodenFork',1,nil))
local missingSurface=false for _,reason in ipairs(preview.conditions) do if reason=='CRAFT_SURFACE_REQUIRED' then missingSurface=true end end
check(missingSurface,'surface-only recipe reports missing surface during preflight')
print('PASS read-only preview contracts: '..checks..' total checks; game/native effects NOT RUN')
