local Custody=require 'EmberRoutesProbe/Field/ToolCustody'
-- Tool return service: executes independent tool return jobs under TaskRuntime.
-- Ensures that tools held in worker inventory are safely returned to warehouse storage.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Store=require 'EmberRoutesProbe/Work/LaborStore'
local Driver=require 'EmberRoutesProbe/Runtime/Driver'
local Runtime=require 'EmberRoutesProbe/Runtime/TaskRuntime'
local Transfer=require 'EmberRoutesProbe/Work/WorkTransfer'
local TransferDuration=require 'EmberRoutesProbe/Work/TransferDuration'
local Record=require 'EmberRoutesProbe/Field/ToolReturnRecord'
local CraftSupply=require 'EmberRoutesProbe/Crafting/CraftSupply'
local Signals=require 'EmberRoutesProbe/Work/LaborSignals'
local Stop=require 'EmberRoutesProbe/Runtime/TaskBusinessStop'
local Clock = require 'EmberRoutesProbe/Kernel/Clock'
require 'TimedActions/ISInventoryTransferAction'

local Service={}
local live={}
local tracked={}
local resultSequence=0
local world
local function currentWorld()
    local root=Registry.data()
    if world~=root then world,live,tracked=root,{},{} end
    return root
end
function Service.returnResult(jobId) currentWorld() return tracked[jobId] end
function Service.forgetResult(jobId) currentWorld() tracked[jobId]=nil end
local function stoppedResult(task)
    local result=tracked[task.returnJobId]
    if result and result.world==task.world and result.sequence==task.resultSequence then
        result.knownStopped=task.knownStopped==true result.state=task.record.state
    end
end

function Service.liveTask(npcId)
    currentWorld()
    return live[tostring(npcId)]
end

function Service.canInterrupt(npcId)
    currentWorld()
    local task=live[tostring(npcId)]
    if not task then return false end
    return not task.stopping and not task.committed and not task.finished and not task.failed
        and not task.recoveryOnly
end

function Service.interrupt(npcId,reason)
    npcId=tostring(npcId)
    if not Service.canInterrupt(npcId) then return false,'CANNOT_INTERRUPT' end
    local task=live[npcId]
    local runtime=Runtime.current()
    if not runtime then return false,'RUNTIME_NOT_ACCEPTING' end
    local before=runtime:status(npcId,task.returnJobId)
    local ok,why=runtime:stopJob(npcId,task.returnJobId,reason or 'TOOL_RETURN_INTERRUPTED')
    -- A cancelled pending request never received a body or dispatched an action.
    if ok and before and before.pending and not task.body then
        if not Custody.abortReturn(task.custodyId,task.returnJobId,task.npc,task.item) then return false,'CUSTODY_CHANGED' end
        task.record.state='CANCELLED' task.stopPersisted=true
        task.knownStopped=true
        stoppedResult(task)
        live[npcId]=nil Signals.changed(npcId)
    end
    return ok,why
end

local function findDestination(actor,npc,scopeId,item,sourceContainerId)
    if sourceContainerId then
        local endpoint=Registry.resolve(sourceContainerId,'put','local-world')
        if endpoint and endpoint.container and Registry.revalidate(endpoint,'put','local-world')
            and Registry.logistics(endpoint)=='STORAGE' and Registry.accepts(endpoint,item) and endpoint.container:hasRoomFor(npc,item) then
            return endpoint
        end
    end
    if CraftSupply and CraftSupply.returnRoute then
        local route=CraftSupply.returnRoute(actor,npc,scopeId,item,function(endpoint)
            return Registry.logistics(endpoint)=='STORAGE' and Registry.accepts(endpoint,item) and endpoint.container:hasRoomFor(npc,item)
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
            if ep and ep.container and Registry.revalidate(ep,'put','local-world') and Registry.logistics(ep)=='STORAGE'
                and Registry.accepts(ep,item) and ep.container:hasRoomFor(npc,item) then
                return ep
            end
        end
    end
    return nil
end

function Service.startFor(actor,npcId,custodyId,returnJobId,scopeId,options)
    npcId=tostring(npcId)
    Service.reconcile()
    if live[npcId] then return false,'ALREADY_RETURNING' end
    local custody=nil
    local list=Custody.forNpc(npcId)
    for _,c in ipairs(list) do
        if c.id==custodyId then custody=c break end
    end
    if not custody then return false,'CUSTODY_NOT_FOUND' end
    local recovering=custody.state=='PENDING_RETURN' or custody.state=='RECONCILE_REQUIRED' and custody.returnIntent~=nil
    if recovering and (custody.returnJobId~=returnJobId or not custody.returnIntent) then
        Custody.reconcile(custody.id,'RETURN_INTENT_REQUIRED')
        return false,'RETURN_INTENT_REQUIRED'
    end

    local binding=Driver.bindId(actor,npcId)
    if not binding or not Driver.valid(binding) then return false,'BINDING_INVALID' end
    local npc=binding.handle
    if npc:isDead() or (actor and actor:isDead()) then return false,'CARRIER_UNAVAILABLE' end

    local inv=npc:getInventory()
    local item=inv:getFirstEvalRecurse(function(i) return i:getID()==custody.itemId end)
    if not item and not recovering then return false,'ITEM_NOT_IN_INVENTORY' end
    local endpoint,destinationId
    if recovering then
        scopeId=custody.returnIntent.scopeId
        destinationId=custody.returnIntent.destinationId
        endpoint=Registry.resolve(destinationId,'put','local-world')
        if item and item:getContainer()==inv and (not endpoint or not endpoint.container
            or not Registry.revalidate(endpoint,'put','local-world')) then
            return false,'DESTINATION_NOT_AVAILABLE'
        end
        if endpoint and endpoint.container and not item then
            local list=endpoint.container:getItems()
            if list:size()<=512 then
                for i=0,list:size()-1 do
                    local candidate=list:get(i)
                    if candidate:getID()==custody.itemId then item=candidate break end
                end
            end
        end
    else
        endpoint=findDestination(actor,npc,scopeId or 'local-world',item,custody.sourceContainerId)
        if not endpoint or not endpoint.container then return false,'DESTINATION_NOT_AVAILABLE' end
        destinationId=endpoint.id
        local ok,err=Custody.assignReturn(custodyId,returnJobId,
            {format=1,jobId=returnJobId,destinationId=endpoint.id,scopeId=scopeId or 'local-world'},npc,item)
        if not ok then return false,err,not require('EmberRoutesProbe/Kernel/CommitFence').status() end
    end

    local record={
        format=1,
        id=returnJobId,
        npcId=npcId,
        custodyId=custodyId,
        itemId=custody.itemId,
        role=custody.role,
        phase='APPROACH',
        destinationId=destinationId,
        state='RUNNING',
        sequence=1
    }
    if not Record.valid(record) then
        if not recovering and not Custody.abortReturn(custodyId,returnJobId,npc,item) then return false,'TOOL_RETURN_ROLLBACK_UNCONFIRMED',false end
        return false,'TOOL_RETURN_RECORD_INVALID'
    end

    local task={
        world=Registry.data(),
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
    -- A pending return with its exact original still in the root inventory
    -- can resume the same intent. UNKNOWN outcomes remain observation-only.
    task.recoveryOnly=recovering and not (custody.state=='PENDING_RETURN' and item
        and item:getContainer()==inv and inv:getItems():contains(item))
    task.itemId=custody.itemId

    local runtime=Runtime.current()
    if not runtime or not runtime:accepting() then
        if not recovering and not Custody.abortReturn(custodyId,returnJobId,npc,item) then return false,'TOOL_RETURN_ROLLBACK_UNCONFIRMED',false end
        return false,'RUNTIME_NOT_ACCEPTING'
    end

    local function arrived()
        return task.item and task.endpoint and task.endpoint.container
            and Registry.revalidate(task.endpoint,'put','local-world') and Registry.logistics(task.endpoint)=='STORAGE'
            and task.item:getContainer()==task.endpoint.container
            and task.endpoint.container:getItems():contains(task.item)
    end
    local function retained()
        return task.item and task.item:getContainer()==inv and inv:getItems():contains(task.item)
    end
    local function transferAllowed()
        local owner=Store.resourceOwner('item:'..task.itemId)
        local c=Custody.byItem(task.itemId)
        return task.world==Registry.data() and not task.stopping and retained()
            and c and c.id==task.custodyId and c.returnJobId==task.returnJobId and c.state=='PENDING_RETURN'
            and owner and owner.taskId==task.custodyId
            and task.endpoint and Registry.revalidate(task.endpoint,'put','local-world')
            and Registry.logistics(task.endpoint)=='STORAGE' and Registry.accepts(task.endpoint,task.item)
            and Transfer.reachable(npc,task.endpoint) and task.endpoint.container:hasRoomFor(npc,task.item)
    end
    local function persistStopped(fact)
        if task.stopPersisted then return true end
        if not fact or fact.bodyStopped~=true then return false end
        if task.world~=Registry.data() then return false end
        local custodyNow=Custody.byItem(task.itemId)
        if arrived() then
            if not Custody.completeReturn(task.custodyId,task.returnJobId,task.endpoint.id,task.item) then return false end
            task.finished=true task.record.state='DONE' task.record.phase='SETTLED'
            task.knownStopped=true
        elseif retained() and task.stopReason=='SAVE' then
            -- Save is a pause, not evidence that the return obligation ended.
            task.record.state='PAUSED'
        elseif retained() then
            if not Custody.abortReturn(task.custodyId,task.returnJobId,task.npc,task.item) then return false end
            task.record.state='CANCELLED'
            task.knownStopped=true
        else
            -- An absent original is not evidence of return. Keep custody for reconciliation.
            task.record.state='FAILED'
            if custodyNow and custodyNow.id==task.custodyId then custodyNow.state='RECONCILE_REQUIRED' end
        end
        task.stopPersisted=true
        stoppedResult(task)
        if live[npcId]==task then live[npcId]=nil end
        Signals.changed(npcId)
        return true
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
            if task.stopping or task.finished or task.failed then return end
            if task.recoveryOnly then task.finished=true return end -- Observation only; never repeat the transfer.
            if npc:isDead() or (actor and actor:isDead()) then
                task.failed=true
                if npc:isDead() then
                    local _,reason=Custody.retainOnDeath(npcId)
                    task.record.reason=reason
                end
                return
            end

            if task.phase=='APPROACH' then
                if not task.endpoint or not Registry.revalidate(task.endpoint,'put','local-world') then
                    task.failed=true task.record.reason='DESTINATION_NOT_AVAILABLE' return
                end
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
                    if not transferAllowed() then task.failed=true return end
                    task.committed=true
                    -- Native and Lua paths share one duration source:
                    -- the Lua action computes the vanilla formula itself,
                    -- the native presentation asks TransferDuration for it.
                    if EmberRoutesProbeJava and EmberRoutesProbeJava.nativeActionStart then
                        task.action='NATIVE'
                        task.startedAt=Clock.nowMs()
                        EmberRoutesProbeJava.nativeActionStart(npc,"Loot",TransferDuration.forTransfer(npc,task.item,inv,task.endpoint.container),true)
                    else
                        task.action=ISInventoryTransferAction:new(npc,task.item,inv,task.endpoint.container)
                        local action=task.action local valid,transfer=action.isValid,action.transferItem
                        action.isValid=function(self) return transferAllowed() and valid(self) end
                        action.transferItem=function(self,item)
                            if item~=task.item or not transferAllowed() then return false end
                            return transfer(self,item)
                        end
                        action.canMergeAction=function() return false end
                        action.checkQueueList=function() end
                        local ok,why=task.body.add(task.action)
                        if not ok then
                            task.failed=true
                            task.record.state='FAILED'
                            Signals.changed(npcId)
                        end
                    end
                    return
                end

                if task.action=='NATIVE' then
                    if not transferAllowed() then
                        if EmberRoutesProbeJava and EmberRoutesProbeJava.nativeActionStop then
                            EmberRoutesProbeJava.nativeActionStop(npc)
                        end
                        task.failed=true
                        task.record.state='FAILED'
                        Signals.changed(npcId)
                        return
                    end
                    if EmberRoutesProbeJava and EmberRoutesProbeJava.nativeActionFinished and EmberRoutesProbeJava.nativeActionFinished(npc) then
                        inv:DoRemoveItem(task.item)
                        task.endpoint.container:AddItem(task.item)
                        Registry.inventoryChanged(inv)
                        Registry.inventoryChanged(task.endpoint.container)
                        task.phase='SETTLED' task.finished=true
                        task.record.phase='SETTLED'
                        Signals.changed(npcId)
                    end
                    return
                end

                -- Action observation: verify physical presence in container
                if task.item:getContainer()==task.endpoint.container
                    and task.endpoint.container:getItems():contains(task.item) then
                    -- Settlement waits for the same physical-stop receipt as interruption.
                    task.phase='SETTLED' task.finished=true
                    task.record.phase='SETTLED'
                    Signals.changed(npcId)
                    return
                end

                -- If action is no longer queued/running but item didn't make it to destination
                local q=ISTimedActionQueue.queues and ISTimedActionQueue.queues[npc]
                local isRunning=q and (q.current==task.action or (q.queue and #q.queue>0))
                if not isRunning then
                    -- Timed action finished or got aborted without physical arrival
                    task.failed=true
                    task.record.state='FAILED'
                    Signals.changed(npcId)
                end
            end
        end,
        validate=function()
            if npc:isDead() or (actor and actor:isDead()) then return false end
            local c=Custody.byItem(custody.itemId)
            return c and c.id==custodyId and c.returnJobId==returnJobId
                and (c.state=='PENDING_RETURN' or task.recoveryOnly and c.state=='RECONCILE_REQUIRED')
        end,
        finished=function()
            return task.finished or task.failed
        end,
        stopAdapter=function(controller,ticket)
            return Stop.new({controller=controller,ticket=ticket,npc=npc,npcId=npcId,jobId=returnJobId,
                same=function() return task.world==Registry.data() and (live[npcId]==task or task.stopPersisted==true) end,
                pause=function(reason)
                    task.stopReason=reason
                    task.stopping=true
                    if task.action=='NATIVE' and EmberRoutesProbeJava and EmberRoutesProbeJava.nativeActionStop then
                        EmberRoutesProbeJava.nativeActionStop(npc)
                    end
                    return task.body.clear()
                end,
                effects=function() return (arrived() or retained()) and 'KNOWN' or 'UNKNOWN' end,
                persist=persistStopped})
        end,
        persistFailure=persistStopped
    }

    local handle=runtime:submit(spec)
    if not handle then
        if not recovering and not Custody.abortReturn(custodyId,returnJobId,npc,item) then return false,'TOOL_RETURN_ROLLBACK_UNCONFIRMED',false end
        return false,'SUBMIT_FAILED'
    end

    task.handle=handle
    live[npcId]=task
    if options and options.trackResult or tracked[returnJobId] then
        resultSequence=resultSequence+1 task.resultSequence=resultSequence
        tracked[returnJobId]={world=task.world,sequence=resultSequence,knownStopped=false}
    end
    return true,returnJobId
end

-- Pending requests may be rejected/cancelled by runtime admission or the save barrier.
-- Only their terminal handle plus absence of a body grant permits cancellation cleanup.
function Service.reconcile()
    currentWorld()
    local runtime=Runtime.current()
    local world=Registry.data()
    for id,task in pairs(live) do
        if task.world~=world then
            live[id]=nil -- World-local cache only; never touch another world's custody.
        elseif not task.body and runtime then
            local result=runtime:inspect(task.handle)
            if result and (result.state=='CANCELLED' or result.state=='REJECTED')
                and (task.recoveryOnly or Custody.abortReturn(task.custodyId,task.returnJobId,task.npc,task.item)) then
                task.record.state='CANCELLED' task.stopPersisted=true
                task.knownStopped=not task.recoveryOnly
                stoppedResult(task)
                live[id]=nil Signals.changed(id)
            end
        end
    end
end

function Service.recoverFor(actor,npcId)
    Service.reconcile()
    npcId=tostring(npcId)
    if live[npcId] then return false,'ALREADY_RETURNING' end
    local list=Custody.forNpc(npcId)
    for _,c in ipairs(list) do
        if (c.state=='PENDING_RETURN' or c.state=='RECONCILE_REQUIRED') and c.returnJobId then
            return Service.startFor(actor,npcId,c.id,c.returnJobId,nil)
        end
        if c.state=='HELD' and not c.activeJobId and not c.returnJobId then
            local returnJobId=Registry.id()
            return Service.startFor(actor,npcId,c.id,returnJobId,nil)
        end
    end
    return false,'NO_HELD_CUSTODY'
end

return Service
