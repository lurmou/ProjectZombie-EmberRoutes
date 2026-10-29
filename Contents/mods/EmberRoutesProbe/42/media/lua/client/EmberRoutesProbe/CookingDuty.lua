-- Furnace responsibility stays with the Job, independently of its body Session.
-- This module observes/publishes obligations; only CookingActions may toggle.
local Context=require 'EmberRoutesProbe/CookingContext'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Inventory=require 'EmberRoutesProbe/CookingInventory'
local Facilities=require 'EmberRoutesProbe/CookingFacilities'
local Food=require 'EmberRoutesProbe/CookingFood'
local Store=require 'EmberRoutesProbe/LaborStore'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local D={}
local function owned(c,endpoint)
    if not Context.current(c) then return nil,'COOKING_JOB_CHANGED' end
    local duty=c.job.payload.duty
    if not duty or duty.siteKey~='cooking:'..endpoint.id or duty.ownerId~=c.job.npcId
        or not Store.validCooking(c.job,c.token,duty.siteKey) then return nil,'FURNACE_DUTY_CHANGED' end
    local stove,why=Facilities.stove(endpoint) if not stove then return nil,why end
    if duty.position then
        local square=endpoint.object:getSquare()
        if duty.endpointId~=endpoint.id or not square then return nil,'FURNACE_IDENTITY_CHANGED' end
        for _,axis in ipairs({'x','y','z'}) do
            local value=axis=='x' and square:getX() or axis=='y' and square:getY() or square:getZ()
            if duty.position[axis]~=value then return nil,'FURNACE_IDENTITY_CHANGED' end
        end
    end
    return stove
end
function D.contents(c,endpoint)
    local items,why=Inventory.snapshot(endpoint.container) if not items then return nil,why end
    local rows,count={},0
    for id,item in pairs(items) do
        local asset=Inventory.asset(c.job,id)
        if not asset or asset.custody~='STATION' or asset.fullType~=item:getFullType()
            or not Store.validCooking(c.job,c.token,'item:'..id) then return nil,'STOVE_FOREIGN_CONTENTS' end
        local row,reason=Food.read(item) if not row then return nil,reason end
        if row.food then
            if item.getHeat then row.heat=item:getHeat() end
            if item.getCookingTime then row.cookingTime=item:getCookingTime() end
            rows[#rows+1]=row count=count+1
        end
    end
    for _,asset in ipairs(c.job.payload.assets) do
        if asset.custody=='STATION' and not items[asset.id] then return nil,'STATION_ORIGINAL_MISSING' end
    end
    return {rows=rows,count=count}
end
function D.reserve(c,endpoint)
    if not Context.active(c) or c.job.effects~='KNOWN' or c.job.payload.duty then return false,'FURNACE_DUTY_RETAINED' end
    local stove,why=Facilities.stove(endpoint) if not stove then return false,why end
    if stove.active then return false,'STOVE_ALREADY_ACTIVE' end
    if not stove.powered or stove.broken then return false,'STOVE_UNAVAILABLE' end
    local contents,reason=D.contents(c,endpoint) if not contents then return false,reason end
    local j=Record.copy(c.job)
    local square=endpoint.object:getSquare()
    if not square then return false,'FURNACE_UNAVAILABLE' end
    j.payload.duty={id=j.id..':furnace',siteKey=stove.siteKey,ownerId=j.npcId,revision=1,
        endpointId=endpoint.id,position={x=square:getX(),y=square:getY(),z=square:getZ()},
        originalActive=false,openedByJob=false,lastActive=false,state='RESERVED'}
    j.payload.claims[#j.payload.claims+1]=stove.siteKey j.obligations.furnace=true
    return Context.publish(c,j)
end
function D.resolve(job)
    local duty=job.payload.duty
    if not duty or not duty.endpointId or not duty.position then return nil,'FURNACE_RECOVERY_UNVERIFIED' end
    local endpoint,why=Registry.resolve(duty.endpointId,'put','local-world') if not endpoint then return nil,why end
    local square=endpoint.object:getSquare()
    if not square or square:getX()~=duty.position.x or square:getY()~=duty.position.y or square:getZ()~=duty.position.z then
        return nil,'FURNACE_IDENTITY_CHANGED'
    end
    if not Facilities.stove(endpoint) then return nil,'FURNACE_UNAVAILABLE' end
    return endpoint
end
function D.toggleCheck(c,endpoint,desired)
    local stove,why=owned(c,endpoint) if not stove then return nil,why end
    local duty=c.job.payload.duty
    local contents,reason=D.contents(c,endpoint) if not contents then return nil,reason end
    if duty.state=='OBSERVATION_REQUIRED' or duty.state=='TRANSFER_PENDING' then return nil,'FURNACE_RECONCILE_REQUIRED' end
    if stove.active~=duty.lastActive then return nil,'STOVE_CHANGED_EXTERNALLY' end
    if desired then
        if duty.openedByJob or stove.active or not stove.powered or stove.broken or contents.count==0 then
            return nil,'STOVE_START_PRECONDITION'
        end
    elseif not duty.openedByJob or duty.originalActive or not stove.active then return nil,'STOVE_NOT_OWNED_ACTIVE' end
    return stove,contents
end
-- Bounded observation, called by the owning coordinator's facilities budget.
function D.observe(c,endpoint)
    local stove,why=owned(c,endpoint) if not stove then return nil,why end
    local content,reason=D.contents(c,endpoint)
    local duty=c.job.payload.duty local state
    local observedOff=false
    if duty.state=='OBSERVATION_REQUIRED' or duty.state=='TRANSFER_PENDING' or c.job.effects=='UNKNOWN'
        or not content then state='OBSERVATION_REQUIRED'
    elseif not stove.active and duty.lastActive and duty.openedByJob then
        -- Power loss or a player may switch OFF a known owned stove. Observe
        -- that fact, never toggle it back on; originals still require unloading.
        state='STOP_REQUIRED' observedOff=true
    elseif stove.active~=duty.lastActive then state='OBSERVATION_REQUIRED'
    elseif not stove.active then state=duty.openedByJob and 'STOP_REQUIRED' or 'RESERVED'
    else
        state='HEATING'
        if not stove.powered or stove.broken or content.count==0 then state='STOP_REQUIRED' end
        for _,row in ipairs(content.rows) do if row.cooked or not row.safe then state='STOP_REQUIRED' break end end
    end
    local j=Record.copy(c.job) local changed=duty.state~=state
    j.payload.duty.state=state
    if observedOff then
        j.payload.duty.lastActive=false j.payload.duty.shutdownObserved=true changed=true
    end
    if state~='OBSERVATION_REQUIRED' and state~='TRANSFER_PENDING' and content then
        local total,allReady=0,content.count>0
        for _,row in ipairs(content.rows) do
            if row.ready then
                local a=Inventory.asset(j,row.id)
                if a.role~='OUTPUT' or a.raw~=row.raw or a.effective~=row.effective then changed=true end
                a.role,a.raw,a.effective='OUTPUT',row.raw,row.effective total=total+row.effective
            else allReady=false end
        end
        if allReady and j.payload.heat then
            local observed={} for _,row in ipairs(content.rows) do observed[row.id]=row end
            total=0
            for _,id in ipairs(j.payload.heat.itemIds) do
                local asset=Inventory.asset(j,id)
                local fact=observed[id] or asset and asset.custody=='HELD' and c.items and c.items[id] and Food.read(c.items[id])
                if fact and fact.ready then total=total+fact.effective
                elseif asset and asset.custody=='DELIVERED' then total=total+asset.effective
                else allReady=false end
            end
        end
        if allReady and j.payload.expected~=total then j.payload.expected=total changed=true end
    end
    if changed then
        if not Context.publish(c,j) then return nil,c.reason end
    end
    return {state=state,reason=reason or state=='OBSERVATION_REQUIRED' and 'STOVE_CHANGED_EXTERNALLY' or nil,
        powered=stove.powered,active=stove.active,foods=content and content.rows}
end
function D.release(c,endpoint)
    local stove,why=owned(c,endpoint) if not stove then return false,why end
    local duty=c.job.payload.duty
    if c.job.effects~='KNOWN' or stove.active or duty.lastActive~=false
        or duty.state=='OBSERVATION_REQUIRED' or duty.state=='TRANSFER_PENDING' then return false,'FURNACE_OBLIGATION_RETAINED' end
    for _,asset in ipairs(c.job.payload.assets) do if asset.custody=='STATION' then return false,'FURNACE_FOOD_RETAINED' end end
    if duty.openedByJob then
        local a=c.job.payload.attempt local r=a and a.receipt
        -- A subsequent unload may replace the last attempt; retain shutdown
        -- evidence on Duty until every original has left the station.
        if not duty.shutdownObserved and (not r or a.state~='APPLIED' or a.kind~='TOGGLE'
            or r.siteKey~=duty.siteKey or r.actualActive~=false) then return false,'FURNACE_SHUTDOWN_NOT_OBSERVED' end
    end
    local j=Record.copy(c.job)
    for i=#j.payload.claims,1,-1 do if j.payload.claims[i]==duty.siteKey then table.remove(j.payload.claims,i) end end
    j.payload.duty=nil j.obligations.furnace=nil
    return Context.publish(c,j)
end
return D
