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
local Service={}
local blocked={ITEM_MISSING=true,ITEM_ID_CONFLICT=true,RECONCILE_REQUIRED=true,INPUT_CHANGED=true}
local paused={USER=true,REPLACED=true,SAVE=true,LOAD_RECOVERY=true,COMPANION_ORDER=true}
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
    local function add(r,kind,order)
        local binding=Probe.ready and Probe.hasJava() and Driver.bindId(actor,r.npcId) or nil
        local control=runtime and runtime:status(r.npcId,r.id)
        local body=Companion.exportState(r.npcId)
        local closed=kind=='CRAFT' and r.released==true or kind=='HAUL' and r.state=='DONE'
        local state=control and control.state=='STOPPING' and 'STOPPING' or r.state
        local activity=control and control.state=='ACTIVE' and (kind=='CRAFT' and 'CRAFTING' or 'HAULING')
            or control and control.state=='STOPPING' and 'STOPPING' or body and body.mode or 'HOLD'
        local unknown=r.uncertain==true or r.controlUncertain==true
        local bucket=closed and 'closed' or unknown and 'attention' or blocked[r.reason] and 'attention'
            or state=='STOPPING' and 'active' or state=='RUNNING' and 'active'
            or paused[r.reason] and 'paused' or 'waiting'
        local row={id=r.orderId and 'ORDER:'..r.orderId or kind..':'..r.id,orderId=r.orderId,jobId=r.id,kind=kind,npcId=r.npcId,generation=r.generation,
            name=binding and binding.handle:getFullName() or string.sub(r.npcId,1,8),carrierAvailable=binding~=nil,
            state=state,phase=r.phase,reason=r.reason,closed=closed,bucket=bucket,
            bodyMode=activity,uncertain=unknown,
            title=order and order.recipeName or nil,product=order and order.product or nil,
            requested=order and order.requested or (kind=='CRAFT' and 1 or #(r.items or {})),
            target=order and order.target or (kind=='CRAFT' and 1 or #(r.items or {})),
            produced=order and order.produced or nil,delivered=order and order.delivered or r.delivered or 0,
            source=endpoint(r.source),destination=endpoint(r.destination),nodes={},assets={}}
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
        if kind=='HAUL' then for _,itemId in ipairs(r.items or {}) do row.assets[#row.assets+1]={id=itemId,kind='cargo'} end end
        result.rows[#result.rows+1]=row
    end
    for _,r in pairs(require('EmberRoutesProbe/BusinessJobs').records('CRAFT')) do
        if r.settlementId==id then add(r,'CRAFT',r.format==3 and require('EmberRoutesProbe/Production').status(r) or Craft.status(r.npcId)) end
    end
    for _,r in pairs(require('EmberRoutesProbe/BusinessJobs').records('HAUL')) do
        if endpoints(entry,r) then add(r,'HAUL') end
    end
    if Probe.publicDispatch then
        for _,o in ipairs(require('EmberRoutesProbe/PublicWork').orders(id)) do
            if not o.jobId then
                local closed=o.state=='DONE' or o.state=='CANCELLED'
                result.rows[#result.rows+1]={id='ORDER:'..o.id,jobId=o.id,orderId=o.id,kind='ORDER',generation='ORDER:'..o.revision,
                    name=getText('IGUI_EmberRoutesProbe_Public_unclaimed'),title=o.name,state=o.state,phase='WAITING_CLAIM',reason=o.reason,
                    closed=closed,bucket=closed and 'closed' or o.state=='PAUSED' and 'paused' or 'waiting',bodyMode='UNCLAIMED',
                    carrierAvailable=true,requested=o.quantity,target=o.target,produced=0,delivered=0,nodes={},assets={},
                    canPause=not closed and o.state~='PAUSED',canResume=o.state=='PAUSED',canCancel=not closed}
            end
        end
    end
    table.sort(result.rows,function(a,b) if a.closed~=b.closed then return not a.closed end return a.id<b.id end)
    return result
end
function Service.watch(actor,id,callback)
    local root=Registry.data()
    return Crafting.watch(actor,id,function(snapshot)
        if root~=Registry.data() or snapshot.reason=='WORLD_RESET' then callback({rows={},reason='WORLD_RESET'})
        else callback(Service.status(actor,id)) end
    end)
end
function Service.command(actor,id,key,generation,action)
    local snapshot=Service.status(actor,id)
    if snapshot.reason then return snapshot.reason end
    local row
    for _,candidate in ipairs(snapshot.rows) do if candidate.id==key then row=candidate break end end
    if not row or row.generation~=generation then return 'TASK_CHANGED' end
    if action=='stop' and not row.canPause or action=='resume' and not row.canResume
        or action=='return' and not row.canCancel then return 'TASK_CHANGED' end
    if row.kind=='ORDER' then
        return require('EmberRoutesProbe/PublicWork').command(actor,id,row.orderId,tonumber(string.sub(generation,7)),action)
    end
    if row.kind=='CRAFT' then return Crafting.command(actor,id,row.npcId,action) end
    return Work.taskCommand(actor,row.npcId,row.jobId,generation,action)
end
return Service
