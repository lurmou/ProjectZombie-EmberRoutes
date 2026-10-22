local Legacy=require "EmberRoutesProbe/CraftRecipeAdapter"
local Recipe={limit=64,outputLimit=32}
local function integer(n,max) return type(n)=="number" and n>=1 and n<=max and n==math.floor(n) end
function Recipe.read(id)
    if not ResourceType or not ResourceType.Item then return nil,"CRAFT_API_UNAVAILABLE" end
    if type(id)~="string" or #id>200 then return nil,"RECIPE_UNAVAILABLE" end
    local manager=getScriptManager()
    local recipe=manager and manager:getCraftRecipe(id)
    if not recipe then return nil,"RECIPE_UNAVAILABLE" end
    if not EmberRoutesProbeJava.recipeHasCallbacks or not EmberRoutesProbeJava.recipeHasSpecialOutputs then return nil,"CRAFT_API_UNAVAILABLE" end
    if recipe:requiresSpecificWorkstation() or recipe:isBuildableRecipe()
        or not (recipe:isAnySurfaceCraft() or recipe:isInHandCraftCraft())
        or recipe:hasOnTickInputs() or recipe:hasOnTickOutputs() or EmberRoutesProbeJava.recipeHasCallbacks(recipe)
        or EmberRoutesProbeJava.recipeHasSpecialOutputs(recipe) then
        return nil,"RECIPE_MECHANISM_UNSUPPORTED"
    end
    local spec={id=id,recipe=recipe,inputs={},outputs={},outputWeight=0,inputCount=0,toolCount=0,
        surface=recipe:isAnySurfaceCraft(),name=recipe:getTranslationName()}
    local signature={id,tostring(recipe:getTime()),tostring(spec.surface)}
    local inputs,outputs=recipe:getInputs(),recipe:getOutputs()
    if inputs:size()==0 or inputs:size()>16 or outputs:size()==0 or outputs:size()>8 then return nil,"RECIPE_MECHANISM_UNSUPPORTED" end
    for i=0,inputs:size()-1 do
        local io=inputs:get(i) local n=io:getIntAmount()
        if io:getResourceType()~=ResourceType.Item or io:isVariableAmount() or not integer(n,32)
            or io:hasCreateToItem() or io:hasConsumeFromItem() or io:isAutomationOnly()
            or io:isWorn() or io:isApplyOnTick() then return nil,"RECIPE_MECHANISM_UNSUPPORTED" end
        local possible=io:getPossibleInputItems()
        if possible:size()==0 or possible:size()>512 then return nil,"RECIPE_MECHANISM_UNSUPPORTED" end
        for j=0,possible:size()-1 do
            if io:isUsesPartialItem(possible:get(j)) then return nil,"RECIPE_MECHANISM_UNSUPPORTED" end
        end
        local slot=recipe:getIndexForIO(io)
        spec.inputs[#spec.inputs+1]={io=io,slot=slot,count=n,keep=io:isKeep()}
        spec.inputCount=spec.inputCount+n
        if io:isKeep() then spec.toolCount=spec.toolCount+n end
        signature[#signature+1]=slot..":"..io:getOriginalLine()
    end
    if spec.inputCount>Recipe.limit then return nil,"RECIPE_MECHANISM_UNSUPPORTED" end
    local total=0
    for i=0,outputs:size()-1 do
        local io=outputs:get(i) local n=io:getIntAmount() local possible=io:getPossibleResultItems()
        if io:getResourceType()~=ResourceType.Item or io:isVariableAmount() or not integer(n,32)
            or possible:size()~=1 or io:getChance()~=1 or io:isApplyOnTick()
            or io:hasCreateToItem() then return nil,"RECIPE_MECHANISM_UNSUPPORTED" end
        local item=possible:get(0) local key=item:getFullName()
        spec.outputs[key]=(spec.outputs[key] or 0)+n
        spec.outputWeight=spec.outputWeight+item:getActualWeight()*n total=total+n
        if i==0 then spec.product=key end
        signature[#signature+1]=io:getOriginalLine()
    end
    if total>Recipe.outputLimit then return nil,"RECIPE_MECHANISM_UNSUPPORTED" end
    spec.yield=spec.outputs[spec.product] spec.outputCount=total
    local skills=recipe:getRequiredSkills()
    if skills then for i=0,skills:size()-1 do signature[#signature+1]=skills:get(i) end end
    spec.signature=table.concat(signature,"\n")
    return spec
end
-- Bounded, detached display metadata. No inventory scan and no native handles escape.
function Recipe.describe(spec)
    local row={id=spec.id,name=spec.name,product=spec.product,yield=spec.yield,surface=spec.surface,inputs={},outputs={},supported=true}
    for _,input in ipairs(spec.inputs) do
        local names,seen,choices={},{},{} local possible=input.io:getPossibleInputItems()
        for i=0,possible:size()-1 do
            local item=possible:get(i) local name=item.getDisplayName and item:getDisplayName() or item:getFullName()
            choices[#choices+1]={name=name,fullType=item:getFullName()}
            if not seen[name] then seen[name]=true names[#names+1]=name end
        end
        table.sort(names)
        local more=math.max(0,#names-4) while #names>4 do table.remove(names) end
        row.inputs[#row.inputs+1]={slot=input.slot,count=input.count,keep=input.keep,names=names,more=more,choices=choices}
    end
    for i=0,spec.recipe:getOutputs():size()-1 do
        local io=spec.recipe:getOutputs():get(i) local item=io:getPossibleResultItems():get(0)
        row.outputs[#row.outputs+1]={name=item.getDisplayName and item:getDisplayName() or item:getFullName(),count=io:getIntAmount(),fullType=item:getFullName()}
    end
    return row
end
-- Reviewed script profiles, not a claim of in-game validation. All share this executor.
-- Full searchable recipe discovery is a separate UI slice.
function Recipe.examples()
    local rows={}
    for _,id in ipairs({"Base.CarveWoodenFork","Base.CarveWoodenSpoon","Base.CraftSheetRope",
        "Base.SawLogs","Base.ChopLog","Base.MakeTentKit","Base.MakeWoodenToolbox"}) do
        local spec=Recipe.read(id)
        if spec then rows[#rows+1]=Recipe.describe(spec) end
    end
    return rows
end
function Recipe.inspect(actor,npc,object,id,requireKnowledge,near)
    local spec,reason=Recipe.read(id) if not spec then return nil,reason end
    if not actor:isRecipeKnown(spec.recipe,true) then return nil,"PLAYER_RECIPE_UNKNOWN" end
    for i=0,spec.recipe:getRequiredSkillCount()-1 do
        local skill=spec.recipe:getRequiredSkill(i)
        if npc:getPerkLevel(skill:getPerk())<skill:getLevel() then return nil,"NPC_SKILL_TOO_LOW" end
    end
    if requireKnowledge and not npc:isRecipeKnown(spec.recipe,true) then return nil,"NPC_RECIPE_UNKNOWN" end
    if spec.surface then
        local square=object and object:getSquare() local cell=getCell()
        if not object or not object.isGenericCraftingSurface or not object:isGenericCraftingSurface()
            or not square or not cell or cell:getGridSquare(square:getX(),square:getY(),square:getZ())~=square
            or not square:getObjects():contains(object) then return nil,"CRAFT_SURFACE_REQUIRED" end
        if object:getUsingPlayer() and object:getUsingPlayer()~=npc then return nil,"BENCH_OCCUPIED" end
        if near and (not Legacy.atBench(npc,object) or not npc:canUseAsGenericCraftingSurface(object)) then return nil,"STAND_BY_SURFACE" end
    end
    return spec
end
function Recipe.manual(spec,entries)
    local manual={}
    for _,entry in ipairs(entries) do
        local items=manual[entry.slot] or ArrayList.new() manual[entry.slot]=items items:add(entry.item)
    end
    return manual
end
function Recipe.applied(logic,entries)
    local applied=logic and logic:getRecipeData():getAllInputItems()
    if not applied or applied:size()~=#entries then return false end
    for _,entry in ipairs(entries) do if not applied:contains(entry.item) then return false end end
    return true
end
return Recipe
