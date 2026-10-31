-- Bounded union traversal shared by field providers. Holes are filtered at use.
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Zones=require 'EmberRoutesProbe/SettlementZones'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local S={}
local world,scans,window,spent=nil,{},0,0
function S.area(entry,zoneId)
    if zoneId and zoneId~='' then
        local z=Zones.get(zoneId)
        if not z or z.settlementId~=entry.id or z.enabled==false then return nil end
        return z
    end
    return entry
end
function S.inside(entry,zoneId,x,y,z)
    local area=S.area(entry,zoneId) if not area then return false end
    if area==entry then return Geometry.inside(entry,x,y) end
    return Zones.contains(area,x,y,z)
end
function S.chunk(entry,zoneId,category,now)
    local root=Ledger.data()
    if root~=world then world,scans,window,spent=root,{},0,0 end
    if now-window>=1000 then window,spent=now,0 end
    if spent>=8 then return nil end
    local area=S.area(entry,zoneId) if not area then return nil end
    local key=entry.id..':'..category
    local stamp=tostring(entry.revision)..':'..tostring(zoneId)..':'..tostring(area.revision)
    local c=scans[key]
    if not c or c.stamp~=stamp then c={stamp=stamp,index=1,seen={},nextAt=0} scans[key]=c end
    if now<c.nextAt then return nil end
    c.nextAt=now+250
    local areas=area.areas or {}
    -- Duplicate chunks at rectangle boundaries consume traversal budget, never scan twice per cycle.
    for _=1,8 do
        local r=areas[c.index]
        if not r then c.index=1 c.x=nil c.y=nil c.seen={} return nil end
        local minX,maxX=math.floor(r.x/10),math.floor((r.x+r.w-1)/10)
        local minY,maxY=math.floor(r.y/10),math.floor((r.y+r.h-1)/10)
        local x,y=c.x or minX,c.y or minY
        c.x=x+1 c.y=y
        if c.x>maxX then c.x=minX c.y=y+1 end
        if c.y>maxY then c.index=c.index+1 c.x=nil c.y=nil end
        local ck=x..':'..y
        if not c.seen[ck] then
            c.seen[ck]=true
            local cell=getCell()
            local chunk=cell and cell:getChunk(x,y)
            if chunk then
                spent=spent+1
                return chunk
            end
        end
    end
end
function S.square(t)
    local cell=getCell() return cell and cell:getGridSquare(t.x,t.y,t.z)
end
-- Objects are marked only during claim, never while evaluating a candidate.
function S.identity(object,create)
    if not object or not object.getModData then return nil end
    local data=object:getModData()
    if not data.EmberRoutesFieldId and create then data.EmberRoutesFieldId=require('EmberRoutesProbe/ContainerRegistry').id() end
    return data.EmberRoutesFieldId
end
function S.reachable(npc,square)
    local own=npc:getCurrentSquare()
    return own and square and own:getZ()==square:getZ() and math.abs(own:getX()-square:getX())<=1
        and math.abs(own:getY()-square:getY())<=1 and own:canReachTo(square) or false
end
function S.walkway(square)
    local system=CFarmingSystem and CFarmingSystem.instance
    return square and (not system or not system:getLuaObjectOnSquare(square)) or false
end
function S.adjacent(npc,square,avoidPlants)
    if S.reachable(npc,square) and (not avoidPlants or S.walkway(npc:getCurrentSquare())) then return npc:getCurrentSquare() end
    local excluded={}
    for _=1,8 do
        local sq=AdjacentFreeTileFinder.Find(square,npc,excluded)
        if not sq then return nil end
        excluded[#excluded+1]=sq
        if sq:getZ()==square:getZ() and sq:TreatAsSolidFloor() and not sq:isSolid() and not sq:isSolidTrans()
            and sq:canReachTo(square) and (not avoidPlants or S.walkway(sq)) then return sq end
    end
end
return S
