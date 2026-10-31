-- Read-only bounded observations. Never moves, equips, creates loot or changes ecology.
local Spatial=require 'EmberRoutesProbe/FieldSpatial'
local Policy=require 'EmberRoutesProbe/JobPolicyService'
local Store=require 'EmberRoutesProbe/LaborStore'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local D={}
local world,caches,watches=nil,{},{}
local function reset()
    local root=Registry.data()
    if world~=root then
        for _,row in pairs(watches) do if row.release then row.release() end end
        world,caches,watches=root,{},{}
    end
end
local function cache(env,category)
    reset() local key=env.entry.id..':'..category local row=caches[key]
    local stamp=tostring(env.entry.revision)..':'..tostring(require('EmberRoutesProbe/SettlementZones').revision())
    if not row or row.stamp~=stamp then row={stamp=stamp,targets={},index=0,nextAt=0} caches[key]=row end
    return row
end
local function add(row,t)
    local key=t.kind..':'..t.x..':'..t.y..':'..t.z..':'..tostring(t.itemId or t.identity or '')
    for i,v in ipairs(row.targets) do if v.key==key then table.remove(row.targets,i) break end end
    t.key=key row.targets[#row.targets+1]=t
    if #row.targets>64 then table.remove(row.targets,1) end
end
function D.plant(t)
    local system=CFarmingSystem and CFarmingSystem.instance
    return system and system:getLuaObjectAt(t.x,t.y,t.z)
end
function D.object(t)
    local sq=Spatial.square(t) if not sq then return nil end
    if t.kind=='TREE' then return sq:getTree() end
    if t.kind=='WATER' or t.kind=='HARVEST' or t.kind=='CLEAR' then
        local p=D.plant(t) return p and p:getObject()
    end
    if t.kind=='CORPSE' then
        local list=sq:getDeadBodys()
        for i=0,list:size()-1 do local b=list:get(i)
            if t.identity and Spatial.identity(b)==t.identity
                or not t.identity and b:getItem() and b:getItem():getID()==t.itemId then return b end
        end
    end
    if t.kind=='STAIN' then
        return (not EmberRoutesProbeJava or not EmberRoutesProbeJava.cleaningSquareHasStains or EmberRoutesProbeJava.cleaningSquareHasStains(sq)) and sq or nil
    end
end
function D.policy(category,scope) return Policy.get(scope,category) end
function D.waterGoal(plant)
    local props=farming_vegetableconf and farming_vegetableconf.props and farming_vegetableconf.props[plant.typeOfSeed] or {}
    local minimum=tonumber(props.waterLvl) or 50
    local goal=math.max(minimum,tonumber(props.waterNeeded) or minimum)
    return math.min(100,goal,tonumber(props.waterLvlMax) or 100),minimum,tonumber(props.waterLvlMax) or 100
end
function D.allowed(category,entry,t,npc)
    local p=Policy.get(entry.id,category)
    local zone=category=='lumberjack' and p.lumberZoneId or category=='forager' and p.searchRange=='assigned_zone' and p.forageZoneId or nil
    if category=='forager' and p.searchRange=='assigned_zone' and (not zone or zone=='') then return false end
    if category=='forager' and p.searchRange=='surrounding' then
        -- Existing surrounding choice means a 20-tile margin around the territory union.
        local near=false
        for _,r in ipairs(entry.areas) do
            local dx=math.max(r.x-t.x,0,t.x-(r.x+r.w-1)) local dy=math.max(r.y-t.y,0,t.y-(r.y+r.h-1))
            if dx*dx+dy*dy<=400 then near=true break end
        end
        if not near then return false end
    elseif not Spatial.inside(entry,zone,t.x,t.y,t.z) then return false end
    if category=='cleaning' then
        if t.kind~='STAIN' and p.cleanBloodOnly then return false end
        local radius=p.cleanRadius or 20
        if (npc:getX()-t.x)^2+(npc:getY()-t.y)^2>radius*radius then return false end
    end
    return true
end
function D.stock(scope,category)
    reset()
    local row=watches[scope]
    if not row then
        row={} watches[scope]=row
        row.release=require('EmberRoutesProbe/WarehouseIndex').watch(scope,function(s) row.snapshot=s end)
    end
    local s=row.snapshot
    if not s or s.state~='READY' or not s.counts or (s.counts.unloaded or 0)>0 or (s.counts.limited or 0)>0 then return nil end
    local count=0
    for _,r in ipairs(s.rows or {}) do
        if category=='LOGS' then if r.fullType=='Base.Log' then count=count+r.count end
        else
            local def=_G.forageSystem and _G.forageSystem.itemDefs[r.fullType]
            for _,cat in ipairs(def and def.categories or {}) do if cat==category then count=count+r.count break end end
        end
    end
    return count
end
function D.logs(scope) return D.stock(scope,'LOGS') end
local function scanNative(env,category,row)
    local p=Policy.get(env.entry.id,category)
    local chunk=Spatial.chunk(env.entry,category=='lumberjack' and p.lumberZoneId or nil,category,env.now)
    if not chunk then return end
    local bridge=EmberRoutesProbeJava
    if category=='lumberjack' then
        if not bridge.lumberjackScanTrees then return end
        for _,pt in ipairs(bridge.lumberjackScanTrees(chunk,16) or {}) do
            add(row,{kind='TREE',x=pt.x,y=pt.y,z=pt.z})
        end
    else
        if bridge.cleaningScanStains then for _,pt in ipairs(bridge.cleaningScanStains(chunk,16) or {}) do
            add(row,{kind='STAIN',x=pt.x,y=pt.y,z=pt.z})
        end end
        if not p.cleanBloodOnly and bridge.cleaningScanCorpses then
            for _,pt in ipairs(bridge.cleaningScanCorpses(chunk,8) or {}) do
                if pt.body and pt.body:getItem() and pt.body:getItem():getFullType()~='Base.CorpseAnimal' then
                    add(row,{kind='CORPSE',x=pt.x,y=pt.y,z=pt.z,itemId=pt.body:getItem():getID()})
                end
            end
        end
    end
end
local function scanPlants(env,row)
    local system=CFarmingSystem and CFarmingSystem.instance if not system then return end
    local count=system:getLuaObjectCount() if count<1 then return end
    for _=1,math.min(32,count) do
        row.index=row.index%count+1
        local p=system:getLuaObjectByIndex(row.index)
        if p and p.x and p.y then
            if p.updateFromIsoObject then p:updateFromIsoObject() end
            local t={x=p.x,y=p.y,z=p.z or 0}
            if p.state=='rotten' or p.isAlive and not p:isAlive() and p.state~='plow' then t.kind='CLEAR'
            elseif p.canHarvest and p:canHarvest() then t.kind='HARVEST'
            elseif p.typeOfSeed and p.typeOfSeed~='none' then
                local _,minimum=D.waterGoal(p)
                if (p.waterLvl or 0)<minimum then t.kind='WATER' end
            end
            if t.kind then add(row,t) end
        end
    end
end
function D.rotten(env,row)
    local p=Policy.get(env.entry.id,'cleaning')
    if p.haulRottenFood~=true or p.cleanBloodOnly then return end
    local ids=require('EmberRoutesProbe/SettlementMembership').query(env.entry) or {}
    if #ids==0 then return end
    row.containerIndex=(row.containerIndex or 0)%#ids+1
    local ep=require('EmberRoutesProbe/CraftSupply').endpoint(env.entry,ids[row.containerIndex],'take')
    if not ep or Registry.logistics(ep)~='STORAGE' then return end
    local list=ep.container:getItems() local sq=ep.object:getSquare()
    -- Never pick up items already accepted here: that would loop between waste bins.
    row.itemIndex=(row.itemIndex or 0)%math.max(1,list:size())
    for _=1,math.min(32,list:size()) do
        local item=list:get(row.itemIndex) row.itemIndex=(row.itemIndex+1)%list:size()
        if instanceof(item,'Food') and item:isRotten() and not Store.owner(item:getID())
            and not Registry.accepts(ep,item) and require('EmberRoutesProbe/LaborProducers').eligible(item) then
            add(row,{kind='ROTTEN',x=sq:getX(),y=sq:getY(),z=sq:getZ(),itemId=item:getID(),sourceId=ep.id})
        end
    end
end
local function forage(env,row)
    local fs=_G.forageSystem
    if not fs or not fs.getForageZoneAt then return end
    local zone=fs.getForageZoneAt(env.npc:getX(),env.npc:getY()) if not zone then return end
    local p=Policy.get(env.entry.id,'forager')
    row.targets={}
    local empty=true for _ in pairs(zone.forageIcons or {}) do empty=false break end
    if empty and p.autoRefillZone and (zone.itemsLeft or 0)>0 then
        add(row,{kind='FORAGE_REFRESH',x=math.floor(env.npc:getX()),y=math.floor(env.npc:getY()),
            z=math.floor(env.npc:getZ()),identity='zone:'..tostring(zone.id)})
        return
    end
    local radius=math.min(16,8+math.floor(env.npc:getPerkLevel(Perks.PlantScavenging)*0.8))
    local n=0
    for id,icon in pairs(zone.forageIcons or {}) do
        n=n+1 if n>256 then break end
        local focus=p.searchFocus or 'balanced' local cat=icon.catName
        local matches=focus=='balanced' or focus=='medicinal' and cat=='MedicinalPlants'
            or focus=='food' and (cat=='Berries' or cat=='Mushrooms' or cat=='WildPlants')
            or focus=='materials' and (cat=='Stones' or cat=='ForestGoods') or focus=='insects' and cat=='Insects'
        local cap=cat=='Stones' and p.maxStones or cat=='MedicinalPlants' and p.maxHerbs
        if cap and cap>0 then local count=D.stock(env.entry.id,cat) if not count or count>=cap then matches=false end end
        if matches and (icon.x-env.npc:getX())^2+(icon.y-env.npc:getY())^2<=radius*radius then
            local t={kind='FORAGE',x=icon.x,y=icon.y,z=icon.z or 0,identity=tostring(id),iconId=id}
            local sq=Spatial.square(t) local floor=sq and sq:getFloor()
            if floor and env.npc:CanSee(floor) then add(row,t) end
        end
    end
end
function D.targets(env,category)
    local row=cache(env,category)
    if env.now>=row.nextAt then
        row.nextAt=env.now+500
        if category=='cleaning' or category=='lumberjack' then scanNative(env,category,row)
        elseif category=='farming' then scanPlants(env,row) else forage(env,row) end
        if category=='cleaning' then D.rotten(env,row) end
    end
    return row.targets
end
function D.claim(target,npc,entry,category)
    if not D.allowed(category,entry,target,npc) then return nil,nil,'FIELD_RANGE_CHANGED' end
    local t={} for k,v in pairs(target) do if k~='key' then t[k]=v end end
    local keys={}
    if t.kind=='STAIN' then
        local sq=Spatial.square(t)
        if not sq or not EmberRoutesProbeJava.cleaningSquareHasStains(sq) then return nil end
        t.identity=t.kind..':'..t.x..':'..t.y..':'..t.z
    elseif t.kind=='FORAGE' or t.kind=='FORAGE_REFRESH' then
        local zone=_G.forageSystem.getForageZoneAt(t.x,t.y)
        if not zone or t.kind=='FORAGE' and not zone.forageIcons[t.iconId] then return nil end
    elseif t.kind=='ROTTEN' then t.identity=tostring(t.itemId)
    else
        local o=D.object(t) if not o then return nil end
        t.identity=Spatial.identity(o,true)
        if not t.identity then return nil end
    end
    keys[1]='field-target:'..t.kind..':'..t.identity
    return t,keys
end
return D
