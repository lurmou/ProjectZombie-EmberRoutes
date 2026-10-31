-- Tool return service: executes independent tool return jobs under TaskRuntime.
-- Ensures that tools held in worker inventory are safely returned to warehouse storage.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Store=require 'EmberRoutesProbe/LaborStore'
local Driver=require 'EmberRoutesProbe/Driver'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Transfer=require 'EmberRoutesProbe/WorkTransfer'
local Record=require 'EmberRoutesProbe/ToolReturnRecord'
local CraftSupply=require 'EmberRoutesProbe/CraftSupply'
local Signals=require 'EmberRoutesProbe/LaborSignals'

local Service={}
local live={}

function Service.liveTask(npcId)
    return live[tostring(npcId)]
end

function Service.canInterrupt(npcId)
    local task=live[tostring(npcId)]
    if not task then return false end
    return not task.committed and not task.finished and not task.failed
end

function Service.interrupt(npcId,reason)
    npcId=tostring(npcId)
    if not Service.canInterrupt(npcId) then return false,'CANNOT_INTERRUPT' end
    local task=live[npcId]
    local runtime=Runtime.current()
    if runtime then runtime:stop(npcId,reason or 'TOOL_RETURN_INTERRUPTED') end
    Store.abortToolReturn(task.custodyId,task.returnJobId)
    task.record.state='CANCELLED'
    live[npcId]=nil
    Signals.changed(npcId)
    return true
end

local function findDestination(actor,npc,scopeId,item,sourceContainerId)
    if sourceContainerId then
        local endpoint=Registry.resolve(sourceContainerId,'put','local-world')
        if endpoint and endpoint.container and Registry.revalidate(endpoint,'put','local-world')
            and Registry.logistics(endpoint)=='STORAGE' and endpoint.container:hasRoomFor(npc,item) then
            return endpoint
        end
    end
    if CraftSupply and CraftSupply.returnRoute then
        local route=CraftSupply.returnRoute(actor,npc,scopeId,item,function(endpoint)
            return Registry.logistics(endpoint)=='STORAGE' and endpoint.container:hasRoomFor(npc,item)
        end,{allowOutside=true})
        if route then
            local endpoint,done=route:step(32)
            if done and endpoint then return endpoint end
        end
    end
    -- Fallback: check all registered storage containers
    local data=Registry.data()
    if data and data.containers then
        for cid,_ in pairs(data.containers) do
            local ep=Registry.resolve(cid,'put','local-world')
            if ep and ep.container and Registry.logistics(ep)=='STORAGE' and ep.container:hasRoomFor(npc,item) then
                return ep
            end
        end
    end
    return nil
end

function Service.startFor(actor,npcId,custodyId,returnJobId,scopeId)
    npcId=tostring(npcId)
    local custody=nil
    local list=Store.custodyForNpc(npcId)
    for _,c in ipairs(list) do
        if c.id==custodyId then custody=c break end
    end
    if not custody then return false,'CUSTODY_NOT_FOUND' end

    local binding=Driver.bindId(actor,npcId)
    if not binding or not Driver.valid(binding) then return false,'BINDING_INVALID' end
    local npc=binding.handle
    if npc:isDead() or (actor and actor:isDead()) then return false,'CARRIER_UNAVAILABLE' end

    local inv=npc:getInventory()
    local item=inv:getFirstEvalRecurse(function(i) return i:getID()==custody.itemId end)
    if not item then return false,'ITEM_NOT_IN_INVENTORY' end

    local ok,err=Store.assignToolReturn(custodyId,returnJobId)
    if not ok then return false,err end

    local endpoint=findDestination(actor,npc,scopeId or 'local-world',item,custody.sourceContainerId)
    if not endpoint or not endpoint.container then
        Store.abortToolReturn(custodyId,returnJobId)
        return false,'DESTINATION_NOT_AVAILABLE'
    end

    local record={
        format=1,
        id=returnJobId,
        npcId=npcId,
        custodyId=custodyId,
        itemId=custody.itemId,
        role=custody.role,
        phase='APPROACH',
        destinationId=endpoint.id,
        state='RUNNING',
        sequence=1
    }
    if not Record.valid(record) then
        Store.abortToolReturn(custodyId,returnJobId)
        return false,'TOOL_RETURN_RECORD_INVALID'
    end

    local task={
        actor=actor,
        npc=npc,
        npcId=npcId,
        custodyId=custodyId,
        returnJobId=returnJobId,
        item=item,
        endpoint=endpoint,
        record=record,
        phase='APPROACH',
        committed=false,
        finished=false,
        failed=false,
        body=nil
    }

    local runtime=Runtime.current()
    if not runtime or not runtime:accepting() then
        Store.abortToolReturn(custodyId,returnJobId)
        return false,'RUNTIME_NOT_ACCEPTING'
    end

    local spec={
        npcId=npcId,
        jobId=returnJobId,
        kind='TOOL_RETURN',
        binding=binding,
        nonPreemptive=true,
        start=function(body)
            task.body=body
            return true
        end,
        tick=function()
            if task.finished or task.failed then return end
            if npc:isDead() or (actor and actor:isDead()) then
                task.failed=true
                if npc:isDead() then Store.markNpcCustodiesDead(npcId) end
                return
            end

            if task.phase=='APPROACH' then
                if not Transfer.reachable(npc,task.endpoint) then
                    local p=Transfer.prepareMove({npc=npc},task.endpoint)
                    if p and p.square then
                        task.body.move(actor,{x=p.square:getX()+0.5,y=p.square:getY()+0.5,z=p.square:getZ()})
                    end
                    return
                end
                task.phase='TRANSFER'
                task.record.phase='TRANSFER'
                task.body.stop()
                return
            end

            if task.phase=='TRANSFER' then
                if not task.action then
                    task.committed=true
                    task.action=ISInventoryTransferAction:new(npc,task.item,inv,task.endpoint.container,60)
                    local ok,why=task.body.add(task.action)
                    if not ok then
                        task.failed=true
                        task.record.state='FAILED'
                        live[npcId]=nil
                        Signals.changed(npcId)
                    end
                    return
                end

                -- Action observation: verify physical presence in container
                if task.item:getContainer()==task.endpoint.container
                    and task.endpoint.container:getItems():contains(task.item) then
                    local completeOk=Store.completeCustodyReturn(task.custodyId,task.returnJobId,task.endpoint.id,task.item)
                    if completeOk then
                        task.phase='SETTLED'
                        task.record.phase='SETTLED'
                        task.record.state='DONE'
                        task.finished=true
                        live[npcId]=nil
                        Signals.changed(npcId)
                    else
                        task.failed=true
                        task.record.state='FAILED'
                        live[npcId]=nil
                    end
                    return
                end

                -- If action is no longer queued/running but item didn't make it to destination
                local q=ISTimedActionQueue.queues and ISTimedActionQueue.queues[npc]
                local isRunning=q and (q.current==task.action or (q.queue and #q.queue>0))
                if not isRunning then
                    -- Timed action finished or got aborted without physical arrival
                    task.failed=true
                    task.record.state='FAILED'
                    live[npcId]=nil
                    Signals.changed(npcId)
                end
            end
        end,
        validate=function()
            if npc:isDead() or (actor and actor:isDead()) then return false end
            local c=Store.custodyByItem(custody.itemId)
            return c and c.id==custodyId and c.state=='PENDING_RETURN'
        end,
        finished=function()
            return task.finished or task.failed
        end,
        stopAdapter=function(controller,ticket)
            return {
                requestStop=function(reason)
                    if not task.committed then
                        Store.abortToolReturn(task.custodyId,task.returnJobId)
                        task.record.state='CANCELLED'
                        live[npcId]=nil
                        Signals.changed(npcId)
                        return true
                    end
                    -- If already committed to native transfer, check physical arrival before resetting
                    if task.item:getContainer()==task.endpoint.container
                        and task.endpoint.container:getItems():contains(task.item) then
                        Store.completeCustodyReturn(task.custodyId,task.returnJobId,task.endpoint.id,task.item)
                        task.record.state='DONE'
                    else
                        task.record.state='FAILED'
                    end
                    live[npcId]=nil
                    Signals.changed(npcId)
                    return true
                end,
                observeStop=function()
                    return {bodyStopped=true,effects='KNOWN'}
                end,
                persistEffects=function(fact)
                    return true
                end
            }
        end,
        persistFailure=function(fact,why)
            if not task.committed then
                Store.abortToolReturn(task.custodyId,task.returnJobId)
            end
            live[npcId]=nil
            Signals.changed(npcId)
        end
    }

    local handle=runtime:submit(spec)
    if not handle then
        Store.abortToolReturn(custodyId,returnJobId)
        return false,'SUBMIT_FAILED'
    end

    live[npcId]=task
    return true,returnJobId
end

function Service.recoverFor(actor,npcId)
    npcId=tostring(npcId)
    if live[npcId] then return false,'ALREADY_RETURNING' end
    local list=Store.custodyForNpc(npcId)
    for _,c in ipairs(list) do
        if c.state=='HELD' and not c.activeJobId and not c.returnJobId then
            local returnJobId=Registry.id()
            return Service.startFor(actor,npcId,c.id,returnJobId,nil)
        end
    end
    return false,'NO_HELD_CUSTODY'
end

function Service.reset()
    live={}
end

return Service
