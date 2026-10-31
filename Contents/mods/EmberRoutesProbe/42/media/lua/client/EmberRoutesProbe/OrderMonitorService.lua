-- Read-only projection of public Orders and independent execution Jobs.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Craft=require 'EmberRoutesProbe/CraftProbe'
local Crafting=require 'EmberRoutesProbe/CraftingService'
local Work=require 'EmberRoutesProbe/Work'
local Driver=require 'EmberRoutesProbe/Driver'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Companion=require 'EmberRoutesProbe/Companion'
local Probe=require 'EmberRoutesProbe/Boot'
local Monitors=require 'EmberRoutesProbe/TaskMonitorProviders'
assert(Monitors.register(require 'EmberRoutesProbe/CookingMonitor'))
assert(Monitors.register(require 'EmberRoutesProbe/FieldWorkMonitor'))
local Service={}
local blocked={ITEM_MISSING=true,ITEM_ID_CONFLICT=true,RECONCILE_REQUIRED=true,INPUT_CHANGED=true}
local paused={USER=true,REPLACED=true,SAVE=true,LOAD_RECOVERY=true,COMPANION_ORDER=true,SELF_CARE=true}
local function endpoints(entry,r)
    if r.settlementId then return r.settlementId==entry.id end
    local a,b=Registry.describe(r.source),Registry.describe(r.destination)
    return a and b and Geometry.inside(entry,a.x,a.y) and Geometry.inside(entry,b.x,b.y)
end
local function endpoint(id)
    local p=id and Registry.describe(id)
    return p and {id=id,x=p.x,y=p.y,z=p.z} or nil
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
        local demand=kind=='CRAFT' and r.orderId and require('EmberRoutesProbe/PublicWork').order and require('EmberRoutesProbe/PublicWork').order(r.orderId)
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
            name=require('EmberRoutesProbe/DisplayNames').name(r.npcId,binding and binding.handle,r.workerName),carrierAvailable=binding~=nil,
            state=state,phase=r.phase,reason=r.reason,closed=closed,bucket=bucket,
            bodyMode=activity,uncertain=unknown,membership=require('EmberRoutesProbe/MembershipService').view(r.npcId),
            title=order and order.recipeName or nil,product=order and order.product or nil,
            requested=order and order.requested or (kind=='CRAFT' and 1 or #(r.items or {})),
            target=order and order.target or (kind=='CRAFT' and 1 or #(r.items or {})),
            produced=order and order.produced or nil,delivered=order and order.delivered or r.delivered or 0,
            source=endpoint(r.source),destination=endpoint(r.destination),nodes={},assets={}}
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
        if kind=='CRAFT' and r.format~=3 then
            for _,name in ipairs({'materialId','toolId'}) do
                if r[name] then row.assets[#row.assets+1]={id=r[name],kind=name=='toolId' and 'tools' or 'materials'} end
            end
            for _,itemId in ipairs(r.outputIds or {}) do row.assets[#row.assets+1]={id=itemId,kind='outputs'} end
        end
        if kind=='HAUL' then
            local types=require('EmberRoutesProbe/ItemDisplay').types(r,binding and binding.handle,displayBudget)
            local summary={}
            for _,itemId in ipairs(r.items or {}) do
                local kind=types[tostring(itemId)]
                local line=r.format==2 and require('EmberRoutesProbe/HaulManifest').line(r,itemId)
                row.assets[#row.assets+1]={id=itemId,kind='cargo',fullType=kind,
                    custodyState=line and line.custodyState,delivered=line and line.custodyState=='DELIVERED' or false,
                    destinationId=line and line.deliveryReceipt and line.deliveryReceipt.destinationId}
                if kind then summary[kind]=(summary[kind] or 0)+1 end
            end
            local names={} for kind,count in pairs(summary) do names[#names+1]=getItemNameFromFullType(kind)..' × '..count end
            table.sort(names)
            if #names>0 then row.title=getText('IGUI_EmberRoutesProbe_Monitor_hauling')..' · '..table.concat(names,', ') end
            if r.format==2 then
                row.delivered,row.withdrawn,row.cargoHeld=require('EmberRoutesProbe/HaulManifest').count(r)
                row.cargoSummary=getText('IGUI_EmberRoutesProbe_Monitor_cargoSummary',tostring(row.cargoHeld),tostring(row.withdrawn))
                if r.reason=='ROUTING_WAIT' then row.reason=getText('IGUI_EmberRoutesProbe_WorkCode_'..(r.routingWait and r.routingWait.reason or 'ROUTING_WAIT')) end
            end
        end
        if r.producer=='DELIVERY' then
            local o=require('EmberRoutesProbe/DeliveryService').order(r.orderId)
            if o then
                row.id='DELIVERY:'..o.id row.kind='DELIVERY' row.generation='ORDER:'..o.revision
                row.title=getText('IGUI_EmberRoutesProbe_Monitor_delivery')
                row.requested,row.delivered=0,0
                for _,request in ipairs(o.items) do
                    row.requested=row.requested+request.quantity row.delivered=row.delivered+request.delivered
                end
                for _,line in ipairs(r.manifest) do
                    if line.deliveryReceipt and line.deliveryReceipt.destinationId=='player:'..o.requesterId then row.delivered=row.delivered+1 end
                end
                row.target=row.requested row.canCancel=not o.cancelled
            end
        end
        result.rows[#result.rows+1]=row
    end
    for _,r in pairs(require('EmberRoutesProbe/BusinessJobs').records('CRAFT')) do
        if r.settlementId==id then add(r,'CRAFT',r.format==3 and require('EmberRoutesProbe/Production').status(r) or Craft.status(r.npcId)) end
    end
    for _,r in pairs(require('EmberRoutesProbe/BusinessJobs').records('HAUL')) do
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
            result.rows[#result.rows+1]={id='DELIVERY:'..o.id,orderId=o.id,kind='DELIVERY',generation='ORDER:'..o.revision,
                title=getText('IGUI_EmberRoutesProbe_Monitor_delivery'),state=o.state,reason=o.reason,
                bucket=closed and 'closed' or o.state=='RECONCILE_REQUIRED' and 'attention' or 'waiting',
                closed=closed,requested=count,target=count,delivered=delivered,nodes={},assets=assets,
                canPause=false,canResume=false,canCancel=not closed}
        end
    end
    local context={actor=actor,scopeId=id,runtime=runtime,bind=function(npcId)
        return Probe.ready and Probe.hasJava() and Driver.bindId(actor,npcId) or nil
    end}
    for _,j in pairs(root.taskJobs and root.taskJobs.byId or {}) do
        if j.scopeId==id then
            local row=Monitors.project(context,j)
            if row then result.rows[#result.rows+1]=row end
        end
    end
    if Probe.publicDispatch then
        for _,o in ipairs(require('EmberRoutesProbe/PublicWork').orders(id)) do
            if not o.jobId then
                local closed=o.state=='DONE' or o.state=='CANCELLED'
                result.rows[#result.rows+1]={id='ORDER:'..o.id,jobId=o.id,orderId=o.id,kind='ORDER',generation='ORDER:'..o.revision,
                    name=getText('IGUI_EmberRoutesProbe_Public_unclaimed'),title=o.name,product=o.product,state=o.state,phase='WAITING_CLAIM',reason=o.reason,
                    closed=closed,bucket=closed and 'closed' or o.state=='PAUSED' and 'paused' or 'waiting',bodyMode='UNCLAIMED',
                    carrierAvailable=true,requested=o.quantity,target=o.target,
                    produced=o.craftProgress and o.craftProgress.delivered or 0,
                    delivered=o.craftProgress and o.craftProgress.delivered or o.delivered or 0,nodes={},assets={},
                    canPause=not closed and o.state~='PAUSED',canResume=o.state=='PAUSED',canCancel=not closed}
            end
        end
    end
    table.sort(result.rows,function(a,b) if a.closed~=b.closed then return not a.closed end return a.id<b.id end)
    return result
end
function Service.watch(actor,id,callback)
    local root=Registry.data()
    local releaseJobs=require('EmberRoutesProbe/TaskJobs').watch(function(scope,jobId,revision,providerType)
        if scope==id and Monitors.has(providerType) then Crafting.invalidateStatus() end
    end)
    local releaseView=Crafting.watch(actor,id,function(snapshot)
        if root~=Registry.data() or snapshot.reason=='WORLD_RESET' then callback({rows={},reason='WORLD_RESET'})
        else callback(Service.status(actor,id)) end
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
        if action=='return' then return require('EmberRoutesProbe/DeliveryService').cancel(actor,row.orderId,tonumber(string.sub(generation,7))) end
        local r=Work.record(row.npcId)
        if not r or r.id~=row.jobId then return 'TASK_CHANGED' end
        return Work.taskCommand(actor,row.npcId,r.id,r.generation,action)
    end
    if row.kind=='ORDER' then
        return require('EmberRoutesProbe/PublicWork').command(actor,id,row.orderId,tonumber(string.sub(generation,7)),action)
    end
    if row.kind=='CRAFT' then return Crafting.command(actor,id,row.npcId,action) end
    if row.kind=='HAUL' then return Work.taskCommand(actor,row.npcId,row.jobId,generation,action) end
    return 'INVALID_COMMAND'
end
return Service
