-- Runtime service factory. No event registration, native calls or asset authority.
local Sessions=require 'EmberRoutesProbe/ExecutionSessions'
local Evidence=require 'EmberRoutesProbe/TaskStopEvidence'
local Controller={}
function Controller.new()
    local sessions=Sessions.new()
    local records,byNpc,queue={},{},{}
    local cursor=0
    local stepping,calling,frozen,retired=false,false,false,false
    local barrier,saveFacts
    local nativeBarrier=false
    local api={}
    local Driver
    local function driver()
        Driver=Driver or require 'EmberRoutesProbe/Driver'
        return Driver
    end
    local function live(ticket)
        local r=records[ticket]
        if r and byNpc[r.npcId]==r then return r end
    end
    local function close(r,state)
        r.state=state byNpc[r.npcId]=nil
        -- Tickets retain their own final summary; no unbounded controller history.
        records[r.ticket]=nil
        r.ticket.result={state=state,reason=r.reason}
    end
    function api:inspect(ticket)
        local r=live(ticket)
        if r then return {state=r.state,reason=r.reason,error=r.error,npcId=r.npcId,jobId=r.jobId,kind=r.kind} end
        local result=type(ticket)=='table' and ticket.result
        if result then return {state=result.state,reason=result.reason} end
    end
    function api:request(npcId,jobId,kind,adapter)
        if retired or frozen then return nil,'ADMISSION_CLOSED' end
        if calling or stepping then return nil,'REENTRANT_REQUEST' end
        if type(npcId)~='string' or npcId=='' or type(jobId)~='string' or jobId==''
            or type(kind)~='string' or kind=='' then return nil,'IDENTITY_REQUIRED' end
        if type(adapter)~='table' or type(adapter.requestStop)~='function'
            or type(adapter.observeStop)~='function' or type(adapter.persistEffects)~='function' then
            return nil,'ADAPTER_REQUIRED'
        end
        if byNpc[npcId] then return nil,'NPC_BUSY' end
        if #queue>=256 then return nil,'CONTROLLER_LIMIT' end
        local ticket={}
        local r={ticket=ticket,npcId=npcId,jobId=jobId,kind=kind,adapter=adapter,state='QUEUED'}
        records[ticket]=r byNpc[npcId]=r queue[#queue+1]=r
        return ticket
    end
    function api:requestStop(ticket,reason)
        local r=live(ticket)
        if not r then return false,'STALE_TICKET' end
        if type(reason)~='string' or reason=='' then return false,'REASON_REQUIRED' end
        r.reason=r.reason or reason
        if r.state=='QUEUED' then close(r,'CANCELLED') return true end
        r.state='STOPPING'
        return sessions:requestStop(r.token,r.reason)
    end
    function api:attachDriver(ticket,binding)
        local r=live(ticket)
        if frozen or retired or calling or stepping or not r or r.state~='ACTIVE' then return false,'NOT_AUTHORIZED' end
        if not binding or binding.id~=r.npcId then return false,'WRONG_NPC' end
        if r.control then return false,'CONTROL_ATTACHED' end
        local session=sessions:inspect(r.npcId)
        local control,why=driver().acquireControl(binding,r.jobId,session.generation)
        if not control then return false,why end
        r.control=control return true
    end
    function api:move(ticket,actor,point)
        local r=live(ticket)
        if not r or not r.control then return false,'CONTROL_REQUIRED' end
        return self:dispatch(ticket,function() return driver().moveControlled(r.control,actor,point) end)
    end
    function api:stopBody(ticket)
        local r=live(ticket)
        if calling or not r or not r.control or r.state~='STOPPING' then return false end
        return driver().stopControlled(r.control)
    end
    function api:bodySnapshot(ticket)
        local r=live(ticket)
        if not r or not r.control or calling then return {available=false} end
        return driver().stopEvidence(r.control)
    end
    function api:dispatch(ticket,callback)
        local r=live(ticket)
        if retired or frozen or calling or stepping or not r or r.state~='ACTIVE' then
            return false,'NOT_AUTHORIZED'
        end
        calling=true
        local ok,value,detail=sessions:dispatch(r.token,callback)
        calling=false
        if not ok and value=='DISPATCH_ERROR' then self:requestStop(ticket,'DISPATCH_ERROR') end
        return ok,value,detail
    end
    -- The business keeps this capability, never a native key. Every call rechecks
    -- this exact ticket; a late closure cannot borrow the successor's authority.
    function api:body(ticket)
        local r=live(ticket)
        if not r or not r.control then return nil end
        if r.body then return r.body end
        local body={}
        function body.current()
            return not retired and not frozen and live(ticket)==r and r.state=='ACTIVE' and r.control~=nil
        end
        function body.retained()
            return live(ticket)==r and r.control~=nil and driver().stopEvidence(r.control).available or false
        end
        function body.requestStop(reason) return api:requestStop(ticket,reason) end
        function body.move(actor,point) return api:move(ticket,actor,point) end
        function body.stop()
            if r.state=='STOPPING' then return api:stopBody(ticket) end
            local ok,result=api:dispatch(ticket,function() return driver().stopControlled(r.control) end)
            return ok and result==true
        end
        function body.add(action)
            if live(ticket)~=r or not r.control then return false,'NOT_AUTHORIZED' end
            if not action or action.character~=r.control.binding.handle then return false,'WRONG_NPC' end
            local ok,result=api:dispatch(ticket,function()
                if not driver().stopEvidence(r.control).available then return false end
                ISTimedActionQueue.add(action) return true
            end)
            return ok and result==true,result
        end
        function body.clear()
            if live(ticket)~=r or not r.control or calling then return false,'NOT_AUTHORIZED' end
            local function clear()
                if not driver().stopEvidence(r.control).available then return false end
                local npc=r.control.binding.handle
                ISTimedActionQueue.clear(npc)
                -- Vanilla clearQueue wipes the array but may retain `current`.
                -- Clean only that empty owned queue; native stop is verified later.
                local queue=ISTimedActionQueue.queues and ISTimedActionQueue.queues[npc]
                if queue and type(queue.queue)=='table' and #queue.queue==0 then queue.current=nil end
                return true
            end
            if r.state~='STOPPING' then
                local ok,result=api:dispatch(ticket,clear)
                return ok and result==true,result
            end
            -- STOPPING may clean its own queue while step runs its adapter. Fence
            -- synchronous stop callbacks until clear has unwound completely.
            calling=true
            local ok,result=pcall(clear)
            calling=false
            if not ok then r.error=tostring(result) return false,'CLEANUP_ERROR' end
            return result==true
        end
        function body.snapshot() return api:bodySnapshot(ticket) end
        r.body=body
        return body
    end
    local function stopOnce(r)
        if not r.stopRequested then
            local ok,err=pcall(r.adapter.requestStop,r.reason)
            if ok and err~=false then r.stopRequested=true else r.error=tostring(err) end
        end
        if r.stopRequested then
            local ok,value=pcall(r.adapter.observeStop)
            if ok and type(value)=='table' and value.bodyStopped==true
                and (value.effects=='KNOWN' or value.effects=='UNKNOWN') then
                -- Pass a detached snapshot; persistence must be idempotent per Job.
                local fact={bodyStopped=true,effects=value.effects}
                local saved,accepted=pcall(r.adapter.persistEffects,
                    {bodyStopped=true,effects=value.effects})
                fact.persisted=saved and accepted==true
                local evidence,why=Evidence.validate(fact)
                if evidence then
                    local released,releaseResult=true,true
                    if r.control then released,releaseResult=pcall(driver().releaseControl,r.control) end
                    if not released or releaseResult~=true then
                        r.error='NATIVE_CONTROL_RETAINED'
                    else
                        r.control=nil
                        local receipt,err=sessions:confirmStopped(r.token,evidence)
                        if receipt then
                            if saveFacts then
                                saveFacts[r.npcId]={npcId=r.npcId,jobId=r.jobId,kind=r.kind,bodyStopped=true,
                                    effects=evidence.effects,persisted=true,reason=r.reason}
                            end
                            close(r,'CLOSED')
                        else r.error=err end
                    end
                else r.error=why end
            elseif not ok then r.error=tostring(value) end
        end
    end
    function api:step()
        if stepping or calling then return false,'CALL_IN_FLIGHT' end
        stepping=true
        local remaining=math.min(4,#queue)
        for _=1,remaining do
            if cursor>=#queue then cursor=0 end
            cursor=cursor+1
            local r=queue[cursor]
            if not live(r.ticket) then
                table.remove(queue,cursor) cursor=cursor-1
            elseif r.state=='QUEUED' and not frozen and not retired then
                local token,why=sessions:acquire(r.npcId,r.jobId,r.kind)
                if token then r.token=token r.state='ACTIVE' else r.error=why end
            elseif r.state=='STOPPING' then
                stopOnce(r)
            end
        end
        stepping=false
        return true
    end
    function api:beginSave()
        if retired then return false,'WORLD_RETIRED' end
        if frozen then return false,'SAVE_ACTIVE' end
        frozen=true saveFacts={}
        barrier=sessions:beginDrain('SAVE')
        local nativeFrozen=not Driver
        if EmberRoutesProbeJava and EmberRoutesProbeJava.freezeBodyControl then
            nativeFrozen=EmberRoutesProbeJava.freezeBodyControl()
            nativeBarrier=nativeFrozen==true
        end
        for _,r in ipairs(queue) do
            if live(r.ticket) then
            r.reason=r.reason or 'SAVE'
            if r.state=='QUEUED' then close(r,'CANCELLED')
            else
                saveFacts[r.npcId]={npcId=r.npcId,jobId=r.jobId,kind=r.kind,bodyStopped=false,effects='UNKNOWN',persisted=false,reason=r.reason}
                r.state='STOPPING'
            end
            end
        end
        -- Never step or wait here: OnSave may have no future game tick.
        if not nativeFrozen then return false,'NATIVE_FREEZE_FAILED' end
        return true
    end
    -- One bounded observation per live owner; never step/wait/retry inside OnSave.
    function api:captureSave()
        if retired or not frozen or not barrier then return nil,'NO_LIVE_BARRIER' end
        if stepping or calling then return nil,'CALL_IN_FLIGHT' end
        stepping=true
        for _,r in ipairs(queue) do
            if live(r.ticket) and r.state=='STOPPING' then
                stopOnce(r)
                if live(r.ticket) and r.stopRequested then
                    local ok,accepted=pcall(r.adapter.persistEffects,{bodyStopped=false,effects='UNKNOWN'})
                    saveFacts[r.npcId].persisted=ok and accepted==true
                end
            end
        end
        stepping=false
        local status=sessions:drainStatus(barrier)
        local facts,known={},true
        for id,fact in pairs(saveFacts) do
            local copy={} for key,value in pairs(fact) do copy[key]=value end facts[id]=copy
            if not fact.bodyStopped or fact.effects~='KNOWN' or not fact.persisted then known=false end
        end
        return {ready=known and status and status.pending==0 or false,byNpc=facts}
    end
    function api:finishSave(success)
        if retired or not frozen or not barrier then return false,'NO_LIVE_BARRIER' end
        if success~=true then return false,'SAVE_BLOCKED' end
        if stepping or calling then return false,'CALL_IN_FLIGHT' end
        local status=sessions:drainStatus(barrier)
        if not status or status.pending~=0 then return false,'SESSIONS_PENDING' end
        if nativeBarrier and not EmberRoutesProbeJava.thawBodyControl() then return false,'NATIVE_CONTROL_RETAINED' end
        local ok,why=sessions:endDrain(barrier)
        if not ok then return false,why end
        frozen=false barrier=nil saveFacts=nil nativeBarrier=false
        return true
    end
    function api:retire(detachedWorld)
        retired=true frozen=true sessions:retire()
        -- A displaced Lua service must not retire the NEW world's Java registry.
        if (Driver or nativeBarrier) and not detachedWorld then EmberRoutesProbeJava.retireBodyControl() end
        for _,r in ipairs(queue) do
            if live(r.ticket) then
            r.reason=r.reason or 'WORLD_RETIRED'
            if r.state=='QUEUED' then close(r,'CANCELLED') else r.state='STOPPING' end
            end
        end
        return true
    end
    return api
end
return Controller
