-- Original-instance movement leaves. Persisted IDs are obligations, not stock.
local Transfer=require 'EmberRoutesProbe/WorkTransfer'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Store=require 'EmberRoutesProbe/LaborStore'
local Supply=require 'EmberRoutesProbe/CraftSupply'
local Custody={}
local function returnable(item,endpoint)
    if not instanceof(item,'Food') or not require('EmberRoutesProbe/CookingProfiles').meal(item:getFullType())
        or item:getHungChange()>=-.001 then return true end
    local fact=require('EmberRoutesProbe/CookingFacilities').cold(endpoint,'put')
    return fact and fact.cold or false
end
local function move(c,endpoint,prepared)
    local operation,deadline
    return {kind='Action',run=function()
        if not c.valid() then return 'Failure' end
        if Transfer.reachable(c.npc,endpoint) then
            if operation and not c.body.stop() then return 'Running' end
            return 'Success'
        end
        if not operation then
            if c.budget.paths<1 then return 'Running' end
            c.budget.paths=c.budget.paths-1
            operation=Transfer.move(c,endpoint,prepared) deadline=getTimestampMs()+operation.timeout
            local state,why=operation.start()
            if state=='FAILED' then c.reason=why return 'Failure' end
        end
        if getTimestampMs()>deadline then c.reason='PATH_TIMEOUT' return 'Failure' end
        local state,why=operation.poll()
        if state=='FAILED' then c.reason=why return 'Failure' end
        return state=='PASSED' and 'Success' or 'Running'
    end}
end
-- Advisory one-original lookahead, called under the routine's existing scan
-- budget while reading/consuming/getting up. No body call, claim or transfer.
function Custody.prepareReturn(c)
    local id=c.payload.itemId
    local item=id and c.items[id]
    if not c.payload.sourceId or not item or item:getContainer()~=c.npc:getInventory() then return end
    local now=getTimestampMs() local p=c.returnPreview
    if p and now<(p.nextAt or 0) then return end
    if c.budget.scan<1 then return end c.budget.scan=c.budget.scan-1
    if not p or p.item~=item then p={item=item} c.returnPreview=p end
    p.nextAt=now+1000
    if p.target then
        local checked=Registry.revalidate(p.target,'put','local-world')
        if not checked or Registry.logistics(checked)~='STORAGE' or not Registry.accepts(checked,item)
            or not returnable(item,checked) or not checked.container:hasRoomFor(c.npc,item) then p.target=nil p.point=nil p.routing=nil
        else p.target=checked end
    end
    local destination=c.payload.destinations and c.payload.destinations[tostring(id)] or c.payload.sourceId
    local endpoint=Registry.resolve(destination,'put','local-world')
    if endpoint and Registry.logistics(endpoint)=='STORAGE' and Registry.accepts(endpoint,item)
        and returnable(item,endpoint) and endpoint.container:hasRoomFor(c.npc,item) then p.target=endpoint p.routing=nil
    elseif not p.target then
        if not p.routing then p.routing=Supply.returnRoute(c.actor,c.npc,c.payload.settlementId,item,
            function(e) return returnable(item,e) end) end
        if p.routing then
            local target,done=p.routing:step(1)
            if done then p.routing=nil p.target=target else p.nextAt=now+50 end
        end
    end
    if p.target and Transfer.prepareMove and not Transfer.reachable(c.npc,p.target) then p.point=Transfer.prepareMove(c,p.target) end
end
local function transfer(c,item,from,to,endpoint,phase)
    local operation
    return {kind='Action',run=function()
        if not c.valid() then return 'Failure' end
        -- Actual original location also reconciles an interrupted native transfer.
        if item:getContainer()==to and to:getItems():contains(item) and not from:getItems():contains(item) then
            c.payload.transfer=nil
            return c.persist() and 'Success' or 'Failure'
        end
        if not operation then
            if item:getContainer()~=from then c.effects='UNKNOWN' c.persist() return 'Failure' end
            c.payload.transfer={itemId=item:getID(),phase=phase,attemptId=c.payload.attemptId}
            if not c.persist() then return 'Failure' end
            c.eligible=function(value)
                return value==item and Store.validPersonal(c.job,c.token,'item:'..item:getID())
                    and (not endpoint or Registry.revalidate(endpoint,phase=='TAKE' and 'take' or 'put','local-world')~=nil
                        and Registry.logistics(endpoint)=='STORAGE' and Registry.accepts(endpoint,item)
                        and (phase~='RETURN' or returnable(item,endpoint)))
            end
            operation=Transfer.item(c,item,from,to,endpoint)
            local state,why=operation.start()
            if state=='FAILED' then c.reason=why return 'Failure' end
            return 'Running'
        end
        local state,why=operation.poll()
        if state=='FAILED' then c.reason=why return 'Failure' end
        if state~='PASSED' then return 'Running' end
        c.payload.transfer=nil
        return c.persist() and 'Success' or 'Failure'
    end}
end
function Custody.take(c,candidate)
    if candidate.container==c.npc:getInventory() then return {kind='Condition',run=function() return 'Success' end} end
    local leaves={}
    if candidate.endpoint then leaves[#leaves+1]=move(c,candidate.endpoint) end
    leaves[#leaves+1]=transfer(c,candidate.item,candidate.container,c.npc:getInventory(),candidate.endpoint,'TAKE')
    return {kind='Sequence',children=leaves}
end
function Custody.returns(c)
    local tree,index,routing,target
    return {kind='Action',run=function()
        if not c.payload.sourceId then return 'Success' end
        local ids={c.payload.itemId}
        for _,id in ipairs(c.payload.consumption and c.payload.consumption.outputs or {}) do ids[#ids+1]=id end
        index=index or 1
        while index<=#ids do
            -- Each original inspection is charged, including missing/depleted IDs.
            if c.budget.scan<1 then return 'Running' end
            c.budget.scan=c.budget.scan-1
            local item=c.items[ids[index]]
            local container=item and item:getContainer()
            local consumed=ids[index]==c.payload.itemId and c.payload.consumption
                and c.payload.consumption.effects=='KNOWN' and c.payload.consumption.after<=0.0001
            local endpoint
            local key=tostring(ids[index])
            local destination=c.payload.destinations and c.payload.destinations[key] or c.payload.sourceId
            if container or not consumed then endpoint=Registry.resolve(destination,'put','local-world') end
            if not container and consumed then
                index=index+1 tree=nil routing=nil target=nil
            elseif endpoint and container==endpoint.container then index=index+1 tree=nil routing=nil target=nil
            elseif container~=c.npc:getInventory() then c.reason='RETURN_ORIGINAL_MISSING' return 'Failure'
            else
                local preview=c.returnPreview
                if preview and preview.item==item and preview.target and not (endpoint and Registry.logistics(endpoint)=='STORAGE'
                    and Registry.accepts(endpoint,item) and endpoint.container:hasRoomFor(c.npc,item)) then
                    local checked=Registry.revalidate(preview.target,'put','local-world')
                    if checked and Registry.logistics(checked)=='STORAGE' and Registry.accepts(checked,item)
                        and returnable(item,checked) and checked.container:hasRoomFor(c.npc,item) then endpoint=checked end
                end
                local usable=endpoint and Registry.logistics(endpoint)=='STORAGE' and Registry.accepts(endpoint,item)
                    and returnable(item,endpoint) and endpoint.container:hasRoomFor(c.npc,item)
                if not usable and not target then
                    if not routing then
                        routing,c.reason=Supply.returnRoute(c.actor,c.npc,c.payload.settlementId,item,
                            function(e) return returnable(item,e) end)
                        if not routing then return 'Failure' end
                    end
                    if c.budget.scan<1 then return 'Running' end c.budget.scan=c.budget.scan-1
                    local done
                    target,done=routing:step(1)
                    if not done then return 'Running' end
                    if not target then c.reason='RETURN_TARGET_UNAVAILABLE' return 'Failure' end
                end
                endpoint=target or endpoint
                if not endpoint then c.reason='RETURN_TARGET_UNAVAILABLE' return 'Failure' end
                if not tree then
                    c.payload.destinations=c.payload.destinations or {} c.payload.destinations[key]=endpoint.id
                    if not c.persist() then return 'Failure' end
                end
                if not tree then tree=assert(require('EmberRoutesProbe/BehaviorTree').new({kind='Sequence',children={
                    move(c,endpoint,preview and preview.item==item and preview.point),
                    transfer(c,item,container,endpoint.container,endpoint,'RETURN')}})) end
                local state=require('EmberRoutesProbe/BehaviorTree').tick(tree,c,c.budget)
                if state~='Success' then return state end
                index=index+1 tree=nil routing=nil target=nil
            end
        end
        c.obligations={}
        return c.persist() and 'Success' or 'Failure'
    end,halt=function()
        return not tree or require('EmberRoutesProbe/BehaviorTree').halt(tree,c)
    end}
end
-- Stop only classifies actual custody; it never replays a transfer or destroys
-- originals. The saved return obligation survives unavailable destinations.
function Custody.observe(c)
    local fact=c.payload.transfer
    if not fact then return c.effects~='UNKNOWN' end
    local item=c.items[fact.itemId]
    local source=c.payload.sourceId and Registry.resolve(c.payload.sourceId,'take','local-world')
    local destination=c.payload.destinations and c.payload.destinations[tostring(fact.itemId)]
    local target=destination and Registry.resolve(destination,'put','local-world')
    local container=item and item:getContainer()
    if not item or not container or container~=c.npc:getInventory()
        and container~=(source and source.container) and container~=(target and target.container)
        and container~=c.origin then c.effects='UNKNOWN' end
    c.payload.transfer=nil
    return c.persist()
end
return Custody
