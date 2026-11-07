-- Allocate indivisible native outputs across ranked targets before delivery.
-- CraftSupply still owns priority, access, filters and physical capacity checks.
local Supply=require 'EmberRoutesProbe/Crafting/CraftSupply'
local Allocation=require 'EmberRoutesProbe/Crafting/ProductionAllocation'
local R={}
function R.new(c)
    local r=c.record
    local reserved,weights={},{}
    for _,asset in ipairs(r.outputs) do
        local location=c.plan.locations[asset.id]
        if location and location.item then weights[asset.id]=location.item:getUnequippedWeight() end
        local row=Allocation.row(r,asset)
        if row.allocated==1 and row.transferred==0 then
            local id=row.targets[1].destinationId
            reserved[id]=(reserved[id] or 0)+(weights[asset.id] or 0)
        end
    end
    local p={position=1}
    function p:step(budget)
        for _=1,budget do
            local asset=r.outputs[self.position]
            if not asset then return true end
            local row=Allocation.row(r,asset)
            if row.allocated==1 then self.position=self.position+1
            else
                local location=c.plan.locations[asset.id]
                if not location or not location.item then return nil,'ITEM_MISSING' end
                local item=location.item
                if not self.route then
                    self.route=Supply.route(c.plan,item,function(target)
                        return target.container:getFreeCapacity(c.npc)-(reserved[target.id] or 0)>=item:getUnequippedWeight()
                    end)
                end
                local target,done=self.route:step(1)
                if done then
                    self.route=nil self.position=self.position+1
                    if target then
                        Allocation.assign(row,target.id) asset.destination=target.id
                        reserved[target.id]=(reserved[target.id] or 0)+item:getUnequippedWeight()
                    end
                    -- Unallocated originals remain visible and owned, never discarded.
                end
            end
        end
        return false
    end
    return p
end
return R
