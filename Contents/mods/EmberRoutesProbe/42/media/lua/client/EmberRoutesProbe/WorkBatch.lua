-- Load a route-sized batch before travelling; all decisions use original IDs.
local View=require "EmberRoutesProbe/InventoryView"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Claims=require "EmberRoutesProbe/LaborStore"
local Producers=require "EmberRoutesProbe/LaborProducers"
local Batch={}
function Batch.choose(context,index)
    local record=context.job local held,source,delivered,problem=nil,nil,0,nil
    for _,id in ipairs(record.items) do
        local item,where,reason=View.find(index,id)
        if not item then
            if reason~="ITEM_MISSING" then return nil,delivered,reason end
            problem=reason
        elseif where==3 then delivered=delivered+1
        elseif where==2 and not held then held={id=id,item=item,where=2}
        elseif where==1 and not source then source={id=id,item=item,where=1} end
    end
    if problem and not held then return nil,delivered,problem end
    if record.phase~="DELIVER" then record.phase="COLLECT" end
    if record.phase=="DELIVER" and held then return held,delivered end
    record.phase="COLLECT"
    local blocked
    if source then
        local item=source.item
        if not Producers.eligible(item) then blocked="ITEM_PROTECTED"
        elseif not Registry.accepts(context.destination,item) then blocked="FILTER_REJECTED"
        elseif not Producers.transfer(context,item,context.source.container,context.npc:getInventory()) then blocked="PRODUCER_RULE_CHANGED"
        elseif not context.npc:getInventory():hasRoomFor(context.npc,item) or Producers.freeCarry(context.npc)<item:getUnequippedWeight() then blocked="NPC_INVENTORY_FULL"
        elseif not context.destination.container:hasRoomFor(context.npc,item) then blocked="DESTINATION_FULL"
        elseif Claims.availableFor(context.token,record.destination,item:getID(),context.destination.container:getFreeCapacity(context.npc))<item:getUnequippedWeight() then blocked="CAPACITY_RESERVED"
        else return source,delivered end
    end
    if held then record.phase="DELIVER" return held,delivered end
    return nil,delivered,blocked or problem or "DONE"
end
return Batch
