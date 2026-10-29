-- Shared furniture discovery; only verified native pure-water shapes are admitted.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Facilities=require 'EmberRoutesProbe/SettlementFacilities'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Fluids=require 'EmberRoutesProbe/CraftFluids'
local Store=require 'EmberRoutesProbe/LaborStore'
local Context=require 'EmberRoutesProbe/CookingContext'
local Record=require 'EmberRoutesProbe/CookingRecord'
local S={}
local function inside(actor,scope,object)
    local entry=Ledger.view(actor,scope)
    local square=object and object.getSquare and object:getSquare() local cell=getCell()
    if not entry or not square or not cell or cell:getGridSquare(square:getX(),square:getY(),square:getZ())~=square
        or not Geometry.inside(entry,square:getX(),square:getY()) or not square:getObjects():contains(object)
        or instanceof(object,'IsoWorldInventoryObject') then return nil end
    return {x=square:getX(),y=square:getY(),z=square:getZ()}
end
local function plumbedFluid(object)
    local fluid=object.getFluidContainer and object:getFluidContainer()
    local snapshot=fluid and Fluids.read(fluid)
    if not snapshot then return nil end
    -- Native plumbing changes TaintedWater into Water, but forwards all other
    -- mixture components. Only a fully observed water-only supply is admitted.
    for _,part in ipairs(snapshot.components) do
        if part.kind~='Water' and part.kind~='TaintedWater' then return nil end
    end
    return snapshot
end
function S.read(actor,scope,object,empty)
    local position=inside(actor,scope,object)
    if not position then return nil,'WATER_SOURCE_UNAVAILABLE' end
    for _,method in ipairs({'getFluidAmount','getFluidContainer','getUsesExternalWaterSource','getPrimaryFluid','isTaintedWater','hasFluid'}) do
        if not object[method] then return nil,'WATER_API_UNAVAILABLE' end
    end
    local amount=object:getFluidAmount()
    if type(amount)~='number' or amount~=amount or amount<0 or amount==math.huge then return nil,'WATER_AMOUNT_UNKNOWN' end
    local fluid=object:getFluidContainer() local mode=fluid and 'FINITE' or 'NATIVE_WATER'
    local backing
    if object:getUsesExternalWaterSource() then
        local bridge=EmberRoutesProbeJava and EmberRoutesProbeJava.waterSourceBacking
        if not bridge then return nil,'WATER_BACKING_UNAVAILABLE' end
        local fact=bridge(object)
        if not fact or fact.reason then return nil,fact and fact.reason or 'WATER_BACKING_UNAVAILABLE' end
        mode=fact.mode
        if mode=='PLUMBED' then
            local p=inside(actor,scope,fact.object)
            local snapshot=p and plumbedFluid(fact.object)
            if not snapshot or math.abs(snapshot.amount-amount)>.00001 then return nil,'PURE_WATER_REQUIRED' end
            backing={object=fact.object,id=fact.object:getModData().EmberRoutesWaterSourceId,
                position=p,snapshot=snapshot}
        elseif mode~='NATIVE_WATER' then return nil,'WATER_SOURCE_UNSUPPORTED' end
    elseif fluid and amount>fluid:getAmount()+.00001 then
        local bridge=EmberRoutesProbeJava and EmberRoutesProbeJava.waterSourceBacking
        local fact=bridge and bridge(object)
        if fact and fact.mode=='NATIVE_WATER' then mode='NATIVE_WATER' end
    end
    if amount>0 then
        if not object:hasFluid() or object:isTaintedWater() or not Fluid or not Fluid.Water then return nil,'PURE_WATER_REQUIRED' end
        if mode=='FINITE' then
            local snapshot=Fluids.water(fluid)
            if not snapshot or math.abs(snapshot.amount-amount)>.00001 then return nil,'PURE_WATER_REQUIRED' end
        elseif mode~='PLUMBED' and object:getPrimaryFluid()~=Fluid.Water then return nil,'PURE_WATER_REQUIRED' end
    elseif not empty then return nil,'WATER_SOURCE_EMPTY' end
    return {object=object,id=object:getModData().EmberRoutesWaterSourceId,amount=amount,mode=mode,
        position=position,backing=backing}
end
function S.reserve(c,object)
    if not Context.active(c) or c.job.effects~='KNOWN' then return nil,'COOKING_CONTROL_REQUIRED' end
    local source,why=S.read(c.actor,c.job.scopeId,object) if not source then return nil,why end
    if c.job.payload.waterSource then return nil,'WATER_SOURCE_RETAINED' end
    local data=object:getModData() local id=data.EmberRoutesWaterSourceId or Registry.id()
    data.EmberRoutesWaterSourceId=id source.id=id source.key='cooking:water:'..id
    local j=Record.copy(c.job)
    j.payload.waterSource={id=id,key=source.key,position=source.position}
    j.payload.claims[#j.payload.claims+1]=source.key j.obligations.water=true
    if source.backing then
        local b=source.backing local data=b.object:getModData()
        b.id=data.EmberRoutesWaterSourceId or Registry.id() data.EmberRoutesWaterSourceId=b.id
        b.key='cooking:water:'..b.id
        j.payload.waterSource.backing={id=b.id,key=b.key,position=b.position}
        j.payload.claims[#j.payload.claims+1]=b.key
    end
    if not Context.publish(c,j) then return nil,c.reason end
    return source
end
function S.valid(c,source,empty)
    local held=c.job.payload.waterSource
    if not Context.current(c) or not held or held.id~=source.id
        or not Store.validCooking(c.job,c.token,held.key) then return nil end
    local current=S.read(c.actor,c.job.scopeId,source.object,empty)
    if not current or current.id~=source.id or current.mode~=source.mode then return nil end
    for _,axis in ipairs({'x','y','z'}) do if held.position[axis]~=current.position[axis] then return nil end end
    if source.backing then
        local b=held.backing
        if not b or not current.backing or current.backing.object~=source.backing.object
            or current.backing.id~=b.id or not Store.validCooking(c.job,c.token,b.key) then return nil end
        for _,axis in ipairs({'x','y','z'}) do if b.position[axis]~=current.backing.position[axis] then return nil end end
    end
    return current
end
-- Post-effect proof reads the pinned tank even when draining it made the tap
-- refresh its native cache to another tank. It never follows that new source.
function S.progress(c,source)
    if not source.backing then return S.valid(c,source,true) end
    local held=c.job.payload.waterSource local b=held and held.backing
    if not Context.current(c) or not b or not Store.validCooking(c.job,c.token,b.key)
        or not inside(c.actor,c.job.scopeId,source.object) then return nil end
    local p=inside(c.actor,c.job.scopeId,source.backing.object)
    local data=source.backing.object:getModData()
    if not p or data.EmberRoutesWaterSourceId~=b.id then return nil end
    for _,axis in ipairs({'x','y','z'}) do if p[axis]~=b.position[axis] then return nil end end
    local snapshot=plumbedFluid(source.backing.object)
    return snapshot and {amount=snapshot.amount,backing={snapshot=snapshot}} or nil
end
function S.release(c,stopped)
    if not Context.current(c) or stopped~=true then return false end
    local held=c.job.payload.waterSource if not held then return true end
    if c.job.effects~='KNOWN' then return true end -- No native occupancy to clear; keep unknown logical responsibility.
    local j=Record.copy(c.job) j.payload.waterSource=nil j.obligations.water=nil
    for i=#j.payload.claims,1,-1 do
        if j.payload.claims[i]==held.key or held.backing and j.payload.claims[i]==held.backing.key then table.remove(j.payload.claims,i) end
    end
    return Context.publish(c,j)
end
function S.search(c)
    local row=Facilities.watch(c.entry,Facilities.describe)
    local request={root=Registry.data(),index=1,version=row.version,tried={},triedBacking={}}
    function request:skip(object,amount,backing)
        self.tried[object]=amount or 0 self.triedBacking[object]=backing or false
    end
    function request:step(budget)
        if self.root~=Registry.data() then return nil,'WORLD_RESET' end
        row=Facilities.watch(c.entry,Facilities.describe)
        if row.version~=self.version then self.index=1 self.version=row.version self.tried={} self.triedBacking={} self.blocker=nil end
        for _=1,math.min(budget or 16,64) do
            local observed=row.slots[self.index] self.index=self.index+1
            if observed==nil then
                self.index=1 return nil,Facilities.pending(row) and Facilities.reason(row) or self.blocker or 'PURE_WATER_UNAVAILABLE'
            end
            if observed then
                local source,why=S.read(c.actor,c.job.scopeId,observed.object)
                if why=='WATER_SOURCE_UNSUPPORTED' or why=='WATER_BACKING_UNAVAILABLE' then self.blocker=why end
                local backing=source and source.backing and source.backing.object or false
                if source and (not self.tried[source.object] or source.amount>self.tried[source.object]+.000001
                    or self.triedBacking[source.object]~=nil and self.triedBacking[source.object]~=backing) then
                    local owner=source.id and Store.resourceOwner('cooking:water:'..source.id)
                    local backingOwner=source.backing and source.backing.id and Store.resourceOwner('cooking:water:'..source.backing.id)
                    if (not owner or owner.taskId==c.job.id) and (not backingOwner or backingOwner.taskId==c.job.id) then return source end
                end
            end
        end
        return nil,'SITE_OBSERVING'
    end
    return request
end
return S
