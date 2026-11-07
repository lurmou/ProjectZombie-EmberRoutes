-- Runtime authority protocol only. No engine calls, asset release or persistence.
-- Consumers must verify bodies/effects and preserve business obligations themselves.
local Sessions={}
local function identity(value) return type(value)=='string' and value~='' end
local function copy(record)
    return {npcId=record.npcId,jobId=record.jobId,kind=record.kind,generation=record.generation,
        state=record.state,reason=record.reason,dispatching=record.dispatching}
end

function Sessions.new()
    local byNpc,byToken={},{},{}
    local sequence,count,retired=0,0,false
    local drain
    local api={}
    local function current(token)
        if type(token)~='table' then return nil end
        local record=byToken[token]
        if record and byNpc[record.npcId]==record then return record end
    end
    local function stop(record,reason)
        if record.state=='ACTIVE' then record.state='STOPPING' record.reason=reason end
    end
    local function close(token,evidence,requiredState)
        local record=current(token)
        if not record then return nil,'STALE_SESSION' end
        if record.dispatching then return nil,'CALL_IN_FLIGHT' end
        if record.state~=requiredState then
            return nil,requiredState=='STOPPING' and 'STOP_NOT_REQUESTED' or 'SESSION_STOPPING'
        end
        if type(evidence)~='table' or evidence.bodyStopped~=true then return nil,'BODY_NOT_STOPPED' end
        if evidence.effects~='KNOWN' and evidence.effects~='UNKNOWN' then return nil,'EFFECTS_REQUIRED' end
        local receipt=copy(record)
        receipt.state='CLOSED' receipt.effects=evidence.effects
        receipt.reason=receipt.reason or 'COMPLETED'
        byNpc[record.npcId]=nil byToken[token]=nil count=count-1
        return receipt
    end

    function api:acquire(npcId,jobId,kind)
        if not identity(npcId) or not identity(jobId) or not identity(kind) then return nil,'IDENTITY_REQUIRED' end
        if retired then return nil,'WORLD_RETIRED' end
        if drain then return nil,'ADMISSION_CLOSED' end
        if byNpc[npcId] then return nil,'NPC_BUSY' end
        if sequence>=9007199254740991 then return nil,'GENERATION_LIMIT' end
        sequence=sequence+1
        local token={}
        local record={npcId=npcId,jobId=jobId,kind=kind,generation=sequence,state='ACTIVE',dispatching=false}
        byNpc[npcId]=record byToken[token]=record count=count+1
        return token
    end

    function api:canAct(token)
        local record=current(token)
        if not record then return false,'STALE_SESSION' end
        if retired then return false,'WORLD_RETIRED' end
        if drain then return false,'ADMISSION_CLOSED' end
        if record.dispatching then return false,'CALL_IN_FLIGHT' end
        if record.state~='ACTIVE' then return false,'SESSION_STOPPING' end
        return true
    end

    -- The callback can request stop, but cannot hand the body off before unwinding.
    -- A thrown native call may already have changed the world: fence, never replay.
    function api:dispatch(token,callback)
        local allowed,reason=self:canAct(token)
        if not allowed then return false,reason end
        if type(callback)~='function' then return false,'CALLBACK_REQUIRED' end
        local record=current(token)
        record.dispatching=true
        local ok,value,detail=pcall(callback)
        record.dispatching=false
        if not ok then
            stop(record,'DISPATCH_ERROR')
            return false,'DISPATCH_ERROR',tostring(value)
        end
        return true,value,detail
    end

    function api:requestStop(token,reason)
        local record=current(token)
        if not record then return false,'STALE_SESSION' end
        if not identity(reason) then return false,'REASON_REQUIRED' end
        stop(record,reason)
        return true
    end

    -- Evidence is an explicit adapter assertion, not an engine check by this core.
    -- Persist UNKNOWN obligations in the business ledger before releasing the grant.
    function api:complete(token,evidence) return close(token,evidence,'ACTIVE') end
    function api:confirmStopped(token,evidence) return close(token,evidence,'STOPPING') end

    function api:inspect(npcId)
        if not identity(npcId) then return nil end
        local record=byNpc[npcId]
        if record then return copy(record) end
    end

    function api:beginDrain(reason)
        if retired then return nil,'WORLD_RETIRED' end
        if drain then return nil,'DRAIN_ACTIVE' end
        if not identity(reason) then return nil,'REASON_REQUIRED' end
        local ticket={}
        drain={ticket=ticket,reason=reason}
        for _,record in pairs(byNpc) do stop(record,reason) end
        return ticket
    end

    function api:drainStatus(ticket)
        if not drain or ticket~=drain.ticket then return nil,'STALE_BARRIER' end
        return {pending=count,reason=drain.reason,retired=retired}
    end

    function api:endDrain(ticket)
        if not drain or ticket~=drain.ticket then return false,'STALE_BARRIER' end
        if retired then return false,'WORLD_RETIRED' end
        if count~=0 then return false,'SESSIONS_PENDING' end
        drain=nil
        return true
    end

    -- Old evidence may still be reconciled; the retired instance never grants again.
    -- This does not remove bodies or release assets. Use a new instance per world.
    function api:retire()
        retired=true
        for _,record in pairs(byNpc) do stop(record,'WORLD_RETIRED') end
        return true
    end
    return api
end
return Sessions
