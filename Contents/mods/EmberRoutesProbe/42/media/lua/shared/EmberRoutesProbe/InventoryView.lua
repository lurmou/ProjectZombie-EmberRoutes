-- Ephemeral read-only index. Never persists userdata or acts as an asset ledger.
local View = {}
function View.scan(containers)
    local scan={containers=containers,lists={},sizes={},index={},location=1,position=0}
    for i,container in ipairs(containers) do
        scan.lists[i]=container:getItems() scan.sizes[i]=scan.lists[i]:size()
    end
    function scan:step(budget)
        for i,container in ipairs(self.containers) do
            if self.sizes[i]>2000 then return nil,"INVENTORY_SCAN_LIMIT" end
            if container:getItems()~=self.lists[i] or self.lists[i]:size()~=self.sizes[i] then return nil,"INVENTORY_CHANGED" end
        end
        local reads=0
        while self.location<=#self.containers do
            local location=self.location
            if self.position>=self.sizes[location] then self.location=location+1 self.position=0
            else
                if reads>=budget then return nil,"SCAN_PENDING" end
                local item=self.lists[location]:get(self.position) local id=item:getID()
                local entry=self.index[id]
                if entry then entry.count=entry.count+1
                else self.index[id]={item=item,container=self.containers[location],location=location,count=1} end
                reads=reads+1 self.position=self.position+1
            end
        end
        return self.index
    end
    return scan
end
function View.index(containers)
    local result = {}
    for location, container in ipairs(containers) do
        local items = container:getItems()
        if items:size() > 2000 then return nil, "INVENTORY_SCAN_LIMIT" end
        for i = 0, items:size()-1 do
            local item = items:get(i)
            local id = item:getID()
            local entry = result[id]
            if entry then entry.count = entry.count+1
            else result[id] = { item=item, container=container, location=location, count=1 } end
        end
    end
    return result
end
function View.find(index, id)
    local entry = index[id]
    if not entry then return nil, nil, "ITEM_MISSING" end
    if entry.count ~= 1 then return nil, nil, "ITEM_ID_DUPLICATED" end
    if entry.item:getContainer() ~= entry.container then return nil, nil, "ITEM_CONTAINER_MISMATCH" end
    return entry.item, entry.location
end
return View
