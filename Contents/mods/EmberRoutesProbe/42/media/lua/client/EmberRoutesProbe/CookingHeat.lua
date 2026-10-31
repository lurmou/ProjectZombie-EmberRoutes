-- Real native heat facts drive this step. No cooking timers or remote device effects.
local Context=require 'EmberRoutesProbe/CookingContext'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Inventory=require 'EmberRoutesProbe/CookingInventory'
local Food=require 'EmberRoutesProbe/CookingFood'
local Facilities=require 'EmberRoutesProbe/CookingFacilities'
local Duty=require 'EmberRoutesProbe/CookingDuty'
local Actions=require 'EmberRoutesProbe/CookingActions'
local Cargo=require 'EmberRoutesProbe/CookingCargo'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Membership=require 'EmberRoutesProbe/SettlementMembership'
local Supply=require 'EmberRoutesProbe/CraftSupply'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Carry=require 'EmberRoutesProbe/ProductionCarry'
local Transfer=require 'EmberRoutesProbe/WorkTransfer'
local H={}
local function admissible(item)
    local fact=Food.read(item)
    if not fact or not fact.food or not fact.safe or fact.frozen or fact.requiresTool then return nil,'HEAT_FOOD_UNSUPPORTED' end
    if not fact.needsHeat then return fact end
    if not item.getReplaceOnCooked or not item.getOnCooked then return nil,'HEAT_API_UNAVAILABLE' end
    local replacements=item:getReplaceOnCooked() local callback=item:getOnCooked()
    if replacements and replacements:size()>0 or callback and callback~='' then return nil,'HEAT_REPLACEMENT_UNSUPPORTED' end
    return fact
end
local function sequence(c)
    local a=c.job.payload.attempt return a and a.state=='PREPARED' and c.job.payload.sequence or c.job.payload.sequence+1
end
function H.new(c,ids,endpoint,cleanupOnly)
    if not Context.active(c) or c.job.effects~='KNOWN' then return nil,'COOKING_CONTROL_REQUIRED' end
    local existing=c.job.payload.heat
    local recovering=c.job.payload.duty~=nil or cleanupOnly==true
    if not existing then
        if type(ids)~='table' or #ids==0 or #ids>16 then return nil,'HEAT_ITEMS_INVALID' end
        local j=Record.copy(c.job)
        j.payload.heat={format=1,itemIds={},closed=false,aborted=cleanupOnly==true}
        local needsHeat=false
        for _,id in ipairs(ids) do
            local asset=Inventory.asset(j,id) local item=c.items[id]
            if not asset or asset.custody~='HELD' or not Inventory.contains(item,c.npc:getInventory(),id) then return nil,'HEAT_ORIGINAL_MISSING' end
            local fact,why=admissible(item) if not fact then return nil,why end
            needsHeat=needsHeat or fact.needsHeat
            asset.role='OUTPUT' j.payload.heat.itemIds[#j.payload.heat.itemIds+1]=id
        end
        -- Already prepared/cooked output needs delivery, not a synthetic heat cycle.
        if not needsHeat then j.payload.heat.closed=true end
        if not Context.publish(c,j) then return nil,c.reason end
    elseif ids then
        if #ids~=#existing.itemIds then return nil,'HEAT_INTENT_CHANGED' end
        for i,id in ipairs(ids) do if existing.itemIds[i]~=id then return nil,'HEAT_INTENT_CHANGED' end end
    end
    local move,arrived,operation,coldGate,targets,targetIndex,nextWall,nextGame
    local function phase(name)
        if c.job.payload.phase==name then return true end
        local j=Record.copy(c.job) j.payload.phase=name return Context.publish(c,j)
    end
    local function fail(why) c.reason=why return 'Failure' end
    local function inside(e)
        local square=e.object:getSquare()
        return square and Geometry.inside(c.entry,square:getX(),square:getY())
            and Registry.revalidate(e,'put','local-world')~=nil or false
    end
    local function close(aborted,reason)
        local j=Record.copy(c.job) local heat=j.payload.heat
        heat.closed=true heat.aborted=heat.aborted or aborted heat.reason=reason or heat.reason
        local total=0 local unsafe=false
        for _,id in ipairs(heat.itemIds) do
            local asset=Inventory.asset(j,id) local fact=Food.read(c.items[id])
            if not fact or not fact.food then return fail('HEAT_ORIGINAL_MISSING') end
            if not fact.safe then unsafe=true heat.aborted=true heat.reason='HEAT_OUTPUT_UNSAFE' end
            if fact.ready then asset.raw,asset.effective=fact.raw,fact.effective total=total+fact.effective
            else heat.aborted=true heat.reason=heat.reason or 'HEAT_STOPPED_BEFORE_COOKED' end
        end
        j.payload.expected=heat.aborted and 0 or total
        if not Context.publish(c,j) then return 'Failure' end
        if c.job.payload.duty and not Duty.release(c,endpoint) then return fail('FURNACE_OBLIGATION_RETAINED') end
        if unsafe then return fail('HEAT_OUTPUT_UNSAFE') end
        return 'Success'
    end
    local function toggle(desired)
        local why
        operation,why=Actions.toggle(c,sequence(c),endpoint,desired)
        if not operation then return fail(why) end return 'Running'
    end
    local function transfer(id,direction)
        local why
        operation,why=Actions.transfer(c,sequence(c),c.items[id],endpoint,direction,direction=='PUT' and 'STATION' or nil)
        if not operation then return fail(why) end return 'Running'
    end
    return {kind='Action',run=function()
        if not Context.active(c) then return fail('COOKING_AUTHORITY_LOST') end
        if operation then
            local state=operation.run() if state~='Success' then return state end
            operation=nil nextWall=nil nextGame=nil return 'Running'
        end
        local heat=c.job.payload.heat local duty=c.job.payload.duty
        if heat.closed and not duty then return 'Success' end
        -- A cancelled preparation that never used a device needs no new stove
        -- reservation or power merely to return its safe unfinished original.
        if cleanupOnly and not duty then
            for _,id in ipairs(heat.itemIds) do
                if Inventory.asset(c.job,id).custody=='STATION' then return fail('FURNACE_OBLIGATION_MISSING') end
            end
            return close(true,'COOKING_CANCELLED')
        end
        if not endpoint then
            if duty then
                local why
                endpoint,why=Duty.resolve(c.job) if not endpoint then return fail(why) end
            else
                if not targets then
                    local why
                    targets,why=Membership.query(c.entry) if not targets then return fail(why) end targetIndex=1
                end
                for _=1,c.budget.scan do
                    c.budget.scan=c.budget.scan-1
                    local id=targets[targetIndex] targetIndex=targetIndex+1
                    if not id then return fail('STOVE_UNAVAILABLE') end
                    local candidate=Supply.endpoint(c.entry,id,'put')
                    local stove=candidate and require('EmberRoutesProbe/CookingDirectives').kitchen(c.job.scopeId,candidate.object) and Facilities.stove(candidate)
                    if stove and stove.powered and not stove.active and not stove.broken
                        and Duty.contents(c,candidate) then endpoint=candidate break end
                end
                if not endpoint then return 'Running' end
            end
        end
        if not inside(endpoint) then return fail('FURNACE_ACCESS_CHANGED') end
        if arrived and not Transfer.reachable(c.npc,endpoint) then arrived=false move=nil end
        if not arrived then
            if not move then move=Cargo.move(c,endpoint,function() return inside(endpoint) end) end
            local state=move.run() if state~='Success' then return state end
            arrived=true
        end
        if not duty then
            if heat.closed then return 'Success' end
            local weight=0
            for _,id in ipairs(heat.itemIds) do
                local item=c.items[id] local fact,why=admissible(item) if not fact then return fail(why) end
                weight=weight+item:getUnequippedWeight()
            end
            if not coldGate then coldGate=Cargo.coldGate(c,weight) end
            local ready=coldGate.run() if ready~='Success' then return ready end
            local ok,why=Duty.reserve(c,endpoint) if not ok then return fail(why) end
            return 'Running'
        end
        local wall=getTimestampMs()
        local game=getGameTime and getGameTime():getWorldAgeHours() or 0
        if nextWall and wall<nextWall and game<(nextGame or 0) then return 'Running' end
        nextWall=wall+250 nextGame=game+1/3600
        local observation,why=Duty.observe(c,endpoint) if not observation then return fail(why) end
        duty=c.job.payload.duty
        local stove=Facilities.stove(endpoint) if not stove then return fail('STOVE_UNAVAILABLE') end
        local station,held={},{}
        local unsafe=false
        for _,id in ipairs(heat.itemIds) do
            local asset=Inventory.asset(c.job,id) local item=c.items[id] local fact=Food.read(item)
            if not item or not fact or not fact.food then return fail('HEAT_ORIGINAL_MISSING') end
            unsafe=unsafe or not fact.safe
            if asset.custody=='STATION' then
                if not Inventory.contains(item,endpoint.container,id) then return fail('STATION_ORIGINAL_MISSING') end
                station[#station+1]={id=id,food=fact,item=item}
            elseif asset.custody=='HELD' then
                if not Inventory.contains(item,c.npc:getInventory(),id) then return fail('HEAT_ORIGINAL_MOVED') end
                held[#held+1]={id=id,food=fact,item=item}
            elseif asset.custody~='DELIVERED' and asset.custody~='RETURNED' then return fail('HEAT_CUSTODY_INVALID') end
        end
        local blocked=observation.state=='OBSERVATION_REQUIRED'
        local draining=recovering or heat.closed or not stove.powered or stove.broken or unsafe
            or duty.openedByJob and not stove.active or blocked
        -- Remove cooked originals while remaining ones continue native heating.
        for _,row in ipairs(station) do
            if draining or row.food.cooked or not row.food.safe then
                if not Carry.fits(c.npc,row.item:getUnequippedWeight()) then
                    if stove.active and duty.openedByJob and not blocked then
                        c.reason='CAPACITY_UNAVAILABLE' return toggle(false) -- Emergency OFF; unload obligation remains.
                    end
                    return fail('CAPACITY_UNAVAILABLE')
                end
                if not phase('UNLOADING') then return 'Failure' end
                return transfer(row.id,'TAKE')
            end
        end
        if blocked then return fail(observation.reason or 'FURNACE_RECONCILE_REQUIRED') end
        if #station==0 and (draining or #held==0 or duty.openedByJob) then
            if stove.active then
                if not phase('UNLOADING') then return 'Failure' end
                return toggle(false)
            end
            return close(cleanupOnly==true or unsafe,unsafe and 'HEAT_OUTPUT_UNSAFE' or nil)
        end
        if draining then return 'Running' end
        if not duty.openedByJob then
            for _,row in ipairs(held) do if row.food.needsHeat then
                if not phase('HEATING') then return 'Failure' end
                return transfer(row.id,'PUT')
            end end
            if #station>0 then return toggle(true) end
            return close(false)
        end
        return 'Running'
    end}
end
return H
