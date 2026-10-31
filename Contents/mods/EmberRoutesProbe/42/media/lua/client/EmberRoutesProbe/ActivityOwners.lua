-- Fixed personal-owner adapter. Reads the real owner's Job; never releases its
-- assets, infers success from IDLE, issues bodies or settles another business.
local Store=require 'EmberRoutesProbe/ActivityStore'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Duties=require 'EmberRoutesProbe/ActivityDuties'
local Phase=require 'EmberRoutesProbe/ActivityPhaseRecord'
local function dutyId(event,id) return event.scriptProfile and Phase.duty(event.stage,id) or 'FREE_SELECTOR' end
local O={}
local function empty(t) for _ in pairs(t or {}) do return false end return true end
local function bound(event,id,ref)
    local m=event and event.roster[id]
    return m and Duties.validRef(ref) and event.dutyFormat==Duties.FORMAT and not event.dutyBlocked
        and ref.worldId==event.worldId and ref.eventId==event.id and ref.stageEpoch==event.stageEpoch
        and type(event.stage)=='table' and type(event.stage.scope)=='table' and ref.controlEpoch==event.stage.scope.controlEpoch
        and ref.participantEpoch==(m.participantEpoch or 1) and ref.dutyId==dutyId(event,id)
        and m.duty and ref.dutyEpoch==m.duty.epoch and m.duty or nil
end
local function owner(id,jobId,attemptId)
    local job=Jobs.current():peek(jobId)
    return job and job.npcId==id and job.providerType=='SELF_CARE' and job.payload.attemptId==attemptId and job or nil
end
local function applicable(job,event)
    local p=job.payload
    if event.scriptProfile then return p.kind=='LEISURE' and p.leisure and p.leisure.roleDuty==dutyId(event,job.npcId) end
    return p.kind=='LEISURE' and p.leisure and not p.leisure.zoneVisit
        or p.kind=='STUDY' and p.study and p.study.leisure or false
end
function O.reference(event,id)
    local m=event.roster[id]
    if not m or not m.duty then return nil end
    return {worldId=event.worldId,stageEpoch=event.stageEpoch,dutyId=dutyId(event,id),dutyEpoch=m.duty.epoch,dutyFormat=Duties.FORMAT}
end
function O.matches(event,id,ref)
    if not event.dutyFormat then return true end
    return bound(event,id,ref)~=nil
end
function O.ready(event,id)
    if not event.dutyFormat then return true end
    local m=event.roster[id]
    return not event.dutyBlocked and m and Duties.clear(m.duty) or false
end
function O.active(event,job)
    if not event.dutyFormat then return true end
    if event.scriptProfile and (event.stage.index~=2 or not event.stage.sharedStart) then return false end
    local d=bound(event,job.npcId,job.payload.activityRef)
    local a=d and d.current
    return a and not a.unknown and a.jobId==job.id and a.attemptId==job.payload.attemptId or false
end
function O.canStart(id,jobId,attemptId)
    local job=owner(id,jobId,attemptId) if not job then return false end
    local ref=job.payload.activityRef
    if not ref or not ref.dutyId then return true end -- legacy/arrival uses its original guards
    local event=Store.get(ref.eventId) local d=bound(event,id,ref)
    return d and require('EmberRoutesProbe/ActivityService').validRef(id,ref) and applicable(job,event) and job.effects=='KNOWN'
        and Duties.canIssue(d,ref.dutyEpoch,jobId,attemptId) or false
end
function O.started(id,jobId,attemptId)
    local job=owner(id,jobId,attemptId) if not job then return false end
    local ref=job.payload.activityRef
    if not ref or not ref.dutyId then return true end
    local event=Store.get(ref.eventId) local d=bound(event,id,ref)
    if not d or not O.canStart(id,jobId,attemptId) or job.payload.step~='ACTING' then return false end
    local accepted,changed=Duties.issue(d,ref.dutyEpoch,jobId,attemptId)
    if changed then Store.touch(event,true) end
    return accepted
end
-- Called by SelfCareExecution's stop persistence closure, after native proof and
-- the owner's Claims/return/state writes. Recovery may explicitly reconcile the
-- same attempt; activity cancellation does not invalidate its cleanup identity.
function O.result(id,jobId,attemptId,ref,fact,status,reconciled)
    if not ref or not ref.dutyId then return true end
    local event=Store.get(ref.eventId) local d=bound(event,id,ref)
    local job=owner(id,jobId,attemptId)
    if not d or not job or not applicable(job,event) or type(fact)~='table' then return false end
    local unknown=job.effects~='KNOWN' or fact.effects~='KNOWN'
    local cleared=not unknown and fact.bodyStopped==true and job.payload.step=='IDLE'
        and empty(job.payload.claims) and empty(job.obligations)
    -- Preserve the original action result while its return still owes custody;
    -- a successful return must not turn a failed original action into success.
    if not unknown and fact.bodyStopped~=true then return true end
    if d.current and d.current.result then status=d.current.result end
    local accepted,changed=Duties.record(d,ref.dutyEpoch,jobId,attemptId,
        unknown and 'UNKNOWN' or status,cleared,reconciled)
    local measured=job.payload.leisure and job.payload.leisure.roleHours
    if accepted and not unknown and fact.bodyStopped==true and event.scriptProfile=='SPEECH_V1'
        and type(measured)=='number' and measured>=0 and measured<=event.durationHours+0.0000001 then
        event.roster[id].participationHours=math.min(measured,event.durationHours) changed=true
    end
    if changed then Store.touch(event,true) end
    return accepted
end
return O
