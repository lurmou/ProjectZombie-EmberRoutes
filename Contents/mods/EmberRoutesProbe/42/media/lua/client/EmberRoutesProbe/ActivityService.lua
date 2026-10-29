-- FREE preference context. Attendance/physical execution remain separate.
local Store=require 'EmberRoutesProbe/ActivityStore'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Definitions=require 'EmberRoutesProbe/ActivityRegistry'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Members=require 'EmberRoutesProbe/MembershipService'
local Zones=require 'EmberRoutesProbe/SettlementZones'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Resume=require 'EmberRoutesProbe/TaskResume'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local S={}
local pumping
local world,opened,tokens,sites
local function clock() return getGameTime():getWorldAgeHours() end
local function load()
    local root=Registry.data()
    if root~=world then world,opened,tokens,sites=root,nil,{},{} end
    local saved,why=Store.current()
    if saved~=opened then opened,tokens,sites=saved,{},{} end
    return saved,why
end
local function memberValid(id,event)
    local expected=event.roster[id] local m=Members.view(id)
    return expected and not expected.withdrawn and m and not m.retired and not m.pending and m.context=='SETTLEMENT'
        and m.settlementId==event.settlementId and m.revision==expected.membershipRevision
        and Resume.epoch(id)==expected.commandEpoch and Members.entry(id,event.settlementId)~=nil
end
local function site(event)
    local entry=Ledger.data().entries[event.settlementId]
    local version=Zones.revision()
    local cache=sites[event.id]
    if cache and cache.parent==entry and cache.parentRevision==(entry and entry.revision)
        and cache.zones==version and cache.zoneRevision==event.zone.revision then return cache.value end
    local zone=Zones.get(event.zone.id)
    local value
    if zone and entry and zone.enabled and zone.revision==event.zone.revision
        and zone.settlementId==event.settlementId and Zones.covered(entry,zone.area) then value=zone end
    sites[event.id]={parent=entry,parentRevision=entry and entry.revision,zones=version,
        zoneRevision=event.zone.revision,value=value}
    return value
end
local function refresh(saved)
    local now=clock()
    for id,event in pairs(saved.events) do
        if event.state=='GATHERING' or event.state=='RUNNING' then
            if now>=event.endsAt then
                local n=0
                for npc,m in pairs(event.roster) do
                    if (m.participationHours or 0)>0 and require('EmberRoutesProbe/ActivityParticipant').present(event,npc) then n=n+1 end
                end
                local host=event.organizerId and event.roster[event.organizerId]
                local completed=event.state=='RUNNING' and host and not host.withdrawn
                    and (host.participationHours or 0)>0 and n>=(event.quorum or 1)
                    and require('EmberRoutesProbe/ActivityParticipant').present(event,event.organizerId)
                Store.close(id,event.revision,completed and 'COMPLETED' or 'INCOMPLETE')
                require('EmberRoutesProbe/ActivityParticipant').collect(event)
            elseif not site(event) then
                Store.close(id,event.revision,'ZONE_CHANGED')
            else
                local any=false
                for npc in pairs(event.roster) do
                    if memberValid(npc,event) then any=true else Store.withdraw(id,npc) end
                end
                if not any then
                    Store.close(id,event.revision,'ROSTER_WITHDRAWN')
                    require('EmberRoutesProbe/ActivityParticipant').collect(event)
                end
            end
        end
        if event.state=='CLOSED' then sites[id]=nil end
    end
end
function S.preview(actor,args,deferred)
    if type(args)~='table' then return nil,'ACTIVITY_DATA_INVALID' end
    local entry,why=Ledger.view(actor,args.settlementId) if not entry then return nil,why end
    local zone=Zones.get(args.zoneId)
    if not zone or not zone.enabled or zone.settlementId~=entry.id or not Zones.covered(entry,zone.area)
        or zone.revision~=args.zoneRevision then return nil,'ZONE_CHANGED' end
    local name=type(args.name)=='string' and args.name:match('^%s*(.-)%s*$')
    local rules=Definitions.rules(args.rules)
    local duration=args.durationHours
    if not name or #name<1 or #name>64 or name:find('[%c]') or not rules
        or type(duration)~='number' or duration~=duration or duration<1/60 or duration>24
        or type(args.roster)~='table' then return nil,'ACTIVITY_DATA_INVALID' end
    local roster,count={},0
    for key,id in pairs(args.roster) do
        count=count+1
        if count>256 or type(key)~='number' or key~=math.floor(key) or key<1 or key>256
            or type(id)~='string' or #id<1 or #id>128 or roster[id] then return nil,'ACTIVITY_ROSTER_INVALID' end
        local m=Members.view(id)
        if not m or m.retired or m.pending or m.context~='SETTLEMENT' or m.settlementId~=entry.id
            or not Members.entry(id,entry.id) then return nil,'ACTIVITY_ROSTER_INVALID' end
        if not deferred and require('EmberRoutesProbe/ActivityParticipant').retains(id) then return nil,'ACTIVITY_SETTLING' end
        roster[id]={membershipRevision=m.revision,commandEpoch=Resume.epoch(id)}
    end
    if count<1 then return nil,'ACTIVITY_ROSTER_INVALID' end
    local organizer=args.organizerId or args.roster[1]
    local quorum=args.quorum or math.min(2,count)
    local gather=args.gatherHours or math.min(duration,1/6)
    if not roster[organizer] or type(quorum)~='number' or quorum~=math.floor(quorum) or quorum<1 or quorum>count
        or quorum>zone.area.w*zone.area.h or type(gather)~='number' or gather~=gather or gather<1/60 or gather>24 then
        return nil,'ACTIVITY_ROSTER_INVALID'
    end
    if not deferred and Jobs.current():ordinaryCount()+count>require('EmberRoutesProbe/JobStore').LIMIT then return nil,'JOB_LIMIT' end
    return {definition='FREE_GATHERING',definitionVersion=1,name=name,settlementId=entry.id,
        zone={id=zone.id,revision=zone.revision},rules=rules,roster=roster,durationHours=duration,
        organizerId=organizer,quorum=quorum,gatherHours=gather,controlEpoch=1,stageEpoch=1}
end
function S.issue(actor,scope)
    local entry,why=Ledger.view(actor,scope) if not entry then return nil,why end
    local saved,reason=load() if not saved then return nil,reason end
    local owner=Members.character(actor) if not owner then return nil,'ACTOR_UNAVAILABLE' end
    local now=getTimestampMs() local count=0
    for id,t in pairs(tokens) do if t.untilTime<now then tokens[id]=nil else count=count+1 end end
    if count>=128 then return nil,'ACTIVITY_LIMIT' end
    local id=Registry.id() tokens[id]={owner=owner,scope=scope,untilTime=now+120000}
    return id
end
function S.start(actor,args,token)
    local saved,why=load() if not saved then return nil,why end
    local scope=type(args)=='table' and args.settlementId
    local entry,reason=Ledger.view(actor,scope) if not entry then return nil,reason end
    local owner=Members.character(actor)
    local signature=Definitions.commandKey(args) if not signature then return nil,'ACTIVITY_DATA_INVALID' end
    for _,e in pairs(saved.events) do
        if e.requestId==token then
            if e.requesterId~=owner or e.settlementId~=scope then return nil,'ACTIVITY_REQUEST_CONFLICT' end
            if e.proposalKey~=signature then return nil,'ACTIVITY_REQUEST_CONFLICT' end
            return Store.copy(e) -- Issued token denotes one immutable intent, including after close.
        end
    end
    local issued=tokens[token]
    if not issued or issued.owner~=owner or issued.scope~=scope or issued.untilTime<getTimestampMs() then
        return nil,'ACTIVITY_REQUEST_EXPIRED'
    end
    refresh(saved)
    local row,invalid=S.preview(actor,args) if not row then return nil,invalid end
    local now=clock()
    row.proposalKey=signature
    row.id=Registry.id() row.requestId=token row.requesterId=owner row.revision=1 row.state='GATHERING'
    row.createdAt=now row.gatherDeadline=now+row.gatherHours row.gatherHours=nil
    row.endsAt=row.gatherDeadline+row.durationHours
    local result,failed=Store.insert(row)
    if result then
        tokens[token]=nil
        local event=Store.get(result.id)
        local ok,why=require('EmberRoutesProbe/ActivityParticipant').prepare(event)
        if not ok then Store.close(event.id,event.revision,why) end
        result=Store.copy(event)
    end
    return result,failed
end
function S.schedule(actor,args,token,firstAt,interval,count)
    local preview,why=S.preview(actor,args,true) if not preview then return nil,why end
    local saved,reason=load() if not saved then return nil,reason end
    local rows,invalid=Store.schedules() if not rows then return nil,invalid end
    local Calendar=require 'EmberRoutesProbe/ActivitySchedule'
    local signature=Definitions.commandKey(args)
    local key=signature..'|schedule:'..tostring(firstAt)..':'..tostring(interval)..':'..tostring(count)
    local owner=Members.character(actor) local total,oldest=0,nil
    for _,s in pairs(rows) do
        if not Calendar.valid(s) or not Store.scalar(s) then return nil,'ACTIVITY_SCHEDULE_INVALID' end
        if s.requestId==token then
            if s.owner==owner and s.key==key then return Store.copy(s) end
            return nil,'ACTIVITY_REQUEST_CONFLICT'
        end
        total=total+1
        if not s.enabled then
            local busy=false for _,e in pairs(saved.events) do if e.scheduleId==s.id and e.state~='CLOSED' then busy=true break end end
            if not busy and (not oldest or s.firstAt<oldest.firstAt) then oldest=s end
        end
    end
    local issued=tokens[token]
    if not issued or issued.owner~=owner or issued.scope~=args.settlementId or issued.untilTime<getTimestampMs() then return nil,'ACTIVITY_REQUEST_EXPIRED' end
    local row={format=1,id=Registry.id(),owner=owner,requestId=token,key=key,enabled=true,
        firstAt=firstAt,intervalHours=interval,count=count,lastIndex=-1,args=Store.copy(args),revision=1}
    if not Calendar.valid(row) or not Store.scalar(row) or firstAt<clock() then return nil,'ACTIVITY_SCHEDULE_INVALID' end
    if total>=Calendar.LIMIT then if not oldest then return nil,'ACTIVITY_LIMIT' end rows[oldest.id]=nil end
    rows[row.id]=row tokens[token]=nil saved.revision=saved.revision+1
    return Store.copy(row)
end
function S.cancelSchedule(actor,id,expected)
    local rows,why=Store.schedules() if not rows then return false,why end
    local row=rows[id]
    if not row or not require('EmberRoutesProbe/ActivitySchedule').valid(row) or not Store.scalar(row) then return false,'ACTIVITY_SCHEDULE_INVALID' end
    if not Ledger.view(actor,row.args.settlementId) then return false,'ACCESS_DENIED' end
    if row.revision~=expected then return false,'ACTIVITY_CHANGED' end
    row.enabled=false row.revision=row.revision+1 return true
end
function S.schedules(actor,scope)
    if not Ledger.view(actor,scope) then return nil,'ACCESS_DENIED' end
    local rows,why=Store.schedules() if not rows then return nil,why end
    local result={}
    for _,s in pairs(rows) do
        if not require('EmberRoutesProbe/ActivitySchedule').valid(s) or not Store.scalar(s) then return nil,'ACTIVITY_SCHEDULE_INVALID' end
        if s.args.settlementId==scope then result[#result+1]=Store.copy(s) end
    end
    table.sort(result,function(a,b) return a.firstAt==b.firstAt and a.id<b.id or a.firstAt<b.firstAt end)
    return result
end
function S.tickSchedules(actor,hours)
    local rows=Store.schedules() if not rows then return end
    local Calendar=require 'EmberRoutesProbe/ActivitySchedule'
    local saved=Store.current() local total=0
    for _,s in pairs(rows) do
        total=total+1 if total>Calendar.LIMIT then return end
        if Calendar.valid(s) and Store.scalar(s) and s.owner==Members.character(actor) then
            local index,run=Calendar.due(s,hours)
            if index and index>s.lastIndex then
                s.lastIndex=index s.revision=s.revision+1
                local busy=false
                for _,e in pairs(saved.events) do if e.scheduleId==s.id and e.state~='CLOSED' then busy=true break end end
                if run and not busy then
                    -- Persisted occurrence identity is separate from UI command tokens.
                    local occurrence='schedule:'..s.id..':'..tostring(index)
                    local exists=false for _,e in pairs(saved.events) do if e.requestId==occurrence then exists=true break end end
                    if not exists then
                        local intent,why=S.preview(actor,s.args)
                        if intent then
                            intent.id=Registry.id() intent.requestId=occurrence intent.requesterId=s.owner intent.scheduleId=s.id
                            intent.proposalKey=Definitions.commandKey(s.args) intent.revision=1 intent.state='GATHERING'
                            intent.createdAt=hours intent.gatherDeadline=hours+intent.gatherHours intent.gatherHours=nil
                            intent.endsAt=intent.gatherDeadline+intent.durationHours
                            local result,failed=Store.insert(intent)
                            if result then
                                local event=Store.get(result.id)
                                local ok,err=require('EmberRoutesProbe/ActivityParticipant').prepare(event)
                                if not ok then Store.close(event.id,event.revision,err) end
                                s.lastEventId=event.id s.reason=nil
                            else s.reason=failed end
                        else s.reason=why end
                    end
                else s.reason=busy and 'ACTIVITY_PREVIOUS_UNSETTLED' or 'ACTIVITY_MISSED_WINDOW' end
                if index>=s.count-1 then s.enabled=false end
            end
        end
    end
end
function S.cancel(actor,id,expected)
    local saved,why=load() if not saved then return false,why end
    local event=saved.events[id] if not event then return false,'ACTIVITY_MISSING' end
    local entry,reason=Ledger.view(actor,event.settlementId) if not entry then return false,reason end
    local ok,failed=Store.close(id,expected,'CANCELLED')
    if ok then
        sites[id]=nil
        local Participant=require 'EmberRoutesProbe/ActivityParticipant'
        for npc in pairs(event.roster) do Participant.stop(npc,event) end
        Participant.collect(event)
    end
    return ok,failed
end
function S.finishScenes(reason)
    local saved,why=load() if not saved then return false,why end
    for id,event in pairs(saved.events) do
        if event.state~='CLOSED' then
            Store.close(id,event.revision,reason)
            local p=require 'EmberRoutesProbe/ActivityParticipant'
            for npc in pairs(event.roster) do p.stop(npc,event) end
            p.collect(event)
        end
    end
    tokens,sites={},{} return true
end
function S.view(actor,scope)
    local entry,why=Ledger.view(actor,scope) if not entry then return nil,why end
    local saved,reason=load() if not saved then return nil,reason end
    refresh(saved)
    local result={}
    for id,event in pairs(saved.events) do
        if event.settlementId==scope then result[#result+1]=Store.copy(event) end
    end
    table.sort(result,function(a,b) return a.createdAt==b.createdAt and a.id<b.id or a.createdAt<b.createdAt end)
    return result
end
-- Detached scalar intent, never a body grant or a claim of attendance.
function S.context(id)
    local saved=load() if not saved then return end
    local event=Store.forNpc(id)
    if not event or event.state~='GATHERING' and event.state~='RUNNING' or clock()>=event.endsAt or not memberValid(id,event)
        or not site(event) then return end
    return {eventId=event.id,settlementId=event.settlementId,
        id=event.zone.id,revision=event.zone.revision,endsAt=event.endsAt,
        controlEpoch=event.controlEpoch,phase=event.state,joined=event.roster[id].joined==true,
        commandEpoch=event.roster[id].commandEpoch,membershipRevision=event.roster[id].membershipRevision}
end
function S.validRef(id,ref)
    local live=S.context(id)
    return live and type(ref)=='table' and live.eventId==ref.eventId and live.controlEpoch==ref.controlEpoch
        and live.id==ref.id and live.revision==ref.revision and live.phase=='RUNNING' and live.joined or false
end
function S.leave(id,reason)
    local ref=S.context(id) if not ref then return false end
    local event=Store.get(ref.eventId)
    event.roster[id].reason=reason
    Store.withdraw(event.id,id)
    require('EmberRoutesProbe/ActivityParticipant').stop(id,event)
    if id==event.organizerId and event.state=='RUNNING' then Store.close(event.id,event.revision,'REQUIRED_ROLE_LEFT') end
    return true
end
function S.allowsPoint(scope,id,point)
    local ref=S.context(id) if not ref then return true end
    return ref.settlementId==scope and Zones.location(scope,ref,point)==true
end
function S.destination(scope,id,ref,point)
    if type(ref)~='table' then return false end
    if not ref.eventId then return Zones.destination(scope,ref,point) end
    local current=S.context(id)
    if not current or current.eventId~=ref.eventId or current.settlementId~=scope
        or current.id~=ref.id or current.revision~=ref.revision or not Zones.location(scope,ref,point) then return false end
    local rule=S.policyAt(scope,id,point.x,point.y,point.z,'OBSERVE')
    return rule~=nil and rule>0
end
function S.arrived(actor,binding,ref,careId)
    local id,npc=binding.id,binding.handle
    if not require('EmberRoutesProbe/Driver').valid(binding) then return false end
    local current=S.context(id)
    local entry=current and Ledger.view(actor,current.settlementId)
    if not entry then return false end
    local point={x=npc:getX(),y=npc:getY(),z=math.floor(npc:getZ())}
    if not S.destination(current.settlementId,id,ref,point) then return false end
    if not require('EmberRoutesProbe/LeisureService').standable(entry,point,{npc}) then return false end
    local ready=require('EmberRoutesProbe/ActivityAttendance').inspect(actor,id,ref,careId)
    if ready~='READY' then return false end
    return Store.arrived(ref.eventId,id,point,clock())
end
function S.policyAt(scope,id,x,y,z,behavior)
    local base,why=Zones.policyAt(scope,x,y,z,behavior)
    if base==nil then return nil,why end
    local saved,reason=load() if not saved then return base,reason end
    local event=Store.forNpc(id)
    if not event or event.state=='CLOSED' or event.settlementId~=scope
        or clock()>=event.endsAt or not memberValid(id,event) then return base end
    local zone=site(event)
    if not zone or z~=zone.area.z or not Geometry.contains(zone.area,x,y) then return base end
    -- Explicit event behavior preferences replace ordinary behavior policy only.
    -- Physical permissions, safety, original-item and body gates remain outside.
    local override=event.rules[behavior]
    if override~=nil then return override end
    return base
end
function S.tick()
    local Probe=require 'EmberRoutesProbe/Boot'
    if not Probe.ready or not Probe.runtimeReady or isClient() or isServer() then return end
    local saved=load() if not saved then return end
    local now,hours=getTimestampMs(),clock()
    if not pumping or pumping.root~=saved then pumping={root=saved,next=0,phaseAt=0,cursor=0,actors={}} end
    if now<pumping.next then return end pumping.next=now+100
    local actor=getSpecificPlayer(0) if not actor or actor:isDead() then return end
    local Participant=require 'EmberRoutesProbe/ActivityParticipant'
    if now>=pumping.phaseAt then
        pumping.phaseAt=now+1000 refresh(saved)
        if S.tickSchedules then S.tickSchedules(actor,hours) end
        local actors={}
        for id,event in pairs(saved.events) do
            if event.state=='GATHERING' and event.organizerId then
                local set,count,all={},0,true
                for npc,m in pairs(event.roster) do
                    if not m.withdrawn then
                        if Participant.proof(event,npc) and (m.readyAt or math.huge)<=event.gatherDeadline then
                            set[npc]=true count=count+1
                        else all=false end
                    end
                end
                if set[event.organizerId] and count>=event.quorum and (all or hours>=event.gatherDeadline) then
                    event.state='RUNNING' event.startedAt=hours event.endsAt=hours+event.durationHours
                    event.stageEpoch=(event.stageEpoch or 1)+1
                    for npc,m in pairs(event.roster) do
                        m.joined=set[npc]==true
                        if not m.joined then m.reason='LATE_ARRIVAL' Store.withdraw(id,npc) end
                    end
                    Store.touch(event)
                elseif hours>=event.gatherDeadline then Store.close(id,event.revision,'QUORUM_NOT_MET') end
            elseif event.state=='RUNNING' then
                local organizer=event.roster[event.organizerId]
                if not organizer or organizer.withdrawn then Store.close(id,event.revision,'REQUIRED_ROLE_LEFT')
                elseif hours>=event.endsAt then
                    local count=0
                    for npc,m in pairs(event.roster) do if (m.participationHours or 0)>0 and Participant.present(event,npc) then count=count+1 end end
                    local complete=(organizer.participationHours or 0)>0 and count>=event.quorum and Participant.present(event,event.organizerId)
                    Store.close(id,event.revision,complete and 'COMPLETED' or 'INCOMPLETE')
                end
            end
            if event.state=='WINDING_DOWN' or event.state=='SETTLING' then Participant.collect(event) end
            if event.state~='CLOSED' then
                for npc,m in pairs(event.roster) do if m.jobId and not m.settled then actors[#actors+1]={event=id,npc=npc} end end
            end
        end
        table.sort(actors,function(a,b) return a.event==b.event and a.npc<b.npc or a.event<b.event end)
        pumping.actors=actors
    end
    local list=pumping.actors
    for _=1,math.min(16,#list) do
        pumping.cursor=pumping.cursor%#list+1 local row=list[pumping.cursor]
        local event=Store.get(row.event)
        if event and event.state~='CLOSED' then Participant.advance(actor,event,row.npc) end
    end
end
local Probe=require 'EmberRoutesProbe/Boot'
Probe.activityContext=S.context Probe.tickActivities=S.tick
return S
