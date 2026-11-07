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
-- CraftRecipeData.processUsedItems also consumes ordinary single-use inputs;
-- mode:destroy is not the default mode of logs/branches. Partial uses, retained
-- vessels and unknown metadata receive no speculative weight credit.
function Carry.consumed(item,input)
    if not input or input.keep then return 0 end
    local io=input.io
    if io.isDestroy and io:isDestroy() then return item:getUnequippedWeight() end
    if not item.getScriptItem or not item.getCurrentUses or not item.getReplaceOnUse
        or not io.isUsesPartialItem or not io.hasConsumeFromItem or not io.hasCreateToItem then return 0 end
    local script=item:getScriptItem()
    if not script or not script.getReplaceOnDeplete or item:getReplaceOnUse() or script:getReplaceOnDeplete()
        or io:hasConsumeFromItem() or io:hasCreateToItem() or io:isUsesPartialItem(script) then return 0 end
    local counted=io.isItemCount and io:isItemCount()
    if not counted and (item:getCurrentUses()~=1 or not item.getFluidContainer or item:getFluidContainer()) then return 0 end
    return item:getUnequippedWeight()
end
-- Read-only exact first-batch plan, shared by public discovery and execution.
function Carry.plan(npc,spec,plan)
    local bySlot={} for _,input in ipairs(spec.inputs) do bySlot[input.slot]=input end
    local added,consumed=0,0
    local selected={}
    for _,name in ipairs({'materials','tools'}) do
        for _,asset in ipairs(plan[name] or {}) do
            local input=bySlot[asset.slot]
            if not input then return false end
            -- Discovery matches the entire order, but execution carries one
            -- batch at a time. Do not sum materials for all future batches.
            if (selected[asset.slot] or 0)<input.count then
                selected[asset.slot]=(selected[asset.slot] or 0)+1
                local location=plan.locations[asset.id]
                if not location or not location.item then return false end
                local item=location.item
                if item:getContainer()~=npc:getInventory() then added=added+item:getUnequippedWeight() end
                consumed=consumed+Carry.consumed(item,input)
            end
        end
    end
    return Carry.fits(npc,added,consumed,spec.outputWeight)
end
return Carry
