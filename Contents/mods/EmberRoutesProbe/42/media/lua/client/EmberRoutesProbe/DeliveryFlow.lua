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
local function nextSource(r)
    for _,line in ipairs(r.manifest) do if line.custodyState=='UNCOLLECTED' then return line.sourceId end end
end
local function withdrawSource(c,sourceId)
    local changes={}
    for _,line in ipairs(c.job.manifest) do
	if line.custodyState=='UNCOLLECTED' and line.sourceId==sourceId then
	    changes[#changes+1]={itemId=line.itemId,state='WITHDRAWN'}
	end
    end
    if #changes>0 then assert(Store.settleHaulLines(c.job,c.token,c.generation,changes)) end
end
function F.next(c,snapshotStep,withdraw)
    local r=c.job
    if r.returning then withdraw(c) end
    local sourceId=not r.deliveryOnly and nextSource(r) or nil
    local source=sourceId and Registry.resolve(sourceId,'take',r.scopeId) or nil
    if sourceId and (not source or Registry.logistics(source)~='STORAGE') then
	-- No effect was attempted at this stop. Withdraw only its untouched
	-- originals; another source's pending requests can still be collected.
	withdrawSource(c,sourceId) c.scan=nil return nil,'SCAN_PENDING'
    end
    if c.scanSourceId~=sourceId then c.scan=nil end
    if not c.scan then
        local containers={c.npc:getInventory()} if source then containers[2]=source.container end
	c.scan=View.scan(containers) c.scanSourceId=sourceId
    end
    local index,why=c.scan:step(32)
    if not index then
        if why=='INVENTORY_CHANGED' then c.scan=nil end
        return nil,(why=='SCAN_PENDING' or why=='INVENTORY_CHANGED') and 'SCAN_PENDING' or 'RECONCILE_REQUIRED'
    end
    c.scan=nil
    local held,uncollected,missing={},nil,{}
    for _,l in ipairs(r.manifest) do
        if Manifest.pending(l) then
            local item,where,reason=View.find(index,l.itemId)
            if item and where==1 then l.custodyState='CARRIED' held[#held+1]=item
	    elseif l.custodyState=='CARRIED' or l.custodyState=='RECONCILE' then return nil,'RECONCILE_REQUIRED'
	    elseif l.sourceId==sourceId then
		if item and where==2 then uncollected=uncollected or {line=l,item=item}
		elseif reason=='ITEM_MISSING' then missing[#missing+1]={itemId=l.itemId,state='WITHDRAWN'}
		else return nil,'RECONCILE_REQUIRED' end
	    end
        end
    end
    if #missing>0 then assert(Store.settleHaulLines(r,c.token,c.generation,missing)) end
    if not r.deliveryOnly then
	if uncollected then
	    local item=uncollected.item
	    c.source=source
	    if Producers.freeCarry(c.npc)>=item:getUnequippedWeight() and c.npc:getInventory():hasRoomFor(c.npc,item) then
		if not Transfer.reachable(c.npc,source) then c.moveEndpoint=source return Transfer.move(c,source) end
		return snapshotStep(c,uncollected.line,item,source,'TAKE',index)
	    end
	    -- Capacity may change after planning. Skip only this untouched item,
	    -- then try other planned originals that may still fit on this trip.
	    assert(Store.settleHaulLines(r,c.token,c.generation,{{itemId=uncollected.line.itemId,state='WITHDRAWN'}}))
	    return nil,'SCAN_PENDING'
	elseif nextSource(r) then return nil,'SCAN_PENDING'
        else withdraw(c) end
    end
    if #held==0 then
	local o=Target.order(r)
	local more=o and not r.returning and require('EmberRoutesProbe/DeliveryService').hasOutstanding(o,r)
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
	return snapshotStep(c,Manifest.line(r,item:getID()),item,target,'PUT',index)
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
    return snapshotStep(c,Manifest.line(r,item:getID()),item,target,'PUT',index)
end
return F
