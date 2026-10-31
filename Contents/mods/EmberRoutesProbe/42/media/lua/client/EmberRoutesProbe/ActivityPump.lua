-- A helper driven only by Service.tick. Cursors/receipts are disposable, not a
-- second scheduler, saved state machine or source of body/asset authority.
local Store=require 'EmberRoutesProbe/ActivityStore'
local Definitions=require 'EmberRoutesProbe/ActivityRegistry'
local Stages=require 'EmberRoutesProbe/ActivityStages'
local Duties=require 'EmberRoutesProbe/ActivityDuties'
local Scripted=require 'EmberRoutesProbe/ActivityScripted'
local Relief=require 'EmberRoutesProbe/ActivityRelief'
local P
local Pump={INTERVAL=100,HEADERS=4,PHASE_MEMBERS=32,BODY_MEMBERS=16,EFFECT_MEMBERS=2,CALENDAR=2,PROOF_TTL=2000}
function Pump.new(env)
    local root,nextAt,headCursor,phaseCursor,bodyCursor,version,lastAt=nil,0,0,0,0,nil,nil
    local phases,bodies,last={},{},{}
    local api={}
    local function cursor(ids,n)
        if #ids==0 then return nil,0 end
        n=n%#ids+1 return Store.get(ids[n]),n
    end
    local function withdraw(event,id)
        local m=event.roster[id]
        if m and not m.withdrawn then m.reason=m.reason or 'ACTIVITY_MEMBERSHIP_CHANGED' Store.withdraw(event.id,id) end
    end
    local function cycle(event,kind)
        local iter,state,key=pairs(event.roster)
        return {phase=event.state,kind=kind,revision=event.revision,control=event.controlEpoch,
            iter=iter,state=state,key=key,any=false,all=true,count=0,set={},oldest=math.huge}
    end
    local function finish(event,c,now,hours)
        if event.state~=c.phase or event.controlEpoch~=c.control then return end
        if c.kind=='CLOSE' then P.finishCollection(event,c.all) return end
        if event.revision~=c.revision then return end
        if c.kind=='SCRIPTED' then
            if c.oldest<math.huge and (now<c.oldest or now-c.oldest>Pump.PROOF_TTL) then return end
            Scripted.finish(event,c,hours,env.memberValid) return
        end
        if not c.any then Store.close(event.id,event.revision,'ROSTER_WITHDRAWN') return end
        if c.oldest<math.huge and (now<c.oldest or now-c.oldest>Pump.PROOF_TTL) then return end
        if c.kind=='GATHER' then
            -- Bounded atomic metadata recheck, not a second native roster scan.
            for id in pairs(c.set) do if not P.receipt(event,id) then return end end
            if c.set[event.organizerId] and (not event.speakerId or c.set[event.speakerId]) and c.count>=event.quorum and (c.all or hours>=event.gatherDeadline) then
                local epoch=(event.stageEpoch or 1)+1
                local stage,why
                if event.scriptProfile then stage=Scripted.open(event,c.set,hours,epoch)
                else stage,why=Stages.free(event,c.set,hours,epoch) end
                if not stage then Store.close(event.id,event.revision,why or 'ACTIVITY_STAGE_INVALID') return end
                event.state='RUNNING' event.startedAt=hours event.endsAt=hours+event.durationHours
                event.stageEpoch=epoch event.stage=stage
                if event.scriptProfile then event.endsAt=stage.deadline end
                event.dutyFormat=Duties.FORMAT
                -- Atomic, bounded scalar publication; no native body operations.
                for id,m in pairs(event.roster) do
                    m.joined=c.set[id]==true
                    if m.joined then m.duty=Duties.new() end
                    m.readyJobId=nil m.readyAt=nil -- gathering-only proof; stage has frozen the accepted set
                    if not m.joined then m.reason=m.reason or 'LATE_ARRIVAL' Store.withdraw(event.id,id) end
                end
                Store.touch(event)
            elseif hours>=event.gatherDeadline then Store.close(event.id,event.revision,'QUORUM_NOT_MET') end
        elseif c.kind=='COMPLETE' then
            Store.close(event.id,event.revision,c.set[event.organizerId] and c.count>=event.quorum and 'COMPLETED' or 'INCOMPLETE')
        end
    end
    local function inspectHeader(event,hours)
        if not event or event.state=='CLOSED' then return end
        if event.state=='GATHERING' or event.state=='RUNNING' then
            if event.stageBlocked or event.dutyBlocked then Store.close(event.id,event.revision,'ACTIVITY_STAGE_UNSUPPORTED')
            elseif not Definitions.compatible(event.definition,event.definitionVersion) then Store.close(event.id,event.revision,'ACTIVITY_DEFINITION_CHANGED')
            elseif not env.site(event) then Store.close(event.id,event.revision,'ZONE_CHANGED')
            elseif event.state=='GATHERING' and hours>=event.endsAt then Store.close(event.id,event.revision,'INCOMPLETE')
            elseif event.state=='RUNNING' and (not env.memberValid(event.organizerId,event)
                or event.speakerId and not env.memberValid(event.speakerId,event)) then
                Store.close(event.id,event.revision,'REQUIRED_ROLE_LEFT')
            end
        end
    end
    local function phaseMember(event,now,hours)
        if not event or event.state=='CLOSED' then return false end
        local closing=event.state=='WINDING_DOWN' or event.state=='SETTLING'
        local kind=closing and 'CLOSE' or event.state=='GATHERING' and event.organizerId and 'GATHER'
            or event.state=='RUNNING' and event.scriptProfile and 'SCRIPTED'
            or event.state=='RUNNING' and hours>=event.endsAt and 'COMPLETE' or 'ACTIVE'
        local c=phases[event.id]
        if not c or c.phase~=event.state or c.control~=event.controlEpoch or c.kind~=kind
            or not closing and c.revision~=event.revision then c=cycle(event,kind) phases[event.id]=c end
        if c.nextAt and now<c.nextAt then return false end
        if c.finished then c=cycle(event,kind) phases[event.id]=c end
        local id,m=c.iter(c.state,c.key) c.key=id
        if not id then
            finish(event,c,now,hours)
            c.finished=true c.nextAt=now+1000
            return false
        end
        if closing then
            P.stop(id,event)
            if not P.collectOne(event,id,true) then c.all=false end
        elseif kind=='SCRIPTED' then
            if not m.withdrawn and not env.memberValid(id,event) then withdraw(event,id) end
            Scripted.inspect(getSpecificPlayer(0),event,id,P,c,now)
        elseif m.withdrawn then
            P.stop(id,event) P.collectOne(event,id)
        elseif not env.memberValid(id,event) then withdraw(event,id)
        else
            c.any=true
            if kind=='GATHER' then
                local ready,at=P.proof(event,id)
                if ready and (m.readyAt or math.huge)<=event.gatherDeadline then
                    c.set[id]=true c.count=c.count+1 c.oldest=math.min(c.oldest,at or now)
                else c.all=false end
            elseif kind=='COMPLETE' and (m.participationHours or 0)>0 then
                if P.present(event,id) then c.set[id]=true c.count=c.count+1 end
                c.oldest=math.min(c.oldest,now)
            end
        end
        return true
    end
    local function bodyMember(event,actor,seen)
        if not event or event.state~='GATHERING' and event.state~='RUNNING' then return false end
        local c=bodies[event.id]
        if not c or c.roster~=event.roster then
            local iter,state,key=pairs(event.roster) c={iter=iter,state=state,key=key,roster=event.roster} bodies[event.id]=c
        end
        local id,m=c.iter(c.state,c.key) c.key=id
        if not id then bodies[event.id]=nil return false end
        if seen[id] or not m.jobId or m.settled then return false end
        seen[id]=true P.advance(actor,event,id) return true
    end
    function api.tick(actor,saved,now,hours)
        P=P or require 'EmberRoutesProbe/ActivityParticipant'
        if saved~=root or lastAt and now<lastAt then
            root=saved nextAt=0 headCursor=0 phaseCursor=0 bodyCursor=0 phases={} bodies={} version=nil
        end
        lastAt=now
        if now<nextAt then return end nextAt=now+Pump.INTERVAL
        Relief.budget(Pump.EFFECT_MEMBERS)
        local ids,changed=Store.active() if not ids then return end
        if changed~=version then
            version=changed
            for id in pairs(phases) do local e=Store.get(id) if not e or e.state=='CLOSED' then phases[id]=nil bodies[id]=nil end end
            for id in pairs(bodies) do local e=Store.get(id) if not e or e.state=='CLOSED' then bodies[id]=nil end end
        end
        last={headers=0,phaseMembers=0,bodyMembers=0}
        for _=1,math.min(Pump.HEADERS,#ids) do
            local event
            event,headCursor=cursor(ids,headCursor) inspectHeader(event,hours) last.headers=last.headers+1
        end
        for _=1,Pump.PHASE_MEMBERS do
            if #ids==0 then break end
            local event
            event,phaseCursor=cursor(ids,phaseCursor)
            if phaseMember(event,now,hours) then last.phaseMembers=last.phaseMembers+1 end
        end
        local seen={}
        for _=1,Pump.BODY_MEMBERS do
            if #ids==0 then break end
            local event
            event,bodyCursor=cursor(ids,bodyCursor)
            if bodyMember(event,actor,seen) then last.bodyMembers=last.bodyMembers+1 end
        end
        if env.calendar then env.calendar(actor,hours,Pump.CALENDAR) end
    end
    function api.stats() return {headers=last.headers or 0,phaseMembers=last.phaseMembers or 0,bodyMembers=last.bodyMembers or 0} end
    return api
end
return Pump
