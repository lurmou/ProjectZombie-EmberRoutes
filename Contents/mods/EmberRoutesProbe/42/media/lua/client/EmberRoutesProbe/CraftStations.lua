-- Shared discovery, existing craft-surface Claims, and generation-fenced native occupancy.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Facilities=require 'EmberRoutesProbe/SettlementFacilities'
local Context=require 'EmberRoutesProbe/CookingContext'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Store=require 'EmberRoutesProbe/LaborStore'
local S={recipeLimit=256}
local function position(object)
    local square=object and object.getSquare and object:getSquare()
    if not square then return nil end
    local cell=getCell()
    if not cell or cell:getGridSquare(square:getX(),square:getY(),square:getZ())~=square
        or not square:getObjects():contains(object) then return nil end
    return {x=square:getX(),y=square:getY(),z=square:getZ()}
end
local function bench(object)
    return object and object.getComponent and ComponentType and ComponentType.CraftBench
        and object:getComponent(ComponentType.CraftBench) or nil
end
function S.read(object,facts)
    local p=position(object) local component=bench(object)
    if not facts.workstation then
        if p and facts.surface and object.isGenericCraftingSurface and object:isGenericCraftingSurface()
            and object.getUsingPlayer and object.setUsingPlayer then
            return {object=object,position=p,id=object:getModData().EmberRoutesCraftProbeBenchId}
        end
        return nil,'CRAFT_SURFACE_REQUIRED'
    end
    if not p or not component or not component.getRecipes then return nil,'CRAFT_STATION_UNAVAILABLE' end
    local recipes=component:getRecipes()
    if not recipes or recipes:size()>S.recipeLimit then return nil,'STATION_RECIPE_LIMIT' end
    for i=0,recipes:size()-1 do if recipes:get(i)==facts.recipe then
        return {object=object,bench=component,position=p,id=object:getModData().EmberRoutesCraftProbeBenchId}
    end end
    return nil,'STATION_RECIPE_UNAVAILABLE'
end
function S.search(entry,facts)
    local row=Facilities.watch(entry,Facilities.describe)
    local request={index=1,version=row.version}
    function request:step(budget)
        if Registry.data()~=self.root then return nil,'WORLD_RESET' end
        row=Facilities.watch(entry,Facilities.describe)
        if self.version~=row.version then self.index=1 self.version=row.version end
        for _=1,math.min(budget or 16,64) do
            local observed=row.slots[self.index] self.index=self.index+1
            if observed==nil then
                self.index=1
                return nil,Facilities.pending(row) and Facilities.reason(row) or 'CRAFT_STATION_UNAVAILABLE'
            end
            if observed then
                local candidate=S.read(observed.object,facts)
                if candidate and not candidate.object:getUsingPlayer() then return candidate end
            end
        end
        return nil,'SITE_OBSERVING'
    end
    request.root=Registry.data()
    return request
end
local function resolve(station)
    local p=station.position local cell=getCell()
    local square=cell and cell:getGridSquare(p.x,p.y,p.z)
    if not square then return nil,'STATION_UNLOADED' end
    local objects=square:getObjects() local found
    if objects:size()>64 then return nil,'STATION_OBSERVATION_LIMIT' end
    for i=0,objects:size()-1 do
        local object=objects:get(i)
        if object:getModData().EmberRoutesCraftProbeBenchId==station.id then
            if found then return nil,'STATION_ID_CONFLICT' end found=object
        end
    end
    if not found then return nil,'CRAFT_STATION_UNAVAILABLE' end
    return found
end
function S.reserve(c,object,facts)
    if not Context.active(c) or c.job.effects~='KNOWN' then return nil,'COOKING_CONTROL_REQUIRED' end
    local site,why=S.read(object,facts) if not site then return nil,why end
    local entry=Ledger.view(c.actor,c.job.scopeId)
    if not entry or not Geometry.inside(entry,site.position.x,site.position.y) then return nil,'ACCESS_DENIED' end
    if object:getUsingPlayer() then return nil,'BENCH_OCCUPIED' end
    local old=c.job.payload.station
    if old then
        if old.id~=site.id or old.state~='RESERVED' then return nil,'STATION_RETAINED' end
        return site
    end
    if #c.job.payload.claims>=Record.limit then return nil,'COOKING_ASSET_LIMIT' end
    local data=object:getModData()
    if data.EmberRoutesCraftOccupancy then return nil,'STATION_RETAINED' end
    local id=data.EmberRoutesCraftProbeBenchId or Registry.id()
    data.EmberRoutesCraftProbeBenchId=id site.id=id
    local j=Record.copy(c.job)
    j.payload.station={id=id,siteKey='craft-surface:'..id,leaseId=Registry.id(),position=site.position,
        ownerId=j.npcId,state='RESERVED'}
    j.payload.claims[#j.payload.claims+1]=j.payload.station.siteKey j.obligations.station=true
    if not Context.publish(c,j) then return nil,c.reason end
    return site
end
function S.valid(c,object,facts)
    if not Context.active(c) then return false end
    local station=c.job.payload.station
    if not station or not Store.validCooking(c.job,c.token,station.siteKey) then return false end
    local entry=Ledger.view(c.actor,c.job.scopeId)
    if not entry or not Geometry.inside(entry,station.position.x,station.position.y) then return false end
    local current=resolve(station)
    return current==object and S.read(object,facts)~=nil
end
function S.acquire(c,object,facts)
    if not S.valid(c,object,facts) then return false end
    local station=c.job.payload.station
    if station.state~='RESERVED' or object:getUsingPlayer() then return false end
    local logic=HandcraftLogic.new(c.npc,bench(object),object)
    if facts.workstation then
        if not logic.isCharacterInRangeOfWorkbench or not logic:isCharacterInRangeOfWorkbench() then return false end
    elseif not require('EmberRoutesProbe/WorkTransfer').reachable(c.npc,{object=object}) then return false end
    local j=Record.copy(c.job) j.payload.station.state='ACQUIRING'
    if not Context.publish(c,j) then return false end
    if not S.valid(c,object,facts) or object:getUsingPlayer() then
        -- The setter has not been entered: never clear the new user's occupancy.
        j=Record.copy(c.job) j.payload.station.state='RELEASED' Context.publish(c,j)
        return false
    end
    local marker={leaseId=station.leaseId,npcId=c.job.npcId,jobId=c.job.id}
    object:getModData().EmberRoutesCraftOccupancy=marker
    c.stationLease={root=Registry.data(),body=c.body,object=object,leaseId=station.leaseId}
    -- This native setter is the only occupancy effect, fenced by a durable claim/intent.
    local ok=pcall(object.setUsingPlayer,object,c.npc)
    if not ok or object:getUsingPlayer()~=c.npc then return false end
    j=Record.copy(c.job) j.payload.station.state='ACQUIRED'
    return Context.publish(c,j)
end
function S.owned(c,object)
    local station,lease=c.job.payload.station,c.stationLease
    if not station or not lease or lease.root~=Registry.data() or lease.body~=c.body
        or lease.object~=object or lease.leaseId~=station.leaseId then return false end
    local marker=object:getModData().EmberRoutesCraftOccupancy
    return marker and marker.leaseId==station.leaseId and marker.jobId==c.job.id
        and marker.npcId==c.job.npcId and object:getUsingPlayer()==c.npc or false
end
-- Invoked only after actual native/Lua stop evidence, including the Session stop adapter.
function S.release(c,stopped,expectedLease)
    if not Context.current(c) or stopped~=true then return false end
    local station=c.job.payload.station
    if not station then return true end
    if expectedLease~=station.leaseId then return false end
    local object=resolve(station)
    if not object and station.state~='RESERVED' and station.state~='RELEASED' then return false end
    local user=object and object:getUsingPlayer()
    if station.state~='RESERVED' and station.state~='RELEASED' then
        if not object then return false end
        if user~=nil and not S.owned(c,object) then return false end
        local marker=object:getModData().EmberRoutesCraftOccupancy
        if user==nil and marker and marker.leaseId~=station.leaseId then return false end
        if user then
            local ok=pcall(object.setUsingPlayer,object,nil)
            if not ok or object:getUsingPlayer()~=nil then return false end
        end
        if marker and marker.leaseId==station.leaseId then object:getModData().EmberRoutesCraftOccupancy=nil end
    end -- RESERVED never owned native usage; RELEASED already proved it was cleared.
    if station.state~='RELEASED' then
        local j=Record.copy(c.job) j.payload.station.state='RELEASED'
        if not Context.publish(c,j) then return false end
    end
    if c.job.effects=='UNKNOWN' then return true end -- Retain logical responsibility until reconciliation.
    local j=Record.copy(c.job) j.payload.station=nil j.obligations.station=nil
    for i=#j.payload.claims,1,-1 do if j.payload.claims[i]==station.siteKey then table.remove(j.payload.claims,i) end end
    if not Context.publish(c,j) then return false end
    c.stationLease=nil return true
end
return S
