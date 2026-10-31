-- Settlement-wide read-only demand matching with executor feasibility hint.
-- Decouples material availability from current worker availability.
local Crafting=require 'EmberRoutesProbe/CraftingService'
local Driver=require 'EmberRoutesProbe/Driver'
local Recipe=require 'EmberRoutesProbe/ProductionRecipe'
local M={}
function M.watch(actor,scope,recipe,quantity,surface,callback,preferences)
    local cooking=require('EmberRoutesProbe/CookingOrders').describe(recipe)
    if cooking then
        callback({state='WAITING',conditions={'COOKING_ASSIGNMENT_PREVIEW'},counts={},cooking=true,recipe=cooking})
        return function() end
    end

    local workers=Crafting.status(actor,scope).workers or {}
    local eligibleCount=0
    local spec=Recipe.read(recipe)
    if spec and spec.recipe then
        for _,w in ipairs(workers) do
            local binding=Driver.bindId(actor,w.id)
            if binding and Driver.valid(binding) and not (binding.handle.isDead and binding.handle:isDead())
                and binding.handle:isRecipeKnown(spec.recipe,true) then
                local meetSkills=true
                for i=0,spec.recipe:getRequiredSkillCount()-1 do
                    local skill=spec.recipe:getRequiredSkill(i)
                    if binding.handle:getPerkLevel(skill:getPerk())<skill:getLevel() then
                        meetSkills=false break
                    end
                end
                if meetSkills then eligibleCount=eligibleCount+1 end
            end
        end
    end

    local stopped=false
    local release=Crafting.preview(actor,scope,nil,recipe,quantity,surface,function(result)
        if stopped then return end
        if result and result.state~='CHECKING' then
            result.eligibleWorkerCount=eligibleCount
            result.totalWorkerCount=#workers
        end
        callback(result)
    end,preferences)

    return function()
        stopped=true
        if release then release() release=nil end
    end
end
return M
