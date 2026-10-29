-- Spatial policy only. Never grants bodies, changes membership, or owns items.
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Zones={LIMIT=32,listeners={}}
local activities=require('EmberRoutesProbe/ActivityRegistry').behaviors()
local known={} for _,id in ipairs(activities) do known[id]=true end
local world,opened,byScope
local coverage={}
local function integer(n) return type(n)=='number' and n==n and n==math.floor(n) and math.abs(n)<=10000000 end
local function copy(row)
    local r={id=row.id,settlementId=row.settlementId,name=row.name,revision=row.revision,enabled=row.enabled,
        area={x=row.area.x,y=row.area.y,w=row.area.w,h=row.area.h,z=row.area.z},rules={}}
    for _,id in ipairs(activities) do r.rules[id]=row.rules[id] or 1 end
    return r
end
local function valid(row)
    if type(row)~='table' or type(row.id)~='string' or row.id=='' or type(row.settlementId)~='string'
        or type(row.name)~='string' or #row.name<1 or #row.name>64 or row.name:find('[%c]')
        or not integer(row.revision) or row.revision<1 or type(row.enabled)~='boolean'
        or not Geometry.valid(row.area) or not integer(row.area.z) or type(row.rules)~='table' then return false end
    for id,value in pairs(row.rules) do if not known[id] or value~=0 and value~=1 and value~=2 then return false end end
    return true
end
local function data()
    local root=Ledger.data()
    if root~=world or root.publicLifeZones~=opened then
        local saved=root.publicLifeZones or {format=1,revision=0,byId={}}
        if type(saved)~='table' or saved.format~=1 or not integer(saved.revision) or saved.revision<0
            or type(saved.byId)~='table' then return nil,'ZONE_FORMAT_UNSUPPORTED' end
        local index,count={},0
        for key,row in pairs(saved.byId) do
            count=count+1
            if count>1024 or not valid(row) or row.id~=key then return nil,'ZONE_DATA_INVALID' end
            local list=index[row.settlementId] or {} index[row.settlementId]=list
            if #list>=Zones.LIMIT then return nil,'ZONE_LIMIT' end
            list[#list+1]=row
        end
        world,opened,byScope=root,saved,index coverage={} root.publicLifeZones=saved
    end
    return opened
end
-- Prove inclusion in a UNION of parent rectangles, including interior gaps.
-- Sweep only rectangle Y edges, not every tile of a potentially large area.
function Zones.covered(entry,area)
    if not entry or not Geometry.valid(area) or not integer(area.z) then return false end
    local cuts={area.y,area.y+area.h}
    for _,r in ipairs(entry.areas or {}) do
        if r.y>area.y and r.y<area.y+area.h then cuts[#cuts+1]=r.y end
        local edge=r.y+r.h
        if edge>area.y and edge<area.y+area.h then cuts[#cuts+1]=edge end
    end
    table.sort(cuts)
    for i=1,#cuts-1 do
        if cuts[i]<cuts[i+1] then
            local spans={}
            for _,r in ipairs(entry.areas or {}) do
                if cuts[i]>=r.y and cuts[i]<r.y+r.h then spans[#spans+1]={r.x,r.x+r.w} end
            end
            table.sort(spans,function(a,b) return a[1]<b[1] end)
            local edge=area.x
            for _,span in ipairs(spans) do
                if span[1]>edge then break end
                if span[2]>edge then edge=span[2] end
                if edge>=area.x+area.w then break end
            end
            if edge<area.x+area.w then return false end
        end
    end
    return true
end
local function coveredRow(entry,row)
    local cache=coverage[row.id]
    if not cache or cache.zone~=row.revision or cache.parent~=entry.revision then
        cache={zone=row.revision,parent=entry.revision,valid=Zones.covered(entry,row.area)} coverage[row.id]=cache
    end
    return cache.valid
end
local function changed(saved,scope,id)
    saved.revision=saved.revision+1
    for _,listener in ipairs(Zones.listeners) do listener(scope,id,saved.revision) end
end
function Zones.activities()
    local result={} for i,id in ipairs(activities) do result[i]=id end return result
end
function Zones.revision()
    local saved,why=data() if not saved then return nil,why end
    return saved.revision
end
-- Scalar destination proof. No body, reservation or native-square claim.
function Zones.location(scope,ref,point)
    local saved,why=data() if not saved then return false,why end
    if type(ref)~='table' or type(point)~='table' then return false,'ZONE_MISSING' end
    for _,name in ipairs({'x','y','z'}) do
        local n=point[name]
        if type(n)~='number' or n~=n or math.abs(n)>10000000 then return false,'ZONE_DATA_INVALID' end
    end
    local row=saved.byId[ref.id]
    local entry=Ledger.data().entries[scope]
    if not row or not entry or row.settlementId~=scope or not row.enabled
        or row.revision~=ref.revision or point.z~=row.area.z
        or not Geometry.contains(row.area,point.x,point.y) then return false,'ZONE_CHANGED' end
    if not coveredRow(entry,row) then return false,'ZONE_OUTSIDE' end
    return true
end
function Zones.destination(scope,ref,point)
    local ok,why=Zones.location(scope,ref,point) if not ok then return false,why end
    -- The first transport profile needs a legal quiet standing spot on arrival.
    -- This does not imply seats, books, instruments or a social partner exist.
    local rule=Zones.policyAt(scope,point.x,point.y,point.z,'OBSERVE')
    return rule~=nil and rule>0,'ZONE_ACTIVITY_DISABLED'
end
function Zones.list(scope)
    local saved,why=data() if not saved then return nil,why end
    local result={} for _,row in ipairs(byScope[scope] or {}) do result[#result+1]=copy(row) end
    table.sort(result,function(a,b) return a.name==b.name and a.id<b.id or a.name<b.name end)
    return result
end
function Zones.get(id)
    local saved,why=data() if not saved then return nil,why end
    if saved.byId[id] then return copy(saved.byId[id]) end
    return nil,'ZONE_MISSING'
end
function Zones.save(actor,scope,id,expected,proposal)
    local entry,why=Ledger.view(actor,scope) if not entry then return nil,why end
    local saved,reason=data() if not saved then return nil,reason end
    local old=id and saved.byId[id]
    if id and (not old or old.settlementId~=scope) then return nil,'ZONE_MISSING' end
    if old and old.revision~=expected then return nil,'ZONE_CHANGED' end
    if type(proposal)~='table' then return nil,'ZONE_DATA_INVALID' end
    local name=type(proposal.name)=='string' and proposal.name:match('^%s*(.-)%s*$')
    local row={id=old and old.id or Registry.id(),settlementId=scope,name=name,
        revision=old and old.revision+1 or 1,enabled=proposal.enabled,area=proposal.area,rules=proposal.rules}
    if saved.byId[row.id] and not old then return nil,'ZONE_ID_CONFLICT' end
    if not valid(row) then return nil,'ZONE_DATA_INVALID' end
    if not Zones.covered(entry,row.area) then return nil,'ZONE_OUTSIDE' end
    local list=byScope[scope] or {}
    if not old and #list>=Zones.LIMIT then return nil,'ZONE_LIMIT' end
    local total=0 for _ in pairs(saved.byId) do total=total+1 end
    if not old and total>=1024 then return nil,'ZONE_LIMIT' end
    row=copy(row) saved.byId[row.id]=row
    if old then for i,r in ipairs(list) do if r.id==old.id then list[i]=row break end end
    else list[#list+1]=row byScope[scope]=list end
    changed(saved,scope,row.id)
    return copy(row)
end
function Zones.remove(actor,scope,id,expected)
    local entry,why=Ledger.view(actor,scope) if not entry then return false,why end
    local saved,reason=data() if not saved then return false,reason end
    local row=saved.byId[id]
    if not row or row.settlementId~=scope then return false,'ZONE_MISSING' end
    if row.revision~=expected then return false,'ZONE_CHANGED' end
    saved.byId[id]=nil coverage[id]=nil
    local list=byScope[scope] or {}
    for i,r in ipairs(list) do if r.id==id then table.remove(list,i) break end end
    changed(saved,scope,id) return true
end
function Zones.policyAt(scope,x,y,z,activity)
    if not known[activity] then return nil,'ZONE_ACTIVITY_UNKNOWN' end
    local saved,why=data() if not saved then return nil,why end
    local entry=Ledger.data().entries[scope]
    if not entry then return nil,'SETTLEMENT_MISSING' end
    local value=1
    for _,row in ipairs(byScope[scope] or {}) do
        local area=row.area
        if row.enabled and z==area.z and Geometry.contains(area,x,y) and coveredRow(entry,row) then
            local rule=row.rules[activity] or 1
            if rule==0 then return 0 end
            if rule==2 then value=2 end
        end
    end
    return value
end
return Zones
