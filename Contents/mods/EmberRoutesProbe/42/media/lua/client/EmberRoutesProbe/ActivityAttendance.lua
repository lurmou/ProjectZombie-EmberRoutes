-- Admission proof only. Old owners retain every body, item and obligation.
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local A={}
local Responsibilities=require 'EmberRoutesProbe/ActivityResponsibilities'
function A.blocksOrdinary(id)
    return require('EmberRoutesProbe/ActivityService').context(id)~=nil
        or require('EmberRoutesProbe/ActivityParticipant').retains(id)
end
local function inspect(actor,id,ref,careId,preview)
    local Service=require 'EmberRoutesProbe/ActivityService'
    local live=preview and ref or Service.context(id)
    if not live or type(ref)~='table' or not preview and (ref.eventId~=live.eventId or ref.id~=live.id
        or ref.revision~=live.revision or ref.controlEpoch~=live.controlEpoch
        or (ref.participantEpoch or 1)~=live.participantEpoch
        or ref.commandEpoch~=live.commandEpoch or ref.membershipRevision~=live.membershipRevision) then
        return 'REJECTED','ACTIVITY_CHANGED'
    end
    if not require('EmberRoutesProbe/SettlementLedger').view(actor,live.settlementId) then return 'REJECTED','ACCESS_DENIED' end
    local fact=Responsibilities.inspect(id,ref,careId)
    local state,reason,rank=fact.state,fact.reason,fact.rank
    local ownCare,freeCraft=fact.ownCare,fact.freeCraft
    local function block(s,r,priority)
        if priority>rank or priority==rank and r<(reason or '') then state,reason,rank=s,r,priority end
    end
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
function A.inspect(actor,id,ref,careId) return inspect(actor,id,ref,careId,false) end
-- Advisory only: no intent publication, stopping, resource reservation or grant.
function A.preview(actor,id,scope) return inspect(actor,id,{settlementId=scope},nil,true) end
function A.request(actor,binding,ref)
    local id=binding.id
    local inspected,blocked=A.inspect(actor,id,ref)
    if inspected=='REJECTED' or inspected=='UNKNOWN' then return inspected,blocked end
    local job=Jobs.current():peekPersonal(id)
    local npc=binding.handle
    local inArea=require('EmberRoutesProbe/ActivityService').allowsPoint(ref.settlementId,id,
        {x=npc:getX(),y=npc:getY(),z=math.floor(npc:getZ())})
    local shouldStop,why=Responsibilities.personalRequest(job,ref,inArea)
    if not shouldStop then return 'WAIT',why end
    local state,reason=A.inspect(actor,id,ref)
    if state=='UNKNOWN' or state=='REJECTED' then return state,reason end
    local runtime=Runtime.current() local current=runtime and runtime:status(id,job.id)
    if current and current.state~='STOPPING' then runtime:stopJob(id,job.id,'ACTIVITY_ATTENDANCE') end
    return state,reason
end
return A
