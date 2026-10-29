-- Prepared-food chain only: held originals -> native water -> native additions.
-- Heating/delivery remain subsequent steps of the same Job, never synthetic recipes.
local Context=require 'EmberRoutesProbe/CookingContext'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Inventory=require 'EmberRoutesProbe/CookingInventory'
local Food=require 'EmberRoutesProbe/CookingFood'
local Policy=require 'EmberRoutesProbe/CookingPolicy'
local Fluids=require 'EmberRoutesProbe/CraftFluids'
local E={}
local function signature(recipe)
    if not recipe then return nil end
    for _,method in ipairs({'getOriginalname','getBaseItem','getFullResultItem','getMaxItems','getMinimumWater','isCookable'}) do
        if not recipe[method] then return nil end
    end
    local minimum,maximum=recipe:getMinimumWater(),recipe:getMaxItems()
    local name,base,result=recipe:getOriginalname(),recipe:getBaseItem(),recipe:getFullResultItem()
    if type(name)~='string' or type(base)~='string' or type(result)~='string' or #name+#base+#result>1500
        or not Policy.finite(minimum) or minimum>1 or not Policy.finite(maximum) or maximum~=math.floor(maximum)
        or maximum<1 or maximum>16 then return nil end
    local minStr=string.format('%.2f',tonumber(minimum) or 0)
    local maxStr=tostring(math.floor(tonumber(maximum) or 0))
    local cookStr=recipe:isCookable() and 'true' or 'false'
    return table.concat({name,base,result,maxStr,minStr,cookStr},':')
end
E.signature=signature
-- Only reads the installed recipe registry; never invokes addItem to plan food.
function E.recipe(id)
    if type(id)~='string' then return nil,'EVOLVED_ID_INVALID' end
    local rawId=string.sub(id,1,8)=='evolved:' and string.sub(id,9) or id
    local manager=getScriptManager and getScriptManager()
    if not manager or not manager.getAllEvolvedRecipes then return nil,'EVOLVED_REGISTRY_UNAVAILABLE' end
    local recipes=manager:getAllEvolvedRecipes()
    if not recipes or recipes:size()>2048 then return nil,'EVOLVED_REGISTRY_LIMIT' end
    for i=0,recipes:size()-1 do
        local recipe=recipes:get(i)
        if recipe:getOriginalname()==rawId or recipe:getOriginalname()==id then return recipe end
    end
    return nil,'EVOLVED_PROFILE_UNAVAILABLE'
end
-- Freeze an exact selection before collecting it. All native handles stay out of Jobs.
-- selection.base/entries are {id,item,endpoint?}; absence of endpoint means personal inventory.
function E.prepare(job,recipe,selection)
    local stamp=signature(recipe)
    if not Record.valid(job) or job.effects~='KNOWN' or job.state~='PREPARING'
        or job.payload.sequence~=0 or #job.payload.assets>0 or #job.payload.claims>0
        or job.payload.fixed or job.payload.evolved or not stamp or recipe:getOriginalname()~=job.payload.profileId
        or type(selection)~='table' or type(selection.base)~='table' or type(selection.entries)~='table'
        or #selection.entries<1 or #selection.entries>16 then return nil,'EVOLVED_PLAN_INVALID' end
    local j=Record.copy(job) local seen={} local main,spices={},{}
    local function retain(row,base)
        local item=row.item
        if not item or row.id~=item:getID() or seen[row.id] then return nil,'INPUT_CHANGED' end
        seen[row.id]=true
        if row.endpoint and item:getContainer()~=row.endpoint.container then return nil,'INPUT_CHANGED' end
        local food,why=Food.read(item)
        if not food or not base and (not food.food or not food.safe or food.frozen)
            or base and food.food and (not food.safe or food.frozen) then return nil,why or 'INGREDIENT_UNSAFE' end
        if base and not recipe:isResultItem(item) and item:getFullType()~=recipe:getBaseItem()
            and (not item.getType or item:getType()~=recipe:getBaseItem()) then return nil,'EVOLVED_BASE_INVALID' end
        local source=row.endpoint and row.endpoint.id
        j.payload.assets[#j.payload.assets+1]={id=row.id,fullType=item:getFullType(),
            custody=source and 'SOURCE' or 'HELD',role=base and 'TOOL' or 'INPUT'}
        j.payload.claims[#j.payload.claims+1]='item:'..row.id
        return {id=row.id,sourceId=source,spice=not base and item:isSpice() or false},food
    end
    local base,food=retain(selection.base,true) if not base then return nil,food end
    for _,row in ipairs(selection.entries) do
        local input,why=retain(row,false) if not input then return nil,why end
        local list=input.spice and spices or main list[#list+1]=input
    end
    if #main==0 or #spices>Policy.maxSpices then return nil,'EVOLVED_PLAN_INVALID' end
    for _,input in ipairs(spices) do main[#main+1]=input end
    j.payload.evolved={recipeId=job.payload.profileId,signature=stamp,originId=base.id,originSourceId=base.sourceId,provenance=true,
        inputs=main,cursor=1,baseSequence=0,mainEffective=food.food and Food.projected(food) or 0,finalUnits=true,
        target=job.payload.target,minimum=Policy.unit/2,completed=false}
    if not Record.valid(j) then return nil,'EVOLVED_PLAN_INVALID' end
    return j
end
function E.new(c,recipe,base,ingredients,target)
    local Actions=require 'EmberRoutesProbe/CookingActions'
    local Water=require 'EmberRoutesProbe/CookingWater'
    if not Context.active(c) or c.job.effects~='KNOWN' or c.job.payload.fixed then return nil,'COOKING_CONTROL_REQUIRED' end
    local stamp=signature(recipe)
    if not stamp or recipe:getOriginalname()~=c.job.payload.profileId then return nil,'EVOLVED_PROFILE_UNSUPPORTED' end
    if not c.job.payload.evolved then
        if not base or type(ingredients)~='table' or #ingredients>16 or not Policy.finite(target) or target<=0
            or c.job.payload.sequence~=0 then return nil,'EVOLVED_PLAN_INVALID' end
        local asset=Inventory.asset(c.job,base:getID())
        if not asset or asset.custody~='HELD' or not Inventory.contains(base,c.npc:getInventory(),asset.id)
            or not recipe:isResultItem(base) and base:getFullType()~=recipe:getBaseItem()
                and (not base.getType or base:getType()~=recipe:getBaseItem()) then return nil,'EVOLVED_BASE_INVALID' end
        local main,spice={},{}
        for _,item in ipairs(ingredients) do
            local row={id=item:getID(),spice=item:isSpice()}
            local a=Inventory.asset(c.job,row.id)
            if not a or a.custody~='HELD' or not Inventory.contains(item,c.npc:getInventory(),row.id) then return nil,'EVOLVED_INPUT_INVALID' end
            local list=row.spice and spice or main list[#list+1]=row
        end
        for _,row in ipairs(spice) do main[#main+1]=row end
        local initial=Food.read(base) if not initial then return nil,'FOOD_READ_UNAVAILABLE' end
        local j=Record.copy(c.job)
        j.payload.evolved={recipeId=recipe:getOriginalname(),signature=stamp,originId=base:getID(),
            inputs=main,cursor=1,baseSequence=0,mainEffective=initial.food and initial.effective or 0,
            target=target,minimum=Policy.unit/2,completed=false}
        if not Context.publish(c,j) then return nil,c.reason end
    elseif c.job.payload.evolved.signature~=stamp then
        print('[EmberRoutes] Evolved.new signature mismatch: expected='..tostring(c.job.payload.evolved.signature)..' actual='..tostring(stamp))
        return nil,'EVOLVED_PROFILE_CHANGED'
    end
    local water,leaf
    local function currentBase()
        local p=c.job.payload.evolved local id=p.originId
        if p.baseSequence>0 then
            local reference=Record.outputReference(c.job,p.baseSequence,1)
            local asset,why=Record.resolveOutput(c.job,reference)
            if not asset then return nil,why end id=asset.id
        end
        local snapshot,why=Inventory.snapshot(c.npc:getInventory())
        if not snapshot then return nil,why end
        local item=snapshot[id] local asset=Inventory.asset(c.job,id)
        if not item or not asset or asset.custody~='HELD' or asset.fullType~=item:getFullType() then return nil,'EVOLVED_BASE_MISSING' end
        return item
    end
    local function advance()
        local p=c.job.payload.evolved local a=c.job.payload.attempt local row=p.inputs[p.cursor]
        if not a or a.kind~='ADD' or a.state~='APPLIED' or a.id~=c.job.id..':'..p.activeSequence
            or not row or a.receipt.ingredientId~=row.id then return false end
        local ref=Record.outputReference(c.job,p.activeSequence,1)
        local asset=Record.resolveOutput(c.job,ref) if not asset then return false end
        local snapshot=Inventory.snapshot(c.npc:getInventory()) local item=snapshot and snapshot[asset.id]
        local food=item and Food.read(item) if not food or not food.food or not food.safe then return false end
        local j=Record.copy(c.job) local e=j.payload.evolved
        e.baseSequence=e.activeSequence e.activeSequence=nil e.cursor=e.cursor+1
        if not row.spice then e.mainEffective=e.finalUnits and Food.projected(food) or food.effective end
        return Context.publish(c,j)
    end
    local function fail(reason) c.reason=reason return 'Failure' end
    return {kind='Action',run=function()
        if not Context.current(c) then return 'Failure' end
        if leaf then
            local result=leaf.run() if result~='Success' then return result end
            if not advance() then return fail('EVOLVED_OUTPUT_UNCONFIRMED') end
            leaf=nil return 'Running'
        end
        local p=c.job.payload.evolved
        if p.activeSequence then
            local a=c.job.payload.attempt
            if a and a.id==c.job.id..':'..p.activeSequence and a.state=='APPLIED' then
                return advance() and 'Running' or fail('EVOLVED_OUTPUT_UNCONFIRMED')
            end
            if a and a.id==c.job.id..':'..p.activeSequence and a.state=='ABORTED' then
                local j=Record.copy(c.job) j.payload.evolved.activeSequence=nil
                return Context.publish(c,j) and 'Running' or 'Failure'
            end
            if p.activeSequence==c.job.payload.sequence+1 and c.job.effects=='KNOWN' then
                local j=Record.copy(c.job) j.payload.evolved.activeSequence=nil
                return Context.publish(c,j) and 'Running' or 'Failure'
            end
            return fail('EVOLVED_ATTEMPT_RETAINED') -- Includes restored dispatched work and unknown effects.
        end
        if water then
            local result=water.run() if result~='Success' then return result end water=nil
        end
        if not Context.active(c) then return 'Failure' end
        local item,why=currentBase() if not item then return fail(why) end
        if p.completed then return 'Success' end
        if p.baseSequence==0 and not recipe:isResultItem(item) and recipe:getMinimumWater()>0 then
            if not Fluids.water(item:getFluidContainer()) then return fail('PURE_WATER_REQUIRED') end
            if not recipe:hasMinimumWater(item) then
                water=Water.ensure(c,recipe,item)
                local j=Record.copy(c.job) j.payload.phase='FILLING'
                return Context.publish(c,j) and 'Running' or 'Failure'
            end
        end
        local row=p.inputs[p.cursor]
        if not row then
            if p.mainEffective+Policy.epsilon<p.minimum then return fail('COOKING_MINIMUM_UNAVAILABLE') end
            local j=Record.copy(c.job) j.payload.evolved.completed=true
            if p.finalUnits then j.payload.expected=p.mainEffective end
            return Context.publish(c,j) and 'Success' or 'Failure'
        end
        local snapshot=Inventory.snapshot(c.npc:getInventory()) local ingredient=snapshot and snapshot[row.id]
        local food=ingredient and Food.read(ingredient)
        local skip=not row.spice and p.mainEffective+Policy.epsilon>=math.max(p.target,p.minimum)
            or row.spice and ((c.job.payload.spiceCount or 0)>=Policy.maxSpices or not ingredient
                or recipe:isSpiceAdded(item,ingredient))
        if ingredient and (not food or not food.food or not food.safe or food.frozen) then skip=true end
        if ingredient and not recipe:isItemUsableInRecipe(c.npc,item,row.id) then skip=true end
        if skip then
            local j=Record.copy(c.job) j.payload.evolved.cursor=j.payload.evolved.cursor+1
            return Context.publish(c,j) and 'Running' or 'Failure'
        end
        if not ingredient then return fail('EVOLVED_INGREDIENT_MISSING') end
        local j=Record.copy(c.job) j.payload.evolved.activeSequence=j.payload.sequence+1
        j.payload.phase=row.spice and 'SEASONING' or 'ADDING'
        if not Context.publish(c,j) then return 'Failure' end
        leaf,why=Actions.add(c,c.job.payload.evolved.activeSequence,recipe,item,ingredient)
        if not leaf then return fail(why) end
        return 'Running'
    end}
end
return E
