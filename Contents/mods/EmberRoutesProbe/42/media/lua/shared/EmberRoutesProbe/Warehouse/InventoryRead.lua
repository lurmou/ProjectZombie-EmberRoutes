-- Immediate, bounded read only. Flat item/id/type triples avoid per-item tables.
-- Callers discard rows before yielding to next tick.
local M={LIMIT=32}
function M.slice(container,items,size,offset,limit)
    if EmberRoutesProbeJava and EmberRoutesProbeJava.inventoryReadSlice then
        local result=EmberRoutesProbeJava.inventoryReadSlice(container,items,size,offset,limit)
        if result.reason then return nil,result.reason end
        return result.rows
    end
    -- Lua host adapters retain the same contract without a Java extension.
    if container:getItems()~=items or items:size()~=size then return nil,'INVENTORY_CHANGED' end
    if size>2000 or offset<0 or offset>size or limit<1 or limit>M.LIMIT then return nil,'SCAN_RANGE_INVALID' end
    local rows={}
    for i=offset,math.min(size,offset+limit)-1 do
        local item=items:get(i)
        if not item or item:getContainer()~=container then return nil,'ITEM_LOCATION_CHANGED' end
        rows[#rows+1]=item rows[#rows+1]=item:getID() rows[#rows+1]=item:getFullType()
    end
    if container:getItems()~=items or items:size()~=size then return nil,'INVENTORY_CHANGED' end
    return rows
end
return M
