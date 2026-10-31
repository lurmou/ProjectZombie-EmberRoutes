-- Controlled SPEECH_V1 profile. Called by the existing Pump/member budget;
-- neither this helper nor the phase record owns a body, resource or new tick.
local Store=require 'EmberRoutesProbe/ActivityStore'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Driver=require 'EmberRoutesProbe/Driver'
local Duties=require 'EmberRoutesProbe/ActivityDuties'
local Phase=require 'EmberRoutesProbe/ActivityPhaseRecord'
local Responsibilities=require 'EmberRoutesProbe/ActivityResponsibilities'
local S={}
function S.available() return EmberRoutesProbeJava and EmberRoutesProbeJava.socialVisible~=nil or false end
local function clean(event,id)
    local m=event.roster[id] local j=m.jobId and Jobs.current():peek(m.jobId)
    local rt=Runtime.current()
    return Duties.clear(m.duty) and not Responsibilities.personalPending(id,event)
        and (not rt or not rt:status(id)) and j and j.effects=='KNOWN' and (j.payload.step=='PERSONAL' or j.payload.step=='FREE')
        and j.payload.stopped and #j.payload.claims==0 or false
end
function S.open(event,set,hours,epoch)
    local actors={}
    for id in pairs(set) do local m=event.roster[id] actors[id]={jobId=m.jobId,participantEpoch=m.participantEpoch or 1} end
    local phase=Phase.new(event,1,actors,hours)
    if phase then phase.scope.stageEpoch=epoch end
    return phase
end
function S.roleActive(event,id,job,status)
    local m=event.roster[id] local p=job and job.payload local d=m and m.duty
    return p and p.kind=='LEISURE' and p.leisure and p.leisure.started and p.step=='ACTING'
        and p.leisure.roleDuty==Phase.duty(event.stage,id) and job.effects=='KNOWN'
        and require('EmberRoutesProbe/ActivityOwners').matches(event,id,p.activityRef)
        and d and d.current and not d.current.unknown and d.current.jobId==job.id and d.current.attemptId==p.attemptId
        and status and status.jobId==job.id and status.state=='ACTIVE' and status.started and not status.pending or false
end
function S.inspect(actor,event,id,P,c,now)
    local m=event.roster[id] local stage=event.stage
    local personal=stage.index==2 and Jobs.current():peekPersonal(id) or nil
    if stage.actors[id] and (m.duty and m.duty.current and m.duty.current.unknown
        or personal and Responsibilities.associated(personal,event) and personal.effects~='KNOWN') then
        Store.close(event.id,event.revision,'ACTIVITY_STAGE_UNKNOWN') c.all=false return
    end
    if not stage.actors[id] or m.withdrawn then
        P.stop(id,event)
        if not P.collectOne(event,id) and stage.actors[id] then c.all=false end
        return
    end
    c.any=true
    if not P.present(event,id) then c.all=false return end
    local binding=Driver.bindId(actor,id)
    local speaker=Driver.bindId(actor,event.speakerId)
    if not binding or not speaker or not Driver.valid(binding) or not Driver.valid(speaker) then c.all=false return end
    local npc,host=binding.handle,speaker.handle
    if not npc.playEmote or not npc.faceLocationF or not npc.setVariable or not npc.clearVariable or not npc.addLineChatElement then
        Store.close(event.id,event.revision,'ACTIVITY_CAPABILITY_UNSUPPORTED') c.all=false return
    end
    if npc:getZ()~=host:getZ() or (npc:getX()-host:getX())^2+(npc:getY()-host:getY())^2>900
        or id~=event.speakerId and not EmberRoutesProbeJava.socialVisible(npc,host) then c.all=false return end
    if stage.index==1 then
        if not clean(event,id) then c.all=false return end
        if id~=event.speakerId then c.x=(c.x or 0)+npc:getX() c.y=(c.y or 0)+npc:getY() c.listeners=(c.listeners or 0)+1 end
    else
        local d=m.duty local job=personal
        if Duties.clear(d) and d.lastStatus and d.lastStatus~='SUCCEEDED' then
            require('EmberRoutesProbe/ActivityService').leave(id,'ACTIVITY_ROLE_FAILED') c.all=false return
        end
        local rt=Runtime.current() local status=rt and rt:status(id)
        local completed=Duties.clear(d) and d.lastStatus=='SUCCEEDED' and clean(event,id)
        if not completed and not S.roleActive(event,id,job,status) then c.all=false return end
        if not completed then c.complete=false end
    end
    c.set[id]=true c.count=c.count+1 c.oldest=math.min(c.oldest,now)
end
function S.finish(event,c,hours,memberValid)
    local old=event.stage
    if hours<old.startedAt then return end
    if hours>=old.deadline then Store.close(event.id,event.revision,'ACTIVITY_STAGE_TIMEOUT') return end
    if not c.all or not c.set[event.organizerId] or not c.set[event.speakerId] or c.count<event.quorum then return end
    if old.index==1 or not old.sharedStart or c.complete~=false then
        for id in pairs(c.set) do
            if not memberValid(id,event) then return end
            if old.index==1 then
                if not clean(event,id) then return end
            elseif not old.sharedStart then
                local rt=Runtime.current()
                if not S.roleActive(event,id,Jobs.current():peekPersonal(id),rt and rt:status(id)) then return end
            elseif not clean(event,id) or event.roster[id].duty.lastStatus~='SUCCEEDED' then return end
        end
    end
    if old.index==1 then
        local phase=Phase.new(event,2,old.actors,hours)
        if not phase then Store.close(event.id,event.revision,'ACTIVITY_STAGE_INVALID') return end
        phase.scope.stageEpoch=event.stageEpoch+1
        phase.focus={x=c.x/c.listeners,y=c.y/c.listeners}
        event.stageEpoch=phase.scope.stageEpoch event.stage=phase event.endsAt=phase.deadline
        event.phaseHistory={{id=old.id,outcome='COMPLETED'}}
        for id in pairs(phase.actors) do local d=event.roster[id].duty if d then d.epoch=d.epoch+1 end end
        Store.touch(event)
    elseif not old.sharedStart then
        old.sharedStart=hours old.sharedEnd=hours+event.durationHours
        old.deadline=old.sharedEnd+(event.gatherDeadline-event.createdAt) event.endsAt=old.deadline Store.touch(event)
    elseif c.complete~=false then
        local phase=Phase.new(event,3,old.actors,hours)
        if not phase then Store.close(event.id,event.revision,'ACTIVITY_STAGE_INVALID') return end
        phase.scope.stageEpoch=event.stageEpoch+1
        event.phaseHistory[#event.phaseHistory+1]={id=old.id,outcome='COMPLETED'}
        event.stageEpoch=phase.scope.stageEpoch event.stage=phase
        Store.touch(event) Store.close(event.id,event.revision,'COMPLETED')
    end
end
function S.candidate(event,id,entry,eligible,ref,hours)
    local stage=event.stage local d=event.roster[id].duty
    if stage.index~=2 or stage.state~='RUNNING' or not Duties.clear(d) or d.lastStatus then return nil,true end
    local binding=Driver.bindId(getSpecificPlayer(0),id) local npc=binding and binding.handle
    if not npc or not Driver.valid(binding) or not npc.playEmote or not npc.faceLocationF
        or not npc.setVariable or not npc.clearVariable or not npc.addLineChatElement then return nil,true end
    local point={x=npc:getX(),y=npc:getY(),z=math.floor(npc:getZ())}
    return {entry=entry,pure=true,activityRef=ref,membershipRevision=eligible.revision,settlementRevision=eligible.entryRevision,
        leisure={format=1,activity='OBSERVE',hours=hours,point=point,brief=true,roleDuty=Phase.duty(stage,id)}},true
end
function S.current(id,ref)
    local e=Store.get(ref.eventId)
    if not e or e.state~='RUNNING' or e.controlEpoch~=ref.controlEpoch or e.stageBlocked or e.dutyBlocked
        or e.scriptProfile~='SPEECH_V1' or not e.stage or e.stage.index~=2 or e.stage.state~='RUNNING'
        or not e.roster[id] or e.roster[id].withdrawn or not require('EmberRoutesProbe/ActivityOwners').matches(e,id,ref) then return nil end
    return e
end
function S.view(actor,id,ref)
    local Service=require 'EmberRoutesProbe/ActivityService'
    if not Service.validRef(id,ref) then return nil end
    local e=S.current(id,ref) if not e then return nil end
    local stage=e.stage
    local target
    if id==e.speakerId then target=stage.focus
    else
        local speaker=Driver.bindId(actor,e.speakerId) local self=Driver.bindId(actor,id)
        if not speaker or not self or not Driver.valid(speaker) or not Driver.valid(self)
            or not EmberRoutesProbeJava.socialVisible(self.handle,speaker.handle) then return nil end
        target={x=speaker.handle:getX(),y=speaker.handle:getY()}
    end
    return {target=target,startedAt=stage.sharedStart,endsAt=stage.sharedEnd,duration=e.durationHours}
end
return S
