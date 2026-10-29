-- Bounded native observations used only at action boundaries, never per-frame.
local Food=require 'EmberRoutesProbe/CookingFood'
local Record=require 'EmberRoutesProbe/CookingRecord'
local I={limit=512}
function I.contains(item,container,id)
    return item and item:getID()==id and item:getContainer()==container and container:getItems():contains(item) or false
end
function I.asset(job,id)
    for _,a in ipairs(job.payload.assets) do if a.id==id then return a end end
end
function I.snapshot(container)
    local list=container:getItems() if list:size()>I.limit then return nil,'INVENTORY_OBSERVATION_LIMIT' end
    local ids={}
    for i=0,list:size()-1 do
        local item=list:get(i) local id=item:getID()
        if ids[id] or item:getContainer()~=container then return nil,'INVENTORY_IDENTITY_CHANGED' end
        ids[id]=item
    end
    return ids
end
function I.amount(item)
    if not instanceof(item,'Food') then return nil,'INGREDIENT_AMOUNT_NOT_ADAPTED' end
    local row,why=Food.read(item) if not row then return nil,why end
    if not row.safe or row.frozen then return nil,'INGREDIENT_UNSAFE' end
    return row.raw
end
function I.foodStamp(item)
    local row,why=Food.read(item) if not row then return nil,why end
    if not row.food then
        if not item.getFluidContainer then return nil,'FLUID_READ_UNAVAILABLE' end
        local fluid=item:getFluidContainer()
        if not fluid then return item:getFullType() end
        if not fluid.getAmount or not fluid.isFilledWithCleanWater or not fluid:isFilledWithCleanWater() then
            return nil,'CLEAN_WATER_REQUIRED'
        end
        return item:getFullType()..':'..tostring(fluid:getAmount())
    end
    if not row.safe or row.frozen then return nil,'INGREDIENT_UNSAFE' end
    local parts={row.fullType,tostring(row.raw),tostring(row.effective),tostring(row.cooked)}
    for _,method in ipairs({'getExtraItems','getSpices'}) do
        if not item[method] then return nil,'FOOD_COMPOSITION_UNAVAILABLE' end
        local list=item[method](item)
        if list and list:size()>32 then return nil,'FOOD_COMPOSITION_LIMIT' end
        parts[#parts+1]=method
        if list then for i=0,list:size()-1 do
            local value=list:get(i) if type(value)~='string' then return nil,'FOOD_COMPOSITION_UNKNOWN' end
            parts[#parts+1]=#value..':'..value
        end end
    end
    return table.concat(parts,'|')
end
-- Keep all old originals while UNKNOWN; only a later verified receipt may
-- consume/release an old one. No deletion/recreation and no type matching.
function I.retainOutputs(job,before,container)
    local after,why=I.snapshot(container) if not after then return nil,why end
    local j=Record.copy(job) local added={}
    for id,item in pairs(after) do
        if not before[id] and not I.asset(j,id) then
            if #j.payload.assets>=Record.limit then return nil,'COOKING_ASSET_LIMIT' end
            -- Neutral retained original until the recipe's returned reference
            -- proves which item is the meal; never credit incidental outputs.
            j.payload.assets[#j.payload.assets+1]={id=id,fullType=item:getFullType(),custody='HELD',role='TOOL'}
            j.payload.claims[#j.payload.claims+1]='item:'..id added[#added+1]=id
        end
    end
    return j,added
end
function I.release(job,id,custody)
    local a=I.asset(job,id) if not a then return false end
    a.custody=custody
    for i=#job.payload.claims,1,-1 do if job.payload.claims[i]=='item:'..id then table.remove(job.payload.claims,i) end end
    return true
end
return I
