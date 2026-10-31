-- One participant Job, short Runtime wait Session, then FREE personal Sessions.
-- This module observes those personal attempts; it never drives their bodies.
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Store=require 'EmberRoutesProbe/ActivityStore'
local Stages=require 'EmberRoutesProbe/ActivityStages'
local Duties=require 'EmberRoutesProbe/ActivityDuties'
local Relief=require 'EmberRoutesProbe/ActivityReliefRecord'
local Record=require 'EmberRoutesProbe/ActivityRecord'
local Driver=require 'EmberRoutesProbe/Driver'
local Assets=require 'EmberRoutesProbe/LaborStore'
local Tile=require 'EmberRoutesProbe/LeisureRecord'
local P={}
local world,handles,samples,ready,assessments=nil,{},{},{},{}
local function load()
    local root=Registry.data() if root~=world then world,handles,samples,ready,assessments=root,{},{},{},{} end
    return root
end
local function empty(t) for _ in pairs(t or {}) do return false end return true end
local function personal(id) return Jobs.current():peekPersonal(id) end
local Responsibilities=require 'EmberRoutesProbe/ActivityResponsibilities'
local associated=Responsibilities.associated
local associatedPending=Responsibilities.personalPending
local function current(id) local rt=Runtime.current() return rt,rt and rt:status(id) end
local function safe(binding)
    if binding.handle:isDead() then return false,'ACTIVITY_CARRIER_UNAVAILABLE' end
    local now=getTimestampMs()
    local sample=require('EmberRoutesProbe/NeedsObserver').sample(binding.handle,binding.id,now)
    if not sample or not sample.safe or now-sample.observedAt>2000 then return false,'ACTIVITY_UNSAFE' end
    local need=require('EmberRoutesProbe/NeedsPolicy').choose(sample,nil,{safe=true},{EAT=true,DRINK=true,REST=true,SLEEP=true})
    return need==nil,need and 'ACTIVITY_NEEDS_CARE' or nil
end
function P.prepare(event)
    local api=Jobs.current() local count=0
    for _,member in pairs(event.roster) do if not member.jobId and not member.withdrawn then count=count+1 end end
    if api:ordinaryCount()+count>require('EmberRoutesProbe/JobStore').LIMIT then return false,'JOB_LIMIT' end
    for id,member in pairs(event.roster) do
        if not member.jobId and not member.withdrawn then
            local job=Record.create(Registry.id(),id,event)
            local ok,why=api:create(job) if not ok then return false,why end
            member.jobId=job.id member.participationHours=0
        end
    end
    Store.touch(event) return true
end
local function update(job,p,state,effects)
    return Jobs.current():update(job.id,job.revision,{payload=p,state=state or job.state,effects=effects or job.effects})
end
local function releasePlacement(job,proof)
    if #job.payload.claims==0 then return true end
    if not proof or job.effects~='KNOWN' then return false end
    local token=Assets.claimActivity(job)
    return token and Assets.finishActivity(job,token) or false
end
local function settle(event,id,member)
    local job=member.jobId and Jobs.current():peek(member.jobId)
    local rt,status=current(id)
    if status and status.jobId==member.jobId then rt:stopJob(id,member.jobId,'ACTIVITY_END') return false end
    if associatedPending(id,event) then return false end
    if not job then
        if member.settled then handles[member.jobId]=nil ready[member.jobId]=nil end
        return member.settled==true
    end
    if job.effects~='KNOWN' or not empty(job.obligations) then return false end
    if job.payload.started and not job.payload.stopped then return false end
    local handle=handles[job.id]
    local result=handle and handle.runtime:inspect(handle.handle)
    local neverStarted=not job.payload.started and result and (result.state=='CANCELLED' or result.state=='REJECTED')
    if not releasePlacement(job,job.payload.stopped or neverStarted) then return false end
    job=Jobs.current():peek(job.id)
    if job.state~='DONE' and job.state~='CANCELLED' then
        local p=Store.copy(job.payload) p.step='SETTLED'
        if job.state~='SETTLING' then
            if not update(job,p,'SETTLING') then return false end job=Jobs.current():peek(job.id)
        end
        if not update(job,p,event.outcome=='COMPLETED' and 'DONE' or 'CANCELLED') then return false end
    end
    member.settled=true member.state='SETTLED' Store.touch(event)
    handles[member.jobId]=nil ready[member.jobId]=nil assessments[id]=nil samples[id]=nil
    job=Jobs.current():peek(member.jobId)
    if job and (not rt or not rt:status(id,job.id)) then Jobs.current():removeSettled(job.id,job.revision) end
    return true
end
function P.collectOne(event,id,applyEffects)
    local member=event.roster[id] if not member then return false end
    if member.jobId then
        local settled=settle(event,id,member)
        if event.dutyBlocked or member.duty and not Duties.clear(member.duty) then return false end
        local before=event.stage and event.stage.exitCount
        if settled and Stages.participantExit(event,id,member.jobId,member.participantEpoch or 1)
            and event.stage and before~=event.stage.exitCount then Store.touch(event,true) end
        if settled and event.reliefPrepared then return require('EmberRoutesProbe/ActivityRelief').step(event,id,applyEffects) end
        return settled
    end
    if associatedPending(id,event) then return false end
    if not member.settled then member.settled=true Store.touch(event) end
    if event.reliefPrepared then return require('EmberRoutesProbe/ActivityRelief').step(event,id,applyEffects) end
    return true
end
function P.finishCollection(event,all)
    if all and (event.state=='WINDING_DOWN' or event.state=='SETTLING') then
        if event.stage or event.stageBlocked then
            local done,outcome=false,'ACTIVITY_STAGE_UNSUPPORTED'
            if not event.stageBlocked then done,outcome=Stages.finish(event.stage,getGameTime():getWorldAgeHours()) end
            if not done then
                if event.state~='SETTLING' or event.reason~=outcome then
                    event.state='SETTLING' event.reason=outcome Store.touch(event)
                end
                return false
            end
            if event.outcome=='COMPLETED' and outcome~='COMPLETED' then
                event.outcome='INCOMPLETE' event.reason='ACTIVITY_STAGE_FAILED'
            end
        end
        if event.reliefVersion and not event.reliefPrepared then Relief.prepare(event,getGameTime():getWorldAgeHours()) Store.touch(event) end
        if Relief.pending(event) then
            if event.state~='SETTLING' then event.state='SETTLING' Store.touch(event) end
            return false
        end
        event.state='CLOSED' Store.touch(event)
    elseif event.state=='WINDING_DOWN' then event.state='SETTLING' Store.touch(event) end
    return all
end
-- Explicit synchronous save/recovery barrier only. Ordinary ticks use collectOne.
function P.collect(event)
    local all=true
    for id in pairs(event.roster) do if not P.collectOne(event,id) then all=false end end
    return P.finishCollection(event,all)
end
function P.retains(id)
    load() local retained=false
    Jobs.current():visitNpc(id,function(job)
        if job.providerType=='ACTIVITY' and job.state~='DONE' and job.state~='CANCELLED' then
            if job.effects~='KNOWN' or not empty(job.obligations) or #job.payload.claims>0
                or job.payload.started and not job.payload.stopped then retained=true end
            local e=Store.get(job.payload.eventId)
            if e and associatedPending(id,e) and (e.state=='WINDING_DOWN' or e.state=='SETTLING'
                or e.roster[id] and e.roster[id].withdrawn) then retained=true end
        end
    end)
    return retained
end
function P.stop(id,event)
    local member=event.roster[id] local rt,status=current(id)
    if rt and status and member and status.jobId==member.jobId then rt:stopJob(id,status.jobId,'ACTIVITY_END') end
    local job=personal(id)
    if rt and job and associated(job,event) and rt:status(id,job.id) then rt:stopJob(id,job.id,'ACTIVITY_END') end
end
local function waitingEvidence(event,id)
    local member=event.roster[id] local job=member and member.jobId and Jobs.current():peek(member.jobId)
    local rt,status=current(id)
    if not member or member.withdrawn or not job or job.effects~='KNOWN' or not empty(job.obligations)
        or job.payload.step~='WAITING' or #job.payload.claims~=1 or not job.payload.started or job.payload.stopped
        or not status or status.jobId~=job.id or status.state~='ACTIVE'
        or not status.started or status.pending then return false end
    local evidence=ready[job.id]
    local now=getTimestampMs()
    if not evidence or now<evidence.at or now-evidence.at>2000 then return false end
    local ref=require('EmberRoutesProbe/ActivityService').context(id)
    local handle=handles[job.id]
    if not ref or ref.participantEpoch~=(job.payload.participantEpoch or 1) or not handle or not Assets.validActivity(job,handle.token) then return false end
    return evidence,job
end
-- Scalar barrier recheck; no actor/grid scan. A STOPPING Session cannot retain a
-- ready receipt until its eventual native stop callback.
function P.receipt(event,id)
    local evidence=waitingEvidence(event,id)
    return evidence~=false and evidence~=nil,evidence and evidence.at or nil
end
function P.proof(event,id)
    local evidence,job=waitingEvidence(event,id) if not evidence then return false end
    local binding=evidence.binding
    if not binding or not Driver.valid(binding) then return false end
    local npc=binding.handle
    local point={x=npc:getX(),y=npc:getY(),z=math.floor(npc:getZ())}
    local valid=job.payload.claims[1]==Tile.tileKey(point)
        and require('EmberRoutesProbe/ActivityService').allowsPoint(event.settlementId,id,point)
        and require('EmberRoutesProbe/LeisureService').standable(require('EmberRoutesProbe/MembershipService').entry(id,event.settlementId),point,{npc})~=nil
    return valid==true,evidence.at
end
function P.present(event,id)
    local member=event.roster[id]
    if not member or member.withdrawn or not member.joined then return false end
    local binding=Driver.bindId(getSpecificPlayer(0),id)
    if not binding or not Driver.valid(binding) or not safe(binding) then return false end
    local npc=binding.handle
    return require('EmberRoutesProbe/SettlementZones').location(event.settlementId,event.zone,
        {x=npc:getX(),y=npc:getY(),z=math.floor(npc:getZ())})==true
end
local function submit(actor,binding,event,member)
    local job=Jobs.current():peek(member.jobId) local rt=Runtime.current()
    if not job or job.effects~='KNOWN' or job.state~='PREPARING' or not rt or not rt:accepting() or rt:owns(binding.id) then return end
    local Service=require 'EmberRoutesProbe/ActivityService'
    local ref=Service.context(binding.id)
    if #job.payload.claims>0 then
        local old=handles[job.id] local outcome=old and old.runtime:inspect(old.handle)
        if not releasePlacement(job,not job.payload.started and outcome and (outcome.state=='CANCELLED' or outcome.state=='REJECTED')) then return end
        job=Jobs.current():peek(job.id)
    end
    if not ref or not Service.allowsPoint(event.settlementId,binding.id,
        {x=binding.handle:getX(),y=binding.handle:getY(),z=math.floor(binding.handle:getZ())}) then return end
    if require('EmberRoutesProbe/ActivityAttendance').inspect(actor,binding.id,ref)~='READY' or not safe(binding) then return end
    if not Service.arrived(actor,binding,ref) then return end
    require('EmberRoutesProbe/SocialCoordinator').withdraw(binding.id)
    local p=Store.copy(job.payload)
    p.sequence=p.sequence+1 p.point={x=binding.handle:getX(),y=binding.handle:getY(),z=math.floor(binding.handle:getZ())}
    p.claims={Tile.tileKey(p.point)}
    local owner=Assets.resourceOwner(p.claims[1])
    if owner and owner.taskId~=job.id then return end
    if not update(job,p) then return end job=Jobs.current():peek(job.id)
    local token=Assets.claimActivity(job)
    if not token then
        p.claims={}
        update(job,p) return
    end
    local sequence=job.payload.sequence local placement=job.payload.claims[1]
    local key=job.id local root=load() local stopping,free=false,false
    local function same()
        local live=Jobs.current():peek(key)
        return Registry.data()==root and live and live.payload.eventId==event.id and live.effects=='KNOWN'
            and live.payload.sequence==sequence
    end
    local spec={npcId=binding.id,jobId=key,kind='ACTIVITY',binding=binding,nonPreemptive=true,captureStop=true,reconcileErrors=true}
    function spec.validate()
        local live=Service.context(binding.id)
        local point={x=binding.handle:getX(),y=binding.handle:getY(),z=math.floor(binding.handle:getZ())}
        return same() and live and live.controlEpoch==ref.controlEpoch and live.participantEpoch==ref.participantEpoch and event.state=='GATHERING'
            and Assets.validActivity(job,token) and placement==Tile.tileKey(point)
            and Service.allowsPoint(event.settlementId,binding.id,point) and safe(binding)==true
            and require('EmberRoutesProbe/LeisureService').standable(require('EmberRoutesProbe/MembershipService').entry(binding.id,event.settlementId),point,{binding.handle})~=nil
    end
    function spec.start(body)
        if not spec.validate() then return false,'ACTIVITY_CHANGED','UNCHANGED' end
        local live=Jobs.current():peek(key) local p=Store.copy(live.payload)
        p.step='WAITING' p.started=true p.stopped=false
        if not update(live,p,'RUNNING') then return false,'ACTIVITY_CHANGED','UNCHANGED' end
        member.state='ACCEPTED' member.attendanceState='READY' member.reason=nil
        member.readyJobId=key member.readyAt=getGameTime():getWorldAgeHours()
        ready[key]={at=getTimestampMs(),binding=binding} Store.touch(event)
        return true
    end
    function spec.tick()
        local live=Service.context(binding.id)
        local ok,why=safe(binding)
        if not live or not ok then Service.leave(binding.id,why or 'ACTIVITY_CHANGED') stopping=true return end
        if event.state=='RUNNING' and member.joined then free=true return end
        if not spec.validate() then Service.leave(binding.id,'ACTIVITY_SITE_CHANGED') stopping=true
        else ready[key]={at=getTimestampMs(),binding=binding} end
    end
    function spec.finished() return stopping or free end
    function spec.stopAdapter(controller,ticket)
        return require('EmberRoutesProbe/TaskBusinessStop').new({controller=controller,ticket=ticket,
            npc=binding.handle,npcId=binding.id,jobId=key,same=same,
            pause=function()
                stopping=true if ready[key] then ready[key]=nil Store.touch(event) end return true
            end,effects=function() return 'KNOWN' end,
            persist=function(fact)
                local live=Jobs.current():peek(key) if not live then return false end
                local p=Store.copy(live.payload) p.stopped=fact.bodyStopped==true
                if ready[key] then ready[key]=nil Store.touch(event) end
                p.step='LEAVING'
                if live.state=='RUNNING' then
                    if not update(live,p,'STOPPING') then return false end live=Jobs.current():peek(key)
                end
                if fact.effects=='KNOWN' and not releasePlacement(live,fact.bodyStopped) then return false end
                live=Jobs.current():peek(key) p=Store.copy(live.payload)
                p.stopped=fact.bodyStopped==true
                p.step=free and event.state=='RUNNING' and (event.scriptProfile and 'PERSONAL' or 'FREE') or 'LEAVING'
                return update(live,p,fact.effects=='KNOWN' and 'SUSPENDED' or 'RECONCILE_REQUIRED',fact.effects)
            end})
    end
    function spec.persistFailure(fact)
        if Registry.data()~=root then return false end
        if ready[key] then ready[key]=nil Store.touch(event) end
        local live=Jobs.current():peek(key) if not live then return false end
        local p=Store.copy(live.payload) p.step='LEAVING'
        if not p.started then p.stopped=true end
        if fact.effects=='KNOWN' and not releasePlacement(live,fact.bodyStopped) then return false end
        live=Jobs.current():peek(key) p.claims=live.payload.claims
        return update(live,p,fact.effects=='KNOWN' and 'SUSPENDED' or 'RECONCILE_REQUIRED',fact.effects)
    end
    local handle=rt:submit(spec)
    if handle then handles[key]={runtime=rt,handle=handle,token=token,sequence=sequence}
    else releasePlacement(Jobs.current():peek(key),true) end
end
function P.advance(actor,event,id)
    load() local member=event.roster[id]
    if not member or not member.jobId then return end
    local job=Jobs.current():peek(member.jobId)
    if not job then return end
    if member.withdrawn or event.state=='WINDING_DOWN' or event.state=='SETTLING' then
        P.stop(id,event) P.collectOne(event,id) return
    end
    local binding=Driver.bindId(actor,id)
    if not binding or not Driver.valid(binding) then
        require('EmberRoutesProbe/ActivityService').leave(id,'ACTIVITY_CARRIER_UNAVAILABLE') return
    end
    if event.state=='GATHERING' and job.payload.step=='INVITED' then
        local now=getTimestampMs() local previous=assessments[id]
        if not previous or previous.event~=event.id or now<previous.at or now-previous.at>=1000 then
            local care=personal(id)
            local ref=require('EmberRoutesProbe/ActivityService').context(id)
            local state,reason=require('EmberRoutesProbe/ActivityAttendance').inspect(actor,id,ref,care and care.id)
            if state=='READY' then
                local allowed,why=safe(binding)
                if not allowed then state,reason='WAIT',why else
                    state=require('EmberRoutesProbe/ActivityService').allowsPoint(event.settlementId,id,
                        {x=binding.handle:getX(),y=binding.handle:getY(),z=math.floor(binding.handle:getZ())}) and 'ADMITTED' or 'TRAVELLING'
                end
            end
            if member.attendanceState~=state or member.reason~=reason then
                member.attendanceState=state member.reason=reason Store.touch(event,true)
            end
            assessments[id]={event=event.id,at=now}
        end
    end
    if event.state=='GATHERING' and job.payload.step=='INVITED' then submit(actor,binding,event,member) return end
    if event.state~='RUNNING' or not member.joined or job.payload.step~='FREE' and job.payload.step~='PERSONAL' then return end
    local live=require('EmberRoutesProbe/ActivityService').context(id)
    if not live or live.eventId~=event.id or not live.joined then samples[id]=nil return end
    local ok,reason=safe(binding)
    if not ok then require('EmberRoutesProbe/ActivityService').leave(id,reason) return end
    local p=personal(id) local rt,status=current(id) local npc=binding.handle
    local inside=require('EmberRoutesProbe/ActivityService').allowsPoint(event.settlementId,id,
        {x=npc:getX(),y=npc:getY(),z=math.floor(npc:getZ())})
    local active=inside and Responsibilities.activeParticipation(p,event,status)
    local now,hours=getTimestampMs(),getGameTime():getWorldAgeHours()
    if event.scriptProfile and event.stage.sharedEnd then hours=math.min(hours,event.stage.sharedEnd) end
    local old=samples[id]
    if active and old and old.event==event.id and old.job==p.id and old.attempt==p.payload.attemptId
        and now>=old.real and now-old.real<=4000 and hours>=old.hours then
        member.participationHours=(member.participationHours or 0)+math.min(hours-old.hours,event.durationHours)
        Store.touch(event,true)
    end
    samples[id]=active and {event=event.id,job=p.id,attempt=p.payload.attemptId,real=now,hours=hours} or nil
end
function P.prepareRecovery(receipt)
    load()
    for _,job in pairs(world.taskJobs and world.taskJobs.byId or {}) do
        if job.providerType=='ACTIVITY' and job.state~='DONE' and job.state~='CANCELLED' then
            local p=Store.copy(job.payload)
            local fact=receipt and receipt.state=='CAPTURED' and receipt.byNpc and receipt.byNpc[job.npcId]
            local proven=fact and fact.jobId==job.id and fact.bodyStopped==true and fact.effects=='KNOWN'
                or not p.started and receipt and receipt.state=='CAPTURED'
            if p.started and not p.stopped and not proven or #p.claims>0 and not p.stopped and not proven then
                update(job,p,'RECONCILE_REQUIRED','UNKNOWN')
            elseif job.effects=='KNOWN' then
                p.step='LEAVING' p.stopped=p.stopped or proven==true
                if update(job,p,job.state=='PREPARING' and 'SUSPENDED' or job.state) then
                    releasePlacement(Jobs.current():peek(job.id),p.stopped)
                end
            end
        end
    end
    return true
end
return P
