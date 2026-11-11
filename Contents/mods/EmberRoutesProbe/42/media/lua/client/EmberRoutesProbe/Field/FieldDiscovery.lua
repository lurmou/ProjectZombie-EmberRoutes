-- Read-only bounded observations. Never moves, equips, creates loot or changes ecology.
local Spatial=require 'EmberRoutesProbe/Field/FieldSpatial'
local Policy=require 'EmberRoutesProbe/Work/JobPolicyService'
local Zones=require 'EmberRoutesProbe/Settlement/SettlementZones'
local Store=require 'EmberRoutesProbe/Work/LaborStore'
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local ToolReq=require 'EmberRoutesProbe/Field/ToolRequirements'
local ToolDiscovery=require 'EmberRoutesProbe/Field/ToolDiscovery'
local RuntimeMetrics=require 'EmberRoutesProbe/Kernel/RuntimeMetrics'
local Index=require 'EmberRoutesProbe/Warehouse/WarehouseIndex'
local Signals=require 'EmberRoutesProbe/Work/LaborSignals'
local D={}
local world,caches,watches=nil,{},{}
-- RUNTIME_PERF spans are armed only while a sampling session is active; the
-- steady path pays a single boolean check per discovery pass.
local function tick() return RuntimeMetrics.active() and RuntimeMetrics.now() or nil end
local function span(name,started) if started then RuntimeMetrics.measureSpan(name,started) end end
local function reset()
    local root=Registry.data()
    if world~=root then
        for _,row in pairs(watches) do if row.release then row.release() end end
        world,caches,watches=root,{},{}
    end
end
-- Policy and zone snapshots are rebuilt only when their store revision changes.
-- Cached values are still detached clones from the service, never live persisted
-- tables; every caller here only reads them. Declared before cache() because the
-- farm-zone switch has to invalidate rows at cache time.
local policyRev,zoneRev=-1,-1
local policyCache,zoneCache={},{}
local function policyOf(scope,category)
    local pr=Policy.revision and Policy.revision() or -1
    if pr~=policyRev then policyRev=pr policyCache={} end
    local key=scope..':'..category
    local row=policyCache[key]
    if not row then row=Policy.get(scope,category) or {} policyCache[key]=row end
    return row
end
local function zoneOf(scope,zoneId)
    local zr=Zones.revision() or -1
    if zr~=zoneRev then zoneRev=zr zoneCache={} end
    local key=scope..':'..tostring(zoneId)
    local row=zoneCache[key]
    if row==nil then
        row=Zones.get(zoneId) or false
        zoneCache[key]=row
    end
    return row or nil
end
local function cache(env,category)
    reset() local key=env.entry.id..':'..category local row=caches[key]
    local stamp=tostring(env.entry.revision)..':'..tostring(Zones.revision())
    -- Switching the farm zone or corpse zone must drop rows collected under the previous one.
    if category=='farming' then
        local policy=policyOf(env.entry.id,'farming')
        stamp=stamp..':'..tostring(policy and policy.farmZoneId or '')
    elseif category=='cleaning' then
        local policy=policyOf(env.entry.id,'cleaning')
        stamp=stamp..':'..tostring(policy and policy.corpseZoneId or '')
    end
    if not row or row.stamp~=stamp then row={stamp=stamp,targets={},byKey={},index=0,nextAt=0} caches[key]=row end
    return row
end
-- Hash-backed de-duplication: the old linear scan plus table.remove made a
-- full discovery round O(N^2) over the 64-row cap.
local function add(row,t)
    local key=t.kind..':'..t.x..':'..t.y..':'..t.z..':'..tostring(t.itemId or t.identity or '')
    local byKey=row.byKey
    if not byKey then byKey={} row.byKey=byKey end
    local old=byKey[key]
    if old then
        for k,v in pairs(t) do old[k]=v end
        old.key=key
        return
    end
    t.key=key
    local targets=row.targets
    targets[#targets+1]=t
    byKey[key]=t
    if #targets>64 then
        local dropped=table.remove(targets,1)
        byKey[dropped.key]=nil
    end
end
local function clearTargets(row) row.targets={} row.byKey={} end
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
function D.invalidate(scope,category)
    if not scope then
        for _,row in pairs(caches) do
            row.plantsNextAt=0
            row.rottenNextAt=0
            row.nextAt=0
        end
        return
    end
    local key=tostring(scope)..':'..(category or 'farming')
    local row=caches[key]
    if row then
        row.plantsNextAt=0
        row.rottenNextAt=0
        row.nextAt=0
    end
end
if Signals and Signals.watch then
    Signals.watch(function() D.invalidate() end)
end
function D.policy(category,scope) return policyOf(scope,category) end
function D.waterGoal(plant)
    local props=farming_vegetableconf and farming_vegetableconf.props and farming_vegetableconf.props[plant.typeOfSeed] or {}
    local minimum=tonumber(props.waterLvl) or 50
    local goal=math.max(minimum,tonumber(props.waterNeeded) or minimum)
    return math.min(100,goal,tonumber(props.waterLvlMax) or 100),minimum,tonumber(props.waterLvlMax) or 100
end
-- Farming work exists only inside an assigned farm zone. Unlike lumber/forage
-- there is no "unset means whole territory" fallback: no zone, no targets.
function D.farmZone(entry)
    if not entry then return nil end
    local p=policyOf(entry.id,'farming')
    local id=p and p.farmZoneId
    if type(id)~='string' or id=='' then return nil end
    local zone=zoneOf(entry.id,id)
    if not zone or zone.settlementId~=entry.id or zone.enabled==false then return nil end
    if not zone.areas and zone.area then zone.areas={zone.area} end
    if not zone.areas or #zone.areas==0 then return nil end
    return zone
end
function D.allowed(category,entry,t,npc)
    local p=policyOf(entry.id,category)
    if category=='farming' then
        -- No assigned farm zone means no farming work, and the check is a plain
        -- containment test rather than a second zone lookup through the union path.
        local id=p.farmZoneId
        if type(id)~='string' or id=='' then return false end
        local zone=D.farmZone(entry)
        if not zone then return false end
        return Zones.contains(zone,t.x,t.y,t.z)
    end
    local zone=category=='lumberjack' and p.lumberZoneId
        or category=='forager' and p.searchRange=='assigned_zone' and p.forageZoneId or nil
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
        if t.kind=='CORPSE' then
            local corpseZone=p.corpseZoneId and p.corpseZoneId~='' and zoneOf(entry.id,p.corpseZoneId)
            if corpseZone and corpseZone.settlementId==entry.id and corpseZone.enabled~=false and Zones.contains(corpseZone,t.x,t.y,t.z) then
                return false
            end
        end
        local radius=p.cleanRadius or 20
        if npc and (npc:getX()-t.x)^2+(npc:getY()-t.y)^2>radius*radius then return false end
    end
    return true
end
function D.stock(scope,category)
    reset()
    local row=watches[scope]
    if not row then
        row={} watches[scope]=row
        row.release=require('EmberRoutesProbe/Warehouse/WarehouseIndex').watch(scope,function(s) row.snapshot=s end)
    end
    local s=row.snapshot
    if not s or s.state~='READY' or not s.counts or (s.counts.unloaded or 0)>0 or (s.counts.limited or 0)>0 then return nil end
    -- Logs are a single fullType: ask the incremental Java aggregate instead of
    -- walking every published row.
    if category=='LOGS' and EmberRoutesProbeJava and EmberRoutesProbeJava.warehouseTypeCount then
        return Index.typeCount(scope,'Base.Log')
    end
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
    local p=policyOf(env.entry.id,category)
    local bridge=EmberRoutesProbeJava
    if category=='lumberjack' then
        local chunk=Spatial.chunk(env.entry,p.lumberZoneId,category,env.now)
        if not chunk or not bridge.lumberjackScanTrees then return end
        for _,pt in ipairs(bridge.lumberjackScanTrees(chunk,16) or {}) do
            add(row,{kind='TREE',x=pt.x,y=pt.y,z=pt.z})
        end
        return
    end
    -- Cleaning is paced in z-level slices: one native call covers at most two
    -- levels (128 squares), so no frame ever pays for a whole 512-square chunk.
    -- Targets accumulate across slices instead of being rebuilt each round.
    if not bridge.cleaningScanTargetsSlice then return end
    local slice=Spatial.slice(env.entry,nil,category,env.now)
    if not slice then return end
    -- Per-slice quota is 1/4 of the old whole-chunk quota: four slices still
    -- yield at most 16 stains and 8 corpses, but no frame scans 512 squares.
    local found=bridge.cleaningScanTargetsSlice(slice.chunk,slice.level,slice.levels,4,
        p.cleanBloodOnly and 0 or 2)
    if not found then return end
    for _,pt in ipairs(found.stains or {}) do
        add(row,{kind='STAIN',x=pt.x,y=pt.y,z=pt.z})
    end
    local corpseZone=p.corpseZoneId and p.corpseZoneId~='' and zoneOf(env.entry.id,p.corpseZoneId)
    local hasDump=corpseZone and corpseZone.settlementId==env.entry.id and corpseZone.enabled~=false
    for _,pt in ipairs(found.corpses or {}) do
        if pt.body and pt.body:getItem() and pt.body:getItem():getFullType()~='Base.CorpseAnimal' then
            if not (hasDump and Zones.contains(corpseZone,pt.x,pt.y,pt.z)) then
                add(row,{kind='CORPSE',x=pt.x,y=pt.y,z=pt.z,itemId=pt.body:getItem():getID()})
            end
        end
    end
end
-- Crops block the tile they stand on: a fully planted rectangle strands the
-- worker. The lane grid is anchored per zone rectangle so multi-rectangle
-- zones keep one consistent walking pattern.
local function walkwayRow(zone,x,y,z,walk)
    if walk<=0 then return false end
    for _,a in ipairs(zone.areas) do
        local az=a.z or 0
        if (z==nil or math.floor(z)==math.floor(az)) and x>=a.x and x<a.x+a.w and y>=a.y and y<a.y+a.h then
            return (y-a.y)%(walk+1)==walk
        end
    end
    return false
end
-- Consumables may sit in the warehouse instead of the worker's bag. Discovery
-- asks the same planner the supply phase uses (same 500-read budget), cached
-- per row so a scan round costs at most one lookup per role.
local function remoteSupply(env,row,kind,filter,role)
    local cache=row.supply if not cache then cache={} row.supply=cache end
    local now=env.now or 0
    local slot=cache[role]
    if slot and now<slot.at then return slot.ok end
    local ok=false
    if env.entry and env.npc then
        local supplies,why=ToolDiscovery.findSupplies(env.entry,env.npc,kind,nil,filter)
        ok=supplies~=nil
        if not ok and why=='FIELD_OBSERVING' and slot then ok=slot.ok end
    end
    cache[role]={at=now+5000,ok=ok}
    return ok
end
-- Tilled-empty ground is not in CFarmingSystem's plant list, so this walks the
-- assigned farm-zone rectangles with a fixed per-tick budget. Vanilla's own
-- predicate decides dirt/ground-floor/free, we never re-implement it.
local function scanPlow(env,row)
    if not (ISFarmingMenu and ISFarmingMenu.canDigHereSquare) then return end
    -- Plowing is bounded by the assigned farm zone, never by the whole
    -- settlement territory.
    local zone=D.farmZone(env.entry)
    if not zone then return end
    local areas=zone.areas
    -- Plowing is demand-gated: only plow when seeds are available in worker inventory or warehouse.
    -- Prevents digging endless empty furrows that decay back to dirt when no seeds exist to plant.
    local hasSeeds=(ToolReq.seedItem(env.npc and env.npc:getInventory())~=nil)
        or remoteSupply(env,row,'SOW',nil,'SEED')
    if not hasSeeds then return end

    -- Bounded batching: buffer up to 8 contiguous plow targets for FieldProviders.continue() chaining.
    -- Stop discovery if there are already sufficient empty furrows (SOW targets) or queued plows.
    local emptyFurrows=0
    local plowCount=0
    for _,t in ipairs(row.targets) do
        if t.kind=='SOW' then emptyFurrows=emptyFurrows+1 end
        if t.kind=='PLOW' then plowCount=plowCount+1 end
    end
    if emptyFurrows>=8 or plowCount>=8 or #row.targets>=56 then return end

    local policy=policyOf(env.entry.id,'farming')
    local walk=math.floor(tonumber(policy and policy.walkwayEvery) or 0)
    if walk<0 then walk=0 end
    local cursor=row.plow
    if not cursor or cursor.zone~=zone.id then cursor={area=1,index=0,zone=zone.id} row.plow=cursor end
    local budget=64
    local cell=getCell()
    for _=1,budget do
        local area=areas[cursor.area]
        if not area then cursor.area=1 cursor.index=0 area=areas[1] end
        if not area then return end
        local total=area.w*area.h
        if cursor.index>=total then
            cursor.index=0
            cursor.area=cursor.area%#areas+1
            area=areas[cursor.area]
            if not area then return end
            total=area.w*area.h
        end
        local i=cursor.index cursor.index=cursor.index+1
        local x=area.x+(i%area.w) local y=area.y+math.floor(i/area.w)
        local z=area.z or 0
        if not walkwayRow(zone,x,y,z,walk) then
            local sq=cell and cell:getGridSquare(x,y,z) or nil
            if sq and ISFarmingMenu.canDigHereSquare(sq) then
                local dup=false
                for _,t in ipairs(row.targets) do if t.x==x and t.y==y and t.z==z then dup=true break end end
                if not dup then
                    add(row,{x=x,y=y,z=z,kind='PLOW'})
                    plowCount=plowCount+1
                    if plowCount>=8 or #row.targets>=56 then return end
                end
            end
        end
    end
end
local function scanPlants(env,row)
    local system=CFarmingSystem and CFarmingSystem.instance if not system then return end
    local count=system:getLuaObjectCount() if count<1 then return end
    local now=env.now or 0
    -- 5000ms TTL spatial snapshot cache aligned with ProjectRemnants FarmingAreaScanner.
    -- Small setups/unit tests (<=4 plants) use 500ms for immediate reactivity.
    local refreshMs=count<=4 and 500 or 5000
    if row.plantsNextAt and now<row.plantsNextAt then return end
    row.plantsNextAt=now+refreshMs

    -- Care targets follow the same zone guard as plowing; the per-target
    -- allowed() check stays the final authority.
    local zone=D.farmZone(env.entry) if not zone then return end
    local policy=policyOf(env.entry.id,'farming')
    local walk=math.floor(tonumber(policy and policy.walkwayEvery) or 0)
    if walk<0 then walk=0 end
    local limit=count<=4 and count or math.min(128,count)
    for _=1,limit do
        row.index=row.index%count+1
        local p=system:getLuaObjectByIndex(row.index)
        if p and p.x and p.y then
            if p.updateFromIsoObject then p:updateFromIsoObject() end
            local t={x=p.x,y=p.y,z=p.z or 0}
            if p.state=='rotten' or p.isAlive and not p:isAlive() and p.state~='plow' then t.kind='CLEAR'
            elseif p.canHarvest and p:canHarvest() then t.kind='HARVEST'
            elseif p.state=='plow' then
                -- Tilled and empty: sow whatever seed the worker carries, but
                -- never on a reserved walkway row.
                if not walkwayRow(zone,t.x,t.y,t.z,walk) then
                    local seed=ToolReq.seedItem(env.npc and env.npc:getInventory())
                    if seed then
                        t.kind='SOW' t.seed=ToolReq.seedType(seed)
                    elseif remoteSupply(env,row,'SOW',nil,'SEED') then
                        t.kind='SOW'
                    end
                end
            elseif p.typeOfSeed and p.typeOfSeed~='none' then
                -- Disease before water: an untreated infection costs the crop.
                -- Only offered when the worker already carries the right spray.
                local disease=(p.mildewLvl or 0)>0 and 'Mildew'
                    or (p.fliesLvl or 0)>0 and 'Flies'
                    or (p.slugsLvl or 0)>0 and 'Slugs'
                    or (p.aphidLvl or 0)>0 and 'Aphids' or nil
                if disease and (ToolReq.cureItem(env.npc and env.npc:getInventory(),disease)
                    or remoteSupply(env,row,'CURE',function(i) return ToolReq.cureType(i)==disease end,'CURE_TOOL')) then
                    t.kind='CURE' t.disease=disease
                end
                local goal,minimum,maximum=D.waterGoal(p)
                if not t.kind and (p.waterLvl or 0)<minimum then
                    t.kind='WATER'
                    -- Water units this target needs, independent of which can is
                    -- carried: supply planning compares it with the can's uses.
                    local level=p.waterLvl or 0
                    t.needUses=math.max(1,math.min(10,math.ceil((goal-level)/10),math.floor((maximum-level)/10)))
                    if t.needUses<1 then t.kind=nil end
                end
            end
            -- Each observed plant replaces its own stale conditions. A water
            -- level change is not a second intent while its target is claimed.
            for i=#row.targets,1,-1 do
                local old=row.targets[i]
                if old.x==t.x and old.y==t.y and old.z==t.z then
                    table.remove(row.targets,i)
                    if row.byKey then row.byKey[old.key]=nil end
                end
            end
            if t.kind then add(row,t) end
        end
    end
end
function D.rotten(env,row)
    local p=policyOf(env.entry.id,'cleaning')
    if p.haulRottenFood~=true or p.cleanBloodOnly then return end
    local now=env.now or 0
    if row.rottenNextAt and now<row.rottenNextAt and #row.targets>0 then return end
    row.rottenNextAt=now+3000
    local ids=require('EmberRoutesProbe/Settlement/SettlementMembership').query(env.entry) or {}
    if #ids==0 then return end
    row.containerIndex=(row.containerIndex or 0)%#ids+1
    local ep=require('EmberRoutesProbe/Crafting/CraftSupply').endpoint(env.entry,ids[row.containerIndex],'take')
    if not ep or Registry.logistics(ep)~='STORAGE' then return end
    local list=ep.container:getItems() local sq=ep.object:getSquare()
    -- Never pick up items already accepted here: that would loop between waste bins.
    row.itemIndex=(row.itemIndex or 0)%math.max(1,list:size())
    for _=1,math.min(32,list:size()) do
        local item=list:get(row.itemIndex) row.itemIndex=(row.itemIndex+1)%list:size()
        if instanceof(item,'Food') and item:isRotten() and not Store.owner(item:getID())
            and not Registry.accepts(ep,item) and require('EmberRoutesProbe/Work/LaborProducers').eligible(item) then
            add(row,{kind='ROTTEN',x=sq:getX(),y=sq:getY(),z=sq:getZ(),itemId=item:getID(),sourceId=ep.id})
        end
    end
end
local function forage(env,row)
    local fs=_G.forageSystem
    if not fs or not fs.getForageZoneAt then return end
    local zone=fs.getForageZoneAt(env.npc:getX(),env.npc:getY()) if not zone then return end
    local p=policyOf(env.entry.id,'forager')
    clearTargets(row)
    local empty=true for _ in pairs(zone.forageIcons or {}) do empty=false break end
    if empty and p.autoRefillZone and (zone.itemsLeft or 0)>0 then
        add(row,{kind='FORAGE_REFRESH',x=math.floor(env.npc:getX()),y=math.floor(env.npc:getY()),
            z=math.floor(env.npc:getZ()),identity='zone:'..tostring(zone.id)})
        return
    end
    local bonus=0
    if fs.getTraitVisionBonus then
        local ok,val=pcall(fs.getTraitVisionBonus,env.npc)
        if ok and type(val)=='number' then bonus=bonus+val end
    end
    if fs.getProfessionVisionBonus then
        local ok,val=pcall(fs.getProfessionVisionBonus,env.npc)
        if ok and type(val)=='number' then bonus=bonus+val end
    end
    local perkLevel=env.npc.getPerkLevel and Perks and Perks.PlantScavenging and env.npc:getPerkLevel(Perks.PlantScavenging) or 0
    local radius=math.max(3,math.min(16,math.floor(8+perkLevel*0.8+bonus)))
    local n=0
    for id,icon in pairs(zone.forageIcons or {}) do
        n=n+1 if n>256 then break end
        local focus=p.searchFocus or 'balanced' local cat=icon.catName
        local matches=focus=='balanced' or focus=='medicinal' and cat=='MedicinalPlants'
            or focus=='food' and (cat=='Berries' or cat=='Mushrooms' or cat=='WildPlants')
            or focus=='materials' and (cat=='Stones' or cat=='ForestGoods') or focus=='insects' and cat=='Insects'
        local cap=cat=='Stones' and p.maxStones or cat=='MedicinalPlants' and p.maxHerbs
        if cap and cap>0 then local count=D.stock(env.entry.id,cat) if not count or count>=cap then matches=false end end
        if matches then
            local dx=math.abs(icon.x-env.npc:getX())
            local dy=math.abs(icon.y-env.npc:getY())
            if dx<=radius and dy<=radius and dx*dx+dy*dy<=radius*radius then
                local t={kind='FORAGE',x=icon.x,y=icon.y,z=icon.z or 0,identity=tostring(id),iconId=id}
                local sq=Spatial.square(t) local floor=sq and sq:getFloor()
                if floor and env.npc:CanSee(floor) then
                    add(row,t)
                    seenLimit=(seenLimit or 8)-1
                    if seenLimit<=0 then break end
                end
            end
        end
    end
end
function D.targets(env,category)
    local row=cache(env,category)
    if env.now>=row.nextAt then
        row.nextAt=env.now+500
        if category=='cleaning' or category=='lumberjack' then
            local t0=tick() scanNative(env,category,row) span('PublicWork.discover.scanNative',t0)
        elseif category=='farming' then
            -- No assigned farm zone means no farming work at all: do not scan
            -- and do not keep yesterday's targets alive.
            if D.farmZone(env.entry) then scanPlants(env,row) scanPlow(env,row)
            else clearTargets(row) end
        else forage(env,row) end
        if category=='cleaning' then
            local r0=tick() D.rotten(env,row) span('PublicWork.discover.rotten',r0)
        end
    end
    return row.targets
end
function D.claim(target,npc,entry,category)
    if not D.allowed(category,entry,target,npc) then return nil,nil,'FIELD_RANGE_CHANGED' end
    if target.kind=='PLOW' then
        local sq=Spatial.square(target)
        if not sq or not (ISFarmingMenu and ISFarmingMenu.canDigHereSquare and ISFarmingMenu.canDigHereSquare(sq)) then
            return nil,nil,'FIELD_TARGET_CHANGED'
        end
        local t={x=target.x,y=target.y,z=target.z,kind='PLOW',identity='sq:'..target.x..':'..target.y..':'..target.z}
        return t,{'field-target:PLOW:'..t.identity}
    end
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
        if category=='farming' then
            local plant=D.plant(t)
            if not plant then return nil end
            local dead=plant.state=='rotten' or plant.isAlive and not plant:isAlive() and plant.state~='plow'
            local harvest=plant.canHarvest and plant:canHarvest()
            local _,minimum=D.waterGoal(plant)
            if t.kind=='CLEAR' and not dead or t.kind=='HARVEST' and (dead or not harvest)
                or t.kind=='WATER' and (dead or harvest or not plant.typeOfSeed or plant.typeOfSeed=='none'
                    or (plant.waterLvl or 0)>=minimum) then return nil,nil,'FIELD_TARGET_CHANGED' end
        end
        t.identity=Spatial.identity(o,true)
        if not t.identity then return nil end
    end
    keys[1]='field-target:'..t.kind..':'..t.identity
    return t,keys
end
return D
