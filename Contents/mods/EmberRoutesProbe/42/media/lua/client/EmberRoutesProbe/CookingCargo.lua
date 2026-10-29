-- Original-ID custody leaves; movement and routing reuse the existing warehouse ports.
local Context=require 'EmberRoutesProbe/CookingContext'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Inventory=require 'EmberRoutesProbe/CookingInventory'
local View=require 'EmberRoutesProbe/InventoryView'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Supply=require 'EmberRoutesProbe/CraftSupply'
local Transfer=require 'EmberRoutesProbe/WorkTransfer'
local Actions=require 'EmberRoutesProbe/CookingActions'
local Tree=require 'EmberRoutesProbe/BehaviorTree'
local Facilities=require 'EmberRoutesProbe/CookingFacilities'
local Store=require 'EmberRoutesProbe/LaborStore'
local Capacity=require 'EmberRoutesProbe/CookingCapacity'
local M={}
local function failure(c,why) c.reason=why return 'Failure' end
-- The base vessel is also a borrowed original, with the same provenance rules.
function M.inputs(job)
    local e=job.payload.evolved local rows={}
    if job.payload.fixed then
        for _,input in ipairs(job.payload.fixed.inputs) do rows[#rows+1]=input end
    elseif job.payload.raw then rows[1]=job.payload.raw
    elseif e then
        rows[1]={id=e.originId,sourceId=e.originSourceId}
        for _,input in ipairs(e.inputs) do rows[#rows+1]=input end
    end
    for _,input in ipairs(job.payload.liquidInputs or {}) do rows[#rows+1]=input end
    return rows
end
function M.locate(c)
    local scan
    return {kind='Action',run=function()
        if not Context.active(c) then return 'Failure' end
        if not scan then
            local containers={c.npc:getInventory()} local seen={[containers[1]]=true}
            local inputs=M.inputs(c.job)
            for _,input in ipairs(inputs) do
                local asset=Inventory.asset(c.job,input.id)
                if asset.custody=='SOURCE' then
                    local endpoint,why=Supply.endpoint(c.entry,input.sourceId,'take')
                    if not endpoint then return failure(c,why or 'SOURCE_UNAVAILABLE') end
                    c.sources[input.id]=endpoint
                    if not seen[endpoint.container] then containers[#containers+1]=endpoint.container seen[endpoint.container]=true end
                end
            end
            if c.job.payload.duty then
                local endpoint,why=require('EmberRoutesProbe/CookingDuty').resolve(c.job)
                if not endpoint then return failure(c,why) end
                c.furnace=endpoint
                if not seen[endpoint.container] then containers[#containers+1]=endpoint.container seen[endpoint.container]=true end
            end
            local total=0 for _,container in ipairs(containers) do total=total+container:getItems():size() end
            if total>20000 then return failure(c,'INVENTORY_SCAN_LIMIT') end
            scan=View.scan(containers)
        end
        for _,endpoint in pairs(c.sources) do
            if not Registry.revalidate(endpoint,'take','local-world') then return failure(c,'SOURCE_ACCESS_CHANGED') end
        end
        local allowance=c.budget.scan c.budget.scan=0
        local index,why=scan:step(allowance)
        if not index then return why=='SCAN_PENDING' and 'Running' or failure(c,why) end
        for _,asset in ipairs(c.job.payload.assets) do
            if asset.custody=='HELD' or asset.custody=='SOURCE' or asset.custody=='STATION' then
                local item,_,missing=View.find(index,asset.id)
                local source=c.sources[asset.id]
                local expected=asset.custody=='HELD' and c.npc:getInventory()
                    or asset.custody=='STATION' and c.furnace and c.furnace.container or source and source.container
                if not item or item:getFullType()~=asset.fullType or item:getContainer()~=expected then
                    return failure(c,missing or 'COOKING_ORIGINAL_MOVED')
                end
                c.items[asset.id]=item
            elseif asset.custody~='CONSUMED' and asset.custody~='RETURNED' and asset.custody~='DELIVERED' then
                return failure(c,'COOKING_ORIGINAL_RECONCILE_REQUIRED')
            end
        end
        return 'Success'
    end}
end
function M.move(c,endpoint,valid)
    local operation,deadline
    local function stopped()
        if not c.body.stop() then return 'Running' end
        local fact=c.body.snapshot()
        return fact.available and fact.nativeStopped and 'Success' or 'Running'
    end
    return {kind='Action',run=function()
        if not Context.active(c) or valid and not valid() then return failure(c,'COOKING_TARGET_CHANGED') end
        if Transfer.reachable(c.npc,endpoint) then
            return stopped()
        end
        if not operation then
            if c.budget.paths<1 then return 'Running' end c.budget.paths=c.budget.paths-1
            operation=Transfer.move(c,endpoint) deadline=getTimestampMs()+operation.timeout
            local state,why=operation.start() if state=='FAILED' then return failure(c,why) end
        end
        if getTimestampMs()>deadline then return failure(c,'PATH_TIMEOUT') end
        local state,why=operation.poll()
        if state=='FAILED' then return failure(c,why) end
        if state=='PASSED' then return stopped() end
        return 'Running'
    end}
end
local function sequence(c)
    local a=c.job.payload.attempt
    return a and a.state=='PREPARED' and c.job.payload.sequence or c.job.payload.sequence+1
end
function M.transfer(c,id,endpoint,direction,custody)
    local leaf
    return {kind='Action',run=function()
        if not leaf then
            local why
            leaf,why=Actions.transfer(c,sequence(c),c.items[id],endpoint,direction,custody)
            if not leaf then return failure(c,why) end
        end
        local state=leaf.run()
        if state=='Failure' then c.reason=c.reason or 'COOKING_TRANSFER_STOPPED' end
        return state
    end}
end
function M.fetch(c)
    local index,tree=1,nil
    return {kind='Action',run=function()
        local input=M.inputs(c.job)[index]
        if not input then return 'Success' end
        local asset=Inventory.asset(c.job,input.id)
        if asset.custody=='HELD' then
            if tree then local state=Tree.tick(tree,c,c.budget) if state~='Success' then return state end end
            index=index+1 tree=nil return 'Running'
        end
        if asset.custody~='SOURCE' then
            -- A resumed mixture may already have consumed its base or an earlier input.
            if c.job.payload.evolved and asset.custody=='CONSUMED' then index=index+1 return 'Running' end
            return failure(c,'COOKING_INPUT_UNAVAILABLE')
        end
        local endpoint=c.sources[input.id]
        if not endpoint then return failure(c,'SOURCE_UNAVAILABLE') end
        if not tree then tree=assert(Tree.new({kind='Sequence',children={
            M.move(c,endpoint,function() return Registry.revalidate(endpoint,'take','local-world')~=nil end),
            M.transfer(c,input.id,endpoint,'TAKE')}})) end
        local state=Tree.tick(tree,c,c.budget)
        if state=='Success' then index=index+1 tree=nil return 'Running' end
        return state
    end}
end
local function cold(endpoint)
    local fact=Facilities.cold(endpoint,'put') return fact and fact.cold or false
end
function M.coldGate(c,weight)
    local ids,index,target
    return {kind='Action',run=function()
        if target then
            if cold(target) and Capacity.free(c,target)>=weight and Capacity.reserve(c,target,weight) then c.coldTarget=target return 'Success' end
            target=nil ids=nil
        end
        if not ids then
            local why
            ids,why=require('EmberRoutesProbe/SettlementMembership').query(c.entry)
            if not ids then return failure(c,why) end index=1
        end
        for _=1,c.budget.scan do
            c.budget.scan=c.budget.scan-1
            local id=ids[index] index=index+1
            if not id then return failure(c,'COLD_STORAGE_UNAVAILABLE') end
            local endpoint=Supply.endpoint(c.entry,id,'put')
            if endpoint and Registry.logistics(endpoint)=='STORAGE' and cold(endpoint)
                and Capacity.free(c,endpoint)>=weight and Capacity.reserve(c,endpoint,weight) then
                target=endpoint c.coldTarget=target return 'Success'
            end
        end
        return 'Running'
    end}
end
-- Deliver actual Food outputs, then return borrowed containers/tools. No remote release.
function M.store(c,outputs,salvage)
    local index,tree,route=1,nil,nil
    ---@type {id:string,object:any,container:any}|nil
    local target
    local blocked,failures={},0
    return {kind='Action',run=function()
        local asset=c.job.payload.assets[index]
        if not asset then return 'Success' end
        if tree then
            local state=Tree.tick(tree,c,c.budget)
            if state=='Success' then
                index=index+1 tree=nil route=nil target=nil blocked={} failures=0 return 'Running'
            end
            if state=='Failure' and c.job.effects=='KNOWN' and asset.custody=='HELD' then
                local a=c.job.payload.attempt
                if not a or a.state=='APPLIED' or a.state=='ABORTED' then
                    if not target then return failure(c,'RETURN_TARGET_UNAVAILABLE') end
                    blocked[target.id]=true failures=failures+1 tree=nil route=nil target=nil
                    if failures<8 then c.reason=nil return 'Running' end
                end
            end
            return state
        end
        local selected=outputs and asset.role=='OUTPUT' or not outputs and asset.role~='OUTPUT'
        if not selected or asset.custody=='DELIVERED' or asset.custody=='RETURNED' or asset.custody=='CONSUMED' then
            index=index+1 tree=nil route=nil target=nil blocked={} failures=0 return 'Running'
        end
        local item=c.items[asset.id]
        if outputs and salvage and asset.custody=='SOURCE' then
            local endpoint=c.sources[asset.id]
            if not endpoint or not Registry.revalidate(endpoint,'take','local-world')
                or not Inventory.contains(item,endpoint.container,asset.id) then return failure(c,'SOURCE_UNAVAILABLE') end
            local j=Record.copy(c.job) Inventory.release(j,asset.id,'RETURNED') j.payload.expected=0
            if not Context.publish(c,j) then return 'Failure' end
            index=index+1 return 'Running'
        end
        if not outputs and asset.custody=='SOURCE' then
            local endpoint=c.sources[asset.id]
            if not endpoint or not Registry.revalidate(endpoint,'take','local-world')
                or not Inventory.contains(item,endpoint.container,asset.id) then return failure(c,'SOURCE_UNAVAILABLE') end
            local j=Record.copy(c.job) Inventory.release(j,asset.id,'RETURNED')
            if not Context.publish(c,j) then return 'Failure' end
            index=index+1 return 'Running'
        end
        if not item or asset.custody~='HELD' or not Inventory.contains(item,c.npc:getInventory(),asset.id) then
            return failure(c,'COOKING_ORIGINAL_UNAVAILABLE')
        end
        if not outputs and not tree then
            local input
            for _,row in ipairs(M.inputs(c.job)) do if row.id==asset.id then input=row end end
            if not input and c.job.payload.fixed then return failure(c,'COOKING_RETURN_ORIGIN_MISSING') end
            if input and not input.sourceId and (c.job.payload.fixed or c.job.payload.raw or c.job.payload.evolved.provenance) then
                local j=Record.copy(c.job) Inventory.release(j,asset.id,'RETURNED')
                if not Context.publish(c,j) then return 'Failure' end
                index=index+1 return 'Running'
            end
            local endpoint=input and Supply.endpoint(c.entry,input.sourceId,'put')
            if endpoint and Registry.logistics(endpoint)=='STORAGE' and Registry.accepts(endpoint,item)
                and not blocked[endpoint.id] and endpoint.container:hasRoomFor(c.npc,item) then target=endpoint end
        end
        if not target and outputs and c.job.payload.capacity then
            local reserved=Supply.endpoint(c.entry,c.job.payload.capacity.endpointId,'put')
            if reserved and not blocked[reserved.id] and cold(reserved) and Registry.accepts(reserved,item)
                and Capacity.free(c,reserved)>=item:getUnequippedWeight() then target=reserved end
        end
        if not target then
            if not route then
                local why
                route,why=Supply.returnRoute(c.actor,c.npc,c.job.scopeId,item,function(endpoint)
                    return not blocked[endpoint.id] and (not outputs or cold(endpoint))
                end)
                if not route then return failure(c,why) end
            end
            local allowance=c.budget.scan c.budget.scan=0
            local done
            target,done=route:step(allowance)
            if not done then return 'Running' end
            if not target then return failure(c,outputs and 'COLD_STORAGE_UNAVAILABLE' or 'RETURN_TARGET_UNAVAILABLE') end
        end
        if not tree then tree=assert(Tree.new({kind='Sequence',children={
            {kind='Action',run=function()
                if not outputs then return 'Success' end
                return Capacity.reserve(c,target,math.max(item:getUnequippedWeight(),
                    c.job.payload.capacity and c.job.payload.capacity.amount or 0)) and 'Success' or failure(c,'COLD_STORAGE_UNAVAILABLE')
            end},
            M.move(c,target,function() return Registry.revalidate(target,'put','local-world')~=nil and (not outputs or cold(target)) end),
            M.transfer(c,asset.id,target,'PUT',outputs and not salvage and 'DELIVERED' or 'RETURNED')}})) end
        return 'Running'
    end}
end
return M
