-- Bounded read-only discovery for old jobs without display metadata.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local M={} local world,cache
function M.types(record,npc,budget)
    local root=Registry.data()
    if world~=root then world=root cache={} end
    local c=cache[record.id]
    if not c then c={types={},container=1,position=0} cache[record.id]=c end
    for k,v in pairs(record.itemTypes or {}) do c.types[k]=v end
    local complete=true
    for _,id in ipairs(record.items or {}) do if not c.types[tostring(id)] then complete=false break end end
    if complete or not Registry.resolve then return c.types end
    local containers={}
    for _,id in ipairs({record.source,record.destination}) do
        local endpoint=Registry.resolve(id,'take','local-world')
        if endpoint then containers[#containers+1]=endpoint.container end
    end
    if npc and npc.getInventory then containers[#containers+1]=npc:getInventory() end
    if c.container>#containers then
        if getTimestampMs()<(c.retryAt or 0) then return c.types end
        c.container,c.position=1,0 c.retryAt=getTimestampMs()+5000
    end
    local wanted={} for _,id in ipairs(record.items or {}) do wanted[id]=true end
    while budget.remaining>0 and c.container<=#containers do
        local items=containers[c.container]:getItems()
        if c.position>=math.min(items:size(),2000) then c.container=c.container+1 c.position=0
        else
            local item=items:get(c.position) c.position=c.position+1 budget.remaining=budget.remaining-1
            if wanted[item:getID()] then c.types[tostring(item:getID())]=item:getFullType() end
        end
    end
    return c.types
end
return M
