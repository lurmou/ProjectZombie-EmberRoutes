local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Geometry=require "EmberRoutesProbe/SettlementGeometry"
local Membership={dirty=true}
local root,buckets,entries,invalidPosition
local function key(x,y) return math.floor(x/10)..":"..math.floor(y/10) end
local function rebuild(data)
    root,buckets,entries,invalidPosition=data,{},{},false
    for id,position in pairs(data.containers) do
        if type(position)=="table" and Geometry.rectangle(position.x,position.y,position.x,position.y) then
            local k=key(position.x,position.y)
            buckets[k]=buckets[k] or {}
            buckets[k][id]=position
            entries[#entries+1]=id
        else invalidPosition=true end
    end
    Membership.dirty=false
end
function Membership.query(settlement)
    local data=Registry.data()
    if root~=data or Membership.dirty then rebuild(data) end
    -- Without a usable position we cannot prove which settlement owns the
    -- record. Fail closed instead of presenting an apparently complete zero.
    if invalidPosition then return nil,"CONTAINER_RECORD_INVALID" end
    local seen,result={},{}
    local cells=0
    for _,r in ipairs(settlement.areas) do
        cells=cells+(math.floor((r.x+r.w-1)/10)-math.floor(r.x/10)+1)
            *(math.floor((r.y+r.h-1)/10)-math.floor(r.y/10)+1)
    end
    -- A wide, mostly empty territory is cheaper to test against our <=256
    -- registered locators than thousands of empty bucket keys. No world scan.
    if cells>#entries*#settlement.areas then
        for _,id in ipairs(entries) do
            local p=data.containers[id]
            if Geometry.inside(settlement,p.x,p.y) then result[#result+1]=id end
        end
        table.sort(result)
        return result
    end
    for _,r in ipairs(settlement.areas) do
        for x=math.floor(r.x/10),math.floor((r.x+r.w-1)/10) do
            for y=math.floor(r.y/10),math.floor((r.y+r.h-1)/10) do
                for id,p in pairs(buckets[x..":"..y] or {}) do
                    if not seen[id] and Geometry.contains(r,p.x,p.y) then seen[id]=true result[#result+1]=id end
                end
            end
        end
    end
    table.sort(result)
    return result
end
if Registry.listeners then
    Registry.listeners[#Registry.listeners+1]=function() Membership.dirty=true end
end
return Membership
