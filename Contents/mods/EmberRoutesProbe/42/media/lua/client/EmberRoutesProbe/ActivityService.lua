-- FREE preference context. Attendance/physical execution remain separate.
local Store=require 'EmberRoutesProbe/ActivityStore'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Definitions=require 'EmberRoutesProbe/ActivityRegistry'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Members=require 'EmberRoutesProbe/MembershipService'
local Zones=require 'EmberRoutesProbe/SettlementZones'
local Resume=require 'EmberRoutesProbe/TaskResume'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Gate=require 'EmberRoutesProbe/RuntimeGate'
local S={}
local world,opened,tokens,sites
local function clock() return getGameTime():getWorldAgeHours() end
local function load()
    Definitions.freeze()
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
        and zone.settlementId==event.settlementId and Zones.coveredZone(entry,zone) then value=zone end
    sites[event.id]={parent=entry,parentRevision=entry and entry.revision,zones=version,
        zoneRevision=event.zone.revision,value=value}
    return value
end
-- Command-local metadata invalidation only; all physical closure is pumped.
local function invalidateRequested(args)
    for _,id in pairs(args.roster) do
        local event=Store.forNpc(id)
        if event then
            if not Definitions.compatible(event.definition,event.definitionVersion) or not site(event) then
                Store.close(event.id,event.revision,'ACTIVITY_CHANGED')
            elseif event.state=='GATHERING' and clock()>=event.endsAt then
                Store.close(event.id,event.revision,'INCOMPLETE')
            elseif not memberValid(id,event) then
                event.roster[id].reason=event.roster[id].reason or 'ACTIVITY_MEMBERSHIP_CHANGED'
                Store.withdraw(event.id,id)
            end
        end
    end
end
function S.preview(actor,args,deferred,current)
    Definitions.freeze()
    if type(args)~='table' then return nil,'ACTIVITY_DATA_INVALID' end
    local definition=Definitions.get(args.definitionId or 'FREE_GATHERING')
    if not definition then return nil,'ACTIVITY_DEFINITION_MISSING' end
    if args.definitionVersion~=nil and args.definitionVersion~=definition.definitionVersion then return nil,'ACTIVITY_DEFINITION_CHANGED' end
    local entry,why=Ledger.view(actor,args.settlementId) if not entry then return nil,why end
    local zone=Zones.get(args.zoneId)
    if not zone or not zone.enabled or zone.settlementId~=entry.id or not Zones.coveredZone(entry,zone)
        or zone.revision~=args.zoneRevision then return nil,'ZONE_CHANGED' end
    local name=type(args.name)=='string' and args.name:match('^%s*(.-)%s*$')
    local rules,ruleError=Definitions.resolve(definition.id,args.rules)
    if not rules then return nil,ruleError end
    local duration=args.durationHours or definition.defaultDurationHours
    if not name or #name<1 or #name>64 or name:find('[%c]') or not rules
        or type(duration)~='number' or duration~=duration or duration<1/60 or duration>24
        or type(args.roster)~='table' then return nil,'ACTIVITY_DATA_INVALID' end
    local roster,count,added={},0,0
    for key,id in pairs(args.roster) do
        count=count+1
        if count>256 or type(key)~='number' or key~=math.floor(key) or key<1 or key>256
            or type(id)~='string' or #id<1 or #id>128 or roster[id] then return nil,'ACTIVITY_ROSTER_INVALID' end
        local m=Members.view(id)
        if not m or m.retired or m.pending or m.context~='SETTLEMENT' or m.settlementId~=entry.id
            or not Members.entry(id,entry.id) then return nil,'ACTIVITY_ROSTER_INVALID',id end
        local previous=current and current.roster[id]
        if previous and not previous.withdrawn and (previous.membershipRevision~=m.revision or previous.commandEpoch~=Resume.epoch(id)) then
            return nil,'ACTIVITY_ROSTER_INVALID',id
        end
        local committed=Store.forNpc(id)
        if not deferred and committed and committed~=current then return nil,'ACTIVITY_NPC_BUSY',id end
        if previous and previous.withdrawn and not previous.settled then return nil,'ACTIVITY_REINVITE_UNAVAILABLE',id end
        if not deferred and (not previous or previous.withdrawn) and require('EmberRoutesProbe/ActivityParticipant').retains(id) then return nil,'ACTIVITY_SETTLING',id end
        if not previous or previous.withdrawn then added=added+1 end
        roster[id]={membershipRevision=m.revision,commandEpoch=Resume.epoch(id),
            participantEpoch=previous and previous.withdrawn and (previous.participantEpoch or 1)+1 or previous and previous.participantEpoch or 1}
    end
    if count<1 then return nil,'ACTIVITY_ROSTER_INVALID' end
    if count>definition.maxParticipants then return nil,'ACTIVITY_ROSTER_LIMIT' end
    if definition.scriptProfile and not require('EmberRoutesProbe/ActivityScripted').available() then return nil,'ACTIVITY_CAPABILITY_UNSUPPORTED' end
    if args.speakerId~=nil and type(args.speakerId)~='string' then return nil,'ACTIVITY_ROSTER_INVALID' end
    local speaker=definition.scriptProfile and (args.speakerId or args.organizerId or args.roster[1]) or nil
    if speaker and (not roster[speaker] or count<2) or not definition.scriptProfile and args.speakerId~=nil then return nil,'ACTIVITY_ROSTER_INVALID' end
    local organizer=args.organizerId or args.roster[1]
    local quorum=args.quorum or math.min(definition.defaultQuorum,count)
    local gather=args.gatherHours or math.min(duration,definition.defaultGatherHours)
    if not roster[organizer] or type(quorum)~='number' or quorum~=math.floor(quorum) or quorum<(speaker and 2 or 1) or quorum>count
        or quorum>Zones.capacity(zone,definition.maxParticipants) or type(gather)~='number' or gather~=gather or gather<1/60 or gather>24 then
        return nil,'ACTIVITY_ROSTER_INVALID'
    end
    if not deferred and Jobs.current():ordinaryCount()+added>require('EmberRoutesProbe/JobStore').LIMIT then return nil,'JOB_LIMIT' end
    return {definition=definition.id,definitionVersion=definition.definitionVersion,name=name,settlementId=entry.id,
        zone={id=zone.id,revision=zone.revision},rules=rules,roster=roster,durationHours=duration,
        organizerId=organizer,speakerId=speaker,scriptProfile=definition.scriptProfile,quorum=quorum,gatherHours=gather,controlEpoch=1,stageEpoch=1}
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
-- Explicit UI preflight. Counts are observations, never attendance promises.
function S.review(actor,args,deferred,eventId)
    local saved,why=load() if not saved then return nil,why end
    local current=eventId and saved.events[eventId]
    if eventId and (not current or current.state~='GATHERING' or clock()>=current.gatherDeadline) then return nil,'ACTIVITY_EDIT_CLOSED' end
    if current and (type(args)~='table' or args.settlementId~=current.settlementId) then return nil,'ACCESS_DENIED' end
    local proposal,invalid,blockedNpc=S.preview(actor,args,deferred,current)
    if not proposal then
        if not blockedNpc then return nil,invalid end
        return {ok=false,reason=invalid,ready=0,waiting=1,unknown=0,
            participants={[blockedNpc]={state='REJECTED',reason=invalid}}}
    end
    local result={ok=true,ready=0,waiting=0,unknown=0,participants={}}
    local admission=require 'EmberRoutesProbe/ActivityAttendance'
    for npc in pairs(proposal.roster) do
        local member=current and current.roster[npc]
        local state,reason
        if member and not member.withdrawn and require('EmberRoutesProbe/ActivityParticipant').proof(current,npc) then state='READY'
        elseif member and not member.withdrawn then state,reason=admission.inspect(actor,npc,S.context(npc))
        else state,reason=admission.preview(actor,npc,proposal.settlementId) end
        if state=='READY' then result.ready=result.ready+1
        elseif state=='UNKNOWN' then result.unknown=result.unknown+1
        else result.waiting=result.waiting+1 end
        result.participants[npc]={state=state,reason=reason}
    end
    return result
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
    invalidateRequested(args)
    local row,invalid=S.preview(actor,args) if not row then return nil,invalid end
    local now=clock()
    row.proposalKey=signature
    row.id=Registry.id() row.worldId=Store.worldId() row.requestId=token row.requesterId=owner row.revision=1 row.state='GATHERING'
    row.createdAt=now row.gatherDeadline=now+row.gatherHours row.gatherHours=nil
    row.endsAt=row.gatherDeadline+row.durationHours
    if row.scriptProfile=='SPEECH_V1' then row.reliefVersion=require('EmberRoutesProbe/ActivityReliefRecord').VERSION end
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
function S.update(actor,id,expected,args,token)
    local saved,why=load() if not saved then return nil,why end
    local event=saved.events[id] if not event then return nil,'ACTIVITY_MISSING' end
    if not Ledger.view(actor,event.settlementId) then return nil,'ACCESS_DENIED' end
    local owner=Members.character(actor) local key=Definitions.commandKey(args)
    if not key then return nil,'ACTIVITY_DATA_INVALID' end
    local receipt=event.editReceipt
    if receipt and receipt.requestId==token then
        if receipt.owner==owner and receipt.key==key and receipt.expected==expected then return Store.copy(event) end
        return nil,'ACTIVITY_REQUEST_CONFLICT'
    end
    local issued=tokens[token]
    if not issued or issued.owner~=owner or issued.scope~=event.settlementId or issued.untilTime<getTimestampMs() then
        return nil,'ACTIVITY_REQUEST_EXPIRED'
    end
    if event.revision~=expected then return nil,'ACTIVITY_CHANGED' end
    if event.state~='GATHERING' or clock()>=event.gatherDeadline then return nil,'ACTIVITY_EDIT_CLOSED' end
    local proposal,invalid=S.preview(actor,args,false,event) if not proposal then return nil,invalid end
    -- Live scene edits are limited to the approved roster/role fields. A new site
    -- or timing rule requires a new scene, after the original owners stop safely.
    if args.settlementId~=event.settlementId or args.zoneId~=event.zone.id or args.zoneRevision~=event.zone.revision
        or (args.definitionId or 'FREE_GATHERING')~=event.definition
        or args.definitionVersion~=nil and args.definitionVersion~=event.definitionVersion
        or proposal.durationHours~=event.durationHours
        or math.abs(proposal.gatherHours-(event.gatherDeadline-event.createdAt))>0.000001 then
        return nil,'ACTIVITY_EDIT_FIELDS'
    end
    for _,behavior in ipairs(Definitions.behaviors()) do
        if proposal.rules[behavior]~=event.rules[behavior] then return nil,'ACTIVITY_EDIT_FIELDS' end
    end
    local live,failed=Store.amend(id,expected,proposal,{requestId=token,owner=owner,key=key,expected=expected})
    if not live then return nil,failed end
    tokens[token]=nil
    local participant=require 'EmberRoutesProbe/ActivityParticipant'
    local prepared,reason=participant.prepare(live)
    if not prepared then Store.close(id,live.revision,reason) end
    return Store.copy(live)
end
local calendar=require('EmberRoutesProbe/ActivityCalendar').new({load=load,clock=clock,
    tokens=function() local saved=load() return saved and tokens or {} end,preview=function(...) return S.preview(...) end})
S.schedule=calendar.schedule S.updateSchedule=calendar.updateSchedule
S.cancelSchedule=calendar.cancelSchedule S.schedules=calendar.schedules S.tickSchedules=calendar.tickSchedules
function S.cancel(actor,id,expected)
    local saved,why=load() if not saved then return false,why end
    local event=saved.events[id] if not event then return false,'ACTIVITY_MISSING' end
    local entry,reason=Ledger.view(actor,event.settlementId) if not entry then return false,reason end
    local ok,failed=Store.close(id,expected,'CANCELLED')
    if ok then sites[id]=nil end
    return ok,failed
end
function S.finishScenes(reason)
    local saved,why=load() if not saved then return false,why end
    for id,event in pairs(saved.events) do
        if event.state~='CLOSED' then
            require('EmberRoutesProbe/ActivityReliefRecord').interrupt(event,reason or 'SAVE_INTERRUPTED')
            Store.touch(event)
            Store.close(id,event.revision,reason)
            local p=require 'EmberRoutesProbe/ActivityParticipant'
            for npc in pairs(event.roster) do p.stop(npc,event) end
            p.collect(event)
        end
    end
    tokens,sites={},{} return true
end
local views=require('EmberRoutesProbe/ActivityViews').new(load)
S.detail=views.detail S.view=views.view S.revision=views.revision
-- Detached scalar intent, never a body grant or a claim of attendance.
function S.context(id)
    local saved=load() if not saved then return end
    local event=Store.forNpc(id)
    if not event or event.state~='GATHERING' and event.state~='RUNNING' or clock()>=event.endsAt or not memberValid(id,event)
        or event.stageBlocked or event.dutyBlocked or not Definitions.compatible(event.definition,event.definitionVersion) or not site(event) then return end
    local ref={eventId=event.id,settlementId=event.settlementId,
        id=event.zone.id,revision=event.zone.revision,endsAt=event.endsAt,
        controlEpoch=event.controlEpoch,phase=event.state,joined=event.roster[id].joined==true,
        participantEpoch=event.roster[id].participantEpoch or 1,
        commandEpoch=event.roster[id].commandEpoch,membershipRevision=event.roster[id].membershipRevision}
    local duty=require('EmberRoutesProbe/ActivityOwners').reference(event,id)
    for key,value in pairs(duty or {}) do ref[key]=value end
    return ref
end
function S.validRef(id,ref)
    local live=S.context(id)
    return live and type(ref)=='table' and live.eventId==ref.eventId and live.controlEpoch==ref.controlEpoch
        and live.id==ref.id and live.revision==ref.revision and live.participantEpoch==(ref.participantEpoch or 1)
        and require('EmberRoutesProbe/ActivityOwners').matches(Store.get(live.eventId),id,ref)
        and live.phase=='RUNNING' and live.joined or false
end
function S.readyForAction(id)
    local ref=S.context(id)
    return not ref or ref.phase~='RUNNING' or require('EmberRoutesProbe/ActivityOwners').ready(Store.get(ref.eventId),id)
end
function S.leave(id,reason)
    local saved=load() if not saved then return false end
    local event=Store.forNpc(id) if not event then return false end
    event.roster[id].reason=reason
    Store.withdraw(event.id,id)
    require('EmberRoutesProbe/ActivityParticipant').stop(id,event)
    if (id==event.organizerId or id==event.speakerId) and event.state=='RUNNING' then Store.close(event.id,event.revision,'REQUIRED_ROLE_LEFT') end
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
        or current.id~=ref.id or current.revision~=ref.revision
        or current.participantEpoch~=(ref.participantEpoch or 1) or not Zones.location(scope,ref,point) then return false end
    -- Attendance travel is not quiet leisure. Disabling OBSERVE must not disable
    -- a roster member's safe route; arrival itself never earns relief or time.
    return true
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
    if not event or event.stageBlocked or event.dutyBlocked or event.state=='CLOSED' or event.settlementId~=scope
        or clock()>=event.endsAt or not memberValid(id,event)
        or not Definitions.compatible(event.definition,event.definitionVersion) then return base end
    local zone=site(event)
    if not zone or not Zones.contains(zone,x,y,z) then return base end
    -- Explicit event behavior preferences replace ordinary behavior policy only.
    -- Physical permissions, safety, original-item and body gates remain outside.
    local override=event.rules[behavior]
    if override~=nil then return override end
    return base
end
local pump=require('EmberRoutesProbe/ActivityPump').new({site=site,memberValid=memberValid,
    calendar=function(actor,hours,budget) return S.tickSchedules(actor,hours,budget) end})
local nextTick=0
local Boot
function S.tick()
    local now=getTimestampMs()
    if now<nextTick then return end
    nextTick=now+100
    Boot=Boot or require 'EmberRoutesProbe/Boot'
    if not Boot.ready or not Boot.runtimeReady or not Gate.isSinglePlayer() then return end
    local saved=load() if not saved then return end
    local actor=getSpecificPlayer(0) if not actor or actor:isDead() then return end
    pump.tick(actor,saved,now,clock())
end
function S.pumpBudget() return pump.stats() end
local Probe=require 'EmberRoutesProbe/Boot'
Probe.activityContext=S.context Probe.tickActivities=S.tick
return S
