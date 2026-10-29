-- Bounded read-only recovery candidates over the one JobStore. Never starts a worker.
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Membership=require 'EmberRoutesProbe/MembershipService'
local Driver=require 'EmberRoutesProbe/Driver'
local Duty=require 'EmberRoutesProbe/CookingDuty'
local Facilities=require 'EmberRoutesProbe/CookingFacilities'
local Inventory=require 'EmberRoutesProbe/CookingInventory'
local Food=require 'EmberRoutesProbe/CookingFood'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Store=require 'EmberRoutesProbe/LaborStore'
local R={}
local function evaluate(actor,binding,job)
    local result={jobId=job.id,npcId=job.npcId,scopeId=job.scopeId,revision=job.revision,ready=false,kind='COOKING_RECOVERY'}
    local function blocked(why) result.reason=why return result end
    if job.effects~='KNOWN' or job.state=='RECONCILE_REQUIRED' then return blocked('COOKING_RECONCILE_REQUIRED') end
    if job.state~='SUSPENDED' and job.state~='SETTLING' then return blocked('BODY_STOP_NOT_CONFIRMED') end
    if not Driver.valid(binding) or binding.handle:isDead() or not actor or actor:isDead() then return blocked('CARRIER_UNAVAILABLE') end
    local entry=Membership.entry(binding.id,job.scopeId)
    local fact=Membership.check(binding.id,'RECOVERY',{x=binding.handle:getX(),y=binding.handle:getY(),
        z=binding.handle:getZ(),scopeId=job.scopeId})
    if not entry or not fact.sharedResources then return blocked('RECOVERY_ACCESS_DENIED') end
    if job.payload.evolved and not job.payload.evolved.completed and not job.payload.heat then
        local work=Membership.check(binding.id,'WORK',{x=binding.handle:getX(),y=binding.handle:getY(),
            z=binding.handle:getZ(),scopeId=job.scopeId})
        if not work.allowed then return blocked('COOKING_PREPARATION_NOT_ALLOWED') end
    end
    local inventory,why=Inventory.snapshot(binding.handle:getInventory())
    if not inventory then return blocked(why) end
    local station={}
    if job.payload.duty then
        if not job.payload.heat then return blocked('FURNACE_RECOVERY_UNVERIFIED') end
        local endpoint,reason=Duty.resolve(job) if not endpoint then return blocked(reason) end
        local square=endpoint.object:getSquare()
        if not square then return blocked('FURNACE_UNAVAILABLE') end
        if not Geometry.inside(entry,square:getX(),square:getY()) then return blocked('FURNACE_ACCESS_CHANGED') end
        local duty=job.payload.duty local stove=Facilities.stove(endpoint)
        if not stove then return blocked('FURNACE_UNAVAILABLE') end
        if duty.state=='OBSERVATION_REQUIRED' or duty.state=='TRANSFER_PENDING' then return blocked('FURNACE_RECONCILE_REQUIRED') end
        if stove.active~=duty.lastActive and (stove.active or not duty.openedByJob) then return blocked('STOVE_CHANGED_EXTERNALLY') end
        local owner=Store.resourceOwner(duty.siteKey)
        if not owner or owner.taskId~=job.id then return blocked('FURNACE_CLAIM_CHANGED') end
        station,why=Inventory.snapshot(endpoint.container) if not station then return blocked(why) end
        for id,item in pairs(station) do
            local asset=Inventory.asset(job,id)
            if not asset or asset.custody~='STATION' or asset.fullType~=item:getFullType() then return blocked('STOVE_FOREIGN_CONTENTS') end
        end
    end
    for _,asset in ipairs(job.payload.assets) do
        if asset.custody=='HELD' or asset.custody=='STATION' then
            local item=(asset.custody=='HELD' and inventory or station)[asset.id]
            local owner=Store.owner(asset.id)
            if not item or item:getFullType()~=asset.fullType or not owner or owner.taskId~=job.id then return blocked('COOKING_ORIGINAL_MISSING') end
            if asset.role=='OUTPUT' then
                local food=Food.read(item) if not food or not food.food or not food.safe then return blocked('HEAT_OUTPUT_UNSAFE') end
            end
        elseif asset.custody=='WORLD' or asset.custody=='UNKNOWN' then return blocked('COOKING_ORIGINAL_RECONCILE_REQUIRED') end
    end
    result.ready=true result.reason=job.payload.duty and 'FURNACE_DRAIN_REQUIRED'
        or job.payload.evolved and not job.payload.evolved.completed and 'COOKING_PREPARATION_REQUIRED' or 'COOKING_DELIVERY_REQUIRED'
    return result
end
function R.new(actor,binding)
    local world=Registry.data() local ids={} local index=1
    Jobs.current():visitNpc(binding.id,function(job)
        if job.providerType=='COOKING' and job.state~='DONE' and job.state~='CANCELLED'
            and (job.payload.duty or job.payload.heat or job.payload.evolved or job.payload.fixed or job.payload.raw) then ids[#ids+1]=job.id end
    end)
    table.sort(ids)
    local request={}
    function request:step(budget)
        if Registry.data()~=world then return nil,true,'WORLD_RESET' end
        for _=1,math.min(budget or 8,32) do
            local id=ids[index] index=index+1
            if not id then return nil,true end
            local job=Jobs.current():peek(id)
            if job and job.npcId==binding.id and job.state~='DONE' and job.state~='CANCELLED' then
                return evaluate(actor,binding,job),false
            end
        end
        return nil,false
    end
    return request
end
return R
