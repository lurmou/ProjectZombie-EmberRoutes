-- Native facts only. Never changes food, calls a recipe, or grants consumption.
local Policy=require 'EmberRoutesProbe/CookingPolicy'
local F={}
-- Current Food.getHungerChange returns hungChange*1.3 once cooked. Project only
-- the uncooked, safe, original-preserving profiles; ready stock always uses actual.
function F.projected(row)
    if not row or not row.food or not row.safe then return nil end
    return row.needsHeat and row.raw*1.3 or row.effective
end
local meals={['Base.PotOfSoupRecipe']=true,['Base.PotOfSoup']=true,['Base.PotOfStew']=true,
    ['Base.PanFriedVegetables']=true,['Base.Salad']=true,['Base.BreadDough']=true}
local required={'getID','getFullType','getHungChange','getHungerChange','getBaseHunger',
    'isRotten','isBurnt','isPoison','getPoisonPower','isTainted','isCooked','isCookable',
    'isbDangerousUncooked','isFrozen','isSpice','getRequireInHandOrInventory'}
function F.read(item)
    if not item or type(instanceof)~='function' or not instanceof(item,'Food') then return {food=false} end
    for _,name in ipairs(required) do if not item[name] then return nil,'FOOD_READ_UNAVAILABLE' end end
    local raw,effective,base=item:getHungChange(),item:getHungerChange(),item:getBaseHunger()
    if type(raw)~='number' or raw~=raw or math.abs(raw)==math.huge
        or type(effective)~='number' or effective~=effective or math.abs(effective)==math.huge
        or type(base)~='number' or base~=base or math.abs(base)==math.huge then return nil,'FOOD_AMOUNT_UNKNOWN' end
    local poison=item:getPoisonPower()
    if not Policy.finite(poison) then return nil,'FOOD_SAFETY_UNKNOWN' end
    local safe=not item:isRotten() and not item:isBurnt() and not item:isPoison()
        and poison==0 and not item:isTainted()
    local fullType=item:getFullType()
    local cooked=item:isCooked()
    local needsHeat=(item:isCookable() or item:isbDangerousUncooked()) and not cooked
    local tools=item:getRequireInHandOrInventory()
    -- Existing care rejects these; do not claim supply until its real adapter exists.
    local requiresTool=tools and tools:size()>0 or false
    local result={food=true,id=item:getID(),fullType=fullType,raw=math.max(0,-raw),
        effective=math.max(0,-effective),base=math.max(0,-base),safe=safe,cooked=cooked,
        frozen=item:isFrozen(),needsHeat=needsHeat,requiresTool=requiresTool}
    result.meal=not item:isSpice() and (cooked or meals[fullType]==true
        or require('EmberRoutesProbe/CookingProfiles').meal(fullType))
    result.ready=result.meal and safe and not needsHeat and not result.frozen and not requiresTool
        and result.effective>0
    if not safe then result.reason='FOOD_UNSAFE'
    elseif needsHeat then result.reason='FOOD_NEEDS_COOKING'
    elseif result.frozen then result.reason='FOOD_FROZEN'
    elseif requiresTool then result.reason='FOOD_TOOL_ADAPTER_REQUIRED'
    elseif not result.meal then result.reason='FOOD_RAW_INGREDIENT' end
    return result
end
return F
