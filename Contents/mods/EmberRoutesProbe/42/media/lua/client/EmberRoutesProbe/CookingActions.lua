-- Per-instance vanilla leaves. No scheduler, remote effect, guessed output or
-- retry of a restored dispatch. The caller supplies the current authorized body.
require 'TimedActions/ISAddItemInRecipe'
require 'TimedActions/ISToggleStoveAction'
require 'TimedActions/ISInventoryTransferAction'
local Context=require 'EmberRoutesProbe/CookingContext'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Inventory=require 'EmberRoutesProbe/CookingInventory'
local Food=require 'EmberRoutesProbe/CookingFood'
local Store=require 'EmberRoutesProbe/LaborStore'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Transfer=require 'EmberRoutesProbe/WorkTransfer'
local Duty=require 'EmberRoutesProbe/CookingDuty'
local Carry=require 'EmberRoutesProbe/ProductionCarry'
local Policy=require 'EmberRoutesProbe/CookingPolicy'
local A={}
local function claimed(c,item,container,custody)
    local id=item:getID() local asset=Inventory.asset(c.job,id)
    return asset and asset.fullType==item:getFullType() and asset.custody==custody
        and Store.validCooking(c.job,c.token,'item:'..id) and Inventory.contains(item,container,id) or false
end
-- PREPARED is created by the owning planner. This adapter adds one immutable
-- native specification before dispatch; reconstructing a leaf never starts work.
local function leaf(c,sequence,kind,itemIds,hooks)
    if isClient() or isServer() or not Context.active(c) then return nil,'COOKING_CONTROL_REQUIRED' end
    if not Policy.finite(sequence) or sequence~=math.floor(sequence) or sequence<1
        or sequence<c.job.payload.sequence or sequence>c.job.payload.sequence+1 then return nil,'STALE_COOKING_SEQUENCE' end
    local previous=c.job.payload.attempt local spec
    if sequence==c.job.payload.sequence then
        if not previous or previous.kind~=kind or #previous.itemIds~=#itemIds then return nil,'COOKING_INTENT_CHANGED' end
        for i,id in ipairs(itemIds) do if previous.itemIds[i]~=id then return nil,'COOKING_INTENT_CHANGED' end end
        if not previous.spec or not hooks.matches(previous.spec) then return nil,'COOKING_INTENT_CHANGED' end
        if previous.state~='PREPARED' then
            local id=previous.id
            return {kind='Action',run=function()
                if not Context.current(c,id) then return 'Failure' end
                c.effects=c.job.effects
                return c.job.payload.attempt.state=='APPLIED' and 'Success' or 'Failure'
            end,halt=function() return true end}
        end
        spec=previous.spec if not spec then return nil,'COOKING_SPEC_MISSING' end
    else
        local why
        spec,why=hooks.capture() if not spec then return nil,why end
        local prepared,reason=Record.begin(c.job,kind,itemIds,spec) if not prepared then return nil,reason end
        if not Context.publish(c,prepared) then return nil,c.reason end
    end
    local attemptId=c.job.payload.attempt.id
    local action,stopped,performed,entered,inCommit
    local node={kind='Action'}
    local function same() return Context.current(c,attemptId) end
    local function retained() return same() and c.body.retained() end
    local function active() return same() and Context.active(c,attemptId) and not stopped end
    local function state() return same() and c.job.payload.attempt.state end
    local function abort()
        if state()~='PREPARED' then return state()=='APPLIED' or state()=='ABORTED' end
        if not hooks.unchanged(spec) then return Context.unknown(c,attemptId,'COOKING_CHANGED_BEFORE_EFFECT') end
        local j=Record.abort(c.job,attemptId)
        return j and Context.publish(c,j) or false
    end
    local boundBody=c.body
    c.settleStopped=function()
        if c.body~=boundBody or not same() or inCommit then return false end
        if state()=='PREPARED' then return abort() end
        return true
    end
    local function effect(self,native,...)
        if entered or not active() or state()~='PREPARED' then return false end
        if not hooks.valid(spec) or not hooks.unchanged(spec) then abort() return false end
        if hooks.beforeEffect and not hooks.beforeEffect(self) then abort() return false end
        local committing=Record.committing(c.job,attemptId)
        if not committing or not Context.publish(c,committing) then return false end
        if not active() or not hooks.live() then
            Context.unknown(c,attemptId,'COOKING_AUTHORITY_CHANGED') return false
        end
        entered,inCommit=true,true
        -- Catch only this irreversible vanilla entry. Always observe after an
        -- exception: a completed physical effect must not be replayed.
        local ok,err=pcall(native,self,...)
        local observed,j,receipt=pcall(hooks.observe,self,spec,ok)
        if not observed then err=j j,receipt=nil,nil end
        local confirmed=j and receipt and Record.confirm(j,attemptId,receipt)
        local done=confirmed and Context.publish(c,confirmed) or false
        if not done then Context.unknown(c,attemptId,ok and observed and 'COOKING_POSTCONDITION_UNKNOWN' or err) end
        if not ok then self.failure=tostring(err) end
        inCommit=false
        return done
    end
    function node.run()
        if not same() then return 'Failure' end
        c.effects=c.job.effects
        if inCommit then return 'Running' end
        if state()=='UNKNOWN' or state()=='COMMITTING' then return 'Failure' end
        if state()=='ABORTED' then return 'Failure' end
        if not action then
            if state()=='APPLIED' then return 'Success' end
            if not active() then if retained() then abort() end return 'Failure' end
            if c.job.payload.attempt.dispatched then
                Context.unknown(c,attemptId,'COOKING_RESTORED_DISPATCH') return 'Failure'
            end
            if not hooks.valid(spec) or not hooks.unchanged(spec) then abort() return 'Failure' end
            local j=Record.copy(c.job) j.payload.attempt.dispatched=true
            if not Context.publish(c,j) then return 'Failure' end
            if hooks.prepare and not hooks.prepare() then abort() return 'Failure' end
            action=hooks.create()
            if not action then abort() return 'Failure' end
            local nativeStart,nativeUpdate,nativeValid=action.start,action.update,action.isValid
            local nativeValidStart,nativeStop,nativePerform=action.isValidStart,action.stop,action.perform
            action.useProgressBar,action.forceProgressBar=false,false
            action.isValid=function(self)
                return active() and (state()=='APPLIED' or (state()=='PREPARED' or inCommit)
                    and hooks.live() and nativeValid(self)) or false
            end
            action.isValidStart=function(self)
                return active() and state()=='PREPARED' and hooks.valid(spec) and hooks.unchanged(spec)
                    and (not nativeValidStart or nativeValidStart(self)) or false
            end
            action.start=function(self)
                if not self:isValidStart() then return end
                nativeStart(self)
                if hooks.started and not hooks.started(self) then self:stop() return end
                if kind=='ADD' and active() then self:setActionAnim('Craft') end
            end
            action.update=function(self) if active() and hooks.live() then nativeUpdate(self) end end
            if kind=='TRANSFER' then
                local nativeTransfer,nativeAnim=action.transferItem,action.startActionAnim
                -- Vanilla merging would let this callback mutate another Job's
                -- originals. One per-instance transfer stays exactly one item.
                action.canMergeAction=function() return false end
                action.checkQueueList=function() end
                action.startActionAnim=function(self)
                    if not active() then return end nativeAnim(self) self.selectedContainer=nil
                end
                action.transferItem=function(self,item)
                    if item~=hooks.item then return false end
                    return effect(self,nativeTransfer,item)
                end
            elseif kind=='CRAFT' then
                local nativeRecipe=action.performRecipe
                action.performRecipe=function(self) return effect(self,nativeRecipe) end
            else
                local nativeComplete=action.complete
                action.complete=function(self) return effect(self,nativeComplete) end
            end
            action.perform=function(self)
                if performed or stopped or not retained() then return end
                performed=true
                local ok,err=pcall(nativePerform,self)
                if not ok then self.failure=tostring(err) if state()=='PREPARED' then abort() end end
            end
            action.stop=function(self)
                if stopped or not retained() or inCommit then return end
                stopped=true abort() nativeStop(self)
            end
            if not c.body.add(action) then abort() return 'Failure' end
        end
        if ISTimedActionQueue.hasAction(action) then return 'Running' end
        if state()=='PREPARED' then abort() end
        if hooks.cleanup then
            local stopped=c.body.snapshot and c.body.snapshot()
            if not hooks.cleanup(stopped and stopped.available and stopped.nativeStopped or false,spec) then return 'Running' end
        end
        return state()=='APPLIED' and 'Success' or 'Failure'
    end
    function node.halt()
        if not retained() or inCommit then return false end
        if not c.body.clear() then return false end
        if state()=='PREPARED' then abort() end
        return true -- Business UNKNOWN remains on the Job; no asset is released.
    end
    return node
end
function A.craft(c,sequence,recipeId,entries,object)
    return require('EmberRoutesProbe/CookingCraft').leaf(c,sequence,recipeId,entries,object,leaf)
end
function A.add(c,sequence,recipe,base,ingredient)
    local root=c.npc:getInventory() local baseId,ingredientId=base:getID(),ingredient:getID()
    local beforeItems
    local function live()
        return claimed(c,base,root,'HELD') and claimed(c,ingredient,root,'HELD')
    end
    local function eligible()
        if not live() or base==ingredient or #c.job.payload.assets>Record.limit-2 then return false end
        if not recipe.isItemUsableInRecipe or not recipe.isResultItem or not recipe.isSpiceAdded
            or not recipe.getOriginalname then return false end
        local row=Food.read(ingredient)
        if not row or not row.food or not row.safe or row.frozen or row.raw<=0 then return false end
        if recipe:getOriginalname()~=c.job.payload.profileId then return false end
        if ingredient:isSpice() and (recipe:isSpiceAdded(base,ingredient)
            or (c.job.payload.spiceCount or 0)>=Policy.maxSpices) then return false end
        return recipe:isItemUsableInRecipe(c.npc,base,ingredientId)
    end
    return leaf(c,sequence,'ADD',{baseId,ingredientId},{live=live,
        matches=function(s) return s.recipeId==recipe:getOriginalname() and s.baseId==baseId and s.ingredientId==ingredientId end,
        capture=function()
            if not eligible() then return nil,'EVOLVED_PRECONDITION' end
            local b=Inventory.foodStamp(base) local i=Inventory.foodStamp(ingredient)
            if not b or not i then return nil,'EVOLVED_OBSERVATION_UNAVAILABLE' end
            beforeItems=Inventory.snapshot(root) if not beforeItems then return nil,'INVENTORY_OBSERVATION_LIMIT' end
            local extra=base:getExtraItems()
            return {recipeId=recipe:getOriginalname(),baseId=baseId,ingredientId=ingredientId,
                baseStamp=b,ingredientStamp=i,beforeAmount=Inventory.amount(ingredient),spice=ingredient:isSpice(),
                baseExtraCount=extra and extra:size() or 0}
        end,
        unchanged=function(s)
            return live() and Inventory.foodStamp(base)==s.baseStamp and Inventory.foodStamp(ingredient)==s.ingredientStamp
        end,
        valid=function(s) return recipe:getOriginalname()==s.recipeId and eligible() end,
        beforeEffect=function() beforeItems=Inventory.snapshot(root) return beforeItems~=nil end,
        create=function() return ISAddItemInRecipe:new(c.npc,recipe,base,ingredient) end,
        observe=function(action,s)
            if not Context.current(c) then return end
            local retained=Inventory.retainOutputs(c.job,beforeItems,root)
            if not retained or not Context.publish(c,retained) then return end
            local result=action.baseItem local after=Inventory.amount(ingredient)
            if not result or not Inventory.contains(result,root,result:getID()) or not recipe:isResultItem(result)
                or not after or after>=s.beforeAmount-0.000001 then return end
            if result~=base and (root:getItems():contains(base) or base:getContainer()==root) then return end
            -- Vanilla uses/removes a nearly depleted Food below its final-use
            -- threshold; getHungChange need not have reached exactly zero.
            -- Positive attributable depletion + the actual recipe result/marker
            -- is required. Relocation into another inventory stays unknown.
            if ingredient:getContainer()~=root and ingredient:getContainer()~=nil then return end
            if s.spice and not recipe:isSpiceAdded(result,ingredient) then return end
            if not s.spice then
                local extra=result:getExtraItems()
                if not extra or extra:size()~=s.baseExtraCount+1 or extra:get(extra:size()-1)~=ingredient:getFullType() then return end
            end
            local j=Record.copy(c.job)
            if result~=base then Inventory.release(j,baseId,'CONSUMED') end
            if not root:getItems():contains(ingredient) then Inventory.release(j,ingredientId,'CONSUMED') end
            local output=Inventory.asset(j,result:getID()) local facts=Food.read(result)
            if not output or not facts or not facts.food then return end
            output.role,output.raw,output.effective='OUTPUT',facts.raw,facts.effective
            if s.spice then j.payload.spiceCount=(j.payload.spiceCount or 0)+1 end
            Registry.inventoryChanged(root)
            return j,{attemptId=j.payload.attempt.id,observed=true,baseBeforeId=baseId,baseAfterId=result:getID(),
                ingredientId=ingredientId,baseKnown=true,beforeAmount=s.beforeAmount,afterAmount=after}
        end})
end
function A.toggle(c,sequence,endpoint,desired)
    if type(desired)~='boolean' then return nil,'STOVE_INTENT_INVALID' end
    local function live() return Transfer.reachable(c.npc,endpoint) end
    return leaf(c,sequence,'TOGGLE',{}, {live=live,
        matches=function(s) return s.siteKey=='cooking:'..endpoint.id and s.desired==desired end,
        capture=function()
            if not live() then return nil,'STOVE_NOT_REACHABLE' end
            local stove,why=Duty.toggleCheck(c,endpoint,desired) if not stove then return nil,why end
            return {siteKey=stove.siteKey,desired=desired,beforeActive=stove.active,dutyRevision=c.job.payload.duty.revision}
        end,
        unchanged=function(s)
            local stove=require('EmberRoutesProbe/CookingFacilities').stove(endpoint)
            return stove and stove.siteKey==s.siteKey and stove.active==s.beforeActive
        end,
        valid=function(s)
            return live() and c.job.payload.duty and c.job.payload.duty.revision==s.dutyRevision
                and Duty.toggleCheck(c,endpoint,desired)~=nil
        end,
        create=function() return ISToggleStoveAction:new(c.npc,endpoint.object) end,
        observe=function(_,s)
            local stove=require('EmberRoutesProbe/CookingFacilities').stove(endpoint)
            if not stove or stove.siteKey~=s.siteKey or stove.active~=desired then return end
            local content=Duty.contents(c,endpoint) if not content then return end
            local j=Record.copy(c.job) local duty=j.payload.duty
            duty.lastActive=desired duty.state=desired and 'HEATING' or 'STOP_REQUIRED'
            if desired then duty.openedByJob=true else duty.shutdownObserved=true end
            return j,{attemptId=j.payload.attempt.id,observed=true,siteKey=s.siteKey,
                expectedActive=desired,actualActive=stove.active,controlled=true}
        end})
end
function A.transfer(c,sequence,item,endpoint,direction,finalCustody)
    if direction~='TAKE' and direction~='PUT' then return nil,'TRANSFER_DIRECTION_INVALID' end
    local root=c.npc:getInventory() local id=item:getID()
    local from=direction=='TAKE' and endpoint.container or root
    local to=direction=='TAKE' and root or endpoint.container
    local custody=direction=='TAKE' and (c.job.payload.duty and c.job.payload.duty.siteKey=='cooking:'..endpoint.id and 'STATION' or 'SOURCE') or 'HELD'
    finalCustody=direction=='TAKE' and 'HELD' or finalCustody
    if finalCustody~='HELD' and finalCustody~='STATION' and finalCustody~='DELIVERED' and finalCustody~='RETURNED' then
        return nil,'TRANSFER_CUSTODY_INVALID'
    end
    local function live() return Transfer.reachable(c.npc,endpoint) end
    local function eligible()
        local e=Registry.revalidate(endpoint,direction=='TAKE' and 'take' or 'put','local-world')
        if not e or not live() or not claimed(c,item,from,custody) or item:getIsCraftingConsumed()
            or (custody~='STATION' and not Registry.accepts(e,item)) or not to:hasRoomFor(c.npc,item) then return false end
        if to==root then return Carry.fits(c.npc,item:getUnequippedWeight()) end
        if item:isFavorite() then return false end
        if finalCustody=='STATION' then
            local d=c.job.payload.duty
            local stove=require('EmberRoutesProbe/CookingFacilities').stove(e)
            return d and d.siteKey=='cooking:'..endpoint.id and Store.validCooking(c.job,c.token,d.siteKey)
                and stove and not stove.active and not stove.broken and Duty.contents(c,e)~=nil or false
        end
        if Registry.logistics(e)~='STORAGE' then return false end
        if finalCustody=='RETURNED' then
            local asset=Inventory.asset(c.job,id)
            if asset.role=='OUTPUT' and c.job.payload.heat and c.job.payload.heat.aborted then
                local food=Food.read(item) local cold=require('EmberRoutesProbe/CookingFacilities').cold(e,'put')
                if not food or not food.food or not food.safe or not cold or not cold.cold then return false end
            end
        end
        if finalCustody=='DELIVERED' then
            local cold=require('EmberRoutesProbe/CookingFacilities').cold(e,'put')
            local food=Food.read(item) local a=Inventory.asset(c.job,id)
            -- A requested recipe may produce an ingredient (Butter), not a meal.
            -- It still needs safe actual Food/cold storage and never enters AUTO reserves.
            local request=c.job.payload.fixed and c.job.payload.source=='REQUEST'
            local ready=food and (food.ready or request and food.food and food.safe and not food.needsHeat
                and not food.frozen and not food.requiresTool and food.effective>0)
            if not cold or not cold.cold or not ready or a.role~='OUTPUT' then return false end
        end
        return Store.availableCooking(c.job,c.token,endpoint.id,to:getFreeCapacity(c.npc))>=item:getUnequippedWeight()
    end
    return leaf(c,sequence,'TRANSFER',{id},{item=item,live=live,
        matches=function(s)
            return s.itemId==id and s.custody==finalCustody
                and s.fromId==(direction=='TAKE' and endpoint.id or 'npc:'..c.job.npcId)
                and s.toId==(direction=='TAKE' and 'npc:'..c.job.npcId or endpoint.id)
        end,
        capture=function()
            if not eligible() then return nil,'TRANSFER_PRECONDITION' end
            return {itemId=id,fullType=item:getFullType(),fromId=direction=='TAKE' and endpoint.id or 'npc:'..c.job.npcId,
                toId=direction=='TAKE' and 'npc:'..c.job.npcId or endpoint.id,custody=finalCustody}
        end,
        unchanged=function(s)
            return Registry.revalidate(endpoint,direction=='TAKE' and 'take' or 'put','local-world')~=nil
                and item:getFullType()==s.fullType and Inventory.contains(item,from,id) and not to:getItems():contains(item)
        end,
        valid=function() return eligible() end,
        create=function() return ISInventoryTransferAction:new(c.npc,item,from,to,90) end,
        observe=function(action,s)
            if not Registry.revalidate(endpoint,direction=='TAKE' and 'take' or 'put','local-world') then return end
            if action.item~=item or not Inventory.contains(item,to,id) or from:getItems():contains(item) then return end
            local j=Record.copy(c.job) local a=Inventory.asset(j,id) a.custody=finalCustody
            if finalCustody=='DELIVERED' or finalCustody=='RETURNED' then
                if a.role=='OUTPUT' then require('EmberRoutesProbe/CookingCapacity').delivered(j,endpoint.id,item:getUnequippedWeight()) end
                Inventory.release(j,id,finalCustody)
                local facts=Food.read(item) if not facts then return end
                if facts.food then a.raw,a.effective=facts.raw,facts.effective end
            end
            Registry.inventoryChanged(from) Registry.inventoryChanged(to)
            return j,{attemptId=j.payload.attempt.id,observed=true,itemId=id,fromId=s.fromId,toId=s.toId,
                sourceAbsent=true,destinationPresent=true}
        end})
end
return A
