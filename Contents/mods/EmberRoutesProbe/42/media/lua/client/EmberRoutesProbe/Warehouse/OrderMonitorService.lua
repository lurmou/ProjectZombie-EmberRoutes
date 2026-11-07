-- Read-only projection of public Orders and independent execution Jobs.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Ledger=require 'EmberRoutesProbe/Settlement/SettlementLedger'
local Geometry=require 'EmberRoutesProbe/Settlement/SettlementGeometry'
local Craft=require 'EmberRoutesProbe/Crafting/CraftProbe'
local Crafting=require 'EmberRoutesProbe/Crafting/CraftingService'
local Work=require 'EmberRoutesProbe/Work/Work'
local Driver=require 'EmberRoutesProbe/Runtime/Driver'
local Runtime=require 'EmberRoutesProbe/Runtime/TaskRuntime'
local Companion=require 'EmberRoutesProbe/Settlement/Companion'
local Probe=require 'EmberRoutesProbe/Kernel/Boot'
local Monitors=require 'EmberRoutesProbe/Runtime/TaskMonitorProviders'
assert(Monitors.register(require 'EmberRoutesProbe/Cooking/CookingMonitor'))
assert(Monitors.register(require 'EmberRoutesProbe/Field/FieldWorkMonitor'))
local Service={}
local blocked={ITEM_MISSING=true,ITEM_ID_CONFLICT=true,RECONCILE_REQUIRED=true,INPUT_CHANGED=true}
local paused={DESTINATION_FILTER_REJECTED=true,DESTINATION_UNREGISTERED=true,DESTINATION_FULL=true,DESTINATION_UNREACHABLE=true,USER=true,REPLACED=true,SAVE=true,LOAD_RECOVERY=true,COMPANION_ORDER=true,SELF_CARE=true}
local function endpoints(entry,r)
    if r.settlementId then return r.settlementId==entry.id end
    local a,b=Registry.describe(r.source),Registry.describe(r.destination)
    return a and b and Geometry.inside(entry,a.x,a.y) and Geometry.inside(entry,b.x,b.y)
end
local function endpoint(id)
    local p=id and Registry.describe(id)
    return p and {id=id,x=p.x,y=p.y,z=p.z} or nil
end
local function deliveryDetails(row,o,r)
    local Delivery=require 'EmberRoutesProbe/Logistics/DeliveryService'
    local counts=r and o.jobId==r.id and Delivery.projectDelivery(o,r)
    row.requested,row.delivered=0,0
    row.destinationId=o.destinationId or 'player:'..o.requesterId
    row.deliveryLines={}
    local summary={}
    local Public=require 'EmberRoutesProbe/Work/PublicWork'
    local OrderQuery=require 'EmberRoutesProbe/Work/OrderQuery'
    for i,line in ipairs(o.items) do
        local delivered=counts and counts[i] or line.delivered
        local reason
        if OrderQuery.deliveryOverlapReason then reason=OrderQuery.deliveryOverlapReason(o,line) else reason=line.reason end
        row.requested=row.requested+line.quantity row.delivered=row.delivered+delivered
        row.deliveryLines[#row.deliveryLines+1]={sourceId=line.sourceId,destinationId=row.destinationId,
            fullType=line.fullType,requested=line.quantity,delivered=delivered,remaining=line.quantity-delivered,reason=reason}
        summary[#summary+1]=getText('IGUI_EmberRoutesProbe_Monitor_deliveryLine',line.sourceId or '*',row.destinationId,
            getItemNameFromFullType(line.fullType),tostring(line.quantity)..' / '..tostring(delivered)..' / '..tostring(line.quantity-delivered))
            ..(reason and ' ['..reason..']' or '')
        if reason and not r then row.reason=reason end
    end
    row.target=row.requested row.remaining=row.requested-row.delivered
    row.deliverySummary=table.concat(summary,'; ')
    row.cargoHeld=row.cargoHeld or 0
    row.cargoSummary=row.cargoSummary or getText('IGUI_EmberRoutesProbe_Monitor_cargoSummary',tostring(row.cargoHeld),tostring(row.withdrawn or 0))
end
function Service.status(actor,id)
    local entry,reason=Ledger.view(actor,id)
    local result={rows={},reason=reason}
    if not entry then return result end
    if Probe.failureCode=='LEGACY_TASK_RESET_REQUIRED' or Probe.failureCode=='LEGACY_STOCK_RESET_REQUIRED'
        or Probe.failureCode=='RECOVERY_RECORDS_INVALID' then result.reason=Probe.failureCode return result end
    local root=Registry.data()
    local runtime=Runtime.current()
    local displayBudget={remaining=256}
    local function add(r,kind,order)
        if r.producer=='DELIVERY' and r.state=='DONE' then
            local delivery=require('EmberRoutesProbe/Logistics/DeliveryService').order(r.orderId)
            if delivery and delivery.jobId~=r.id then return end -- Its receipts are already in the Order baseline.
        end
        local demand=kind=='CRAFT' and r.orderId and require('EmberRoutesProbe/Work/OrderQuery').order and require('EmberRoutesProbe/Work/OrderQuery').order(r.orderId)
        if demand and demand.jobId~=r.id then return end -- A continued demand has one visible current execution.
        local binding=Probe.ready and Probe.hasJava() and Driver.bindId(actor,r.npcId) or nil
        local control=runtime and runtime:status(r.npcId,r.id)
        local body=Companion.exportState(r.npcId)
        local closed=kind=='CRAFT' and r.released==true or kind=='HAUL' and r.state=='DONE'
        local state=control and control.state=='STOPPING' and 'STOPPING' or r.state
        local activity=control and control.state=='ACTIVE' and (kind=='CRAFT' and 'CRAFTING' or 'HAULING')
            or control and control.state=='STOPPING' and 'STOPPING' or body and body.mode or 'HOLD'
        activity=Probe.careActivity and Probe.careActivity(r.npcId) or activity
        local unknown=r.uncertain==true or r.controlUncertain==true
        local bucket=closed and 'closed' or unknown and 'attention' or blocked[r.reason] and 'attention'
            or state=='STOPPING' and 'active' or state=='RUNNING' and 'active'
            or paused[r.reason] and 'paused' or 'waiting'
        local row={id=r.orderId and 'ORDER:'..r.orderId or kind..':'..r.id,orderId=r.orderId,jobId=r.id,kind=kind,npcId=r.npcId,generation=r.generation,
            name=require('EmberRoutesProbe/Warehouse/DisplayNames').name(r.npcId,binding and binding.handle,r.workerName),carrierAvailable=binding~=nil,
            state=state,phase=r.phase,reason=r.reason,closed=closed,bucket=bucket,
            bodyMode=activity,uncertain=unknown,membership=require('EmberRoutesProbe/Settlement/MembershipService').view(r.npcId),
            title=order and order.recipeName or nil,product=order and order.product or nil,
            requested=order and order.requested or (kind=='CRAFT' and 1 or #(r.items or {})),
            target=order and order.target or (kind=='CRAFT' and 1 or #(r.items or {})),
            produced=order and order.produced or nil,delivered=order and order.delivered or r.delivered or 0,
            source=endpoint(r.source),destination=endpoint(r.destination),nodes={},assets={}}
        if demand then row.reason=require('EmberRoutesProbe/Work/OrderQuery').overlapReason(demand.id) or row.reason end
        if demand and demand.craftProgress then
            local prior=demand.craftProgress.delivered
            row.requested,row.target=demand.quantity,demand.target
            row.produced=math.min(row.target,prior+(order and order.produced or 0))
            row.delivered=math.min(row.target,prior+(order and order.delivered or 0))
        end
        row.canPause=not closed and state=='RUNNING'
        row.canResume=not closed and state~='RUNNING' and state~='STOPPING' and not row.uncertain
            and (kind=='HAUL' or order and order.resumable==true) and binding~=nil
        row.canCancel=kind=='CRAFT' and not closed and state~='RUNNING' and state~='STOPPING' and binding~=nil
        if r.chain then
            row.chainIndex=r.chain.index
            for _,node in ipairs(r.chain.nodes or {}) do
                row.nodes[#row.nodes+1]={name=node.recipeName,product=node.product,requested=node.requested}
            end
        end
        for _,name in ipairs({'materials','tools','outputs','held'}) do
            for _,asset in ipairs(r[name] or {}) do
                row.assets[#row.assets+1]={id=asset.id,kind=name,fullType=asset.fullType,delivered=asset.delivered==true}
            end
        end
        if kind=='CRAFT' and r.format==4 then
            row.allocated,row.settled,row.remaining=require('EmberRoutesProbe/Crafting/ProductionAllocation').count(r,r.product)
            if order and order.allocated~=nil then row.allocated,row.settled,row.remaining=order.allocated,order.settled,order.remaining end
            if demand and demand.craftProgress then
                row.allocated=math.min(row.target,demand.craftProgress.delivered+row.allocated)
                row.settled=row.delivered row.remaining=math.max(0,row.target-row.settled)
            end
            row.allocationSummary=getText('IGUI_EmberRoutesProbe_Monitor_allocation',row.allocated,row.settled,row.remaining)
            row.outputAllocation={} row.allocationLines={}
            for _,a in ipairs(r.outputAllocation and r.outputAllocation.assets or {}) do
                local targets={}
                for _,t in ipairs(a.targets) do targets[#targets+1]={destinationId=t.destinationId,quantity=t.quantity,transferred=t.transferred} end
                if #row.allocationLines<64 then
                    row.allocationLines[#row.allocationLines+1]=getText('IGUI_EmberRoutesProbe_Monitor_allocationItem',
                        tostring(a.id),targets[1] and targets[1].destinationId or '-',tostring(a.transferred),tostring(a.remaining))
                end
                row.outputAllocation[#row.outputAllocation+1]={id=a.id,fullType=a.fullType,actual=a.actual,
                    allocated=a.allocated,transferred=a.transferred,remaining=a.remaining,state=a.state,targets=targets}
            end
        end
        if row.allocationLines then row.allocationDetails=table.concat(row.allocationLines,'\n') end
        if kind=='HAUL' then
            local types=require('EmberRoutesProbe/Warehouse/ItemDisplay').types(r,binding and binding.handle,displayBudget)
            local summary={}
            for _,itemId in ipairs(r.items or {}) do
                local kind=types[tostring(itemId)]
		local line=(r.format==2 or r.format==3) and require('EmberRoutesProbe/Hauling/HaulManifest').line(r,itemId)
                row.assets[#row.assets+1]={id=itemId,kind='cargo',fullType=kind,
                    custodyState=line and line.custodyState,delivered=line and line.custodyState=='DELIVERED' or false,
                    destinationId=line and line.deliveryReceipt and line.deliveryReceipt.destinationId}
                if kind then summary[kind]=(summary[kind] or 0)+1 end
            end
            row.title=getText('IGUI_EmberRoutesProbe_Monitor_hauling')
            row.targetCount=#(r.items or {})
            row.deliveredCount=row.delivered or 0
	    if (r.format==2 or r.format==3) then
                row.delivered,row.withdrawn,row.cargoHeld=require('EmberRoutesProbe/Hauling/HaulManifest').count(r)
                row.cargoSummary=getText('IGUI_EmberRoutesProbe_Monitor_cargoSummary',tostring(row.cargoHeld),tostring(row.withdrawn))
                if r.reason=='ROUTING_WAIT' then row.reason=getText('IGUI_EmberRoutesProbe_WorkCode_'..(r.routingWait and r.routingWait.reason or 'ROUTING_WAIT')) end
            end
        end
        if r.producer=='DELIVERY' then
            local o=require('EmberRoutesProbe/Logistics/DeliveryService').order(r.orderId)
            if o then
                row.id='DELIVERY:'..o.id row.kind='DELIVERY' row.generation='ORDER:'..o.revision
                row.title=getText('IGUI_EmberRoutesProbe_Monitor_delivery')
                deliveryDetails(row,o,r) row.canCancel=not o.cancelled
                if o.cancelled then
                    row.state='CANCELLED' row.reason=row.uncertain and 'RECONCILE_REQUIRED' or 'CANCEL_REQUESTED'
                    row.canPause,row.canResume=false,false
                    -- A cancelled demand may still own cargo: keep the responsible Job visible.
                    row.closed=false row.bucket=row.uncertain and 'attention' or 'paused'
                end
            end
        end
        local job=root.taskJobs and root.taskJobs.byId[r.id]
        if kind=='CRAFT' and r.format==4 then
            require('EmberRoutesProbe/Crafting/CraftWorkflowView').attach(row,r,control,job and job.revision)
        elseif kind=='HAUL' and (r.format==2 or r.format==3) then
            require('EmberRoutesProbe/Hauling/HaulWorkflowView').attach(row,r,control,job and job.revision)
        end
        result.rows[#result.rows+1]=row
    end
    for _,r in pairs(require('EmberRoutesProbe/Work/BusinessJobs').records('CRAFT')) do
        if r.settlementId==id then add(r,'CRAFT',Craft.status(r.npcId)) end
    end
    for _,r in pairs(require('EmberRoutesProbe/Work/BusinessJobs').records('HAUL')) do
        if endpoints(entry,r) then add(r,'HAUL') end
    end
    for _,o in pairs(root.deliveryOrders and root.deliveryOrders.orders or {}) do
        if o.settlementId==id and not o.jobId then
            local count,delivered=0,0 local assets={}
            for _,line in ipairs(o.items) do
                count=count+line.quantity delivered=delivered+line.delivered
                assets[#assets+1]={kind='cargo',fullType=line.fullType}
            end
            local closed=o.state=='DONE' or o.state=='CANCELLED'
            local row={id='DELIVERY:'..o.id,orderId=o.id,kind='DELIVERY',generation='ORDER:'..o.revision,
                title=getText('IGUI_EmberRoutesProbe_Monitor_delivery'),state=o.state,reason=o.reason,
                bucket=closed and 'closed' or o.state=='RECONCILE_REQUIRED' and 'attention' or 'waiting',
                closed=closed,requested=count,target=count,delivered=delivered,nodes={},assets=assets,
                canPause=false,canResume=false,canCancel=not closed}
            deliveryDetails(row,o)
            result.rows[#result.rows+1]=row
        end
    end
    local context={actor=actor,scopeId=id,runtime=runtime,displayBudget=displayBudget,bind=function(npcId)
        return Probe.ready and Probe.hasJava() and Driver.bindId(actor,npcId) or nil
    end}
    for _,j in pairs(root.taskJobs and root.taskJobs.byId or {}) do
        if j.scopeId==id and not (j.providerType=='FIELD_WORK' and j.payload.category=='cleaning') then
            local row=Monitors.project(context,j)
            if row then result.rows[#result.rows+1]=row end
        end
    end
    if Probe.publicDispatch then
        for _,o in ipairs(require('EmberRoutesProbe/Work/OrderQuery').orders(id)) do
            if not o.jobId then
                local closed=o.state=='DONE' or o.state=='CANCELLED'
                result.rows[#result.rows+1]={id='ORDER:'..o.id,jobId=o.id,orderId=o.id,kind='ORDER',generation='ORDER:'..o.revision,
                    name=getText('IGUI_EmberRoutesProbe_Public_unclaimed'),title=o.name,product=o.product,state=o.state,phase='WAITING_CLAIM',reason=require('EmberRoutesProbe/Work/OrderQuery').overlapReason(o.id) or o.reason,
                    closed=closed,bucket=closed and 'closed' or o.state=='PAUSED' and 'paused' or 'waiting',bodyMode='UNCLAIMED',
                    carrierAvailable=true,requested=o.quantity,target=o.target,
                    produced=o.craftProgress and o.craftProgress.delivered or 0,
                    delivered=o.craftProgress and o.craftProgress.delivered or o.delivered or 0,nodes={},assets={},
                    canPause=not closed and o.state~='PAUSED',canResume=o.state=='PAUSED',canCancel=not closed}
            end
        end
    end
    for _,row in ipairs(require('EmberRoutesProbe/Field/ToolCustodyMonitor').rows(id,context)) do result.rows[#result.rows+1]=row end
    table.sort(result.rows,function(a,b) if a.closed~=b.closed then return not a.closed end return a.id<b.id end)
    return result
end
function Service.watch(actor,id,callback,projector)
    local root=Registry.data()
    local releaseJobs=require('EmberRoutesProbe/Runtime/TaskJobs').watch(function(scope,jobId,revision,providerType)
        if scope==id then
            if Monitors.has(providerType) then Crafting.invalidateStatus() end
            callback((projector or Service.status)(actor,id))
        end
    end)
    local releaseView=Crafting.watch(actor,id,function(snapshot)
        if root~=Registry.data() or snapshot.reason=='WORLD_RESET' then callback({rows={},reason='WORLD_RESET'})
        else callback((projector or Service.status)(actor,id)) end
    end)
    return function() releaseJobs() releaseView() end
end
function Service.command(actor,id,key,generation,action)
    if action~='stop' and action~='resume' and action~='return' then return 'INVALID_COMMAND' end
    local snapshot=Service.status(actor,id)
    if snapshot.reason then return snapshot.reason end
    local row
    for _,candidate in ipairs(snapshot.rows) do if candidate.id==key then row=candidate break end end
    if not row or row.generation~=generation then return 'TASK_CHANGED' end
    if row.readOnly then return 'TASK_READ_ONLY' end
    if action=='stop' and not row.canPause or action=='resume' and not row.canResume
        or action=='return' and not row.canCancel then return 'TASK_CHANGED' end
    if row.providerType then return Monitors.command({actor=actor,scopeId=id},row,action) end
    if row.kind=='DELIVERY' then
        if action=='return' then return require('EmberRoutesProbe/Logistics/DeliveryService').cancel(actor,row.orderId,tonumber(string.sub(generation,7))) end
        local r=Work.record(row.npcId)
        if not r or r.id~=row.jobId then return 'TASK_CHANGED' end
        return Work.taskCommand(actor,row.npcId,r.id,r.generation,action)
    end
    if row.kind=='ORDER' then
        return require('EmberRoutesProbe/Work/PublicWork').command(actor,id,row.orderId,tonumber(string.sub(generation,7)),action)
    end
    if row.kind=='CRAFT' then return Crafting.command(actor,id,row.npcId,action) end
    if row.kind=='HAUL' then return Work.taskCommand(actor,row.npcId,row.jobId,generation,action) end
    return 'INVALID_COMMAND'
end
return Service
