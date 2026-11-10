-- Field tool supply executor: drives navigation to warehouse containers,
-- performs native ISInventoryTransferAction, verifies physical arrival in worker
-- inventory, and transitions job phase from PREPARE to WORK.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Store=require 'EmberRoutesProbe/Work/LaborStore'
local Transfer=require 'EmberRoutesProbe/Work/WorkTransfer'
local Native=require 'EmberRoutesProbe/Field/FieldActions'

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
            return ISInventoryTransferAction:new(c.npc,item,from,to)
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
        if inInv then
            if not Store.validToolUse(c.job.npcId,c.job.id,req.itemId) then c.reason='TOOL_CUSTODY_CHANGED' return 'Failure' end
            local custody=Store.custodyByItem(req.itemId)
            if custody then custody.state='HELD' end
        else
            pendingReq=req
            break
        end
    end

    if not pendingReq then
        -- Water before work: the target carries how many sprays it still needs.
        -- Two fills are the cap so a small container cannot loop forever.
        local liquid=c.job.payload.target and c.job.payload.target.liquid
        if liquid then
            local item=inv:getFirstEvalRecurse(function(i) return i:getID()==liquid.itemId end)
            if not item then c.reason='FIELD_LIQUID_INSUFFICIENT' return 'Failure' end
            local have=require('EmberRoutesProbe/Field/ToolRequirements').uses(item)
            if have<liquid.needUses and (liquid.fills or 0)<2 then
                local node,why=require('EmberRoutesProbe/Field/FieldWater').node(c,item,liquid.needUses)
                if not node and why=='SITE_OBSERVING' then return 'Running' end
                if not node then c.reason=why or 'FIELD_WATER_SOURCE_UNAVAILABLE' return 'Failure' end
                if not c.change(function(j)
                    local t=j.payload.target
                    if t and t.liquid then t.liquid.fills=(t.liquid.fills or 0)+1 end
                end) then c.reason='FIELD_JOB_CHANGED' return 'Failure' end
                c.node=node
                return 'Running'
            end
        end
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

-- Stop cleanup distinguishes warehouse reservations from held originals.
function S.releaseUncollected(c,supply)
    local observed={}
    for _,req in ipairs(supply and supply.requirements or {}) do
        local held=c.npc:getInventory():getFirstEvalRecurse(function(item) return item:getID()==req.itemId end)
        local custody=Store.custodyByItem(req.itemId)
        if not custody or custody.id~=req.custodyId then return false end
        if held then observed[#observed+1]={custody=custody,held=true}
        else
            local source=Registry.resolve(req.containerId,'take','local-world')
            local found=false
            if source and Registry.revalidate(source,'take','local-world') then
                local items=source.container:getItems()
                for i=0,items:size()-1 do
                    local item=items:get(i)
                    if item:getID()==req.itemId and item:getContainer()==source.container then found=true break end
                end
            end
            if not found then return false end
            observed[#observed+1]={custody=custody}
        end
    end
    for _,row in ipairs(observed) do
        if row.held then row.custody.state='HELD'
        elseif not Store.releaseCustody(row.custody.id) then return false end
    end
    return true
end
return S
