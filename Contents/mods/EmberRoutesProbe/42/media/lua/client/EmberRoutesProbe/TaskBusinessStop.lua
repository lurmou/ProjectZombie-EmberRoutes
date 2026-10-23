-- Business stop adapter. No event loop, automatic admission, or asset release.
local Stop={}
function Stop.new(spec)
    assert(type(spec)=='table' and type(spec.ticket)=='function' and type(spec.controller)=='table'
        and type(spec.same)=='function' and type(spec.pause)=='function'
        and type(spec.effects)=='function' and type(spec.persist)=='function'
        and type(spec.jobId)=='string' and spec.jobId~='' and type(spec.npcId)=='string' and spec.npcId~='', 'STOP_SPEC_REQUIRED')
    local paused=false
    local stopping=false
    local function owner()
        local ticket=spec.ticket()
        local state=spec.controller:inspect(ticket)
        return state and state.state=='STOPPING' and state.npcId==spec.npcId and state.jobId==spec.jobId
            and spec.controller:bodySnapshot(ticket).available
    end
    local adapter={}
    function adapter.requestStop(reason)
        if stopping or not owner() or not spec.same(paused) then return false end
        stopping=true
        -- pause fences business callbacks before any queue/native stop call.
        local ok,result=pcall(spec.pause,reason)
        stopping=false
        if not ok then error(result) end
        if result==false then return false end
        paused=true
        return spec.controller:stopBody(spec.ticket())
    end
    function adapter.observeStop()
        if not paused or not spec.same(true) then return {bodyStopped=false,reason='STALE_BUSINESS'} end
        local native=spec.controller:bodySnapshot(spec.ticket())
        local queues=ISTimedActionQueue and ISTimedActionQueue.queues
        if type(queues)~='table' then return {bodyStopped=false,reason='LUA_QUEUE_UNKNOWN'} end
        local queue=queues[spec.npc]
        local empty=not queue or (type(queue.queue)=='table' and #queue.queue==0 and queue.current==nil)
        return {bodyStopped=native.available and native.nativeStopped and empty or false,effects=spec.effects()}
    end
    function adapter.persistEffects(fact)
        if not paused or not spec.same(true) then return false end
        -- Called only after Lua/native observation by TaskController. No queue release here.
        return spec.persist(fact)==true
    end
    return adapter
end
return Stop
