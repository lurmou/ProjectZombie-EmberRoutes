-- Delivery-specific leaves, hosted by HaulAgent's single execution lifecycle.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Manifest=require 'EmberRoutesProbe/HaulManifest'
local Store=require 'EmberRoutesProbe/LaborStore'
local View=require 'EmberRoutesProbe/InventoryView'
local Transfer=require 'EmberRoutesProbe/WorkTransfer'
local Producers=require 'EmberRoutesProbe/LaborProducers'
local Target=require 'EmberRoutesProbe/DeliveryTarget'
local Routing=require 'EmberRoutesProbe/HaulRouting'
local F={}
function F.next(c,snapshotStep,withdraw)
    local r=c.job
    local source=not r.deliveryOnly and not r.returning and Registry.resolve(r.source,'take',r.scopeId) or nil
    if not c.scan then
        local containers={c.npc:getInventory()} if source then containers[2]=source.container end
        c.scan=View.scan(containers)
    end
    local index,why=c.scan:step(32)
    if not index then
        if why=='INVENTORY_CHANGED' then c.scan=nil end
        return nil,(why=='SCAN_PENDING' or why=='INVENTORY_CHANGED') and 'SCAN_PENDING' or 'RECONCILE_REQUIRED'
    end
    c.scan=nil
    local held,uncollected={},nil
    for _,l in ipairs(r.manifest) do
        if Manifest.pending(l) then
            local item,where,reason=View.find(index,l.itemId)
            if item and where==1 then l.custodyState='CARRIED' held[#held+1]=item
            elseif l.custodyState=='CARRIED' or l.custodyState=='RECONCILE' or reason~='ITEM_MISSING' and not item then
                return nil,'RECONCILE_REQUIRED'
            elseif item and where==2 then uncollected=uncollected or {line=l,item=item} end
        end
    end
    if r.returning or r.deliveryOnly or not source then withdraw(c) end
    if not r.deliveryOnly and uncollected then
        local item=uncollected.item
        c.source=source
        if Producers.freeCarry(c.npc)>=item:getUnequippedWeight() and c.npc:getInventory():hasRoomFor(c.npc,item) then
            if not Transfer.reachable(c.npc,source) then c.moveEndpoint=source return Transfer.move(c,source) end
            return snapshotStep(c,uncollected.line,item,source,'TAKE')
        elseif #held==0 then return nil,'NPC_CAPACITY_WAIT'
        else withdraw(c) end
    elseif not r.deliveryOnly then withdraw(c) end
    if #held==0 then
        local o=Target.order(r) local more=false
        if o and not r.returning then
            for _,request in ipairs(o.items) do
                local delivered=request.delivered
                for _,line in ipairs(r.manifest) do
                    if line.deliveryReceipt and line.deliveryReceipt.destinationId=='player:'..o.requesterId
                        and r.itemTypes[tostring(line.itemId)]==request.fullType
                        and (not request.sourceId or request.sourceId==r.source) then delivered=delivered+1 end
                end
                if delivered<request.quantity then more=true end
            end
        end
        if more then
            -- Return empty before releasing this segment, so the sole courier is
            -- inside its work context when ordinary dispatch offers the next batch.
            r.returnForNextBatch=true r.phase='RETURN' r.reason='RETURNING'
            local home=Registry.resolve(r.source,'take',r.scopeId)
            if not home then return nil,'ROUTING_WAIT' end
            if not Transfer.reachable(c.npc,home) then c.moveEndpoint=home return Transfer.move(c,home) end
        end
        r.returnForNextBatch=nil
        return nil,'DONE'
    end
    local item=held[1]
    if not r.returning then
        local target=Target.endpoint(c)
        if not target then r.returning=true return nil,'SCAN_PENDING' end
        r.phase='DELIVER'
        if not Transfer.reachable(c.npc,target) then return Target.move(c) end
        if not c.body.stop() then return nil,'CONTROL_REQUIRED' end
        if not Target.still(c) then r.reason='PLAYER_MOVING' return nil,'SCAN_PENDING' end
        if not Target.room(c,item) then
            r.reason='PLAYER_CAPACITY_WAIT'
            if getTimestampMs()>=(c.nextCapacityNote or 0) then
                c.nextCapacityNote=getTimestampMs()+10000
                if c.npc.Say then c.npc:Say(getText('IGUI_EmberRoutesProbe_Warehouse_courierCapacityWait')) end
            end
            return nil,'SCAN_PENDING'
        end
        if not Target.handoff(c,target,item) then return nil,'SCAN_PENDING' end
        c.destination=target r.reason='DELIVERING'
        return snapshotStep(c,Manifest.line(r,item:getID()),item,target,'PUT')
    end
    r.phase='RETURN' r.reason='RETURNING'
    local target=Target.returnTarget(c,item)
    if target and getTimestampMs()<(c.backoff[target.id] or 0) then target=nil end
    if not target then
        c.search=c.search or Routing.new(c,held)
        if not c.search then return nil,'ROUTING_WAIT' end
        local candidate,status=c.search:step(Routing.allowance())
        if not candidate then
            if status~='SCAN_PENDING' then c.search=nil end
            return nil,status=='SCAN_PENDING' and status or 'ROUTING_WAIT'
        end
        item,target=candidate.item,candidate.endpoint c.search=nil
    end
    c.destination=target
    local ok=Store.capacity(c.token,item:getID(),target.id,item:getUnequippedWeight(),target.container:getFreeCapacity(c.npc))
    if not ok then return nil,'ROUTING_WAIT' end
    if not Transfer.reachable(c.npc,target) then c.moveEndpoint=target return Transfer.move(c,target) end
    return snapshotStep(c,Manifest.line(r,item:getID()),item,target,'PUT')
end
return F
