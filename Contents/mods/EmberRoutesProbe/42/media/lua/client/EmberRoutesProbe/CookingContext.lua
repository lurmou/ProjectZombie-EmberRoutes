-- Shared durable publication. A body capability authorizes actions; it never
-- owns the asset ledger. Effect observations may finish after body invalidation.
local Store=require 'EmberRoutesProbe/LaborStore'
local Record=require 'EmberRoutesProbe/CookingRecord'
local C={}
function C.current(c,attemptId)
    return c and c.job and Store.validCooking(c.job,c.token)
        and (not attemptId or c.job.payload.attempt and c.job.payload.attempt.id==attemptId) or false
end
function C.active(c,attemptId)
    return C.current(c,attemptId) and not c.stopping and c.body and c.body.current() and c.valid()
        and EmberRoutesProbeJava.carrierId(c.npc)==c.job.npcId
        and EmberRoutesProbeJava.carrierActive(c.npc) or false
end
function C.publish(c,proposed)
    local ok,job,token=Store.replaceCooking(c.job,c.token,proposed)
    if not ok then c.reason=job return false end
    c.job,c.token,c.effects=job,token,job.effects
    return true
end
function C.unknown(c,attemptId,reason)
    if not C.current(c,attemptId) then return false end
    local a=c.job.payload.attempt
    if a.state=='APPLIED' or a.state=='ABORTED' then return false end
    local j=Record.copy(c.job) j.effects='UNKNOWN' j.payload.attempt.state='UNKNOWN'
    j.payload.reason=string.sub(tostring(reason or 'COOKING_EFFECT_UNKNOWN'),1,256)
    if j.payload.duty then j.payload.duty.state='OBSERVATION_REQUIRED' end
    c.reason=j.payload.reason
    return C.publish(c,j)
end
-- Runtime.captureStop uses this adapter for completion, cancellation and revoke.
-- Native occupancy is cleaned only after the existing controller proves stop.
function C.stopAdapter(c,controller,ticket)
    local body,jobId=c.body,c.job.id
    local world=require('EmberRoutesProbe/ContainerRegistry').data()
    return require('EmberRoutesProbe/TaskBusinessStop').new({controller=controller,ticket=ticket,
        npc=c.npc,npcId=c.job.npcId,jobId=jobId,
        same=function()
            if require('EmberRoutesProbe/ContainerRegistry').data()~=world or c.body~=body or c.job.id~=jobId then return false end
            if C.current(c) then return true end
            local saved=c.closed and require('EmberRoutesProbe/TaskJobs').current():peek(jobId)
            return saved and saved.revision==c.job.revision and (saved.state=='DONE' or saved.state=='CANCELLED') or false
        end,
        pause=function(reason)
            c.stopping=true
            c.reason=c.reason or reason
            if c.job.state=='RUNNING' then
                local j=Record.copy(c.job) j.state='STOPPING'
                if not C.publish(c,j) then return false end
            end
            return body.clear()
        end,
        effects=function()
            -- A healthy progressive native action remains UNKNOWN while running.
            -- Classify its measured partial result only with the same native/Lua
            -- stop proof, before TaskController snapshots the effect evidence.
            if c.progressive and c.settleStopped then
                local native=body.snapshot()
                local queues=ISTimedActionQueue and ISTimedActionQueue.queues
                local queue=type(queues)=='table' and queues[c.npc]
                local empty=type(queues)=='table' and (not queue or type(queue.queue)=='table'
                    and #queue.queue==0 and queue.current==nil)
                if native.available and native.nativeStopped and empty then c.settleStopped() end
            end
            return c.job.effects
        end,
        persist=function(fact)
            if fact.bodyStopped~=true then return false end
            if c.settleStopped and not c.settleStopped() then return false end
            if c.job.payload.waterSource and not require('EmberRoutesProbe/CookingWaterSources').release(c,true) then return false end
            local station=c.job.payload.station
            if station and not require('EmberRoutesProbe/CraftStations').release(c,true,station.leaseId) then return false end
            local j=Record.copy(c.job)
            if j.state=='DONE' or j.state=='CANCELLED' then
                if c.completed and not c.closed then c.closed=Store.finishCooking(c.job,c.token)==true return c.closed end
                return true
            end
            if c.completed and j.effects=='KNOWN' and #j.payload.claims==0 and not j.payload.duty and not j.payload.station then
                for _ in pairs(j.obligations) do return false end
                j.state=c.cancelled and 'CANCELLED' or 'DONE' j.payload.phase='SETTLED'
                if not C.publish(c,j) then return false end
                c.closed=Store.finishCooking(c.job,c.token)==true
                return c.closed
            end
            j.state=j.effects=='UNKNOWN' and 'RECONCILE_REQUIRED' or 'SUSPENDED'
            j.payload.stopProof={npcId=j.npcId,bodyStopped=true,sequence=j.payload.sequence}
            j.payload.reason=string.sub(tostring(c.reason or 'COOKING_STOPPED'),1,256)
            return C.publish(c,j)
        end})
end
return C
