-- Bounded detached fluid facts; no liquid mutation or replacement containers.
local F={limit=32}
local function finite(n) return type(n)=='number' and n==n and n>=0 and n<math.huge end
local function near(a,b) return math.abs(a-b)<=math.max(0.00001,0.000001*math.max(a,b)) end
function F.valid(s)
    if type(s)~='table' or not finite(s.amount) or not finite(s.capacity) or s.capacity<=0
        or s.amount>s.capacity+0.00001 or type(s.components)~='table' or #s.components>F.limit then return false end
    local count,total,previous=0,0,''
    for key in pairs(s.components) do
        if type(key)~='number' or key~=math.floor(key) or key<1 or key>#s.components then return false end
        count=count+1
    end
    if count~=#s.components then return false end
    for _,part in ipairs(s.components) do
        if type(part)~='table' or type(part.kind)~='string' or part.kind=='' or #part.kind>200
            or part.kind<=previous or not finite(part.amount) or part.amount<=0 then return false end
        previous=part.kind total=total+part.amount
    end
    return near(total,s.amount)
end
function F.read(container)
    if not container or not container.createFluidSample or not container.getAmount or not container.getCapacity then
        return nil,'FLUID_READ_UNAVAILABLE'
    end
    local sample=container:createFluidSample()
    if not sample or not sample.release then return nil,'FLUID_SAMPLE_UNAVAILABLE' end
    local result={amount=container:getAmount(),capacity=container:getCapacity(),components={}}
    if not sample.size or not sample.getFluid or not sample.getPercentage or sample:size()>F.limit then
        sample:release() return nil,'FLUID_SAMPLE_LIMIT'
    end
    for i=0,sample:size()-1 do
        local fluid=sample:getFluid(i) local ratio=sample:getPercentage(i)
        if not fluid or not fluid.getFluidTypeString or not finite(ratio) or ratio>1 then
            sample:release() return nil,'FLUID_SAMPLE_UNAVAILABLE'
        end
        -- FluidSample is Lua-exposed; FluidInstance is not in the pinned exposer.
        result.components[#result.components+1]={kind=fluid:getFluidTypeString(),amount=result.amount*ratio}
    end
    sample:release()
    table.sort(result.components,function(a,b) return tostring(a.kind)<tostring(b.kind) end)
    if not F.valid(result) then return nil,'FLUID_SAMPLE_INVALID' end
    return result
end
function F.equal(a,b)
    if not F.valid(a) or not F.valid(b) or not near(a.amount,b.amount) or not near(a.capacity,b.capacity)
        or #a.components~=#b.components then return false end
    for i,part in ipairs(a.components) do
        local other=b.components[i]
        if part.kind~=other.kind or not near(part.amount,other.amount) then return false end
    end
    return true
end
function F.pureWater(s)
    return F.valid(s) and (s.amount==0 and #s.components==0
        or #s.components==1 and s.components[1].kind=='Water') or false
end
-- Native purity predicate avoids pooled composition scans on every water update.
function F.water(container)
    if not container or not container.getAmount or not container.getCapacity or not container.isPureFluid
        or not Fluid or not Fluid.Water then return nil,'WATER_READ_UNAVAILABLE' end
    local amount,capacity=container:getAmount(),container:getCapacity()
    if not finite(amount) or not finite(capacity) or capacity<=0 or amount>capacity then return nil,'WATER_AMOUNT_UNKNOWN' end
    if amount>0 and not container:isPureFluid(Fluid.Water) then return nil,'PURE_WATER_REQUIRED' end
    return {amount=amount,capacity=capacity,components=amount>0 and {{kind='Water',amount=amount}} or {}}
end
function F.waterAdded(before,after,amount)
    return finite(amount) and F.pureWater(before) and F.pureWater(after) and near(before.capacity,after.capacity)
        and after.amount>=before.amount and near(after.amount-before.amount,amount) or false
end
-- The supported native removeFluid(amount) shape removes the mixture proportionally.
function F.consumed(before,after,amount)
    if not F.valid(before) or not F.valid(after) or not finite(amount) or amount<=0
        or before.amount<amount or not near(before.capacity,after.capacity)
        or not near(before.amount-after.amount,amount) then return false end
    if after.amount<=0.00001 then return #after.components==0 end
    if #before.components~=#after.components then return false end
    local ratio=after.amount/before.amount
    for i,part in ipairs(before.components) do
        if part.kind~=after.components[i].kind or not near(part.amount*ratio,after.components[i].amount) then return false end
    end
    return true
end
-- Both sides must retain the exact proportional mixture, including liquid
-- already in the target. Equal total volume alone is not transfer evidence.
function F.transferred(sourceBefore,sourceAfter,targetBefore,targetAfter,amount)
    if not finite(amount) or not F.valid(sourceBefore) or not F.valid(sourceAfter)
        or not F.valid(targetBefore) or not F.valid(targetAfter) then return false end
    if amount<=0.000001 then return near(amount,0) and F.equal(sourceBefore,sourceAfter) and F.equal(targetBefore,targetAfter) end
    if not F.consumed(sourceBefore,sourceAfter,amount) or not near(targetBefore.capacity,targetAfter.capacity)
        or not near(targetAfter.amount-targetBefore.amount,amount) then return false end
    local expected={}
    for _,part in ipairs(targetBefore.components) do expected[part.kind]=part.amount end
    for _,part in ipairs(sourceBefore.components) do
        expected[part.kind]=(expected[part.kind] or 0)+amount*part.amount/sourceBefore.amount
    end
    for _,part in ipairs(targetAfter.components) do
        if not expected[part.kind] or not near(expected[part.kind],part.amount) then return false end
        expected[part.kind]=nil
    end
    for _,remaining in pairs(expected) do if remaining>0.000001 then return false end end
    return true
end
return F
