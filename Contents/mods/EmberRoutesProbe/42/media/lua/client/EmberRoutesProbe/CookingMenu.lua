-- Read-only native EvolvedRecipe selection. One bounded pantry pass serves all
-- candidate recipes; no addItem simulation and no separate production ledger.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Membership=require 'EmberRoutesProbe/SettlementMembership'
local Supply=require 'EmberRoutesProbe/CraftSupply'
local Read=require 'EmberRoutesProbe/InventoryRead'
local Food=require 'EmberRoutesProbe/CookingFood'
local Evolved=require 'EmberRoutesProbe/CookingEvolved'
local Fluids=require 'EmberRoutesProbe/CraftFluids'
local Policy=require 'EmberRoutesProbe/CookingPolicy'
local Store=require 'EmberRoutesProbe/LaborStore'
local Producers=require 'EmberRoutesProbe/LaborProducers'
local Wake=require 'EmberRoutesProbe/PlanningWake'
local M={}
local function fresh(item)
    if not item.getAge or not item.getOffAgeMax then return math.huge,2 end
    local age,off=item:getAge(),item:getOffAgeMax()
    if not Policy.finite(age) or not Policy.finite(off) or off<=0 or off>=1000000000 then return math.huge,2 end
    local remaining=math.max(0,off-age)
    return remaining,remaining/off<.3 and 0 or 1
end
local function better(a,b)
    if a.tier~=b.tier then return a.tier<b.tier end
    if a.fresh~=b.fresh then return a.fresh<b.fresh end
    return a.id<b.id
end
-- Refit to the NOW-current gap after public claim competition. Prediction is in
-- final effective fullness, not raw hunger and not the size of the vessel.
function M.fit(selection,target)
    if selection.kind=='HEAT' then
        local food=Food.read(selection.base.item)
        if not food or not food.safe or not food.needsHeat or food.frozen then return nil,'HEAT_FOOD_UNSUPPORTED' end
        local amount=Food.projected(food)
        return {kind='HEAT',base=selection.base,entries={},estimated=amount,minimum=amount,target=math.min(target,amount)}
    end
    if not Policy.finite(target) or target<=0 or Evolved.signature(selection.recipe)~=selection.signature then return nil,'EVOLVED_PROFILE_CHANGED' end
    local entries,spices,locations,total,minimum={},{},{[selection.base.endpoint.id]=true},0,nil
    for _,row in ipairs(selection.entries) do
        local food=Food.read(row.item)
        if not food or not food.food or not food.safe or food.frozen then return nil,'INGREDIENT_UNSAFE' end
        if row.item:isSpice() then spices[#spices+1]=row
        else
            local input=selection.recipe:getItemRecipe(row.item) local use=input and input:getUse()
            if not Policy.finite(use) or use<=0 then return nil,'EVOLVED_PROFILE_CHANGED' end
            local contribution=math.min(use/100,math.floor(food.effective*100)/100)*(selection.recipe:isCookable() and 1.3 or 1)
            if contribution>0 and not (total+Policy.epsilon>=Policy.unit/2 and total+contribution>target+Policy.epsilon) then
                entries[#entries+1]=row total=total+contribution locations[row.endpoint.id]=true
                if not minimum and total+Policy.epsilon>=Policy.unit/2 then minimum=total end
            end
        end
    end
    if not minimum then return nil,'COOKING_MINIMUM_UNAVAILABLE' end
    for _,row in ipairs(spices) do if locations[row.endpoint.id] and #entries<16 then entries[#entries+1]=row end end
    return {recipe=selection.recipe,signature=selection.signature,base=selection.base,entries=entries,
        target=math.min(target,total),estimated=total,minimum=minimum}
end
function M.new(entry,npc,target,recipeId,accept,options)
    if not Policy.finite(target) or target<=0 then return nil,'EVOLVED_PLAN_INVALID' end
    local manager=getScriptManager and getScriptManager()
    if not manager or not manager.getAllEvolvedRecipes then return nil,'EVOLVED_REGISTRY_UNAVAILABLE' end
    local recipes=manager:getAllEvolvedRecipes()
    if not recipes or recipes:size()>2048 then return nil,'EVOLVED_REGISTRY_LIMIT' end
    local ids,why=Membership.query(entry) if not ids then return nil,why end
    local world,watch=Registry.data(),Wake.capture(entry)
    local owner,revision=Store.claimsVersion()
    local q={recipes={},types={},pantry={},seen={},recipeIndex=0,phase='CATALOG',position=1,read=0}
    local directives=require 'EmberRoutesProbe/CookingDirectives'
    local less=directives.less(entry.id)
    local cookPolicy=require('EmberRoutesProbe/JobPolicyService').get(entry.id,'cooking')
    local waterAmount,waterSeen,waterRequest=0,{},nil
    local portableAmounts={}
    local actor=options and options.actor or getSpecificPlayer and getSpecificPlayer(0)
    local function valid()
        local current,version=Store.claimsVersion()
        return Registry.data()==world and current==owner and version==revision and not Wake.changed(watch)
    end
    local function inspect(item,endpoint)
        local id=item:getID()
        if q.seen[id] then return false,'ITEM_ID_CONFLICT' end q.seen[id]=true
        if Store.owner(id) or not Producers.eligible(item) or item:getIsCraftingConsumed()
            or not Registry.accepts(endpoint,item) then return true end
        local food,err=Food.read(item) if not food then return false,err end
        if not require('EmberRoutesProbe/FoodPolicyEvaluator').allows(cookPolicy,item) then return true end
        if food.food and (not food.safe or food.frozen) then return true end
        local container=item.getFluidContainer and item:getFluidContainer()
        local water=container and Fluids.water(container)
        if water and water.amount>0 then
            portableAmounts[id]=water.amount waterAmount=waterAmount+water.amount
        end
        if not food.food and not q.types[item:getFullType()] and (not item.getType or not q.types[item:getType()]) then return true end
        if #q.pantry>=2048 then return false,'COOKING_PANTRY_LIMIT' end
        local remaining,tier=math.huge,2
        if food.food then remaining,tier=fresh(item) end
        q.pantry[#q.pantry+1]={id=id,item=item,endpoint=endpoint,food=food,fresh=remaining,tier=tier}
        if not recipeId and food.food and food.needsHeat and not food.requiresTool and item.getReplaceOnCooked and item.getOnCooked then
            local replacements,callback=item:getReplaceOnCooked(),item:getOnCooked()
            if (not replacements or replacements:size()==0) and (not callback or callback=='') then
                local amount=Food.projected(food)
                if amount and amount>=Policy.unit/2 then
                    local candidate={kind='HEAT',base=q.pantry[#q.pantry],entries={},estimated=amount,minimum=amount,
                        target=math.min(target,amount),fresh=remaining,tier=tier,cost=1,profileId='heat:'..item:getFullType()}
                    local best=q.rawBest
                    if not best or less(candidate.base,best.base) then q.rawBest=candidate end
                end
            end
        end
        return true
    end
    local function finishRecipe()
        local r=q.current
        if r.base and #r.main>0 and (not r.recipe:isCookable() or q.hasStove) then
            table.sort(r.main,less)
            local selected,total,minimum,locations={},0,nil,{}
            locations[r.base.endpoint.id]=true
            for _,row in ipairs(r.main) do
                -- Prefer a complete portion below Q over an unnecessary extra
                -- native addition. Only the indivisible minimum may exceed Q.
                if total+Policy.epsilon>=Policy.unit/2 and total+row.contribution>target+Policy.epsilon then break end
                selected[#selected+1]=row total=total+row.contribution locations[row.endpoint.id]=true
                if not minimum and total+Policy.epsilon>=Policy.unit/2 then minimum=total end
                if total+Policy.epsilon>=math.max(target,Policy.unit/2) then break end
            end
            if total+Policy.epsilon>=Policy.unit/2 then
                local spices,types=0,{}
                for _,row in ipairs(r.spices) do
                    local kind=row.item:getFullType()
                    if locations[row.endpoint.id] and not types[kind] and spices<Policy.maxSpices and #selected<16 then
                        selected[#selected+1]=row types[kind]=true spices=spices+1
                    end
                end
                local candidate={recipe=r.recipe,signature=r.signature,base=r.base,entries=selected,
                    target=math.min(target,total),minimum=minimum,estimated=total,fresh=r.main[1].fresh,tier=r.main[1].tier,
                    cost=r.baseRank+(r.recipe:isCookable() and 1 or 0),rank=r.main[1]}
                local best=q.best
                local bestRank=best and (best.rank or best.base)
                if not best or less(candidate.rank,bestRank) or not less(bestRank,candidate.rank)
                    and (candidate.cost<best.cost or candidate.cost==best.cost
                        and r.recipe:getOriginalname()<(best.recipe and best.recipe:getOriginalname() or best.profileId)) then q.best=candidate end
            end
        end
        q.current=nil q.offset=nil
    end
    function q:step(budget)
        if not Policy.finite(budget) or budget<1 or budget>32 or budget~=math.floor(budget) then return nil,'SCAN_BUDGET_INVALID' end
        if not valid() then return nil,'SUPPLY_CHANGED' end
        if self.done then return true end
        for _=1,budget do
            if self.phase=='CATALOG' then
                if self.recipeIndex>=recipes:size() then self.phase='SCAN'
                else
                    local r=recipes:get(self.recipeIndex) self.recipeIndex=self.recipeIndex+1
                    local stamp=Evolved.signature(r)
                    if stamp and (not recipeId or r:getOriginalname()==recipeId) and (not accept or accept(r))
                        and r.getItemRecipe and r.needToBeCooked then
                        self.recipes[#self.recipes+1]={recipe=r,signature=stamp}
                        self.types[r:getBaseItem()]=true
                        if r:getMinimumWater()>0 then self.needsWater=true end
                    end
                end
            elseif self.phase=='SCAN' then
                if self.rows then
                    local item=self.rows[self.rowOffset]
                    if not item then self.rows=nil
                    else
                        self.rowOffset=self.rowOffset+3
                        if not Registry.revalidate(self.source,'take','local-world') then return nil,'SOURCE_ACCESS_CHANGED' end
                        if item:getContainer()~=self.source.container then return nil,'INPUT_CHANGED' end
                        local ok,err=inspect(item,self.source) if not ok then return nil,err end
                    end
                elseif self.source then
                    if not Registry.revalidate(self.source,'take','local-world') then return nil,'SOURCE_ACCESS_CHANGED' end
                    if self.cursor>=self.size then self.source=nil
                    else
                        local count=math.min(8,self.size-self.cursor)
                        local rows,err=Read.slice(self.source.container,self.list,self.size,self.cursor,count)
                        if not rows then return nil,err end
                        self.rows,self.rowOffset,self.cursor=rows,1,self.cursor+count
                        self.read=self.read+count if self.read>20000 then return nil,'INVENTORY_SCAN_LIMIT' end
                    end
                else
                    local id=ids[self.position] self.position=self.position+1
                    if not id then
                        if self.hasStove then self.best=self.rawBest end
                        self.phase=self.needsWater and actor and 'WATER' or 'MATCH' self.position=1
                    else
                        local oven=Supply.endpoint(entry,id,'put')
                        local stove=oven and require('EmberRoutesProbe/CookingFacilities').stove(oven)
                        if stove and directives.kitchen(entry.id,oven.object) and stove.powered and not stove.active and not stove.broken
                            and not Store.resourceOwner(stove.siteKey) and oven.container:getItems():size()==0 then self.hasStove=true end
                        local endpoint,err=Supply.endpoint(entry,id,'take')
                        if not endpoint and err=='CONTAINER_UNLOADED' then return nil,err end
                        if endpoint and Registry.logistics(endpoint)=='STORAGE' then
                            self.source=endpoint self.list=endpoint.container:getItems() self.size=self.list:size() self.cursor=0
                            if self.size>2000 then return nil,'SOURCE_SCAN_LIMIT' end
                        end
                    end
                end
            elseif self.phase=='WATER' then
                if not waterRequest then waterRequest=require('EmberRoutesProbe/CookingWaterSources').search(
                    {actor=actor,entry=entry,job={id='offer:'..entry.id,scopeId=entry.id}}) end
                local source,why=waterRequest:step(1)
                if source then
                    local identity=source.backing and source.backing.object or source.object
                    waterAmount=waterAmount-(waterSeen[identity] or 0)+source.amount waterSeen[identity]=source.amount
                    waterRequest:skip(source.object,source.amount,source.backing and source.backing.object)
                elseif why~='SITE_OBSERVING' and why~='FACILITIES_SCANNING' then self.phase='MATCH' end
            else
                if not self.current then
                    local profile=self.recipes[self.position] self.position=self.position+1
                    if not profile then self.done=true return true end
                    self.current={recipe=profile.recipe,signature=profile.signature,main={},spices={}} self.offset=1
                else
                    local row=self.pantry[self.offset] self.offset=self.offset+1
                    if not row then finishRecipe()
                    else
                        local r=self.current local item=row.item
                        if not row.food.food and (item:getFullType()==r.recipe:getBaseItem() or item.getType and item:getType()==r.recipe:getBaseItem()) then
                            local water=true local rank=0
                            if r.recipe:getMinimumWater()>0 then
                                local fluid=item.getFluidContainer and Fluids.water(item:getFluidContainer())
                                water=fluid~=nil rank=r.recipe:hasMinimumWater(item) and 0 or 1
                                if fluid and rank>0 then water=waterAmount-(portableAmounts[row.id] or 0)+Policy.epsilon
                                    >=math.max(0,fluid.capacity*r.recipe:getMinimumWater()-fluid.amount) end
                            end
                            if water and (not r.base or rank<r.baseRank or rank==r.baseRank and row.id<r.base.id) then
                                r.base=row r.baseRank=rank
                            end
                        elseif row.food.food and r.recipe:needToBeCooked(item) then
                            local input=r.recipe:getItemRecipe(item) local use=input and input:getUse()
                            if Policy.finite(use) and use>0 and row.food.effective>0 then
                                local candidate={id=row.id,item=item,endpoint=row.endpoint,fresh=row.fresh,tier=row.tier,
                                    contribution=math.min(use/100,math.floor(row.food.effective*100)/100)
                                        *(r.recipe:isCookable() and 1.3 or 1)}
                                if item:isSpice() then
                                    -- Keep bounded alternatives; no extra pantry walk for seasoning.
                                    if #r.spices<16 then r.spices[#r.spices+1]=candidate end
                                elseif candidate.contribution>0 then
                                    r.main[#r.main+1]=candidate table.sort(r.main,less)
                                    if #r.main>r.recipe:getMaxItems() then table.remove(r.main) end
                                end
                            end
                        end
                    end
                end
            end
        end
        return false
    end
    function q:result()
        if not self.done then return nil,'SUPPLY_NOT_OBSERVED' end
        if not valid() then return nil,'SUPPLY_CHANGED' end
        if not self.best then return nil,'COOKING_MATERIALS_UNAVAILABLE' end
        local selection=self.best
        if selection.kind~='HEAT' and Evolved.signature(selection.recipe)~=selection.signature then return nil,'EVOLVED_PROFILE_CHANGED' end
        local rows={selection.base} for _,row in ipairs(selection.entries) do rows[#rows+1]=row end
        for _,row in ipairs(rows) do
            if not Registry.revalidate(row.endpoint,'take','local-world') or Store.owner(row.id)
                or not Producers.eligible(row.item) or row.item:getIsCraftingConsumed()
                or row.item:getID()~=row.id or row.item:getContainer()~=row.endpoint.container
                or not Registry.accepts(row.endpoint,row.item) then return nil,'INPUT_CHANGED' end
            local food=Food.read(row.item)
            if not food or food.food and (not food.safe or food.frozen) then return nil,'INGREDIENT_UNSAFE' end
        end
        return selection
    end
    return q
end
return M
