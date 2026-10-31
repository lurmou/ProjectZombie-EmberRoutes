-- Field tool supply executor: drives navigation to warehouse containers,
-- performs native ISInventoryTransferAction, verifies physical arrival in worker
-- inventory, and transitions job phase from PREPARE to WORK.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Store=require 'EmberRoutesProbe/LaborStore'
local Transfer=require 'EmberRoutesProbe/WorkTransfer'
local Native=require 'EmberRoutesProbe/FieldActions'

local S={}

local function transferNode(c,item,from,to,endpoint,req)
    local function valid()
        if not c.valid() or not Store.validToolUse(c.job.npcId,c.job.id,item:getID()) then return false end
        return Registry.revalidate(endpoint,'take','local-world') and Transfer.reachable(c.npc,endpoint)
            and item:getContainer()==from and to:hasRoomFor(c.npc,item)
    end
    local function observe(ok,finished)
        if item:getContainer()==to and to:getItems():contains(item) then
            local custody=Store.custodyByItem(item:getID())
            if custody then
                custody.state='HELD'
            end
            Registry.inventoryChanged(from)
            Registry.inventoryChanged(to)
            return true,true
        end
        local unchanged=item:getContainer()==from and from:getItems():contains(item)
        return unchanged==true,false,not finished
    end
    local hooks={
        kind='SUPPLY_TOOL',
        transfer=item,
        valid=valid,
        observe=observe,
        create=function()
            if not valid() then return nil end
            return ISInventoryTransferAction:new(c.npc,item,from,to,60)
        end
    }
    return Native.new(c,hooks)
end

function S.step(c)
    if c.node then
        local state=c.node.run()
        if state=='Running' then return state end
        if state=='Failure' then
            c.reason=c.reason or 'TOOL_TRANSFER_FAILED'
            return state
        end
        c.node=nil c.path=nil c.approach=nil
        return 'Running'
    end

    local supply=c.job.payload.toolSupply
    local reqs=supply and supply.requirements or {}
    local inv=c.npc:getInventory()

    -- Check if there are any tools still needing warehouse pickup
    local pendingReq=nil
    for _,req in ipairs(reqs) do
        local inInv=inv:getFirstEvalRecurse(function(i) return i:getID()==req.itemId end)
        if not inInv then
            pendingReq=req
            break
        end
    end

    if not pendingReq then
        -- All required tools are in worker inventory. Transition to WORK.
        local ok=c.change(function(j)
            j.payload.phase='WORK'
            j.payload.toolSupply=nil
        end)
        if not ok then
            c.reason='TOOL_PHASE_TRANSITION_FAILED'
            return 'Failure'
        end
        return 'Running'
    end

    local endpoint=Registry.resolve(pendingReq.containerId,'take','local-world')
    if not endpoint or not endpoint.container then
        c.reason='TOOL_CONTAINER_UNAVAILABLE'
        return 'Failure'
    end

    local item=nil
    local items=endpoint.container:getItems()
    for i=0,items:size()-1 do
        local it=items:get(i)
        if it and it:getID()==pendingReq.itemId then
            item=it
            break
        end
    end
    if not item then
        c.reason='TOOL_ITEM_MISSING'
        return 'Failure'
    end

    if not Transfer.reachable(c.npc,endpoint) then
        if not c.approach then
            local p=Transfer.prepareMove(c,endpoint)
            c.approach=p and p.square
        end
        return c.move(c.approach,false)
    end

    c.path=nil c.approach=nil
    if not c.body.snapshot().nativeStopped then
        c.body.stop()
        return 'Running'
    end

    c.node=transferNode(c,item,endpoint.container,inv,endpoint,pendingReq)
    return c.node and 'Running' or 'Failure'
end

return S
