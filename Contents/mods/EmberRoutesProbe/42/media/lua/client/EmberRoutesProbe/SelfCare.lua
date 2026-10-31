-- Personal candidates use the same Runtime as work/follow, never Public Orders.
local Probe=require 'EmberRoutesProbe/Boot'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Record=require 'EmberRoutesProbe/SelfCareRecord'
local Store=require 'EmberRoutesProbe/LaborStore'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Resume=require 'EmberRoutesProbe/TaskResume'
local Resources=require 'EmberRoutesProbe/SelfCareResources'
local Observer=require 'EmberRoutesProbe/NeedsObserver'
local Policy=require 'EmberRoutesProbe/NeedsPolicy'
local Driver=require 'EmberRoutesProbe/Driver'
local Facilities=require 'EmberRoutesProbe/SettlementFacilities'
local Performance=require 'EmberRoutesProbe/RuntimeMetrics'
local Log=require 'EmberRoutesProbe/Log'
local cached={}
local function use(name)
    if not cached[name] then cached[name]=require('EmberRoutesProbe/'..name) end
    return cached[name]
end
local Service={}
local world,rows,cursor,nextTick,budget=nil,{},0,0,{}
local function load()
    local root=Registry.data()
    if root~=world then world,rows,cursor,nextTick=root,{},0,0 end
    return root
end
local function personal(id,create)
    for _,job in ipairs(Jobs.current():forNpc(id,'SELF_CARE')) do if job.providerType=='SELF_CARE' then return job end end
    if not create then return end
    local job=Record.create(Registry.id(),id)
    if Jobs.current():create(job) then return Jobs.current():get(job.id) end
end
local function personalView(id)
    local store=Jobs.current()
    if store.peekPersonal then return store:peekPersonal(id) end
    return personal(id,false)
end
function Service.blocksWork(id)
    local job=personalView(id)
    if not job then return false end
    local p=job.payload local ref=p.resume
    if job.effects~='KNOWN' or p.step~='IDLE' or #p.claims>0 then return true end
    for _ in pairs(job.obligations) do return true end
    return ref and ref.state~='RESTORED' and ref.state~='INVALIDATED' and ref.epoch==Resume.epoch(id) or false
end
function Service.activity(id)
    local job=personalView(id)
    if not job then return end
    local runtime=Runtime.current() local current=runtime and runtime:status(id)
    if current and current.jobId==job.id then
        local relief=job.payload.relief
        return current.state=='STOPPING' and 'STOPPING' or relief and not relief.finished and relief.kind or job.payload.leisure and job.payload.leisure.activity or job.payload.kind
    end
    if not current and job.payload.step~='IDLE' then
        return job.effects=='UNKNOWN' and 'SELF_CARE_RECONCILE' or 'SELF_CARE_WAIT'
    end
end
function Service.studyStatus(id)
    load() local row=rows[id] return row and row.studyReason
end
-- Player-issued sleep order: one forced-selection window. It bypasses the
-- fatigue threshold and follow-context shared-resource gating (explicit player
-- intent), but not safety, backoff windows, or the no-bed give-up in advance().
function Service.force(id,kind)
    if kind~='SLEEP' then return false,'UNSUPPORTED_KIND' end
    if not EmberRoutesProbeJava or not EmberRoutesProbeJava.reposeWithControl
        or not EmberRoutesProbeJava.reposeAtWithControl then return false,'REPOSE_UNAVAILABLE' end
    load()
    local row=rows[id] or {} rows[id]=row
    row.forced={kind='SLEEP',untilTime=getTimestampMs()+300000}
    return true
end
function Service.prepareRemoval(id)
    local job=personalView(id)
    if not job then return true end
    local runtime=Runtime.current()
    if runtime and runtime:status(id,job.id) then runtime:stopJob(id,job.id,'REMOVE') return false end
    if job.effects~='KNOWN' or #job.payload.claims>0 then return false end
    for _ in pairs(job.obligations) do return false end
    return job.payload.step=='IDLE'
end
local function submit(actor,binding,job,candidate,row,settle,items,reliefOnly,interruptCompanion)
    local runtime=Runtime.current()
    if not runtime or not runtime:accepting() then return end
    local spec=use('SelfCareExecution').new(actor,binding,job,candidate,function() return budget end,settle,items,function()
        return row.sample and row.sample.safe and getTimestampMs()-row.sample.observedAt<=2000
            and not binding.handle:isOnFire() and binding.handle:getSurroundingAttackingZombies(false)==0
    end,reliefOnly,interruptCompanion)
    local handle,reason=runtime:submit(spec)
    row.handle=handle row.reason=reason
end
local function idle(job,row,reason)
    local token=Store.claimPersonal(job)
    if not token then row.reason='PERSONAL_CLAIM_CONFLICT' return end
    local p=job.payload p.step='IDLE' p.reason=reason
    if not Jobs.current():update(job.id,job.revision,{payload=p,obligations={}}) then return end
    if not Store.finishPersonal(job,token) then row.reason='PERSONAL_RELEASE_FAILED' end
end
local function settle(actor,binding,job,row)
    local p=job.payload
    if p.step=='RECONCILE_REQUIRED' or job.effects~='KNOWN' then return end
    if p.resume and p.resume.state=='REQUESTED' then row.reason='PREDECESSOR_STOP_PENDING' return end
    if (p.step=='REQUESTED' or p.step=='STOP_CONFIRMED') and p.kind~='STUDY'
        and not (p.activityRef and p.activityRef.dutyId)
        and not p.consumption and not p.transfer and not p.repose and not p.reading then
        idle(job,row,'CANDIDATE_NOT_STARTED') return
    end
    if not p.sourceId and not p.readingSite then
        -- A loaded duty attempt needs its actual owner stop path, even when it
        -- carries no item. IDLE alone is not native/asset cleanup evidence.
        if p.activityRef and p.activityRef.dutyId then
            if not Runtime.current():owns(binding.id) then submit(actor,binding,job,nil,row,true,{}) end
        else idle(job,row,'PERSONAL_STOPPED') end
        return
    end
    local current=Runtime.current():status(binding.id)
    local interruptCompanion=current and current.kind=='COMPANION' and current.state=='ACTIVE' and current.started and not current.pending
    if current and not interruptCompanion then return end
    local member=use('MembershipService').view(binding.id)
    -- Recovery is not a new study candidate. In particular pending transfer MUST be able to return a borrowed original.
    local reliefOnly=p.kind=='STUDY' and member and member.context=='FOLLOW' and not member.pending
    if reliefOnly then
        local need=Policy.choose(row.sample,nil,{safe=true},{EAT=true,DRINK=true,REST=true})
        if not need or getTimestampMs()<(row.reliefRetryAt or 0) then return end
    end
    row.recovery=row.recovery or {index=1,items={}}
    local recovery=row.recovery local ids={}
    local consumed=p.consumption and p.consumption.effects=='KNOWN' and p.consumption.after
        and p.consumption.after<=.0001
    if not consumed then ids[#ids+1]=p.itemId end
    for _,id in ipairs(p.consumption and p.consumption.outputs or {}) do ids[#ids+1]=id end
    local id=ids[recovery.index]
    if not id then
        row.recovery=nil
        if interruptCompanion then
            local accepted,reason=Resume.prepare(actor,binding.id,job.id)
            if not accepted then row.reason=reason return end
            job=Jobs.current():get(job.id)
        end
        if reliefOnly then row.reliefRetryAt=getTimestampMs()+5000 end
        submit(actor,binding,job,nil,row,true,recovery.items,reliefOnly,interruptCompanion)
        return
    end
    if budget.scan<1 then return end
    local destination=p.destinations and p.destinations[tostring(id)] or p.sourceId
    recovery.request=recovery.request or Resources.new(actor,binding.handle,'CUSTODY',false,id,destination,job.id)
    local slice=math.min(8,budget.scan)
    local candidate,done,reason=recovery.request:step(slice) budget.scan=budget.scan-slice
    if not done then return end
    local depleted=id==p.itemId and p.consumption and p.consumption.effects=='KNOWN'
        and type(p.consumption.after)=='number' and p.consumption.after<=0.0001
    if candidate then recovery.items[id]=candidate.item
    elseif not depleted then
        if destination~=p.sourceId and not recovery.triedSource then
            recovery.request=Resources.new(actor,binding.handle,'CUSTODY',false,id,p.sourceId,job.id)
            recovery.triedSource=true return
        end
        row.reason=reason row.recovery=nil row.retryAt=getTimestampMs()+5000
        return
    end
    recovery.index=recovery.index+1 recovery.request=nil recovery.triedSource=nil
end
local function observe(actor,binding,row,now)
    if now<(row.observeAt or 0) then return end
    row.observeAt=now+1000
    row.sample,row.reason=Observer.sample(binding.handle,binding.id,now)
end
local function advance(actor,binding,row,now)
    local id=binding.id local runtime=Runtime.current()
    local forcedSleep=row.forced and row.forced.kind=='SLEEP' and now<row.forced.untilTime
    if row.forced and not forcedSleep then row.forced=nil end
    if row.handle then
        local state=runtime:inspect(row.handle)
        if state and (state.state=='CLOSED' or state.state=='CANCELLED' or state.state=='REJECTED') then
            row.handle=nil row.scan=nil row.retryAt=now+1000
            local ended=personal(id,false)
            if ended and ended.payload.site and ended.payload.site.key and ended.payload.reason
                and (string.find(ended.payload.reason,'^SITE_') or string.find(ended.payload.reason,'^SLEEP_')
                    or string.find(ended.payload.reason,'^SIT_')
                    or ended.payload.reason=='NATIVE_REPOSE_TIMEOUT') then
                row.siteUnavailable=row.siteUnavailable or {}
                local n=0 for key,untilTime in pairs(row.siteUnavailable) do
                    if now>=untilTime then row.siteUnavailable[key]=nil else n=n+1 end
                end
                if n>=128 then row.siteUnavailable={} end
                row.siteUnavailable[ended.payload.site.key]=now+10000
            end
            if ended and ended.payload.reason=='NATIVE_REPOSE_TIMEOUT' then
                row.unavailable=row.unavailable or {} row.unavailable[ended.payload.kind]=now+60000
            end
            if ended and ended.payload.reason and string.find(ended.payload.reason,'^FLOOR_') then
                row.unavailable=row.unavailable or {} row.unavailable.SLEEP=now+10000
            end
        end
    end
    observe(actor,binding,row,now)
    local sample=row.sample
    if not sample or not sample.safe or now-sample.observedAt>2000 then
        local job=personal(id,false)
        if job and runtime:status(id,job.id) then runtime:stopJob(id,job.id,'SELF_CARE_UNSAFE') end
        row.scan=nil row.reposeScan=nil return
    end
    local gathering=use('ActivityService').context(id)
    if gathering then
        if forcedSleep or Policy.choose(sample,nil,{safe=true},{EAT=true,DRINK=true,REST=true,SLEEP=true}) then
            use('ActivityService').leave(id,'ACTIVITY_NEEDS_CARE') gathering=nil
        else use('ActivityAttendance').request(actor,binding,gathering) end
    end
    if row.handle then
        local active=personal(id,false)
        if active and active.payload.kind=='LEISURE' then
            local need=Policy.choose(sample,nil,{safe=true},{EAT=true,DRINK=true,REST=true,SLEEP=true})
            if active.payload.leisure and active.payload.leisure.activity=='OBSERVE'
                and not active.payload.leisure.roleDuty
                and use('SocialCoordinator').pending(id) then
                runtime:stopJob(id,active.id,'SOCIAL_INVITE')
            end
            if need or forcedSleep or not use('LeisureService').valid(actor,binding.handle,id,active.payload) then
                runtime:stopJob(id,active.id,forcedSleep and 'USER_SLEEP' or 'LEISURE_NEEDS_CARE')
            end
        end
        if active and active.payload.kind=='STUDY' and active.payload.step=='ACTING'
            and not (active.payload.reading and active.payload.reading.completed) then
            local need=Policy.choose(sample,nil,{safe=true},{EAT=true,DRINK=true,REST=true,SLEEP=true})
            if need or forcedSleep or not use('StudyService').valid(actor,binding.handle,id,active.payload)
                or active.payload.reading and active.payload.reading.total>0 and now>(row.studyReviewAt or math.huge) then
                runtime:stopJob(id,active.id,forcedSleep and 'USER_SLEEP' or (need and 'STUDY_NEEDS_CARE' or 'STUDY_REEVALUATE'))
            end
        end
        return
    end
    if now<(row.retryAt or 0) then return end
    local job=personal(id,false)
    if job and job.effects~='KNOWN' then return end
    if job and job.payload.step~='IDLE' then
        local ref=job.payload.resume
        if job.payload.reliefOnly and ref and (ref.state=='STOP_CONFIRMED' or ref.state=='RESTORE_QUEUED') then
            Resume.resume(actor,id,job.id) return
        end
        local current=runtime:status(id)
        if not runtime:owns(id) or job.payload.kind=='STUDY' and current and current.kind=='COMPANION' then settle(actor,binding,job,row) end
        -- An inaccessible return must not keep the body or strand the original
        -- work. It still blocks unrelated public work and NPC removal.
        if not row.handle and job.payload.step=='SETTLING' and job.payload.kind~='STUDY' then Resume.resume(actor,id,job.id) end
        return
    end
    local repose=EmberRoutesProbeJava.reposeWithControl~=nil
    local ref=job and job.payload.resume
    local eligibility=use('MembershipService').check(id,'SELF_CARE',
        {x=binding.handle:getX(),y=binding.handle:getY(),z=binding.handle:getZ()})
    local ownOnly=not eligibility.sharedResources
    local offers={EAT=true,DRINK=true,REST=repose,SLEEP=repose and (forcedSleep or (not ownOnly
        and sample.hunger<0.5 and sample.thirst<0.5))}
    for blocked,deadline in pairs(row.unavailable or {}) do if now<deadline then offers[blocked]=false end end
    local kind=Policy.choose(sample,job and job.payload.lastKind,{safe=true},offers)
    -- A player sleep order overrides the fatigue threshold only; safety,
    -- backoff windows and the bed requirement below still gate it.
    if forcedSleep and offers.SLEEP then kind='SLEEP' end
    local studyCandidate
    -- Idle discovery runs at most one settled round per 1.5s per NPC. Both
    -- providers re-check their own offers each call; the cooldown only stops
    -- the no-result rescan of standable/social/facility paths at 200ms cadence.
    local discoverReady=now>=(row.discoverAt or 0)
    local studyAttempted,leisureAttempted,leisureSettled=false,false,true
    local idleEligible=use('MembershipService').check(id,'LEISURE',
        {x=binding.handle:getX(),y=binding.handle:getY(),z=binding.handle:getZ()}).allowed
    if discoverReady and not gathering and not kind and idleEligible and (not job or not job.payload.resume or job.payload.resume.state=='RESTORED'
        or job.payload.resume.state=='INVALIDATED') and budget.scan>0 then
        studyAttempted=true
        local candidate,done,reason=use('StudyService').candidate(actor,binding.handle,id,budget,job and job.payload.leisureMemory)
        row.studyReason=reason
        if candidate then studyCandidate=candidate kind='STUDY'
        elseif not done then row.studyReason=reason or 'LIBRARY_OBSERVING' end
    end
    if discoverReady and not kind and idleEligible and not runtime:owns(id) and (not ref or ref.state=='RESTORED' or ref.state=='INVALIDATED') then
        leisureAttempted=true
        local candidate,done=use('LeisureService').candidate(actor,binding,sample,budget,job and job.payload.leisureMemory)
        if candidate and candidate.study then studyCandidate=candidate kind='STUDY'
        elseif candidate then
            job=job or personal(id,true) if not job then return end
            local before=job.payload local p=Record.begin(job,'LEISURE',before.resume)
            if not p then use('LeisureService').note(id,'PERSONAL_ATTEMPT_RETAINED') return end
            p.leisure=candidate.leisure p.settlementId=candidate.entry.id p.membershipRevision=candidate.membershipRevision
            p.activityRef=candidate.activityRef
            if p.leisure.roleDuty then p.claims={use('LeisureRecord').tileKey(p.leisure.point)} end
            p.settlementRevision=candidate.settlementRevision
            if candidate.item then p.itemId=candidate.item:getID() p.claims={'item:'..p.itemId,'item:'..candidate.fire:getID()} end
            if p.leisure.socialId then
                local point=use('SocialCoordinator').view(p.leisure.socialId,id,nil,now)
                if not point then return end
                local q=point.point p.claims={'leisureTile:'..math.floor(q.x)..':'..math.floor(q.y)..':'..q.z}
            end
            if p.leisure.zoneVisit then
                p.claims={use('LifeZoneVisits').tileKey(p.leisure.point)}
            end
            if candidate.site then p.site=candidate.site p.claims=candidate.claims end
            local updated,why=Jobs.current():update(job.id,job.revision,{payload=p})
            if not updated then
                use('LeisureService').failed(id,candidate.targetKey,why or 'PERSONAL_RECORD_REJECTED')
                row.retryAt=now+1500 return
            end
            job=Jobs.current():get(job.id) local token=Store.claimPersonal(job)
            if token and Resume.prepare(actor,id,job.id) then
                job=Jobs.current():get(job.id) submit(actor,binding,job,candidate,row,false)
            end
            if not row.handle then
                use('LeisureService').failed(id,candidate.targetKey,row.reason or 'LEISURE_SUBMIT_REJECTED')
                row.retryAt=now+1500
                if token then Store.finishPersonal(job,token) end
                local live=Jobs.current():get(job.id)
                Jobs.current():update(live.id,live.revision,{payload=before})
                use('SocialCoordinator').withdraw(id)
            end
            return
        else leisureSettled=done~=false end
    end
    if not kind then
        row.scan=nil row.reposeScan=nil
        if studyAttempted and leisureAttempted and leisureSettled then row.discoverAt=now+1500 end
        if job then Resume.resume(actor,id,job.id) end
        return
    end
    local current=runtime:status(id)
    if kind=='STUDY' and current and current.kind~='COMPANION' then return end
    if current and (current.pending or current.state~='ACTIVE' or not current.started
        or current.kind~='PRODUCTION' and current.kind~='TRANSFER' and current.kind~='COMPANION' and current.kind~='MEMBERSHIP_RETURN') then return end
    -- Follow can use only personal supplies; it never walks back to settlement.
    -- A moving squad can pause briefly for supplies/endurance; long sleep is
    -- offered only in settlement life. Both paths restore the same predecessor relation.
    if kind=='REST' or kind=='SLEEP' then
        local site,floorSite
        if not row.floorScan and (not ownOnly or forcedSleep) and EmberRoutesProbeJava.reposeAtWithControl then
            if not row.reposeScan or row.reposeKind~=kind then
                row.reposeScan=require('EmberRoutesProbe/ReposeSites').new(actor,binding.handle,id,kind,row.siteUnavailable)
                row.reposeKind=kind
            end
            if budget.scan<1 then return end
            local slice=math.min(8,budget.scan) local candidate,done,reason=row.reposeScan:step(slice)
            row.reposeReason=reason
            budget.scan=budget.scan-slice
            if not done and reason=='SITE_OBSERVING' then return end
            row.reposeScan=nil
            if candidate then
                site=require('EmberRoutesProbe/ReposeSites').prepare(candidate,actor,binding.handle,id,kind)
                if not site then row.retryAt=now+1000 return end
            end
        else row.reposeScan=nil end
        if kind=='SLEEP' and not site then
            if not EmberRoutesProbeJava.floorSleepSafe then row.reason='FLOOR_BRIDGE_UNAVAILABLE' return end
            row.floorScan=row.floorScan or use('FloorSleep').scan(binding.handle,id)
            local slice=math.min(8,budget.scan)
            if slice<1 then return end
            local done
            floorSite,done=row.floorScan:step(slice) budget.scan=budget.scan-slice
            if not done then return end
            row.floorScan=nil
            if not floorSite then
                row.forced=nil row.reason='SLEEP_NO_BED' row.retryAt=now+5000
                binding.handle:Say(getText('IGUI_EmberRoutesProbe_Membership_SLEEP_NO_BED'))
                return
            end
        else row.floorScan=nil end
        row.scan=nil job=job or personal(id,true) if not job then return end
        local before=job.payload
        local p=Record.begin(job,kind,before.resume) if not p then return end
        if site then p.site=site p.claims=require('EmberRoutesProbe/ReposeSites').keys(site,kind) end
        if floorSite then
            p.floorSite=floorSite p.settlementId=floorSite.settlementId p.claims={use('FloorSleep').key(floorSite)}
        end
        if not Jobs.current():update(job.id,job.revision,{payload=p}) then return end
        job=Jobs.current():get(job.id)
        local token=Store.claimPersonal(job)
        if not token then
            if not Jobs.current():update(job.id,job.revision,{payload=before}) then error('PERSONAL_ROLLBACK_FAILED') end
            row.retryAt=now+1000 return
        end
                local prepared=Resume.prepare(actor,id,job.id)
                job=Jobs.current():get(job.id)
                if prepared then submit(actor,binding,job,nil,row,false) end
                if row.handle and job.payload.kind=='SLEEP' then row.forced=nil end
        if not row.handle then
            local live=Jobs.current():get(job.id)
            if not Store.finishPersonal(live,token) then error('PERSONAL_RELEASE_FAILED') end
            live=Jobs.current():get(job.id)
            if not Jobs.current():update(live.id,live.revision,{payload=before}) then error('PERSONAL_ROLLBACK_FAILED') end
        end
        return
    end
    row.reposeScan=nil
    if not studyCandidate and (not row.scan or row.scan.kind~=kind or row.ownOnly~=ownOnly) then
        row.scan=Resources.new(actor,binding.handle,kind,ownOnly) row.ownOnly=ownOnly
    end
    if budget.scan<1 then return end
    local slice=math.min(8,budget.scan)
    local candidate,done,reason=studyCandidate,studyCandidate~=nil,nil
    if not studyCandidate then candidate,done,reason=row.scan:step(slice) budget.scan=budget.scan-slice end
    if not done then return end row.scan=nil
    if not candidate or not Resources.revalidate(candidate,kind) then
        row.reason=reason row.unavailable=row.unavailable or {} row.unavailable[kind]=now+5000 return
    end
    job=job or personal(id,true) if not job then row.reason='PERSONAL_JOB_LIMIT' return end
    local before=job
    local p,why=Record.begin(job,kind,job.payload.resume)
    if not p then row.reason=why return end
    p.itemId=candidate.id p.sourceId=candidate.endpoint and candidate.endpoint.id
    p.settlementId=candidate.entry and candidate.entry.id
    if kind=='STUDY' then
        p.activityRef=candidate.activityRef
        p.study=candidate.study p.membershipRevision=candidate.membershipRevision row.studyReviewAt=now+30000
        p.settlementRevision=candidate.settlementRevision
    else
        local food=kind=='EAT' and require('EmberRoutesProbe/CookingFood').read(candidate.item)
        local available=food and food.meal and food.effective or kind=='EAT' and -candidate.item:getHungChange() or 0
        p.fraction=kind=='EAT' and math.min(1,math.max(.05,(sample.hunger-.08)/math.max(.001,available))) or .5
    end
    p.claims={'item:'..candidate.id}
    local obligations=p.sourceId and {RETURN_ORIGINALS={sourceId=p.sourceId,itemId=p.itemId}} or {}
    if not Jobs.current():update(job.id,job.revision,{payload=p,obligations=obligations}) then return end
    job=Jobs.current():get(job.id)
    local token=Store.claimPersonal(job)
    local function rollback(reason)
        local live=Jobs.current():get(job.id)
        if token then
            if not Jobs.current():update(live.id,live.revision,{obligations={}})
                or not Store.finishPersonal(job,token) then error('PERSONAL_ROLLBACK_FAILED') end
            live=Jobs.current():get(job.id)
        end
        if not Jobs.current():update(live.id,live.revision,{payload=before.payload,obligations=before.obligations}) then
            error('PERSONAL_ROLLBACK_FAILED')
        end
        row.reason=reason row.retryAt=now+3000
    end
    if not token then rollback('RESOURCE_CLAIM_FAILED') return end
    local accepted,blocked=Resume.prepare(actor,id,job.id)
    if not accepted then rollback(blocked) return end
    job=Jobs.current():get(job.id)
    submit(actor,binding,job,candidate,row,false)
    if not row.handle then rollback(row.reason or 'CANDIDATE_CHANGED') end
end
function Service.tick()
    -- One clock read feeds both the facilities pump and the 200ms gate; the
    -- pump accepts it so its idle path costs no extra bridge.
    local now=getTimestampMs()
    budget.nodes,budget.scan,budget.paths,budget.containers=16,32,1,4
    if not Facilities.due or Facilities.due(now) then
        if Performance.active() then Performance.measure('Facilities',function() Facilities.tick(64,now) end)
        else Facilities.tick(64,now) end
    end
    if now<nextTick then return end
    load()
    local runtime=Runtime.current()
    if not runtime or not runtime:accepting() then return end
    if world.executionSave and world.executionSave.state=='BLOCKED' then return end
    nextTick=now+200
    local actor=getSpecificPlayer(0)
    if not actor or actor:isDead() then return end
    local count=EmberRoutesProbeJava.workerCount()
    if count<1 or count>256 then return end
    local function rosterRound()
        for _=1,math.min(4,count) do
            cursor=cursor%count+1 local id=EmberRoutesProbeJava.workerIdAt(cursor-1)
            local binding=Driver.bindId(actor,id)
            if binding then
                local row=rows[id] or {} rows[id]=row
                local ok,reason=pcall(advance,actor,binding,row,now)
                if not ok then
                    row.retryAt=now+5000
                    local job=personal(id,false)
                    if job and runtime:status(id,job.id) then runtime:stopJob(id,job.id,'SELF_CARE_ERROR') end
                    if row.fault~=tostring(reason) then
                        row.fault=tostring(reason)
                        Log.write('SELF_CARE','npc='..id..' '..row.fault)
                    end
                end
            end
        end
    end
    -- Sub-bucket only while sampling: separates the 200ms discovery/validation
    -- round from the bucket's fixed overhead (Facilities has its own row).
    if Performance.active() then Performance.measure('SCAdvance',rosterRound) else rosterRound() end
end
function Service.prepareRecovery(receipt)
    load()
    for _,saved in pairs(world.taskJobs and world.taskJobs.byId or {}) do
        if saved.providerType=='SELF_CARE' then
            if not Record.valid(saved) then error('PERSONAL_RECORD_INVALID') end
            if saved.payload.kind=='LEISURE' and saved.effects=='KNOWN' and saved.payload.step~='IDLE'
                and not saved.payload.leisure.applying then
                local live=Jobs.current():get(saved.id) local p=live.payload
                p.step='STOP_CONFIRMED' p.leisure.stopped=true
                if not Jobs.current():update(live.id,live.revision,{payload=p}) then error('LEISURE_RECOVERY_FAILED') end
            elseif saved.payload.step=='ACTING' then
                -- No stopped/persisted fact means the native call may have run.
                local live=Jobs.current():get(saved.id) local p=live.payload p.step='RECONCILE_REQUIRED'
                if not Jobs.current():update(live.id,live.revision,{payload=p,effects='UNKNOWN',state='RECONCILE_REQUIRED'}) then
                    error('PERSONAL_RECOVERY_FAILED')
                end
            end
        end
    end
    return true
end
function Service.reset() world,rows,cursor,nextTick,Service.offerLogged=nil,{},0,0 use('LeisureService').reset() end
function Service.install()
    if Probe.selfCareInstalled then return end
    Resume.install()
    local previous=Probe.prepareCareRecovery
    Probe.prepareCareRecovery=function(receipt)
        if previous and previous(receipt)~=true then return false end
        return Service.prepareRecovery(receipt)
    end
    Probe.tickSelfCare=Service.tick Probe.resetSelfCare=Service.reset
    Probe.careBlocksWork=Service.blocksWork Probe.careRemovalReady=Service.prepareRemoval
    Probe.careActivity=Service.activity
    Probe.forceCare=Service.force
    Probe.studyStatus=Service.studyStatus
    Probe.idleStudy=function(id,entry,target) use('StudyService').offer(id,entry,target) end
    Probe.invalidateStudy=function(scope,id) use('StudyService').changed(scope,id) end
    Probe.idleLeisure=function(id,entry)
        use('LeisureService').offer(id,entry)
        -- First link of the leisure diagnostics chain (OFFER -> IDLE -> ACTIVE):
        -- no OFFER lines at all means upstream gate blocked the offer itself.
        local now=getTimestampMs()
        local row=Service.offerLogged and Service.offerLogged[id]
        if not row or row.entry~=entry.id or now-row.at>=10000 then
            Service.offerLogged=Service.offerLogged or {}
            Service.offerLogged[id]={entry=entry.id,at=now}
            require "EmberRoutesProbe/Log".write("LEISURE","OFFER npc="..tostring(id).." entry="..tostring(entry.id))
        end
    end
    Probe.careProbeWork=function(id) return use('LeisureService').probeable(id) end
    Probe.leisureWorkState=function(id,entry,state) use('LeisureService').workState(id,entry,state) end
    Probe.leisureWorkReady=function(id) use('LeisureService').workReady(id) end
    Probe.invalidateLeisure=function(id,reason) use('LeisureService').invalidate(id,reason) end
    Probe.selfCareInstalled=true
end
return Service
