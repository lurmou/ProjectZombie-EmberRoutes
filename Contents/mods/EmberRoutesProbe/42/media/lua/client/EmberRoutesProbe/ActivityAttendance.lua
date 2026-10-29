-- Admission proof only. Old owners retain every body, item and obligation.
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local A={}
local function occupied(value) for _ in pairs(value or {}) do return true end return false end
function A.blocksOrdinary(id)
    return require('EmberRoutesProbe/ActivityService').context(id)~=nil
        or require('EmberRoutesProbe/ActivityParticipant').retains(id)
end
function A.inspect(actor,id,ref,careId)
    local Service=require 'EmberRoutesProbe/ActivityService'
    local live=Service.context(id)
    if not live or type(ref)~='table' or ref.eventId~=live.eventId or ref.id~=live.id
        or ref.revision~=live.revision then return 'REJECTED','ACTIVITY_CHANGED' end
    if not require('EmberRoutesProbe/SettlementLedger').view(actor,live.settlementId) then return 'REJECTED','ACCESS_DENIED' end
    local state,reason,rank='READY',nil,0
    local function block(s,r,priority)
        if priority>rank or priority==rank and r<(reason or '') then state,reason,rank=s,r,priority end
    end
    local ownCare,freeCraft
    Jobs.current():visitNpc(id,function(job)
        local p=job.payload
        if job.effects~='KNOWN' then block('UNKNOWN','ACTIVITY_EFFECTS_UNKNOWN',4) return end
        if occupied(job.obligations) then block('WAIT','ACTIVITY_OBLIGATIONS_PENDING',3) end
        if job.providerType~='SELF_CARE' and occupied(p.claims) then block('WAIT','ACTIVITY_OBLIGATIONS_PENDING',3) end
        if job.providerType=='SELF_CARE' then
            local route=p.leisure and p.leisure.zoneVisit
            local own=job.id==careId and p.kind=='LEISURE' and route and route.eventId==ref.eventId
                and route.id==ref.id and route.revision==ref.revision and #p.claims==1 and not occupied(job.obligations)
                and p.leisure.point and p.claims[1]==require('EmberRoutesProbe/LifeZoneVisits').tileKey(p.leisure.point)
            if own then ownCare=job.id
            elseif p.step~='IDLE' or #p.claims>0 then block('WAIT','ACTIVITY_PERSONAL_SETTLING',2) end
            local resume=p.resume
            if resume and resume.state~='RESTORED' and resume.state~='INVALIDATED'
                and resume.epoch==require('EmberRoutesProbe/TaskResume').epoch(id) then
                block('WAIT','ACTIVITY_PREDECESSOR_PENDING',3)
            end
        elseif job.providerType=='ACTIVITY' and p.eventId==ref.eventId then
            if p.step~='INVITED' and p.step~='FREE' then block('WAIT','ACTIVITY_BODY_BUSY',2) end
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
    if rank>0 then return state,reason end -- No native inventory scan while any ledger already blocks admission.
    local runtime=Runtime.current()
    -- Arrival is observed INSIDE Runtime.step(), where new admission is closed.
    -- The already-owned matching route may report a fact; it gets no new body.
    if not runtime then block('WAIT','ADMISSION_CLOSED',1) return state,reason end
    if not ownCare and not runtime:accepting() then block('WAIT','ADMISSION_CLOSED',1) end
    local current=runtime:status(id)
    if runtime:owns(id) and (not current or current.jobId~=ownCare or current.pending or current.state~='ACTIVE') then
        block('WAIT','ACTIVITY_BODY_BUSY',1)
    end
    if rank>0 then return state,reason end
    local binding=require('EmberRoutesProbe/Driver').bindId(actor,id)
    if not binding or not require('EmberRoutesProbe/Driver').valid(binding) then block('WAIT','ACTIVITY_CARRIER_UNAVAILABLE',1)
    elseif not binding.handle:getCharacterActions():isEmpty() then block('WAIT','ACTIVITY_NATIVE_ACTION_BUSY',1) end
    -- This includes retained native executors, even without a current Session.
    if require('EmberRoutesProbe/Work').hasCargo(actor,id,freeCraft and 'CRAFT_PROBE' or nil) then block('WAIT','ACTIVITY_CARGO_RETAINED',2) end
    return state,reason
end
function A.request(actor,binding,ref)
    local id=binding.id
    local job=Jobs.current():peekPersonal(id)
    local p=job and job.payload
    if not p or p.step~='ACTING' or p.kind~='LEISURE' and p.kind~='STUDY' then return 'WAIT','ACTIVITY_WAIT' end
    local npc=binding.handle
    local inArea=require('EmberRoutesProbe/ActivityService').allowsPoint(ref.settlementId,id,
        {x=npc:getX(),y=npc:getY(),z=math.floor(npc:getZ())})
    if p and p.step=='ACTING' and (p.kind=='LEISURE' or p.kind=='STUDY') then
        local route=p.leisure and p.leisure.zoneVisit
        local sameRoute=route and route.eventId==ref.eventId and route.id==ref.id and route.revision==ref.revision
        local workingStudy=p.kind=='STUDY' and not (p.study and p.study.leisure)
        if not sameRoute and (ref.phase=='GATHERING' or not inArea or workingStudy) then
            local state,reason=A.inspect(actor,id,ref)
            if state=='UNKNOWN' or state=='REJECTED' then return state,reason end
            local runtime=Runtime.current() local current=runtime and runtime:status(id,job.id)
            if current and current.state~='STOPPING' then runtime:stopJob(id,job.id,'ACTIVITY_ATTENDANCE') end
            return state,reason
        end
    end
    return 'WAIT','ACTIVITY_PERSONAL_SETTLING'
end
return A
