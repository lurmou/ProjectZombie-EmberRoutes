-- Pure physical and functional matching for field tools and consumables.
-- Decoupled completely from ownership, reservation, and claim state.
local T={}

function T.matchPhysical(item,role)
    if not item or (item.isBroken and item:isBroken()) then return false end
    if role=='CHOP_TREE' then
        return item.hasTag and ItemTag and item:hasTag(ItemTag.CHOP_TREE) or false
    elseif role=='CLEAN_TOOL' then
        local t1=ItemTag and ItemTag.CLEAN_STAINS and item:hasTag(ItemTag.CLEAN_STAINS)
        local t2=ItemTag and ItemTag.MOP and item:hasTag(ItemTag.MOP)
        local t3=ItemTag and ItemTag.BROOM and item:hasTag(ItemTag.BROOM)
        return item.hasTag and (t1 or t2 or t3) or false
    elseif role=='CLEAN_FLUID' then
        local f=item.getFluidContainer and item:getFluidContainer()
        local minAmount=(ZomboidGlobals and ZomboidGlobals.CleanBloodBleachAmount) or 0.2
        local b1=Fluid and Fluid.Bleach and f:contains(Fluid.Bleach)
        local b2=Fluid and Fluid.CleaningLiquid and f:contains(Fluid.CleaningLiquid)
        return f and (b1 or b2) and f:getAmount()>=minAmount or false
    elseif role=='WATER_FLUID' then
        local f=item.getFluidContainer and item:getFluidContainer()
        local uses=ISFarmingMenu and ISFarmingMenu.getWaterUsesInteger and ISFarmingMenu.getWaterUsesInteger(item) or (f and f:getAmount() or 0)
        return f and f:isFilledWithCleanWater() and uses>0 or false
    elseif role=='DIG_PLOW' then
        return item.hasTag and ItemTag and item:hasTag(ItemTag.DIG_PLOW) or false
    end
    return false
end

function T.requiredRoles(kind)
    if kind=='TREE' then
        return {'CHOP_TREE'}
    elseif kind=='STAIN' then
        return {'CLEAN_TOOL','CLEAN_FLUID'}
    elseif kind=='WATER' then
        return {'WATER_FLUID'}
    elseif kind=='CLEAR' then
        return {'DIG_PLOW'}
    end
    return {}
end

return T
