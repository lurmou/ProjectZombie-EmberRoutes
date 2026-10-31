-- Idle discovery called by SelfCare, using its shared budget and Runtime.
-- Activities are data: LeisureRegistry holds the ordered seek defs, each with
-- its own budget kind and def-private offer state. Adding an activity means
-- Registry.define here (and an action builder in LeisureActions) until 4.5
-- formalizes the public surface.
local Registry=require 'EmberRoutesProbe/LeisureRegistry'
local Perf=require 'EmberRoutesProbe/RuntimeMetrics'
local ContainerRegistry=require 'EmberRoutesProbe/ContainerRegistry'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Policy=require 'EmberRoutesProbe/LeisurePolicy'
local Config=require 'EmberRoutesProbe/LeisureConfig'
local LifeZones=require 'EmberRoutesProbe/SettlementZones'
local Social=require 'EmberRoutesProbe/SocialCoordinator'
local Service={}
-- Optional local policy; absence of a configured zone preserves old selection.
local function zoneRule(entry,point,activity,id)
    local context=require 'EmberRoutesProbe/ActivityService'
    if not context.allowsPoint(entry.id,id,point) then return 0 end
    return context.policyAt(entry.id,id,point.x,point.y,math.floor(point.z),activity)
end
local function candidateRule(entry,point,candidate,id)
    local target=candidate.point or point
    if candidate.site then
        for _,part in ipairs(candidate.site.parts or {}) do
            if part.id==candidate.site.partId then target=part break end
        end
    end
    return zoneRule(entry,target,candidate.activity or (candidate.leisure and candidate.leisure.activity) or 'READING',id)
end
local world,offers,statuses=nil,{},{}
local preferred={}
-- Rate-limited idle diagnostics: one line per reason change or per 10s, so a
-- standing NPC explains itself without flooding the console.
local idleLogged={}
local function noteIdle(id,reason)
    statuses[id]={reason=reason,at=getTimestampMs()}
    local now=getTimestampMs()
    local row=idleLogged[id]
    if not row or row.reason~=reason or now-row.at>=10000 then
        idleLogged[id]={reason=reason,at=now}
        require "EmberRoutesProbe/Log".write("LEISURE","IDLE npc="..tostring(id).." reason="..reason)
    end
end
local function load()
    local root=ContainerRegistry.data() if root~=world then world,offers,statuses=root,{},{ } preferred={} end
end
-- PublicWork reports observations; membership, not this report, permits life.
function Service.workState(id,entry,state)
    load()
    local member=require('EmberRoutesProbe/MembershipService').view(id)
    if not member or member.pending or member.context~='SETTLEMENT' or member.settlementId~=entry.id then return end
    local row=offers[id]
    if not row or row.entry.id~=entry.id or row.membershipRevision~=member.revision
        or row.entryRevision~=entry.revision then row={entry=entry} offers[id]=row end
    row.untilTime=getTimestampMs()+3000 row.state=state
    row.membershipRevision=member.revision row.entryRevision=entry.revision
end
function Service.offer(id,entry) Service.workState(id,entry,'IDLE') end
function Service.status(id)
    load() local s=statuses[id]
    return s and {reason=s.reason,activity=s.activity,at=s.at} or nil
end
function Service.note(id,reason) load() noteIdle(id,reason) end
function Service.invalidate(id,reason)
    load() offers[id]=nil preferred[id]=nil Social.withdraw(id) noteIdle(id,reason or 'STALE_MEMBERSHIP')
end
function Service.probeable(id)
    local job=Jobs.current():forNpc(id,'SELF_CARE')[1]
    local p=job and job.payload
    return job and job.effects=='KNOWN' and p.step=='ACTING'
        and (p.kind=='LEISURE' or p.kind=='STUDY') or false
end
function Service.workReady(id)
    load() offers[id]=nil preferred[id]=nil Social.withdraw(id)
    require('EmberRoutesProbe/StudyService').changed(nil,id)
    local job=Jobs.current():forNpc(id,'SELF_CARE')[1]
    if job and Service.probeable(id) then
        local runtime=require('EmberRoutesProbe/TaskRuntime').current()
        require "EmberRoutesProbe/Log".write("LEISURE","WORK_READY npc="..tostring(id).." job="..tostring(job.id))
        if runtime then runtime:stopJob(id,job.id,'LEISURE_WORK_READY') end
    end
end
function Service.valid(actor,npc,id,p)
    if p.activityRef and not require('EmberRoutesProbe/ActivityService').validRef(id,p.activityRef) then return false end
    if p.leisure and p.leisure.roleDuty and (not p.leisure.point
        or require('EmberRoutesProbe/LeisureRecord').tileKey(p.leisure.point)~=require('EmberRoutesProbe/LeisureRecord').tileKey(
            {x=npc:getX(),y=npc:getY(),z=math.floor(npc:getZ())})) then return false end
    local M=require 'EmberRoutesProbe/MembershipService'
    local eligible=M.check(id,'LEISURE',{x=npc:getX(),y=npc:getY(),z=npc:getZ(),scopeId=p.settlementId},p.membershipRevision)
    if not eligible.allowed or p.membershipRevision==nil or p.settlementRevision~=eligible.entryRevision then return false end
    -- Live membership check: faction equality plus geometry replace the detached
    -- copy and actor re-authorization on this 200ms-cadence advisory path.
    -- Replaced Ledger modules without data() keep the old view() form.
    local entry=M.entry(id,p.settlementId)
    if p.leisure and p.leisure.zoneVisit and (not entry
        or not require('EmberRoutesProbe/ActivityService').destination(entry.id,id,p.leisure.zoneVisit,p.leisure.point)) then return false end
    if entry and p.leisure and p.leisure.activity=='SIT' and p.site==nil then return false end
    if entry and p.leisure and p.leisure.started and not p.leisure.brief and not p.leisure.zoneVisit then
        local rule=zoneRule(entry,{x=npc:getX(),y=npc:getY(),z=npc:getZ()},p.leisure.activity,id)
        if not rule or rule==0 then return false end
    end
    return entry~=nil and require('EmberRoutesProbe/SettlementGeometry').inside(entry,npc:getX(),npc:getY()) or false
end
function Service.sample(npc,sample)
    if not sample then return end
    local s={} for k,v in pairs(sample) do s[k]=v end
    local stats=npc:getStats()
    s.pain=stats:get(CharacterStat.PAIN)/100
    s.boredom=CharacterStat.BOREDOM and stats:get(CharacterStat.BOREDOM)/100 or 0
    s.stress=CharacterStat.STRESS and stats:get(CharacterStat.STRESS) or 0
    s.health=npc:getBodyDamage():getOverallBodyHealth()
    s.healthy=s.health>=Config.gates.health
    s.handsFree=npc:getPrimaryHandItem()==nil and npc:getSecondaryHandItem()==nil
    s.smoker=CharacterTrait and npc:hasTrait(CharacterTrait.SMOKER) or false
    s.fitnessKnown=false s.stiff=true
    if npc.getFitness then
        local f=npc:getFitness()
        if f and f.getCurrentExeStiffnessTimer and f.getCurrentExeStiffnessInc and f.onGoingStiffness then
            s.fitnessKnown=true s.stiff=f:onGoingStiffness()
            for _,part in ipairs({'legs','arms','chest','abs'}) do
                if f:getCurrentExeStiffnessTimer(part)>0 or f:getCurrentExeStiffnessInc(part)>0 then s.stiff=true end
            end
            local parts=npc:getBodyDamage():getBodyParts()
            for i=0,parts:size()-1 do if parts:get(i):getStiffness()>0 or parts:get(i):bleeding() then s.stiff=true end end
        end
    end
    return s
end
-- Exported for the 4.5 activity coordinator (A3): legal standing spots near a
-- target use the same settlement/floor/rain/occupancy rules as leisure does.
function Service.standable(entry,point,allowed)
    if not require('EmberRoutesProbe/SettlementGeometry').inside(entry,point.x,point.y) then return end
    local square=getCell():getGridSquare(math.floor(point.x),math.floor(point.y),point.z)
    if not square or not square:TreatAsSolidFloor() or square:isSolid() or square:isSolidTrans()
        or square:HasStairs() or square:isDoorSquare() or not square:isFree(false) then return end
    if square:isOutside() and (not RainManager or RainManager.isRaining()) then return end
    local moving=square:getMovingObjects()
    if moving:size()>16 then return end
    for i=0,moving:size()-1 do
        local object=moving:get(i)
        if not allowed or object~=allowed[1] and object~=allowed[2] then return end
    end
    return square
end
local standable=Service.standable

local function seekSocial(env)
    local rule=zoneRule(env.entry,env.point,'SOCIAL',env.id)
    if not rule or rule==0 then Social.withdraw(env.id) return nil,true end
    if env.hours>=(env.cooling.SOCIAL or 0) then
        Social.advertise(env.id,env.entry,env.point,env.now)
    end
    local key=Social.pending(env.id)
    local time=getGameTime():getTimeOfDay()
    local chance=time>=Config.socialChance.from and time<Config.socialChance.to
        and Config.socialChance.evening or Config.socialChance.other
    if rule==2 then chance=math.min(1,chance*2) end
    if not key and env.hours>=(env.cooling.SOCIAL or 0) and env.budget.paths>0 and ZombRand(10000)/10000<chance then
        env.budget.paths=env.budget.paths-1
        key=Social.invite(env.id,env.entry,env.now,function(a,b,aid,bid)
            local partner=require('EmberRoutesProbe/Driver').bindId(env.actor,bid)
            if not partner then return end
            local allowed={env.npc,partner.handle}
            local target={x=math.floor(b.x)+0.5,y=math.floor(b.y)+0.5,z=b.z}
            for _,offset in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
                local p={x=target.x+offset[1],y=target.y+offset[2],z=target.z}
                if env.budget.scan<1 then return end env.budget.scan=env.budget.scan-1
                local sa,sb=standable(env.entry,p,allowed),standable(env.entry,target,allowed)
                local aRule,bRule=zoneRule(env.entry,p,'SOCIAL',aid),zoneRule(env.entry,target,'SOCIAL',bid)
                if sa and sb and aRule and aRule>0 and bRule and bRule>0 and sa:canReachTo(sb) then return p,target end
            end
        end)
    end
    if key then
        local mine=Social.view(key,env.id,nil,env.now)
        local other=mine and Social.view(key,mine.other,nil,env.now)
        if not mine or not other or (zoneRule(env.entry,mine.point,'SOCIAL',env.id) or 0)==0
            or (zoneRule(env.entry,other.point,'SOCIAL',mine.other) or 0)==0 then
            Social.withdraw(env.id) return nil,true
        end
        return {leisure={format=1,activity='SOCIAL',socialId=key,hours=env.hours},entry=env.entry,pure=true},true
    end
    return nil,true
end

local function seekReading(env)
    if env.hours<(env.cooling.READING or 0) or env.budget.scan<1 then return nil,true end
    local candidate,done,reason,offset=require('EmberRoutesProbe/LibraryIndex').choose(
        env.actor,env.npc,env.entry,nil,env.budget,env.state.offset,true)
    env.state.offset=done and 1 or offset or env.state.offset
    if candidate then return require('EmberRoutesProbe/StudyService').decorateLeisure(candidate,env.id),true end
    if not done then return nil,false,reason end
    return nil,true
end

local function seekSmoke(env)
    if not Policy.allowed('SMOKE',env.s,{hold=true}) or env.hours<(env.cooling.SMOKE or 0)
        or env.budget.scan<1 then return nil,true end
    env.state.cache=env.state.cache or {}
    local smoke,done=require('EmberRoutesProbe/LeisureSmoke').find(env.npc,env.budget,env.state.cache)
    if smoke then
        return {leisure={format=1,activity='SMOKE',hours=env.hours,fireId=smoke.fire:getID()},
            item=smoke.item,fire=smoke.fire,entry=env.entry,pure=true},true
    end
    if not done then return nil,false end
    return nil,true
end

-- Seated idle reuses the P2 furniture discovery/reservation untouched: a
-- prepared proof plus its repose keys ride the LEISURE payload the same
-- way REST carries them, so occupancy claims interlock with the same store.
local function seekSit(env,preview)
    if not Policy.allowed('SIT',env.s,{hold=true}) or env.hours<(env.cooling.SIT or 0)
        or env.budget.scan<1
        or not (EmberRoutesProbeJava and EmberRoutesProbeJava.reposeAtWithControl) then return nil,true end
    local Facilities=require 'EmberRoutesProbe/SettlementFacilities'
    local facility=Facilities.watch(env.entry,Facilities.describe)
    local location=math.floor(env.point.x)..':'..math.floor(env.point.y)..':'..env.point.z
    local stamp=tostring(facility.version)..':'..tostring(env.offer.seatEpoch or 0)..':'..location
    if env.state.stamp~=stamp and not env.state.iter then env.state.retryAt=nil env.state.stamp=stamp end
    if env.now<(env.state.retryAt or 0) then return nil,true end
    env.offer.blocked=env.offer.blocked or {}
    env.state.blocked=env.offer.blocked
    if not env.state.iter then
        env.state.iter=require('EmberRoutesProbe/ReposeSites').new(env.actor,env.npc,env.id,'REST',env.state.blocked,
            {seatingOnly=true,excludeBeds=true,preferredPoint=env.memory and env.memory.seatPreference})
    end
    local slice=math.min(8,env.budget.scan)
    local found,done,reason=env.state.iter:step(slice)
    env.budget.scan=env.budget.scan-slice
    if not done then return nil,false,reason end
    env.state.iter=nil
    if found then
        if preview then return {leisure={activity='SIT'},moving=true,targetKey=found.key},true end
        local Sites=require 'EmberRoutesProbe/ReposeSites'
        local proof=Sites.prepare(found,env.actor,env.npc,env.id,'REST')
        if proof then
            return {leisure={format=1,activity='SIT',hours=env.hours},entry=env.entry,site=proof,
                claims=Sites.keys(proof,'REST')},true
        end
        env.state.blocked[found.key]=getTimestampMs()+5000
    end
    env.state.retryAt=env.now+Config.seatRetryMs
    return nil,true
end

Registry.define({id='SOCIAL',budget='paths',seek=seekSocial})
Registry.define({id='READING',budget='scan',seek=seekReading,review=seekReading})
Registry.define({id='SMOKE',budget='scan',seek=seekSmoke,review=seekSmoke})
Registry.define({id='SIT',budget='scan',seek=seekSit,review=function(env)
    return seekSit(env,true)
end})
Registry.define({id='PUBLIC_LIFE',budget='scan',policyAtTarget=true,seek=function(env)
    if require('EmberRoutesProbe/ActivityService').context(env.id) then return nil,true end
    return require('EmberRoutesProbe/LifeZoneVisits').seek(env,standable)
end})

-- Resource release wakes failed seat discovery, without owning or reserving a
-- chair. No per-frame furniture walk or second scheduler is introduced.
function Service.seatReleased(settlementId)
    load()
    for _,offer in pairs(offers) do
        if offer.entry.id==settlementId then offer.seatEpoch=(offer.seatEpoch or 0)+1 end
    end
end

-- Bounded challenger review; the incumbent Session retains its body and claims.
function Service.review(c,elapsed)
    load()
    local id=c.job.npcId local offer=offers[id]
    if not offer then return false end
    local s=Service.sample(c.npc,c.sample())
    if not s then return false end
    local kind=c.payload.leisure.activity
    local currentPoint={x=c.npc:getX(),y=c.npc:getY(),z=math.floor(c.npc:getZ())}
    local incumbentRule=zoneRule(offer.entry,currentPoint,kind,id)
    if not incumbentRule or incumbentRule==0 then return true end
    local hours,now=getGameTime():getWorldAgeHours(),getTimestampMs()
    local memory=c.payload.leisureMemory or {} local cooling=memory.cooldowns or {}
    local budget={scan=math.min(4,c.budget and c.budget.scan or 0),paths=0,
        containers=math.min(1,c.budget and c.budget.containers or 0)}
    local available,availableContainers=budget.scan,budget.containers
    local env={actor=c.actor,id=id,npc=c.npc,binding={id=id,handle=c.npc},entry=offer.entry,
        s=s,hours=hours,now=now,budget=budget,cooling=cooling,offer=offer,
        point={x=c.npc:getX(),y=c.npc:getY(),z=math.floor(c.npc:getZ())}}
    offer.reviewData=offer.reviewData or {}
    local candidates={}
    if Policy.allowed('FITNESS',s,{hold=true}) then candidates[#candidates+1]={activity='FITNESS'} end
    local definitions=Registry.all()
    offer.reviewCursor=(offer.reviewCursor or 0)%math.max(1,#definitions)+1
    for offset=0,#definitions-1 do
        local def=definitions[(offer.reviewCursor+offset-1)%#definitions+1]
        local rule=zoneRule(offer.entry,currentPoint,def.id,id)
        if rule and rule>0 and def.review and def.id~=kind and not (kind=='SIT' and def.id=='READING')
            and hours>=(cooling[def.id] or 0) then
            env.state=offer.reviewData[def.id] or {} offer.reviewData[def.id]=env.state
            local granted=math.min(2,budget.scan)
            env.budget={scan=granted,paths=0,containers=budget.containers}
            local candidate=def.review(env)
            budget.scan=budget.scan-(granted-env.budget.scan)
            budget.containers=env.budget.containers
            if candidate then
                candidate.activity=candidate.leisure and candidate.leisure.activity or 'READING'
                candidate.moving=true
                if candidate.item then candidate.targetKey='item:'..candidate.item:getID() end
                candidates[#candidates+1]=candidate
            end
        end
    end
    local socialKey=Social.peekPending and Social.peekPending(id)
    if socialKey then candidates[#candidates+1]={activity='SOCIAL',moving=true} end
    if c.budget then
        c.budget.scan=c.budget.scan-(available-budget.scan)
        c.budget.containers=(c.budget.containers or 0)-(availableContainers-budget.containers)
    end
    local incumbent=kind=='STROLL' and 'OBSERVE' or kind
    local current=Policy.weight(incumbent,s,Config.weights[incumbent] or 1)
        *(1-0.75*math.min(1,elapsed/Config.habituationMs))
    if incumbentRule==2 then current=current*2 end
    local best,score
    for _,candidate in ipairs(candidates) do
        local other=candidate.activity
        if other~=kind and not (kind=='STROLL' and other=='OBSERVE') and hours>=(cooling[other] or 0)
            and (not candidate.moving or hours>=(memory.moveAfter or 0))
            and (not candidate.targetKey or now>=((offer.blocked or {})[candidate.targetKey] or 0))
            and Policy.allowed(other,s,{hold=true}) then
            local rule=candidateRule(offer.entry,currentPoint,candidate,id)
            local value=Policy.weight(other,s,Config.weights[other] or 1)*(rule==2 and 2 or 1)
                -(candidate.moving and Config.switchMoveCost or 0)
            if rule and rule>0 and value>current+Config.switchMargin and (not score or value>score) then best,score=candidate,value end
        end
    end
    if best then
        preferred[id]={activity=best.activity,targetKey=best.targetKey,untilTime=now+30000}
        require('EmberRoutesProbe/Log').write('LEISURE','SWITCH npc='..id..' from='..kind..' to='..best.activity)
        return true
    end
    statuses[id]={activity=kind,reason='CONTINUING',at=now}
    return false
end

function Service.candidate(actor,binding,sample,budget,memory)
    load() local id,npc=binding.id,binding.handle local offer=offers[id]
    local M=require 'EmberRoutesProbe/MembershipService'
    local eligible=M.check(id,'LEISURE',{x=npc:getX(),y=npc:getY(),z=npc:getZ()})
    if not eligible.allowed then Social.withdraw(id) noteIdle(id,eligible.reason) return nil,true end
    local entry=M.entry(id,eligible.settlementId)
    if not entry then Social.withdraw(id) noteIdle(id,'NO_ENTRY') return nil,true end
    if not offer or offer.membershipRevision~=eligible.revision or offer.entryRevision~=eligible.entryRevision then
        offer={entry=entry,membershipRevision=eligible.revision,entryRevision=eligible.entryRevision}
        offers[id]=offer
    end
    local s=Service.sample(npc,sample)
    if not Policy.allowed('OBSERVE',s,{hold=true}) then Social.withdraw(id) noteIdle(id,'NOT_ELIGIBLE') return nil,true end
    local now,hours=getTimestampMs(),getGameTime():getWorldAgeHours()
    local point={x=npc:getX(),y=npc:getY(),z=math.floor(npc:getZ())}
    local state=offer.untilTime and offer.untilTime>=now and offer.state or 'OBSERVING'
    local Activities=require 'EmberRoutesProbe/ActivityService'
    local gathering=Activities.context(id)
    if gathering then
        local ready,why=require('EmberRoutesProbe/ActivityAttendance').inspect(actor,id,gathering)
        if ready~='READY' then Social.withdraw(id) noteIdle(id,why or 'ACTIVITY_WAIT') return nil,true end
        if not Activities.allowsPoint(entry.id,id,point) then
            Social.withdraw(id)
            offer.stateData=offer.stateData or {}
            offer.stateData.ATTENDANCE=offer.stateData.ATTENDANCE or {}
            local env={actor=actor,id=id,npc=npc,entry=entry,s=s,hours=hours,now=now,point=point,
                budget=budget,memory=memory,offer=offer,state=offer.stateData.ATTENDANCE,eventId=gathering.eventId,activityRef=gathering,
                destinationZone=LifeZones.get(gathering.id),destination=function(scope,ref,target)
                    return Activities.destination(scope,id,ref,target)
                end}
            if not env.destinationZone then return nil,true end
            local candidate,done,why=require('EmberRoutesProbe/LifeZoneVisits').seek(env,standable)
            if candidate then
                candidate.membershipRevision=eligible.revision candidate.settlementRevision=eligible.entryRevision
                statuses[id]={activity='OBSERVE',reason='ACTIVITY_APPROACH',at=now}
            else noteIdle(id,why or 'ACTIVITY_WAIT') end
            return candidate,done
        end
        if not Activities.arrived(actor,binding,gathering) then return nil,true end
        if gathering.phase=='GATHERING' then noteIdle(id,'ACTIVITY_WAITING_FOR_START') return nil,true end
        if not Activities.readyForAction(id) then noteIdle(id,'ACTIVITY_PERSONAL_SETTLING') return nil,true end
        local event=require('EmberRoutesProbe/ActivityStore').get(gathering.eventId)
        if event and event.scriptProfile then
            Social.withdraw(id)
            return require('EmberRoutesProbe/ActivityScripted').candidate(event,id,entry,eligible,gathering,hours)
        end
        state='IDLE' -- Explicit roster intent suppresses ordinary-work discovery.
    end
    if state=='READY' then Social.withdraw(id) noteIdle(id,'WORK_READY') return nil,true end
    if state~='IDLE' then
        Social.withdraw(id) noteIdle(id,'WORK_OBSERVING')
        return {leisure={format=1,activity='OBSERVE',hours=hours,brief=true},entry=entry,pure=true,
            membershipRevision=eligible.revision,settlementRevision=eligible.entryRevision},true
    end
    local hint=preferred[id]
    if hint and hint.untilTime<now then preferred[id]=nil hint=nil end
    if not gathering and not hint and memory and hours<(memory.decisionAfter or 0) then
        Social.withdraw(id) noteIdle(id,'LEISURE_PAUSE') return nil,true,'LEISURE_PAUSE'
    end
    offer.stateData=offer.stateData or {}
    local env={actor=actor,binding=binding,id=id,npc=npc,offer=offer,entry=entry,s=s,hours=hours,
        point=point,budget=budget,cooling=memory and memory.cooldowns or {},now=now,memory=memory}
    local candidates={}
    local deferred
    for _,def in ipairs(Registry.all()) do
        local originRule=def.policyAtTarget and 1 or zoneRule(entry,point,def.id,id)
        if originRule and originRule>0 then
        env.state=offer.stateData[def.id]
        if not env.state then env.state={} offer.stateData[def.id]=env.state end
        local started=Perf.active() and Perf.now()
        local candidate,done,reason=def.seek(env)
        if started then Perf.measureSpan('Leisure.'..def.id,started) end
        if candidate then
            local kind=candidate.leisure and candidate.leisure.activity or 'READING'
            candidate.activity=kind
            candidate.weight=candidate.weight or Policy.weight(kind,s,Config.weights[kind] or 1)
            if kind=='SOCIAL' then
                candidate.membershipRevision=eligible.revision candidate.settlementRevision=eligible.entryRevision
                candidate.activityRef=gathering
                statuses[id]={activity=kind,reason='STARTING',at=now}
                return candidate,true -- an existing reservation has an acceptance deadline
            end
            if candidate.site then
                candidate.targetKey=candidate.site.key
                for _,part in ipairs(candidate.site.parts or {}) do
                    if part.id==candidate.site.partId then
                        candidate.weight=candidate.weight/(1+math.sqrt((part.x-point.x)^2+(part.y-point.y)^2)/8)
                        break
                    end
                end
            end
            if candidate.item then candidate.targetKey='item:'..candidate.item:getID() end
            candidates[#candidates+1]=candidate
        end
        if done==false then deferred=reason or 'DISCOVERING' end
        elseif def.id=='SOCIAL' then Social.withdraw(id) end
    end
    candidates[#candidates+1]={activity='OBSERVE',weight=Config.weights.OBSERVE}
    if Policy.allowed('FITNESS',s,{hold=true}) and npc:getCurrentState()==IdleState.instance() then
        candidates[#candidates+1]={activity='FITNESS',weight=Policy.weight('FITNESS',s,Config.weights.FITNESS)}
    end
    if Policy.allowed('STROLL',s,{hold=true}) and budget.scan>0 then
        local offset=ZombRand(4) local offsets={{2,0},{0,2},{-2,0},{0,-2}}
        local v=offsets[offset+1] local p={x=math.floor(point.x)+v[1]+0.5,y=math.floor(point.y)+v[2]+0.5,z=point.z}
        budget.scan=budget.scan-1
        if standable(entry,p,{npc}) then candidates[#candidates+1]={activity='STROLL',point=p,weight=Config.weights.STROLL} end
    end
    local Facilities=require 'EmberRoutesProbe/SettlementFacilities'
    local facility=Facilities.watch(entry,Facilities.describe)
    local used=Facilities.advance(facility,math.min(8,budget.scan)) budget.scan=budget.scan-used
    local siteState=offer.stateData.SITE_OBSERVE or {}
    offer.stateData.SITE_OBSERVE=siteState
    siteState.offset=siteState.offset or 1
    for _=1,math.min(8,#facility.slots) do
        if budget.scan<1 then break end budget.scan=budget.scan-1
        siteState.offset=siteState.offset%#facility.slots+1
        local record=facility.slots[siteState.offset]
        if record and record.feature and record.z==point.z and (record.x-point.x)^2+(record.y-point.y)^2<=100 then
            local object=record.object local sq=object:getSquare()
            if sq and sq:getObjects():contains(object) then
                for _,offset in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
                    if budget.scan<1 then break end budget.scan=budget.scan-1
                    local p={x=record.x+offset[1]+0.5,y=record.y+offset[2]+0.5,z=record.z}
                    local near=standable(entry,p,{npc})
                    if near and near:canReachTo(sq) then
                        candidates[#candidates+1]={activity='OBSERVE',point=p,target=object,weight=Config.weights.SITE_OBSERVE}
                        break
                    end
                end
                break
            end
        end
    end
    -- Bounded target backoff lives with this membership/entry observation.
    offer.blocked=offer.blocked or {}
    for _,c in ipairs(candidates) do
        local rule=candidateRule(entry,{x=npc:getX(),y=npc:getY(),z=npc:getZ()},c,id)
        c.zonePreferred=rule==2
        if not rule or rule==0 then c.weight=0 elseif rule==2 then c.weight=(c.weight or 1)*2 end
        local point=c.point
        if point then
            c.moving=(point.x-npc:getX())^2+(point.y-npc:getY())^2>0.8^2
            c.weight=(c.weight or 1)/(1+math.sqrt((point.x-npc:getX())^2+(point.y-npc:getY())^2)/8)
            c.targetKey=c.targetKey or c.activity..':'..math.floor(point.x)..':'..math.floor(point.y)..':'..point.z
        end
        if c.targetKey and (offer.blocked[c.targetKey] or 0)>now then c.weight=0 end
    end
    local c
    if hint then
        for _,candidate in ipairs(candidates) do
            if candidate.activity==hint.activity and (not hint.targetKey or candidate.targetKey==hint.targetKey)
                and candidate.weight>0 and hours>=(env.cooling[candidate.activity] or 0)
                and (not candidate.moving or hours>=(memory and memory.moveAfter or 0)) then c=candidate break end
        end
    end
    if not c then
        local activities,seats,standing={},{},{}
        local combined,hasPreferred={},false
        for _,candidate in ipairs(candidates) do
            combined[#combined+1]=candidate
            hasPreferred=hasPreferred or candidate.zonePreferred and (candidate.weight or 1)>0
            local target=candidate.publicVisit and activities or candidate.activity=='SIT' and seats
                or (candidate.activity=='OBSERVE' or candidate.activity=='STROLL') and standing or activities
            target[#target+1]=candidate
        end
        local roll=ZombRand(10000)/10000
        if hasPreferred then c=Policy.choose(combined,memory,hours,roll)
        else c=Policy.choose(activities,memory,hours,roll) or Policy.choose(seats,memory,hours,roll)
            or Policy.choose(standing,memory,hours,roll) end
    end
    if not c then noteIdle(id,deferred or 'NO_CANDIDATE') return nil,true end
    if not c.leisure and not c.study then
        c={leisure={format=1,activity=c.activity,point=c.point,hours=hours,moving=c.moving},entry=entry,pure=true,
            leisureTarget=c.target,targetKey=c.targetKey}
    end
    c.membershipRevision=eligible.revision c.settlementRevision=eligible.entryRevision
    c.activityRef=gathering
    local activity=c.leisure and c.leisure.activity or 'READING'
    preferred[id]=nil
    if c.leisure and c.leisure.zoneVisit or activity~='SOCIAL' and activity~='OBSERVE' then Social.withdraw(id) end
    statuses[id]={activity=activity,reason=c.leisure and c.leisure.zoneVisit and 'LIFE_ZONE_APPROACH' or 'STARTING',at=now}
    require('EmberRoutesProbe/Log').write('LEISURE','SELECT npc='..id..' activity='..activity)
    return c,true
end
function Service.pause(memory)
    return Policy.pause(memory,getGameTime():getWorldAgeHours(),ZombRand(10000)/10000)
end
function Service.started(id,activity,brief,zoneVisit)
    load() statuses[id]={activity=activity,reason=zoneVisit and (zoneVisit.eventId and 'ACTIVITY_APPROACH' or 'LIFE_ZONE_APPROACH')
        or brief and 'WORK_OBSERVING' or 'ACTIVE',at=getTimestampMs()}
    require('EmberRoutesProbe/Log').write('LEISURE','ACTIVE npc='..id..' activity='..activity)
end
function Service.failed(id,key,reason)
    preferred[id]=nil
    load() local offer=offers[id]
    if offer and key then
        offer.blocked=offer.blocked or {} local count=0
        for k,t in pairs(offer.blocked) do if t<=getTimestampMs() then offer.blocked[k]=nil else count=count+1 end end
        if count<32 then offer.blocked[key]=getTimestampMs()+Config.failedTargetMs end
    end
    noteIdle(id,reason or 'START_FAILED')
end

function Service.finished(c,stopped)
    local p=c.payload local l=p.leisure
    if not l then return end
    if not l.finished and c.reason~='LEISURE_WORK_READY' and c.reason~='SOCIAL_INVITE' then
        Service.failed(c.job.npcId,c.leisureKey,c.reason or 'ACTIVITY_INTERRUPTED')
    end
    if not l.zoneVisit and not l.roleDuty then
        p.leisureMemory=Policy.remember(p.leisureMemory,l.activity,getGameTime():getWorldAgeHours(),l.finished==true)
    else p.leisureMemory=p.leisureMemory or {cooldowns={}} end
    if l.activity=='SIT' and l.seated and p.site then
        for _,part in ipairs(p.site.parts or {}) do
            if part.id==p.site.partId then
                p.leisureMemory.seatPreference={x=part.x,y=part.y,z=part.z} break
            end
        end
        if stopped then Service.seatReleased(p.settlementId) end
    end
    if l.moving then p.leisureMemory.moveAfter=getGameTime():getWorldAgeHours()+Config.movementIntervalHours end
    if l.finished and not l.brief and not l.zoneVisit and not preferred[c.job.npcId] then p.leisureMemory=Service.pause(p.leisureMemory) end
    if l.finished then statuses[c.job.npcId]={reason='CHOOSING',at=getTimestampMs()} end
    if l.socialId then
        if not l.finished then Social.cancel(l.socialId,c.job.npcId,p.attemptId) end
        Social.release(l.socialId,c.job.npcId,p.attemptId,stopped)
    end
end
function Service.reset() world,offers,statuses=nil,{},{ } preferred={} idleLogged={} Social.reset() end
return Service
