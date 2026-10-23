-- Production permits only the first two vanilla HeavyLoad levels.
-- Use the same effective root weight as Moodle.update, including worn bag reduction.
local Carry={}
local function valid(n) return type(n)=="number" and n==n and n>=0 and n<math.huge end
function Carry.fits(npc,added,consumed,output)
    added,consumed,output=added or 0,consumed or 0,output or 0
    local root=npc:getInventory()
    local maximum,weight,capacity=npc:getMaxWeight(),root:getCapacityWeight(),root:getEffectiveCapacity(npc)
    local facts={maximum=maximum,weight=weight,capacity=capacity,added=added,consumed=consumed,output=output}
    if not valid(maximum) or maximum==0 or not valid(weight) or not valid(capacity)
        or not valid(added) or not valid(consumed) or not valid(output) then return false,facts end
    local before=weight+added
    if consumed>before then return false,facts end
    local peak=math.max(before,before-consumed+output)
    facts.peak=peak facts.limit=math.min(capacity,maximum*1.5-0.01)
    return peak<=facts.limit,facts
end
-- Only whole Destroy inputs are removed before native outputs are handed back.
function Carry.consumed(item,input)
    if input and not input.keep and input.io.isDestroy and input.io:isDestroy() then
        return item:getUnequippedWeight()
    end
    return 0
end
return Carry
