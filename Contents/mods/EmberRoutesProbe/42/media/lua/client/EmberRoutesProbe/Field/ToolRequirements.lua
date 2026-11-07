-- Pure physical and functional matching for field tools and consumables.
-- Decoupled completely from ownership, reservation, and claim state.
local T={}

-- Remaining pure-water sprays in a container. Uses the native menu helper when
-- available so supply planning and the watering action agree on the unit.
function T.uses(item)
    if not item or not item.getFluidContainer then return 0 end
    local f=item:getFluidContainer()
    if not f then return 0 end
    if ISFarmingMenu and ISFarmingMenu.getWaterUsesInteger then
        local ok,value=pcall(ISFarmingMenu.getWaterUsesInteger,item)
        if ok and type(value)=='number' then return math.max(0,math.floor(value)) end
    end
    return math.max(0,math.floor(f:getAmount() or 0))
end

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
        if not f then return false end
        local b1=Fluid and Fluid.Bleach and f:contains(Fluid.Bleach)
        local b2=Fluid and Fluid.CleaningLiquid and f:contains(Fluid.CleaningLiquid)
        return f and (b1 or b2) and f:getAmount()>=minAmount or false
    elseif role=='WATER_FLUID' then
        local f=item.getFluidContainer and item:getFluidContainer()
        return f and f:isFilledWithCleanWater() and T.uses(item)>0 or false
    elseif role=='DIG_PLOW' then
        return item.hasTag and ItemTag and item:hasTag(ItemTag.DIG_PLOW) or false
    elseif role=='CURE_TOOL' then
        return T.cureType(item)~=nil
    elseif role=='SEED' then
        return T.seedType(item)~=nil
    end
    return false
end

-- Garden sprays, per vanilla ISFarmingMenu. Cigarettes serve both mildew and
-- flies; the other three map one-to-one.
local SPRAY={Mildew='GardeningSprayCigarettes',Flies='GardeningSprayMilk',
    Slugs='SlugRepellent',Aphids='GardeningSprayAphids'}
-- Seed packet -> vegetable type, using vanilla's own seedTypes table so our
-- mapping cannot drift from the crop config.
local function isSeedBag(full)
    return type(full)=='string' and string.find(full,'BagSeed',1,true)~=nil
end

function T.seedType(item)
    if not item or not item.getFullType or not farming_vegetableconf or not farming_vegetableconf.props then return nil end
    local full=item:getFullType()
    if isSeedBag(full) then return nil end
    for typeOfSeed,props in pairs(farming_vegetableconf.props) do
        local seedTypes=props.seedTypes or (props.seedName and {props.seedName}) or nil
        if seedTypes then
            for i=1,#seedTypes do if full==seedTypes[i] then return typeOfSeed end end
        end
    end
    return nil
end

function T.seedItem(inventory)
    if not inventory then return nil end
    return inventory:getFirstEvalRecurse(function(i)
        return i.hasTag and ItemTag and i:hasTag(ItemTag.IS_SEED) and T.seedType(i)~=nil
            and not (i.isBroken and i:isBroken())
    end)
end

function T.cureType(item)
    if not item or not item.getType or item.isBroken and item:isBroken() then return nil end
    local kind=item:getType()
    for disease,spray in pairs(SPRAY) do if kind==spray then return disease end end
    return nil
end

-- A usable spray for this disease: matching type and at least one use left.
function T.cureItem(inventory,disease)
    if not inventory or not disease then return nil end
    local wanted=SPRAY[disease]
    if not wanted then return nil end
    return inventory:getFirstEvalRecurse(function(i)
        return i:getType()==wanted and i.getCurrentUses and i:getCurrentUses()>0
    end)
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
    elseif kind=='CURE' then
        return {'CURE_TOOL'}
    elseif kind=='SOW' then
        return {'SEED'}
    end
    return {}
end

return T
