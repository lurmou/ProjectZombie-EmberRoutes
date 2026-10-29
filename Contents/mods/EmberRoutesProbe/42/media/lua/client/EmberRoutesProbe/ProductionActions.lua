local Store=require "EmberRoutesProbe/LaborStore"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Supply=require "EmberRoutesProbe/CraftSupply"
local Carry=require "EmberRoutesProbe/ProductionCarry"
local Recipe=require "EmberRoutesProbe/ProductionRecipe"
local Inputs=require "EmberRoutesProbe/CraftRecipeInputs"
require "Entity/TimedActions/ISHandcraftAction"
require "TimedActions/ISInventoryTransferAction"
---@class EmberRoutesProductionTransfer:ISInventoryTransferAction
---@field attempted boolean?
---@field performed boolean?
---@field stopped boolean?
---@field failure string?
---@class EmberRoutesProductionCraft:ISHandcraftAction
---@field attempted boolean?
---@field entered boolean?
---@field performed boolean?
---@field stopped boolean?
---@field failure string?
local Actions={}
function Actions.inRoot(item,container,id)
    return item and item:getID()==id and item:getContainer()==container and container:getItems():contains(item)
end
function Actions.transfer(c,item,from,to,endpoint,delivered)
    local id=item:getID() local npcRoot=c.npc:getInventory()
    local function valid()
        local intent=to==npcRoot and "take" or "put"
        local current=Supply.endpoint(c.entry,endpoint.id,intent)
        return c.valid() and EmberRoutesProbeJava.carrierActive(c.npc) and current and current.container==endpoint.container
            and Actions.inRoot(item,from,id) and Store.validNative(c.record,c.token,"item:"..id)
            and (c.returnOnly or Registry.accepts(current,item)) and Registry.logistics(current)=="STORAGE"
            and to:hasRoomFor(c.npc,item) and not item:getIsCraftingConsumed()
            and (to~=npcRoot or Carry.fits(c.npc,item:getUnequippedWeight()))
            and (to==npcRoot or Store.availableCapacity(endpoint.id,to:getFreeCapacity(c.npc))>=item:getUnequippedWeight())
    end
    if not valid() then return nil,"TRANSFER_PRECONDITION" end
    local action=ISInventoryTransferAction:new(c.npc,item,from,to,90)
    ---@cast action EmberRoutesProductionTransfer
    local nativeValid,nativePerform,nativeStop,nativeAnim=action.isValid,action.perform,action.stop,action.startActionAnim
    action.useProgressBar,action.forceProgressBar=false,false
    action.isValid=function(self) return valid() and nativeValid(self) end
    action.startActionAnim=function(self)
        if c.body and not c.body.current() then return end
        nativeAnim(self) self.selectedContainer=nil
    end
    action.perform=function(self)
        if self.attempted then return end self.attempted=true
        if not self:isValid() then self.failure="TRANSFER_PRECONDITION" self:stop() return end
        local ok,reason=pcall(nativePerform,self)
        self.performed=Actions.inRoot(item,to,id) and not from:getItems():contains(item)
        if self.performed then
            c.plan.locations[id]={item=item,endpoint=to~=npcRoot and endpoint or nil}
            if delivered then delivered() end
            Registry.inventoryChanged(from) Registry.inventoryChanged(to)
        else self.failure=ok and "TRANSFER_POSTCONDITION" or tostring(reason) end
    end
    action.stop=function(self)
        if c.body and (self.stopped or self.performed) then return end
        self.stopped=true
        if not c.body or c.body.retained() then nativeStop(self) end
    end
    return action
end
function Actions.craft(c)
    local r,npc=c.record,c.npc local inventory=npc:getInventory()
    local before={} local items=inventory:getItems()
    if items:size()>512 then return nil,"INVENTORY_LIMIT" end
    for i=0,items:size()-1 do
        local id=items:get(i):getID() if before[id] then return nil,"ITEM_ID_CONFLICT" end before[id]=true
    end
    local entries=c.inputs
    local function invalid()
        if not c.valid() then return "CRAFT_CONTEXT_CHANGED" end
        if not EmberRoutesProbeJava.carrierActive(npc) then return "CARRIER_MOVING" end
        if r.phase~="CRAFTING" or r.uncertain or r.unitMade then return "CRAFT_PHASE_CHANGED" end
        local spec,reason=Recipe.inspect(c.actor,npc,c.object,r.recipeId,true,true)
        if not spec then return reason end
        if spec.signature~=r.signature then return "RECIPE_CHANGED" end
        if spec.surface and (not c.object:isUsingPlayer(npc) or c.object:getModData().EmberRoutesCraftProbeBenchId~=r.benchId) then
            return "SURFACE_OCCUPANCY_CHANGED"
        end
        for _,entry in ipairs(entries) do
            if not Actions.inRoot(entry.item,inventory,entry.id) or not Store.validNative(r,c.token,"item:"..entry.id)
                or not entry.io:canUseItem(entry.item,npc) then return "INPUT_CHANGED" end
        end
        local consumed=0
        for _,entry in ipairs(entries) do
            consumed=consumed+Carry.consumed(entry.item,{keep=entry.keep,io=entry.io})
        end
        if not Carry.fits(npc,0,consumed,spec.outputWeight) then
            return "OUTPUT_CAPACITY_UNAVAILABLE"
        end
    end
    local binding,bindingReason=Inputs.bind(c.spec.facts,entries,npc)
    if not binding then return nil,bindingReason end
    if c.spec.surface then
        if c.object:getUsingPlayer() and c.object:getUsingPlayer()~=npc then return nil,"BENCH_OCCUPIED" end
        c.object:setUsingPlayer(npc) c.ownsBench=true
    end
    local why=invalid() if why then return nil,why end
    local action=ISHandcraftAction:new(npc,c.spec.recipe,ArrayList.new(),c.object,nil,binding.manual,nil,nil,1,0)
    ---@cast action EmberRoutesProductionCraft
    action.containers:add(inventory)
    local nativeValid,nativeStart,nativeStop,nativePerform,nativeRecipe=action.isValid,action.start,action.stop,action.perform,action.performRecipe
    action.useProgressBar,action.forceProgressBar=false,false
    action.isValid=function(self)
        local reason=invalid()
        if reason or not nativeValid(self) then self.failure=reason or "NATIVE_ACTION_INVALID" return false end return true
    end
    action.start=function(self)
        if not self:isValid() then self:forceStop() return end
        nativeStart(self)
        if not self.craftStarted or not Inputs.applied(self.logic,binding) then
            self.failure="NATIVE_INPUT_SET_CHANGED" self:forceStop()
        end
    end
    action.stop=function(self)
        if c.body and (self.stopped or self.performed) then return end
        self.stopped=true
        if not c.body or c.body.retained() then nativeStop(self) end
    end
    action.perform=function(self)
        if self.entered then return end self.entered=true
        if not self:isValid() or not Inputs.applied(self.logic,binding) then self:stop() return end
        local ok,reason=pcall(nativePerform,self)
        if not ok then self.failure=tostring(reason) if self.attempted then r.uncertain=true end end
    end
    action.performRecipe=function(self)
        if self.attempted then return end
        if not self:isValid() or not Inputs.applied(self.logic,binding) then self:stop() return end
        self.attempted=true r.phase="COMMITTING" c.changed("COMMITTING")
        if not c.valid() then self.failure="CRAFT_CONTEXT_CHANGED" return end
        local ok,reason=pcall(nativeRecipe,self)
        local outputs=ArrayList.new() self.logic:getCreatedOutputItems(outputs)
        r.outputs={} r.untrackedOutputs=outputs:size()>128 or nil
        local counts,seen={},{} local verified=ok and outputs:size()==c.spec.outputCount
        for i=0,math.min(outputs:size(),128)-1 do
            local item=outputs:get(i) local id,kind=item:getID(),item:getFullType()
            if not seen[id] and not before[id] then r.outputs[#r.outputs+1]={id=id,fullType=kind,delivered=false} end
            if seen[id] or before[id] or not Actions.inRoot(item,inventory,id) then verified=false end
            seen[id]=true counts[kind]=(counts[kind] or 0)+1
            c.plan.locations[id]={item=item}
        end
        for kind,n in pairs(c.spec.outputs) do if counts[kind]~=n then verified=false end counts[kind]=nil end
        for _ in pairs(counts) do verified=false end
        local consumed=self.logic:getRecipeData():getAllConsumedItems()
        for _,entry in ipairs(entries) do
            if entry.keep then
                if not Actions.inRoot(entry.item,inventory,entry.id) or consumed:contains(entry.item) then verified=false end
            elseif not consumed:contains(entry.item) or entry.item:getContainer()~=nil or inventory:getItems():contains(entry.item) then verified=false end
        end
        local claimed,claimReason=Store.extendNative(r,c.token)
        if verified and claimed and c.valid() then
            r.unitMade=true r.produced=r.produced+r.unitYield r.phase="CONFIRMED" self.performed=true
            c.changed("CONFIRMED") Registry.inventoryChanged(inventory)
        else
            r.uncertain=true r.phase="RECONCILE_REQUIRED" self.failure=tostring(reason or claimReason or "ASSET_POSTCONDITION")
            c.changed("RECONCILE_REQUIRED "..self.failure)
        end
    end
    return action
end
return Actions
