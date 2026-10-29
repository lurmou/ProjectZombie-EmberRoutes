-- One active read-only request per dialog, evaluated sequentially across workers.
local Crafting=require 'EmberRoutesProbe/CraftingService'
local M={}
function M.watch(actor,scope,recipe,quantity,surface,callback,preferences)
    local cooking=require('EmberRoutesProbe/CookingOrders').describe(recipe)
    if cooking then
        callback({state='WAITING',conditions={'COOKING_ASSIGNMENT_PREVIEW'},counts={},cooking=true,recipe=cooking})
        return function() end
    end
    local workers=Crafting.status(actor,scope).workers or {}
    local stopped=false local release local position=0 local best local token
    local function advance()
        position=position+1
        if position>#workers then callback(best or {state='WAITING',conditions={'WAITING_CLAIM'},counts={}}) return end
        local current={} token=current
        local unsubscribe=Crafting.preview(actor,scope,workers[position].id,recipe,quantity,surface,function(result)
            if stopped or token~=current then return end
            if result.state=='CHECKING' then return end
            token=nil
            if release then release() release=nil end
            if result.state=='READY' then callback(result)
            else
                best=best or result
                if result.conditions and result.conditions[1]~='NPC_RECIPE_UNKNOWN' and result.conditions[1]~='NPC_SKILL_TOO_LOW' then best=result end
                advance()
            end
        end,preferences)
        if stopped or token~=current then if unsubscribe then unsubscribe() end else release=unsubscribe end
    end
    advance()
    return function() stopped=true token=nil if release then release() release=nil end end
end
return M
