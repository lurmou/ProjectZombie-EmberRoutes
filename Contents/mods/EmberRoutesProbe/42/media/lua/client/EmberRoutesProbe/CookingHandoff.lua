-- Verify a stopped, world-located Duty, then change the SAME Job's owner once.
-- Never reads another NPC's backpack or transfers an unknown native effect.
local Record=require 'EmberRoutesProbe/CookingRecord'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Store=require 'EmberRoutesProbe/LaborStore'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Driver=require 'EmberRoutesProbe/Driver'
local Members=require 'EmberRoutesProbe/MembershipService'
local Duty=require 'EmberRoutesProbe/CookingDuty'
local Facilities=require 'EmberRoutesProbe/CookingFacilities'
local Inventory=require 'EmberRoutesProbe/CookingInventory'
local Supply=require 'EmberRoutesProbe/CraftSupply'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local H={}
function H.transfer(actor,job,binding)
    local runtime=Runtime.current()
    if not runtime or not runtime:accepting() or not binding or not Driver.valid(binding)
        or not actor or actor:isDead() or binding.handle:isDead()
        or runtime:status(job.npcId,job.id) or runtime:owns(binding.id)
        or Registry.data().executionSave and Registry.data().executionSave.state=='BLOCKED' then return nil,'HANDOFF_BODY_BUSY' end
    local proposed,why=Record.handoff(job,binding.id) if not proposed then return nil,why end
    local saved=Jobs.current():peek(job.id)
    if not saved or saved.revision~=job.revision then return nil,'COOKING_JOB_CHANGED' end
    local entry=Members.entry(binding.id,job.scopeId)
    local fact=Members.check(binding.id,'RECOVERY',{x=binding.handle:getX(),y=binding.handle:getY(),
        z=binding.handle:getZ(),scopeId=job.scopeId})
    if not entry or not fact.sharedResources then return nil,'RECOVERY_ACCESS_DENIED' end
    local endpoint,reason=Duty.resolve(job) if not endpoint then return nil,reason end
    local square=endpoint.object:getSquare()
    if not square or not Geometry.inside(entry,square:getX(),square:getY()) then return nil,'FURNACE_ACCESS_CHANGED' end
    local stove=Facilities.stove(endpoint)
    if not stove or stove.active~=job.payload.duty.lastActive then return nil,'STOVE_CHANGED_EXTERNALLY' end
    local items,err=Inventory.snapshot(endpoint.container) if not items then return nil,err end
    for id,item in pairs(items) do
        local asset=Inventory.asset(job,id)
        if not asset or asset.custody~='STATION' or item:getFullType()~=asset.fullType then return nil,'STOVE_FOREIGN_CONTENTS' end
    end
    for _,asset in ipairs(job.payload.assets) do
        if asset.custody=='SOURCE' or asset.custody=='STATION' then
            local item=items[asset.id]
            if asset.custody=='SOURCE' then
                local source
                for _,input in ipairs(require('EmberRoutesProbe/CookingCargo').inputs(job)) do
                    if input.id==asset.id then source=input.sourceId end
                end
                local e=source and Supply.endpoint(entry,source,'take')
                local snapshot=e and Inventory.snapshot(e.container)
                item=snapshot and snapshot[asset.id]
            end
            local owner=Store.owner(asset.id)
            if not item or item:getFullType()~=asset.fullType or not owner or owner.taskId~=job.id then return nil,'COOKING_ORIGINAL_MISSING' end
        end
    end
    local key=Store.resourceOwner(job.payload.duty.siteKey)
    if not key or key.taskId~=job.id then return nil,'FURNACE_CLAIM_CHANGED' end
    local token,err2=Store.claimCooking(job) if not token then return nil,err2 end
    return Store.transferCooking(job,token,binding.id)
end
return H
