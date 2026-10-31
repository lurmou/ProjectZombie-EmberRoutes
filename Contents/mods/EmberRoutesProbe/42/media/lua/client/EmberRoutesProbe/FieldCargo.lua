-- Only proven output IDs travel. Shared warehouse ranking/access and native transfer.
require 'TimedActions/ISInventoryTransferAction'
require 'TimedActions/ISGrabItemAction'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Store=require 'EmberRoutesProbe/LaborStore'
local Record=require 'EmberRoutesProbe/FieldRecord'
local Spatial=require 'EmberRoutesProbe/FieldSpatial'
local Supply=require 'EmberRoutesProbe/CraftSupply'
local Transfer=require 'EmberRoutesProbe/WorkTransfer'
local Native=require 'EmberRoutesProbe/FieldActions'
local C={}
function C.snapshot(container)
    local list=container:getItems() if list:size()>512 then return nil end
    local result={}
    for i=0,list:size()-1 do local item=list:get(i) result[item:getID()]=item end
    return result
end
function C.ground(target)
    local result={} local cell=getCell() if not cell then return nil end
    for dx=-1,1 do for dy=-1,1 do
        local sq=cell:getGridSquare(target.x+dx,target.y+dy,target.z)
        if sq then
            local list=sq:getWorldObjects() if list:size()>128 then return nil end
            for i=0,list:size()-1 do local w=list:get(i) local item=w:getItem()
                if item then result[item:getID()]={item=item,world=w,x=sq:getX(),y=sq:getY(),z=sq:getZ()} end
            end
        end
    end end
    return result
end
function C.outputs(c,before,after,ground)
    if not before or not after then return false end
    return c.change(function(j)
        for id,value in pairs(after) do
            if not before[id] and not Record.asset(j,id) then
                local item=ground and value.item or value
                if #j.payload.assets>=96 then error('FIELD_OUTPUT_LIMIT') end
                j.payload.assets[#j.payload.assets+1]={id=id,fullType=item:getFullType(),
                    custody=ground and 'GROUND' or 'HELD',x=ground and value.x or nil,
                    y=ground and value.y or nil,z=ground and value.z or nil}
                Record.addClaim(j.payload,'item:'..id)
            end
        end
    end)
end
local function original(c,a)
    local inv=C.snapshot(c.npc:getInventory()) if not inv then return nil end
    local held=inv[a.id]
    if held and held:getFullType()==a.fullType then return held end
end
local function releaseCapacity(c)
    Store.releaseCapacity(c.token)
    return c.change(function(j) j.payload.capacity=nil end)
end
local function transfer(c,item,from,to,endpoint,pickup,destination)
    local function valid()
        if not c.valid() or not Store.validField(c.job,c.token,'item:'..item:getID()) then return false end
        if not require('EmberRoutesProbe/LaborProducers').eligible(item) or item:getIsCraftingConsumed() then return false end
        if pickup then
            return pickup:getItem()==item and pickup:getSquare()~=nil and pickup:getSquare():getWorldObjects():contains(pickup)
                and Spatial.reachable(c.npc,pickup:getSquare()) and to:hasRoomFor(c.npc,item)
        end
        return Registry.revalidate(endpoint,'put','local-world') and Registry.accepts(endpoint,item)
            and Registry.logistics(endpoint)=='STORAGE' and Transfer.reachable(c.npc,endpoint)
            and (not destination or destination(c,endpoint,item))
            and item:getContainer()==from and from:getItems():contains(item) and to:hasRoomFor(c.npc,item)
    end
    local function observe(ok,finished)
        if item:getContainer()==to and to:getItems():contains(item)
            and (pickup and (not pickup:getSquare() or not pickup:getSquare():getWorldObjects():contains(pickup))
                or not pickup and not from:getItems():contains(item)) then
            local saved=c.change(function(j)
                local a=Record.asset(j,item:getID())
                a.custody=pickup and 'HELD' or 'DELIVERED'
                if not pickup then Record.dropClaim(j.payload,'item:'..item:getID()) end
            end)
            if not pickup then Registry.inventoryChanged(from) Registry.inventoryChanged(to) end
            return saved,true
        end
        local unchanged=pickup and pickup:getSquare() and pickup:getSquare():getWorldObjects():contains(pickup)
            or not pickup and item:getContainer()==from and from:getItems():contains(item)
        return unchanged==true,false,not finished
    end
    local hooks={kind=pickup and 'PICKUP' or 'PUT',valid=valid,observe=observe,
        create=function()
            if not valid() then return nil end
            if pickup then
                -- Construction is not enqueued; prevent merging into a predecessor.
                local action=ISGrabItemAction:new(c.npc,pickup,50)
                action.queueList={{items={pickup},time=50,type=item:getFullType()}}
                action.ignoreAction=false action.checkQueueList=function() end
                return action
            end
            return ISInventoryTransferAction:new(c.npc,item,from,to,90)
        end}
    if pickup then
        -- Installed ISGrabItemAction mutates originals in perform, not complete.
        hooks.performEffect=true
    else hooks.transfer=item end
    return Native.new(c,hooks)
end
function C.step(c,def)
    if c.node then
        local state=c.node.run()
        if state=='Running' then return state end
        if state=='Failure' then c.reason=c.reason or 'FIELD_TRANSFER_STOPPED' return state end
        c.node=nil c.path=nil c.endpoint=nil c.route=nil
        if c.job.payload.capacity and not releaseCapacity(c) then return 'Failure' end
        return 'Running'
    end
    local ground,held
    for _,a in ipairs(c.job.payload.assets) do
        if a.custody=='GROUND' and not ground then ground=a end
        if a.custody=='HELD' and not held then held=a end
    end
    -- Deliver a carried batch before picking up more than the safe carry allowance.
    if ground and not held then
        local square=Spatial.square(ground) if not square then c.reason='FIELD_OUTPUT_UNLOADED' return 'Failure' end
        local list=square:getWorldObjects() local w,item
        for i=0,list:size()-1 do local o=list:get(i) local it=o:getItem()
            if it and it:getID()==ground.id and it:getFullType()==ground.fullType then w,item=o,it break end
        end
        if not item then c.unknown('FIELD_GROUND_ORIGINAL_MISSING') return 'Failure' end
        if require('EmberRoutesProbe/LaborProducers').freeCarry(c.npc)<item:getUnequippedWeight() then
            c.reason='FIELD_ITEM_TOO_HEAVY' return 'Failure'
        end
        c.approach=c.approach or Spatial.adjacent(c.npc,square)
        local state=c.move(c.approach,Spatial.reachable(c.npc,square))
        if state~='Success' then return state end
        c.approach=nil
        if not c.body.snapshot().nativeStopped then c.body.stop() return 'Running' end
        c.node=transfer(c,item,nil,c.npc:getInventory(),nil,w)
        return c.node and 'Running' or 'Failure'
    end
    if not held then return ground and 'Running' or 'Success' end
    local item=original(c,held)
    if not item then c.unknown('FIELD_HELD_ORIGINAL_MISSING') return 'Failure' end
    if not c.endpoint then
        if c.job.payload.capacity and not releaseCapacity(c) then return 'Failure' end
        if not c.route then
            local why
            c.route,why=Supply.returnRoute(c.actor,c.npc,c.job.scopeId,item,function(e)
                return not def.destination or def.destination(c,e,item)
            end,{allowOutside=true})
            if not c.route then c.reason=why return 'Failure' end
        end
        local endpoint,done=c.route:step(16)
        if not done then return 'Running' end
        if not endpoint then c.reason='FIELD_STORAGE_UNAVAILABLE' return 'Failure' end
        local amount=item:getUnequippedWeight()
        if not Store.reserveField(c.job,c.token,endpoint.id,item:getID(),amount,endpoint.container:getFreeCapacity(c.npc)) then
            c.reason='FIELD_CAPACITY_UNAVAILABLE' return 'Failure'
        end
        if not c.change(function(j) j.payload.capacity={key=endpoint.id,itemId=item:getID(),amount=amount} end) then
            Store.releaseCapacity(c.token) return 'Failure'
        end
        c.endpoint=endpoint
    end
    local endpoint=c.endpoint
    if not Registry.revalidate(endpoint,'put','local-world') or not Registry.accepts(endpoint,item)
        or def.destination and not def.destination(c,endpoint,item) then
        c.endpoint=nil c.route=nil releaseCapacity(c) return 'Running'
    end
    if not Transfer.reachable(c.npc,endpoint) then
        if not c.approach then local p=Transfer.prepareMove(c,endpoint) c.approach=p and p.square end
        return c.move(c.approach,false)
    end
    c.path=nil c.approach=nil
    if not c.body.snapshot().nativeStopped then c.body.stop() return 'Running' end
    c.node=transfer(c,item,c.npc:getInventory(),endpoint.container,endpoint,nil,def.destination)
    return c.node and 'Running' or 'Failure'
end
return C
