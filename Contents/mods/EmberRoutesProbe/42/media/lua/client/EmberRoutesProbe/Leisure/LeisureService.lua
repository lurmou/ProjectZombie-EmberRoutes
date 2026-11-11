-- Idle discovery called by SelfCare, using its shared budget and Runtime.
-- Activities are data: LeisureRegistry holds the ordered seek defs, each with
-- its own budget kind and def-private offer state. Adding an activity means
-- Registry.define here (and an action builder in LeisureActions) until 4.5
-- formalizes the public surface. Seeks do not find facilities themselves:
-- they query LeisureAds, the single advertisement table; finding lives in
-- its collectors (SOCIAL/READING/SMOKE/SIT/PUBLIC_LIFE pilot).
local Registry=require 'EmberRoutesProbe/Leisure/LeisureRegistry'
local Ads=require 'EmberRoutesProbe/Leisure/LeisureAds'
local Perf=require 'EmberRoutesProbe/Kernel/RuntimeMetrics'
local ContainerRegistry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Jobs=require 'EmberRoutesProbe/Runtime/TaskJobs'
local Policy=require 'EmberRoutesProbe/Leisure/LeisurePolicy'
local Config=require 'EmberRoutesProbe/Leisure/LeisureConfig'
local Constants=require 'EmberRoutesProbe/Kernel/Constants'
local LifeZones=require 'EmberRoutesProbe/Settlement/SettlementZones'
local Social=require 'EmberRoutesProbe/Activity/SocialCoordinator'
local Clock = require 'EmberRoutesProbe/Kernel/Clock'
local Service={}
-- Optional local policy; absence of a configured zone preserves old selection.
local function zoneRule(entry,point,activity,id)
    local context=require 'EmberRoutesProbe/Activity/ActivityService'
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
    statuses[id]={reason=reason,at=Clock.nowMs()}
    local now=Clock.nowMs()
    local row=idleLogged[id]
    if not row or row.reason~=reason or now-row.at>=10000 then
        idleLogged[id]={reason=reason,at=now}
        require "EmberRoutesProbe/Kernel/Log".write("LEISURE","IDLE npc="..tostring(id).." reason="..reason)
    end
end
local function load()
    local root=ContainerRegistry.data() if root~=world then world,offers,statuses=root,{},{ } preferred={} end
end
-- PublicWork reports observations; membership, not this report, permits life.
function Service.offer(id,entry)
    load()
    local member=require('EmberRoutesProbe/Settlement/MembershipService').view(id)
    if not member or member.pending or member.context~='SETTLEMENT' or member.settlementId~=entry.id then return end
    local row=offers[id]
    if not row or row.entry.id~=entry.id or row.membershipRevision~=member.revision
        or row.entryRevision~=entry.revision then row={entry=entry} offers[id]=row end

    row.membershipRevision=member.revision row.entryRevision=entry.revision
end

function Service.status(id)
    load() local s=statuses[id]
    return s and {reason=s.reason,activity=s.activity,at=s.at} or nil
end
local function clearOffer(id)
    offers[id]=nil preferred[id]=nil Social.withdraw(id)
end
function Service.note(id,reason) load() noteIdle(id,reason) end
-- reason is a diagnostic label only: it only feeds noteIdle's idle status,
-- no execution branch reads it.
function Service.invalidate(id,reason)
    load() clearOffer(id) noteIdle(id,reason or 'STALE_MEMBERSHIP')
end
function Service.probeable(id)
    local job=Jobs.current():forNpc(id,'SELF_CARE')[1]
    local p=job and job.payload
    return job and job.effects=='KNOWN' and p.step=='ACTING'
        and (p.kind=='LEISURE' or p.kind=='STUDY') or false
end
function Service.workReady(id,targetJobId)
    load() clearOffer(id)
    require('EmberRoutesProbe/Leisure/StudyService').changed(nil,id)
    local job=Jobs.current():forNpc(id,'SELF_CARE')[1]
    if job and Service.probeable(id) then
        local runtime=require('EmberRoutesProbe/Runtime/TaskRuntime').current()
        require "EmberRoutesProbe/Kernel/Log".write("LEISURE","WORK_READY npc="..tostring(id).." job="..tostring(job.id)..(targetJobId and (" target="..tostring(targetJobId)) or ""))
        if runtime then runtime:stopJob(id,job.id,'LEISURE_WORK_READY') end
    end
end
function Service.valid(actor,npc,id,p)
    if p.activityRef and not require('EmberRoutesProbe/Activity/ActivityService').validRef(id,p.activityRef) then return false end
    if p.leisure and p.leisure.roleDuty and (not p.leisure.point
        or require('EmberRoutesProbe/Leisure/LeisureRecord').tileKey(p.leisure.point)~=require('EmberRoutesProbe/Leisure/LeisureRecord').tileKey(
            {x=npc:getX(),y=npc:getY(),z=math.floor(npc:getZ())})) then return false end
    local M=require 'EmberRoutesProbe/Settlement/MembershipService'
    local eligible=M.check(id,'LEISURE',{x=npc:getX(),y=npc:getY(),z=npc:getZ(),scopeId=p.settlementId},p.membershipRevision)
    if not eligible.allowed or p.membershipRevision==nil or p.settlementRevision~=eligible.entryRevision then return false end
    -- Live membership check: faction equality plus geometry replace the detached
    -- copy and actor re-authorization on this 200ms-cadence advisory path.
    -- Replaced Ledger modules without data() keep the old view() form.
    local entry=M.entry(id,p.settlementId)
    if p.leisure and p.leisure.zoneVisit and (not entry
        or not require('EmberRoutesProbe/Activity/ActivityService').destination(entry.id,id,p.leisure.zoneVisit,p.leisure.point)) then return false end
    if entry and p.leisure and p.leisure.activity=='SIT' and p.site==nil then return false end
    if entry and p.leisure and p.leisure.started and not p.leisure.brief and not p.leisure.zoneVisit then
        local rule=zoneRule(entry,{x=npc:getX(),y=npc:getY(),z=npc:getZ()},p.leisure.activity,id)
        if not rule or rule==0 then return false end
    end
    return entry~=nil and require('EmberRoutesProbe/Settlement/SettlementGeometry').inside(entry,npc:getX(),npc:getY()) or false
end
function Service.sample(npc,sample)
    if not sample then return end
    local s={} for k,v in pairs(sample) do s[k]=v end
    local stats=npc:getStats()
    -- Native scales differ per stat (see Constants.Stat): PAIN and BOREDOM
    -- are 0-100, STRESS is 0-1. The snapshot below is all 0-1.
    s.pain=Constants.Stat.toUnit('PAIN',stats:get(CharacterStat.PAIN))
    s.boredom=CharacterStat.BOREDOM and Constants.Stat.toUnit('BOREDOM',stats:get(CharacterStat.BOREDOM)) or 0
    s.stress=CharacterStat.STRESS and Constants.Stat.toUnit('STRESS',stats:get(CharacterStat.STRESS)) or 0
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
    if not require('EmberRoutesProbe/Settlement/SettlementGeometry').inside(entry,point.x,point.y) then return end
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
Ads.install({zoneRule=zoneRule,standable=standable})

local function seekSocial(env)
    local ad,done,reason=Ads.lookup('SOCIAL',env)
    if not ad then return nil,done,reason end
    return {leisure={format=1,activity='SOCIAL',socialId=ad.payload.key,hours=env.hours},entry=env.entry,pure=true},true
end
function Service.seatedSocialAllowed(c)
    local entry=require('EmberRoutesProbe/Settlement/MembershipService').entry(c.job.npcId,c.payload.settlementId)
    local s=Service.sample(c.npc,c.sample())
    return c.valid() and Service.valid(c.actor,c.npc,c.job.npcId,c.payload)
        and Policy.allowed('SOCIAL',s,{hold=true}) and entry
        and (zoneRule(entry,{x=c.npc:getX(),y=c.npc:getY(),z=math.floor(c.npc:getZ())},'SOCIAL',c.job.npcId) or 0)>0
end
-- Called only by the active SIT leaf, with its existing proof and body retained.
function Service.seatedSocial(c)
    load()
    local id=c.job.npcId local offer=offers[id]
    if not offer
        or not c.valid() then Social.withdraw(id) return end
    local seat=Social.seated(id,c.actor)
    if not seat then Social.withdraw(id) return end
    local s=Service.sample(c.npc,c.sample())
    if not Policy.allowed('SOCIAL',s,{hold=true}) then Social.withdraw(id) return end
    local memory=c.payload.leisureMemory or {cooldowns={}}
    if getGameTime():getWorldAgeHours()<(memory.decisionAfter or 0) then Social.withdraw(id) return end
    offer.stateData=offer.stateData or {}
    offer.stateData.SOCIAL=offer.stateData.SOCIAL or {}
    local candidate=seekSocial({actor=c.actor,npc=c.npc,id=id,entry=offer.entry,point=seat,
        hours=getGameTime():getWorldAgeHours(),now=Clock.nowMs(),cooling=memory.cooldowns or {},
        budget=c.budget,state=offer.stateData.SOCIAL})
    return candidate and candidate.leisure.socialId
end


local function seekReading(env)
    local ad,done,reason=Ads.lookup('READING',env)
    if not ad then return nil,done,reason end
    return require('EmberRoutesProbe/Leisure/StudyService').decorateLeisure(ad.payload.candidate,env.id),true
end

local function seekSmoke(env)
    local ad,done,reason=Ads.lookup('SMOKE',env)
    if not ad then return nil,done,reason end
    local smoke=ad.payload
    return {leisure={format=1,activity='SMOKE',hours=env.hours,fireId=smoke.fire:getID()},
        item=smoke.item,fire=smoke.fire,entry=env.entry,pure=true},true
end

-- Seated idle reuses the P2 furniture discovery/reservation untouched: a
-- prepared proof plus its repose keys ride the LEISURE payload the same
-- way REST carries them, so occupancy claims interlock with the same store.
local function seekSit(env,preview,nearby)
    local ad,done,reason=Ads.lookup('SIT',env,{preview=preview,nearby=nearby})
    if not ad then return nil,done,reason end
    if ad.payload.preview then return {leisure={activity='SIT'},moving=true,targetKey=ad.payload.found.key},true end
    if ad.payload.site then
        return {leisure={format=1,activity='SIT',hours=env.hours},entry=env.entry,
            site=ad.payload.site,claims=ad.payload.claims,targetKey=ad.payload.targetKey},true
    end
    -- Claim step only: the seat was found and advertised by the collector.
    local Sites=require 'EmberRoutesProbe/SelfCare/ReposeSites'
    local proof=Sites.prepare(ad.payload.found,env.actor,env.npc,env.id,'REST')
    if proof then
        return {leisure={format=1,activity='SIT',hours=env.hours},entry=env.entry,site=proof,
            claims=Sites.keys(proof,'REST')},true
    end
    env.state.blocked[ad.payload.found.key]=Clock.nowMs()+5000
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
    if require('EmberRoutesProbe/Activity/ActivityService').context(env.id) then return nil,true end
    local ad,done,reason=Ads.lookup('PUBLIC_LIFE',env)
    if not ad then return nil,done,reason end
    return ad.payload.candidate,true
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
    local hours,now=getGameTime():getWorldAgeHours(),Clock.nowMs()
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
    if socialKey and kind~='SIT' then candidates[#candidates+1]={activity='SOCIAL',moving=true} end
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
        require('EmberRoutesProbe/Kernel/Log').write('LEISURE','SWITCH npc='..id..' from='..kind..' to='..best.activity)
        return true
    end
    statuses[id]={activity=kind,reason='CONTINUING',at=now}
    return false
end

-- Resource-free standing episode, still admitted through the ordinary personal
-- Job/Session. A decision pause keeps its original deadline and memory.
local function ambient(entry,point,id,eligible,hours,untilHours)
    if (zoneRule(entry,point,'OBSERVE',id) or 0)==0 then return end
    statuses[id]={activity='OBSERVE',reason='AMBIENT_IDLE',at=Clock.nowMs()}
    return {leisure={format=1,activity='OBSERVE',hours=hours,ambient=true,
        untilHours=untilHours or hours+Config.observeMinutes/60},entry=entry,pure=true,
        membershipRevision=eligible.revision,settlementRevision=eligible.entryRevision}
end

-- Clearing is a Job update, never a mutation of a detached discovery snapshot alone.
function Service.consumeResume(id,memory)
    local jobs=Jobs.current()
    local job=jobs:forNpc(id,'SELF_CARE')[1]
    if job and job.payload.leisureMemory and job.payload.leisureMemory.resumeHint then
        local p=job.payload
        p.leisureMemory.resumeHint=nil
        if not require('EmberRoutesProbe/SelfCare/SelfCareCommit').update(job.id,job.revision,{payload=p}) then return false end
    end
    if memory then memory.resumeHint=nil end
    return true
end

function Service.interrupted(c)
    local p=c.payload local l=p.leisure
    local reading=p.study and p.study.leisure
    if c.reason~='LEISURE_WORK_READY' or l and (l.finished or l.ambient or l.zoneVisit or l.roleDuty)
        or not reading and not (l and l.activity=='SIT') then return false end
    p.leisureMemory=p.leisureMemory or {cooldowns={}}
    local h
    if reading then
        local r=p.reading
        if r and (r.completed or r.windowEnded) then return false end
        h={activity='READING',settlementId=p.settlementId,itemId=p.itemId}
    elseif p.site then
        for _,part in ipairs(p.site.parts or {}) do
            if part.id==p.site.partId then
                h={activity='SIT',settlementId=p.settlementId,targetKey=p.site.key,
                    objectId=p.site.id,partId=p.site.partId,point={x=part.x,y=part.y,z=part.z}}
                break
            end
        end
    end
    p.leisureMemory.resumeHint=h
    return true
end

function Service.candidate(actor,binding,sample,budget,memory)
    load() local id,npc=binding.id,binding.handle local offer=offers[id]
    local M=require 'EmberRoutesProbe/Settlement/MembershipService'
    local eligible=M.check(id,'LEISURE',{x=npc:getX(),y=npc:getY(),z=npc:getZ()})
    if not eligible.allowed then
        Service.consumeResume(id,memory)
        Social.withdraw(id) noteIdle(id,eligible.reason) return nil,true
    end
    local entry=M.entry(id,eligible.settlementId)
    if not entry then
        Service.consumeResume(id,memory)
        Social.withdraw(id) noteIdle(id,'NO_ENTRY') return nil,true
    end
    if not offer or offer.membershipRevision~=eligible.revision or offer.entryRevision~=eligible.entryRevision then
        offer={entry=entry,membershipRevision=eligible.revision,entryRevision=eligible.entryRevision}
        offers[id]=offer
    end
    local s=Service.sample(npc,sample)
    if not Policy.allowed('OBSERVE',s,{hold=true}) then
        Service.consumeResume(id,memory)
        Social.withdraw(id) noteIdle(id,'NOT_ELIGIBLE') return nil,true
    end
    local now,hours=Clock.nowMs(),getGameTime():getWorldAgeHours()
    local point={x=npc:getX(),y=npc:getY(),z=math.floor(npc:getZ())}

    local Activities=require 'EmberRoutesProbe/Activity/ActivityService'
    local gathering=Activities.context(id)
    if gathering then
        local ready,why=require('EmberRoutesProbe/Activity/ActivityAttendance').inspect(actor,id,gathering)
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
            local candidate,done,why=require('EmberRoutesProbe/Settlement/LifeZoneVisits').seek(env,standable)
            if candidate then
                candidate.membershipRevision=eligible.revision candidate.settlementRevision=eligible.entryRevision
                statuses[id]={activity='OBSERVE',reason='ACTIVITY_APPROACH',at=now}
            else noteIdle(id,why or 'ACTIVITY_WAIT') end
            return candidate,done
        end
        if not Activities.arrived(actor,binding,gathering) then return nil,true end
        if gathering.phase=='GATHERING' then noteIdle(id,'ACTIVITY_WAITING_FOR_START') return nil,true end
        if not Activities.readyForAction(id) then noteIdle(id,'ACTIVITY_PERSONAL_SETTLING') return nil,true end
        local event=require('EmberRoutesProbe/Activity/ActivityStore').get(gathering.eventId)
        if event and event.scriptProfile then
            Social.withdraw(id)
            return require('EmberRoutesProbe/Activity/ActivityScripted').candidate(event,id,entry,eligible,gathering,hours)
        end
    end
    if memory and memory.resumeHint then
        local h=memory.resumeHint
        if h.settlementId==entry.id and Policy.allowed(h.activity,s,{hold=true})
            and (zoneRule(entry,point,h.activity,id) or 0)>0 then
            offer.stateData=offer.stateData or {}
            local key='RESUME_'..h.activity
            local seekState=offer.stateData[key] or {}
            offer.stateData[key]=seekState
            local env={actor=actor,binding=binding,id=id,npc=npc,offer=offer,entry=entry,s=s,hours=hours,
                point=point,budget=budget,cooling={},now=now,memory=memory,state=seekState,resume=h}
            local def=Registry.get(h.activity)
            local candidate,done=def.seek(env)
            if candidate then
                candidate.membershipRevision=eligible.revision candidate.settlementRevision=eligible.entryRevision
                candidate.activityRef=gathering
                local p={settlementId=entry.id,membershipRevision=eligible.revision,
                    settlementRevision=eligible.entryRevision,leisure=candidate.leisure,site=candidate.site,
                    study=candidate.study,activityRef=gathering}
                local valid=h.activity=='SIT' and Service.valid(actor,npc,id,p)
                    or h.activity=='READING' and require('EmberRoutesProbe/Leisure/StudyService').valid(actor,npc,id,p)
                if valid and (candidateRule(entry,point,candidate,id) or 0)>0 then
                    candidate.resume=true -- Receipt only; the hint remains solely in leisureMemory until admission.
                    offer.stateData[key]=nil
                    Social.withdraw(id)
                    return candidate,true
                end
            elseif done==false then return nil,false end
            offer.stateData[key]=nil
        end
        if not Service.consumeResume(id,memory) then return nil,true end
    end
    local hint=preferred[id]
    if hint and hint.untilTime<now then preferred[id]=nil hint=nil end
    if not gathering and not hint and memory and hours<(memory.decisionAfter or 0) then
        Social.withdraw(id)
        return ambient(entry,point,id,eligible,hours,memory.decisionAfter),true,'LEISURE_PAUSE'
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
    local strollOffsets={{2,0},{0,2},{-2,0},{0,-2}}
    local strollChecked={}
    local function strollPoint(index)
        local v=strollOffsets[index]
        return {x=math.floor(point.x)+v[1]+0.5,y=math.floor(point.y)+v[2]+0.5,z=point.z}
    end
    if Policy.allowed('STROLL',s,{hold=true}) and budget.scan>0 then
        local index=ZombRand(4)+1
        strollChecked[index]=true
        local p=strollPoint(index)
        budget.scan=budget.scan-1
        if standable(entry,p,{npc}) then candidates[#candidates+1]={activity='STROLL',point=p,weight=Config.weights.STROLL} end
    end
    local Facilities=require 'EmberRoutesProbe/Settlement/SettlementFacilities'
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
    -- Only the no-candidate IDLE fallback gets this independent, one-shot
    -- allowance. Never advance the facility sweep or retain a partial iterator.
    -- Decision pauses and gathering behavior keep their existing contracts.
    if not c and not gathering and (zoneRule(entry,point,'SIT',id) or 0)>0
        and standable(entry,point,{npc}) and hours>=(memory and memory.moveAfter or 0) then
        offer.ambientSit=offer.ambientSit or {}
        local nearby={actor=actor,npc=npc,id=id,entry=entry,point=point,s=s,hours=hours,now=now,
            cooling=env.cooling,memory=memory,offer=offer,state=offer.ambientSit,budget={scan=8}}
        c=seekSit(nearby,false,true)
        nearby.state.iter=nil
        if c and (candidateRule(entry,point,c,id) or 0)==0 then c=nil end
        if c then c.leisure.moving=true c.targetKey=c.site.key end
    end
    -- Fallback-only fresh cardinal points; the normal random point is never
    -- checked twice in one decision. All ordinary STROLL admission gates apply.
    if not c and not gathering and Policy.allowed('STROLL',s,{hold=true})
        and hours>=(env.cooling.STROLL or 0) and hours>=(memory and memory.moveAfter or 0) then
        for index=1,4 do
            if not strollChecked[index] then
                strollChecked[index]=true
                local p=strollPoint(index)
                local key='STROLL:'..math.floor(p.x)..':'..math.floor(p.y)..':'..p.z
                if (zoneRule(entry,p,'STROLL',id) or 0)>0
                    and (offer.blocked[key] or 0)<=now and standable(entry,p,{npc}) then
                    c={activity='STROLL',point=p,moving=true,targetKey=key}
                    break
                end
            end
        end
    end
    if not c then
        Social.withdraw(id)
        local fallback=ambient(entry,point,id,eligible,hours)
        if fallback then fallback.activityRef=gathering end
        if not fallback then noteIdle(id,deferred or 'NO_CANDIDATE') end
        return fallback,true
    end
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
    require('EmberRoutesProbe/Kernel/Log').write('LEISURE','SELECT npc='..id..' activity='..activity)
    return c,true
end
function Service.pause(memory)
    return Policy.pause(memory,getGameTime():getWorldAgeHours(),ZombRand(10000)/10000)
end
function Service.started(id,activity,brief,zoneVisit)
    load() statuses[id]={activity=activity,reason=zoneVisit and (zoneVisit.eventId and 'ACTIVITY_APPROACH' or 'LIFE_ZONE_APPROACH')
        or brief and 'WORK_OBSERVING' or 'ACTIVE',at=Clock.nowMs()}
    require('EmberRoutesProbe/Kernel/Log').write('LEISURE','ACTIVE npc='..id..' activity='..activity)
end
function Service.failed(id,key,reason)
    preferred[id]=nil
    load() local offer=offers[id]
    if offer and key then
        offer.blocked=offer.blocked or {} local count=0
        for k,t in pairs(offer.blocked) do if t<=Clock.nowMs() then offer.blocked[k]=nil else count=count+1 end end
        if count<32 then offer.blocked[key]=Clock.nowMs()+Config.failedTargetMs end
    end
    noteIdle(id,reason or 'START_FAILED')
end

function Service.finished(c,stopped)
    local p=c.payload local l=p.leisure
    if not l then return end
    if not l.finished and c.reason~='LEISURE_WORK_READY' and c.reason~='SOCIAL_INVITE' then
        Service.failed(c.job.npcId,c.leisureKey,c.reason or 'ACTIVITY_INTERRUPTED')
    end
    if l.ambient then return end -- Waiting must not restart the decision pause or activity cooldowns.
    if Service.interrupted(c) then
        if stopped and l.activity=='SIT' then Service.seatReleased(p.settlementId) end
        return
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
    if l.finished then statuses[c.job.npcId]={reason='CHOOSING',at=Clock.nowMs()} end
    if l.socialId then
        if not l.finished then Social.cancel(l.socialId,c.job.npcId,p.attemptId) end
        Social.release(l.socialId,c.job.npcId,p.attemptId,stopped)
    end
end
function Service.reset() world,offers,statuses=nil,{},{ } preferred={} idleLogged={} Social.reset() Ads.reset() end
return Service
