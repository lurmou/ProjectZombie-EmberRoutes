-- Narrow B42 native adapter. Registration rejects changed scripts rather than guessing IO.
local Rules=require "EmberRoutesProbe/HaulRules"
local Adapter={limit=512}
function Adapter.list(item)
    local result=ArrayList.new() result:add(item) return result
end
function Adapter.atBench(character,object)
    local square=object and object:getSquare()
    local current=character and character:getCurrentSquare()
    local cell=getCell()
    return square and current and cell and cell:getGridSquare(square:getX(),square:getY(),square:getZ())==square
        and square:getObjects():contains(object) and current:canReachTo(square)
        and Rules.near(character:getX(),character:getY(),character:getZ(),square:getX()+0.5,square:getY()+0.5,square:getZ())
end
function Adapter.inspect(actor,npc,object,requireKnowledge,requireNear)
    if not object or not object.isGenericCraftingSurface or not npc.canUseAsGenericCraftingSurface
        or not ResourceType or not ResourceType.Item
        or not HandcraftLogic or not HandcraftLogic.new then return nil,"CRAFT_API_UNAVAILABLE" end
    local square=object:getSquare() local cell=getCell()
    if not square or not cell or cell:getGridSquare(square:getX(),square:getY(),square:getZ())~=square
        or not square:getObjects():contains(object) or not object:isGenericCraftingSurface() then return nil,"CRAFT_SURFACE_REQUIRED" end
    if requireNear~=false and (not Adapter.atBench(npc,object) or not npc:canUseAsGenericCraftingSurface(object)) then return nil,"STAND_BY_SURFACE" end
    local occupant=object:getUsingPlayer()
    if occupant and occupant~=npc then return nil,"BENCH_OCCUPIED" end
    local manager=getScriptManager()
    if not manager or not manager.getCraftRecipe then return nil,"CRAFT_API_UNAVAILABLE" end
    local recipe=manager:getCraftRecipe("Base.CarveWoodenFork")
    if not recipe or (recipe:getName()~="CarveWoodenFork" and recipe:getName()~="Base.CarveWoodenFork")
        or not recipe:isAnySurfaceCraft() or recipe:requiresSpecificWorkstation() then return nil,"RECIPE_UNAVAILABLE" end
    local inputs,outputs=recipe:getInputs(),recipe:getOutputs()
    if inputs:size()~=2 or outputs:size()~=1 or recipe:getRequiredSkillCount()~=1
        or not recipe:needToBeLearn() then return nil,"RECIPE_CHANGED" end
    local skill=recipe:getRequiredSkill(0)
    if not Perks or skill:getPerk()~=Perks.Carving or skill:getLevel()~=2 then return nil,"RECIPE_CHANGED" end
    if not actor:isRecipeKnown(recipe,true) then return nil,"PLAYER_RECIPE_UNKNOWN" end
    if npc:getPerkLevel(skill:getPerk())<skill:getLevel() then return nil,"NPC_SKILL_TOO_LOW" end
    if requireKnowledge and not npc:isRecipeKnown(recipe,true) then return nil,"NPC_RECIPE_UNKNOWN" end
    local spec={recipe=recipe,object=object} -- Generic surface: no CraftBench component required.
    for i=0,inputs:size()-1 do
        local input=inputs:get(i)
        if input:getResourceType()~=ResourceType.Item or input:isVariableAmount() or input:getIntAmount()~=1 then
            return nil,"RECIPE_CHANGED"
        end
        local key=input:isKeep() and "tool" or "material"
        if spec[key] then return nil,"RECIPE_CHANGED" end spec[key]=input
    end
    local output=outputs:get(0)
    local possible=output:getPossibleResultItems()
    if not spec.tool or not spec.material or output:getResourceType()~=ResourceType.Item
        or output:isVariableAmount() or output:getIntAmount()~=1 or possible:size()~=1
        or possible:get(0):getFullName()~="Base.WoodenFork" then return nil,"RECIPE_CHANGED" end
    spec.outputWeight=possible:get(0):getActualWeight()
    return spec
end
function Adapter.manual(spec,material,tool)
    return {[spec.recipe:getIndexForIO(spec.material)]=Adapter.list(material),
        [spec.recipe:getIndexForIO(spec.tool)]=Adapter.list(tool)}
end
function Adapter.applied(logic,material,tool)
    if not logic then return false,"NATIVE_LOGIC_MISSING" end
    -- Native start already populated/validated these inputs. Re-running the
    -- planner after craftStarted counts this action's own queued reservation.
    -- Native performCurrentRecipe validates again with testOnly=false.
    local items=logic:getRecipeData():getAllInputItems()
    if items:size()~=2 or not items:contains(material) or not items:contains(tool) then
        return false,"NATIVE_INPUT_SET_CHANGED"
    end
    return true
end
return Adapter
