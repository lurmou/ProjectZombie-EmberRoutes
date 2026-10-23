-- World-local admission and execution loop. No task selection or asset ledger.
local Controller=require 'EmberRoutesProbe/TaskController'
local Schedule=require 'EmberRoutesProbe/LaborSchedule'
local Driver=require 'EmberRoutesProbe/Driver'
local Runtime={}
local Signals=require 'EmberRoutesProbe/LaborSignals'
local function luaStopped(binding)
    local queues=ISTimedActionQueue and ISTimedActionQueue.queues
    if type(queues)~='table' then return false end
    local queue=queues[binding.handle]
    return not queue or (type(queue.queue)=='table' and #queue.queue==0 and queue.current==nil)
end

function Runtime.new()
    local controller=Controller.new()
    local schedule=Schedule.new()
    local current,pending={},{}
    local count=0
    local processing,frozen,retired=false,false,false
    local api={}
    local function result(r,state,reason)
        local previous=r.handle.result
        r.handle.result={npcId=r.spec.npcId,jobId=r.spec.jobId,kind=r.spec.kind,state=state,reason=reason,error=r.error}
        if not previous or previous.state~=state or previous.reason~=reason then Signals.changed(r.spec.npcId) end
    end
    local function remove(id)
        if current[id] or pending[id] then return end
        schedule:remove(id) count=count-1
    end
    local function observe(r)
        local native=r.body.snapshot()
        return {bodyStopped=native.available and native.nativeStopped and luaStopped(r.spec.binding) or false,
            effects=r.unchanged and 'KNOWN' or 'UNKNOWN'}
    end
    local function adapter(r)
        return {
            requestStop=function(reason)
                if not r.attached then return true end -- No body grant or business call occurred.
                if r.started then
                    if not r.stop then r.stop=assert(r.spec.stopAdapter(controller,function() return r.ticket end)) end
                    return r.stop.requestStop(reason)
                end
                -- A failed start may have had effects. Never retry it automatically.
                if not r.body.clear() then return false end
                return r.body.stop()
            end,
            observeStop=function()
                if not r.attached then return {bodyStopped=true,effects='KNOWN'} end
                if r.started then
                    local fact=r.stop.observeStop()
                    -- Opt in only when the business verifies originals/commit
                    -- facts itself; an exception is never a generic rollback.
                    if r.error and not r.spec.reconcileErrors and type(fact)=='table' then fact.effects='UNKNOWN' end
                    return fact
                end
                return observe(r)
            end,
            persistEffects=function(fact)
                if not r.attached then return true end
                if r.started and r.stop.persistEffects(fact)~=true then return false end
                if not r.started or r.error then return r.spec.persistFailure(fact,r.error)==true end
                return true
            end,
        }
    end
    function api:submit(spec)
        if retired or frozen then return nil,'ADMISSION_CLOSED' end
        if processing then return nil,'REENTRANT_REQUEST' end
        if type(spec)~='table' or type(spec.npcId)~='string' or spec.npcId==''
            or type(spec.jobId)~='string' or spec.jobId=='' or type(spec.kind)~='string' or spec.kind==''
            or type(spec.binding)~='table' or spec.binding.id~=spec.npcId
            or type(spec.start)~='function' or type(spec.stopAdapter)~='function'
            or type(spec.persistFailure)~='function' or type(spec.validate)~='function'
            or type(spec.tick)~='function' or type(spec.finished)~='function' then return nil,'START_SPEC_REQUIRED' end
        local id=spec.npcId
        if pending[id] then return nil,'REQUEST_PENDING' end
        if current[id] and spec.nonPreemptive then return nil,'NPC_BUSY' end
        -- Reject an invalid replacement before interrupting useful current work.
        -- Providers evaluate conditions only; nested admission stays fenced.
        processing=true
        local valid,accepted=pcall(function() return spec.validate()==true and Driver.valid(spec.binding) end)
        processing=false
        if not valid or accepted~=true then return nil,'CANDIDATE_CHANGED' end
        if retired or frozen then return nil,'ADMISSION_CLOSED' end
        if not current[id] then
            if count>=256 then return nil,'RUNTIME_LIMIT' end
            count=count+1 schedule:add(id)
        end
        -- Copy the request shape; callers cannot replace callbacks/identity later.
        local copy={} for key,value in pairs(spec) do copy[key]=value end
        copy.binding={id=spec.binding.id,handle=spec.binding.handle}
        local r={spec=copy,handle={}}
        pending[id]=r result(r,'PENDING')
        if current[id] then controller:requestStop(current[id].ticket,'REPLACED') end
        return r.handle
    end
    function api:inspect(handle)
        local value=type(handle)=='table' and handle.result
        if not value then return nil end
        local copy={} for key,item in pairs(value) do copy[key]=item end return copy
    end
    function api:stop(id,reason)
        if type(reason)~='string' or reason=='' then return false,'REASON_REQUIRED' end
        local p=pending[id]
        if p then result(p,'CANCELLED',reason) pending[id]=nil end
        local r=current[id]
        if r then return controller:requestStop(r.ticket,reason) end
        if p then remove(id) return true end
        return false,'NO_CURRENT_TASK'
    end
    function api:owns(id) return current[id]~=nil or pending[id]~=nil end
    function api:accepting() return not retired and not frozen and not processing end
    function api:status(id,jobId)
        local r=current[id]
        if not r or jobId and r.spec.jobId~=jobId then r=pending[id] end
        if not r or jobId and r.spec.jobId~=jobId then return nil end
        local state=r.ticket and controller:inspect(r.ticket) or r.handle.result
        return {jobId=r.spec.jobId,kind=r.spec.kind,state=state and state.state or 'PENDING'}
    end
    function api:stopJob(id,jobId,reason)
        if type(reason)~='string' or reason=='' then return false,'REASON_REQUIRED' end
        local p=pending[id]
        if p and p.spec.jobId==jobId then result(p,'CANCELLED',reason) pending[id]=nil end
        local r=current[id]
        if r and r.spec.jobId==jobId then return controller:requestStop(r.ticket,reason) end
        if p and p.spec.jobId==jobId then remove(id) return true end
        return false,'STALE_JOB'
    end
    local function advance(id)
        local r=current[id]
        if r then
            local state=controller:inspect(r.ticket)
            if state.state=='CLOSED' or state.state=='CANCELLED' then
                result(r,state.state,state.reason) current[id]=nil
                -- Never start the successor inside the old cleanup/closing turn.
                remove(id) return
            end
            if state.state~='ACTIVE' or frozen or retired then
                r.error=r.error or state.error result(r,state.state,state.reason) return
            end
            if not r.attached then
                local valid,accepted=pcall(r.spec.validate)
                if not valid or accepted~=true then
                    controller:requestStop(r.ticket,'CANDIDATE_CHANGED') return
                end
                if not luaStopped(r.spec.binding) then
                    r.error='LUA_QUEUE_NOT_STOPPED' controller:requestStop(r.ticket,'CONTROL_DENIED') return
                end
                local ok,why=controller:attachDriver(r.ticket,r.spec.binding)
                if not ok then r.error=why controller:requestStop(r.ticket,'CONTROL_DENIED') return end
                r.attached=true r.body=controller:body(r.ticket)
                local success,accepted,reason,effects=pcall(r.spec.start,r.body)
                r.unchanged=success and accepted==false and effects=='UNCHANGED'
                -- Labor keeps the adapter while its context is live. Completion
                -- may remove that context before the runtime requests final stop.
                if r.spec.captureStop then
                    local captured,stop=pcall(r.spec.stopAdapter,controller,function() return r.ticket end)
                    if captured and stop then r.stop=stop r.started=true end
                end
                if not success or accepted~=true then
                    r.error=tostring(success and (reason or 'START_REJECTED') or accepted)
                    controller:requestStop(r.ticket,'START_FAILED') return
                end
                if r.spec.captureStop and not r.stop then
                    r.error='STOP_ADAPTER_REQUIRED' controller:requestStop(r.ticket,'START_FAILED') return
                end
                r.started=true result(r,'ACTIVE') return
            end
            local ok,err=pcall(r.spec.tick,r.body)
            if ok then
                local completed,done=pcall(r.spec.finished)
                if not completed then ok=false err=done
                elseif done==true then controller:requestStop(r.ticket,'COMPLETED') end
            end
            if not ok then r.error=tostring(err) controller:requestStop(r.ticket,'EXECUTION_ERROR') end
            result(r,controller:inspect(r.ticket).state)
            return
        end
        local p=pending[id]
        if not p or frozen or retired then return end
        local valid,accepted=pcall(p.spec.validate)
        if not valid or accepted~=true or not Driver.valid(p.spec.binding) then
            result(p,'REJECTED','CANDIDATE_CHANGED') pending[id]=nil remove(id) return
        end
        local ticket,why=controller:request(id,p.spec.jobId,p.spec.kind,adapter(p))
        if not ticket then
            result(p,'REJECTED',why) pending[id]=nil remove(id) return
        end
        pending[id]=nil current[id]=p p.ticket=ticket result(p,'QUEUED')
    end
    function api:step()
        if processing then return false,'CALL_IN_FLIGHT' end
        processing=true
        controller:step()
        schedule:step(4,function(id)
            local ok,err=pcall(advance,id)
            if not ok then
                local r=current[id] or pending[id]
                if r then
                    r.error=tostring(err)
                    if r.ticket then controller:requestStop(r.ticket,'RUNTIME_ERROR')
                    else result(r,'REJECTED','RUNTIME_ERROR') pending[id]=nil remove(id) end
                end
            end
        end)
        processing=false
        return true
    end
    function api:beginSave()
        if retired or frozen then return false,'ADMISSION_CLOSED' end
        frozen=true
        -- Snapshot IDs: stop() may remove schedule entries.
        local ids={} for id in pairs(pending) do ids[#ids+1]=id end
        for _,id in ipairs(ids) do self:stop(id,'SAVE') end
        return controller:beginSave()
    end
    function api:finishSave(success)
        local ok,why=controller:finishSave(success)
        if ok then
            -- Reclaim terminal owners before recovery candidates are admitted.
            -- No successor is started in this call.
            local ids={}
            for id,r in pairs(current) do
                local state=controller:inspect(r.ticket)
                if state.state=='CLOSED' or state.state=='CANCELLED' then
                    result(r,state.state,state.reason) ids[#ids+1]=id
                end
            end
            for _,id in ipairs(ids) do current[id]=nil remove(id) end
            frozen=false
        end return ok,why
    end
    function api:captureSave()
        if not frozen or retired or processing then return nil,'NO_LIVE_BARRIER' end
        processing=true
        local facts,why=controller:captureSave()
        if facts then
            for id,r in pairs(current) do
                local fact=facts.byNpc[id]
                if fact and not fact.bodyStopped then
                    -- Keep scalar/original-ID business obligations even if stop
                    -- failed before its adapter could pause. Never replay start.
                    pcall(r.spec.persistFailure,{bodyStopped=false,effects='UNKNOWN'},'SAVE_STOP_UNCONFIRMED')
                end
            end
        end
        processing=false
        return facts,why
    end
    function api:retire(detachedWorld)
        retired=true frozen=true
        local ids={} for id in pairs(pending) do ids[#ids+1]=id end
        for _,id in ipairs(ids) do self:stop(id,'WORLD_RETIRED') end
        return controller:retire(detachedWorld)
    end
    return api
end

-- P1 enables all business/save entrances together. No live player toggle:
-- switching only Companion would strand managed NPCs in legacy work.
local world,service,blocked
function Runtime.current()
    local Probe=require 'EmberRoutesProbe/Boot'
    if blocked or Probe.controlledExecution~=true or not Probe.ready
        or Probe.runtimeReady==false or Probe.enabled==false then return nil end
    local root=require('EmberRoutesProbe/ContainerRegistry').data()
    if root~=world then
        if service then service:retire(true) end
        world,service=root,Runtime.new()
    end
    return service
end
function Runtime.tick()
    local active=Runtime.current()
    if active then active:step() end
end
function Runtime.reset()
    if service then service:retire() end
    world,service,blocked=nil,nil,true
end
function Runtime.begin()
    blocked=false
end
return Runtime
