-- Fixed read-only adapters for known business payloads. Never stops, releases,
-- resumes or settles another owner's work; unknown business remains blocked.
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local R={}
local responsibilityReasons={CRAFT='ACTIVITY_CRAFT_SETTLING',HAUL='ACTIVITY_HAUL_SETTLING',COOKING='ACTIVITY_COOKING_SETTLING'}
local function occupied(value) for _ in pairs(value or {}) do return true end return false end
function R.inspect(id,ref,careId)
    local state,reason,rank='READY',nil,0
    local function block(s,r,priority)
        if priority>rank or priority==rank and r<(reason or '') then state,reason,rank=s,r,priority end
    end
    local ownCare,freeCraft
    Jobs.current():visitNpc(id,function(job)
        local p=job.payload
        if job.effects~='KNOWN' then block('UNKNOWN','ACTIVITY_EFFECTS_UNKNOWN',4) return end
        local responsibility=responsibilityReasons[job.providerType]
            or job.providerType=='SELF_CARE' and p.kind=='STUDY' and 'ACTIVITY_BOOK_RETURN'
            or 'ACTIVITY_OBLIGATIONS_PENDING'
        if occupied(job.obligations) then block('WAIT',responsibility,3) end
        if job.providerType~='SELF_CARE' and occupied(p.claims) then block('WAIT',responsibility,3) end
        if job.providerType=='SELF_CARE' then
            local route=p.leisure and p.leisure.zoneVisit
            local own=job.id==careId and p.kind=='LEISURE' and route and route.eventId==ref.eventId
                and route.id==ref.id and route.revision==ref.revision and #p.claims==1 and not occupied(job.obligations)
                and p.leisure.point and p.claims[1]==require('EmberRoutesProbe/LifeZoneVisits').tileKey(p.leisure.point)
            if own then ownCare=job.id
            elseif p.step~='IDLE' or #p.claims>0 then
                block('WAIT',p.kind=='STUDY' and 'ACTIVITY_BOOK_RETURN' or 'ACTIVITY_PERSONAL_SETTLING',2)
            end
            local resume=p.resume
            if resume and resume.state~='RESTORED' and resume.state~='INVALIDATED'
                and resume.epoch==require('EmberRoutesProbe/TaskResume').epoch(id) then
                block('WAIT','ACTIVITY_PREDECESSOR_PENDING',3)
            end
        elseif job.providerType=='ACTIVITY' and p.eventId==ref.eventId then
            if job.state~='DONE' and job.state~='CANCELLED' and p.step~='INVITED' and p.step~='FREE' and p.step~='PERSONAL' then
                block('WAIT','ACTIVITY_BODY_BUSY',2)
            end
        elseif job.providerType=='CRAFT' then
            local cleared=require('EmberRoutesProbe/ProductionYield').assetFree(p)
            if cleared then freeCraft=true end
            if not p.released and not cleared or occupied(p.claims) then block('WAIT','ACTIVITY_CRAFT_SETTLING',2) end
        elseif job.providerType=='HAUL' then
            if p.state~='DONE' then block('WAIT','ACTIVITY_HAUL_SETTLING',2) end
        elseif job.providerType=='COOKING' then
            if job.state~='DONE' and job.state~='CANCELLED' or p.duty~=nil or occupied(p.claims) then
                block('WAIT','ACTIVITY_COOKING_SETTLING',3)
            end
        elseif job.state~='DONE' and job.state~='CANCELLED' then block('WAIT','ACTIVITY_OTHER_JOB_RETAINED',2) end
    end)
    return {state=state,reason=reason,rank=rank,ownCare=ownCare,freeCraft=freeCraft}
end
function R.associated(job,event)
    local p=job and job.payload
    local ref=p and (p.activityRef or p.leisure and p.leisure.zoneVisit)
    return ref and ref.eventId==event.id or false
end
function R.personalPending(id,event)
    local job=Jobs.current():peekPersonal(id)
    return R.associated(job,event) and (job.effects~='KNOWN' or job.payload.step~='IDLE'
        or occupied(job.obligations) or occupied(job.payload.claims)) or false
end
function R.activeParticipation(job,event,status)
    local p=job and job.payload
    if not p or not R.associated(job,event) or job.effects~='KNOWN' or p.step~='ACTING'
        or not status or status.jobId~=job.id or status.state~='ACTIVE' or not status.started then return false end
    local member=event.roster[job.npcId] local ref=p.activityRef
    if not member or not ref or ref.controlEpoch~=event.controlEpoch
        or (ref.participantEpoch or 1)~=(member.participantEpoch or 1) then return false end
    if not require('EmberRoutesProbe/ActivityOwners').active(event,job) then return false end
    return p.kind=='LEISURE' and p.leisure and p.leisure.started and not p.leisure.zoneVisit
        or p.kind=='STUDY' and p.study and p.study.leisure and p.reading and p.reading.started or false
end
function R.personalRequest(job,ref,inArea)
    local p=job and job.payload
    if not p or p.step~='ACTING' or p.kind~='LEISURE' and p.kind~='STUDY' then return false,'ACTIVITY_WAIT' end
    local route=p.leisure and p.leisure.zoneVisit
    local sameRoute=route and route.eventId==ref.eventId and route.id==ref.id and route.revision==ref.revision
    local workingStudy=p.kind=='STUDY' and not (p.study and p.study.leisure)
    return not sameRoute and (ref.phase=='GATHERING' or not inArea or workingStudy),'ACTIVITY_PERSONAL_SETTLING'
end
return R
