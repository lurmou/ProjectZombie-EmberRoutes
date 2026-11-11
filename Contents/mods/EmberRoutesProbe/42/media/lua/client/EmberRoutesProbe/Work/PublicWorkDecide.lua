-- Decision pass for PublicWork (split of PublicWork.lua).
-- One worker's discovery scan, provider choice and claim, plus the
-- fault-isolated safeDecide wrapper. Reads the shared state in
-- PublicWorkState; reservations and eligibility live in the sibling
-- PublicWork*.lua modules.
local S=require 'EmberRoutesProbe/Work/PublicWorkState'
local Service=S.Service
local Eligibility=require 'EmberRoutesProbe/Work/PublicWorkEligibility'
local Reservations=require 'EmberRoutesProbe/Work/PublicWorkReservations'
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Providers=require 'EmberRoutesProbe/Work/PublicWorkProviders'
local Selector=require 'EmberRoutesProbe/Work/WorkSelector'
local OrderQuery=require 'EmberRoutesProbe/Work/OrderQuery'
local NeedsObserver=require 'EmberRoutesProbe/SelfCare/NeedsObserver'
local NeedsPolicy=require 'EmberRoutesProbe/SelfCare/NeedsPolicy'
local MedicalCare=require 'EmberRoutesProbe/SelfCare/MedicalCare'
local PostingFilter=require 'EmberRoutesProbe/Settlement/MembershipPosting'
local Work=require 'EmberRoutesProbe/Work/Work'
local TaskJobs=require 'EmberRoutesProbe/Runtime/TaskJobs'
local JobStore=require 'EmberRoutesProbe/Kernel/JobStore'
local Config=require 'EmberRoutesProbe/Kernel/TickConfig'
local Log=require 'EmberRoutesProbe/Kernel/Log'
local Signals=require 'EmberRoutesProbe/Work/LaborSignals'
local Perf=require 'EmberRoutesProbe/Kernel/RuntimeMetrics'
local Probe=require 'EmberRoutesProbe/Kernel/Boot'
local Wake=require 'EmberRoutesProbe/Runtime/PlanningWake'

-- Wake predicate offers: every need kind counts, at its unchanged
-- NeedsPolicy enter threshold (choose() never reads warn). A missing or
-- unreadable sample fails open and wakes, never sleeps.
local WAKE_OFFERS={MEDICAL=true,EAT=true,DRINK=true,REST=true,SLEEP=true}
local discoverName={}
-- One faulty carrier must not abort the whole dispatch pass. Each decision is
-- isolated; its error is rate-limited per worker so a stuck one cannot flood
-- the log every pass.
local WORKER_FAULT_LOG_MS=10000

-- Discovery environment for one provider scan. Built here so decide no longer
-- knows the env's field shape; fields, closures and evaluation order are
-- unchanged from the inline table it replaces.
local function newDiscoverEnv(actor,npc,npcId,entry,priorities,now,candidates,setStudyTarget)
    return {
        actor=actor,npc=npc,npcId=npcId,entry=entry,priorities=priorities,
        now=now,candidates=candidates,
        setStudyTarget=setStudyTarget,
        directory=S.directory,
        orders=S.data.orders,
        orderIds=OrderQuery.orderIds(entry.id),
        sequence=S.data.sequence,
        candidateReady=function(key) return S.retryReady({id=key},npcId,now) end,
        retryReady=S.retryReady,
        cool=S.cool,
        signal=S.signal,
        upsertOffer=function(key,rev,cat,scope)
            return S.directory:upsert(key,rev,cat,scope or entry.id)
        end
    }
end
-- Posting filter for one tier's candidates. Marks rejected candidates in
-- place and returns the updated posting reason and acceptance flag.
local function applyPostingFilter(posting,zone,candidates,postingReason,postingAccepted)
    if posting and #candidates>0 then
        for _,candidate in ipairs(candidates) do
            if candidate.allowed~=false then
                local allowed,blocked=PostingFilter.allows(posting,zone,candidate)
                if not allowed then
                    candidate.allowed=false
                    if blocked=='POSTING_TARGET_UNAVAILABLE' then postingReason=blocked end
                elseif candidate.allowed then
                    postingAccepted=true
                end
            end
        end
    end
    return postingReason,postingAccepted
end

local function decide(actor,npcId,now,binding,entry)
    if S.pendingReservations[npcId] then return end

    if not binding then binding,entry=Eligibility.eligible(actor,npcId) end
    if not binding then Providers.cancelPending(npcId) S.idle:clear(npcId) Reservations.cancelReservation(npcId,'ELIGIBLE_FAILED') return end
    local npc=binding.handle
    if Providers.blocksDecision(actor,npcId,entry) then Reservations.cancelReservation(npcId,'DECISION_BLOCKED') return end
    if Work.hasCargo(actor,npcId) then Providers.cancelPending(npcId) Reservations.cancelReservation(npcId,'CARGO_INTERRUPT') return end
    if TaskJobs.current():ordinaryCount()>=JobStore.LIMIT then
	Providers.capacityBlocked(npcId,S.data.orders,S.signal)
	Providers.cancelPending(npcId) Reservations.cancelReservation(npcId,'CAPACITY_BLOCKED') return
    end
    local probing=Probe.careProbeWork and Probe.careProbeWork(npcId)
    if not probing then S.leisureStops[npcId]=nil end
    local priorities=Service.priorities(npcId) local candidates={} local studyTarget
    local member=S.Members and S.Members.view and S.Members.view(npcId)
    local stamp=entry.id..':'..tostring(entry.revision)..':'..tostring(member and member.revision)
        ..':'..tostring(member and member.postingRevision)..':'..tostring(priorities.revision)..':'..tostring(S.catalogEpoch[entry.id] or 0)
    if not Providers.hasPending(npcId) and not S.idle:due(npcId,now,stamp,Wake.revision and Wake.revision() or 0,Providers.discoveryChanged) then

        for _,provider in ipairs(Providers.all()) do
            if (priorities[provider.category] or 0)>0 and provider.idle then
                provider.idle(npcId,entry,S.idleStudyTargets[npcId])
            end
        end
        return
    end
    if S.retryWake[npcId] and S.retryWake[npcId]<=now then S.retryWake[npcId]=nil end

    local sample=NeedsObserver.sample(npc,npcId,now)
    -- NPC sleep (P0 pilot, cross-game Factorio §1.3): the 1Hz light
    -- recheck. A sleeper wakes when the world changed since it fell asleep
    -- (entry stamp: orders/priorities/member/catalog), a labor signal
    -- arrived, a provider precheck holds work for it, its discovery
    -- dependencies changed, its sample is unreadable (fail open), or a need
    -- crossed its unchanged enter threshold. Quiet sleepers recheck again
    -- in npcSleepRecheckMs; past npcSleepMaxMs a full discovery pass runs
    -- anyway, so no wake-condition gap can stall dispatch past the old
    -- idle-sleep bound. The gates above and advanceReservations still ran.
    if S.sleeping[npcId] then
        local s=S.sleeping[npcId]
        local wake=s.stamp~=stamp or S.wakeSignal or Providers.hasPending(npcId) or not sample
            or (s.watch and Providers.discoveryChanged(s.watch))
            or NeedsPolicy.choose(sample,nil,{safe=true},WAKE_OFFERS)~=nil
        if not wake and now-s.enteredAt<Config.npcSleepMaxMs then
            s.untilTime=now+Config.npcSleepRecheckMs
            return
        end
        S.sleeping[npcId]=nil
    end
    -- P0 pilot (cross-game RimWorld): emergency short-circuit. An NPC who
    -- needs medical care, is extremely hungry/thirsty, or is severely
    -- injured returns here, before the warn demotion and the provider
    -- scan: dispatch is certainly wasted, SelfCare owns the recovery on
    -- its own path. Thresholds live in NeedsPolicy.EMERGENCY only; the
    -- medical facts are SelfCare's last 1Hz observation (MedicalCare
    -- cache), so this adds no second body-part scan, and a missing
    -- observation fails open to normal dispatch. This is a second gate
    -- behind eligible()'s canWork check (same facts, 1s cache): it closes
    -- the window where the NPC was hurt after eligibility passed. A plain
    -- return: no reservation exists here (decide returns early when one
    -- does), and advanceReservations cancels a pending one once SelfCare
    -- starts the job. A sleeper that does not wake returns from the sleep
    -- block above before reaching this point, so it is never dispatched
    -- anyway; a sleeper that wakes on an extreme need is cleared there
    -- and then short-circuits here.
    local medical=MedicalCare.lastFacts(npcId)
    if NeedsPolicy.medicalEmergency(medical) then return end
    if NeedsPolicy.extremeNeed(sample) then return end
    if NeedsPolicy.severeInjury(medical) then return end

    local envDiscover=newDiscoverEnv(actor,npc,npcId,entry,priorities,now,candidates,function(t) studyTarget=t end)
    -- Discovery pass over all eligible providers (ordered by priority ascending, then provider registration order).
    local regIndex={}
    for i,cat in ipairs(Providers.categories()) do regIndex[cat]=i end
    local orderedProviders={}
    for _,provider in ipairs(Providers.all()) do
        local p=priorities[provider.category] or 0
        if p>=1 and p<=4 and provider.discover then orderedProviders[#orderedProviders+1]=provider end
    end
    table.sort(orderedProviders,function(a,b)
        local pa,pb=priorities[a.category] or 0,priorities[b.category] or 0
        if pa~=pb then return pa<pb end
        return (regIndex[a.category] or 0)<(regIndex[b.category] or 0)
    end)

    local posting=member and member.posting
    local zone,why=posting and PostingFilter.zone(posting,entry)
    local postingReason=why or (posting and (priorities[posting.category] or 0)==0 and 'POSTING_PRIORITY_ZERO' or 'POSTING_NO_ELIGIBLE_WORK')
    local postingAccepted=false

    local selected,jobId
    if #orderedProviders>0 then
        for _,provider in ipairs(orderedProviders) do
            envDiscover.priority=priorities[provider.category] or 0
            if Perf.active() then
                local name=discoverName[provider.category]
                if not name then name='PublicWork.discover:'..provider.category discoverName[provider.category]=name end
                S.measured(name,provider.discover,envDiscover)
            else
                provider.discover(envDiscover)
            end
        end

        postingReason,postingAccepted=applyPostingFilter(posting,zone,candidates,postingReason,postingAccepted)

        if #candidates>0 then
            local firstMap=OrderQuery.firstLiveByProduct()
            for _,candidate in ipairs(candidates) do
                if candidate.allowed~=false then
                    local order=candidate.order or candidate.orderId and S.data.orders[candidate.orderId]
                    local reason=order and OrderQuery.reasonFor(order,firstMap)
                    if reason then candidate.allowed=false S.signal(order,reason) end
                    if not S.retryReady({id=candidate.key},npcId,now) then candidate.allowed=false end
                end
            end
        end

        if Providers.holdSelection(envDiscover) then return end

        for _=1,3 do
            selected=Selector.choose(candidates,priorities)
            if not selected then break end
            jobId=Registry.id()
            if S.directory:claim(selected.key,selected.revision,npcId,jobId) then break end
            S.cool({id=selected.key},npcId,{watch=Wake.capture(entry)},'CLAIM_BUSY',now)
            selected.allowed=false selected=nil
        end
    end

    if posting and S.Members.notePosting then
        if postingAccepted then S.Members.notePosting(npcId,nil) else S.Members.notePosting(npcId,postingReason) end
    end

    if not selected then
            S.workerBackoff[npcId]=(S.workerBackoff[npcId] or 0)+1
            local orders=OrderQuery.orderIds(entry.id)
	    local complete,scanWatch=Providers.scanStatus(npcId,orders)
            if envDiscover.pending then complete=false end
            S.idleStudyTargets[npcId]=studyTarget
            S.idle:empty(npcId,now,stamp,Wake.revision and Wake.revision() or 0,scanWatch,
		complete and not Providers.hasPending(npcId),S.retryWake[npcId])
            if not probing and complete and not Providers.hasPending(npcId) and Probe.idleLeisure then
                Probe.idleLeisure(npcId,entry)
            end
            for _,provider in ipairs(Providers.all()) do
		if not probing and (priorities[provider.category] or 0)>0 and not Providers.hasPending(npcId) and provider.idle then
                    provider.idle(npcId,entry,studyTarget)
                end
            end
            -- NPC sleep entry (P0 pilot): one complete empty discovery with
            -- no pending work and no over-threshold need puts this NPC to
            -- sleep at once (no 10s wait like the IdleDiscovery sleep).
            -- Probing NPCs (leisure probe) and unreadable samples never
            -- sleep; a need already past enter keeps the NPC on the normal
            -- backoff cadence instead. Leisure was already offered above,
            -- so sleeping only paces the next offer, it never starves it.
            if not probing and complete and not Providers.hasPending(npcId) and sample
                and not NeedsPolicy.choose(sample,nil,{safe=true},WAKE_OFFERS) then
                S.sleeping[npcId]={untilTime=now+Config.npcSleepRecheckMs,stamp=stamp,watch=scanWatch,enteredAt=now}
                -- The pilot sleep subsumes the IdleDiscovery sleep for this
                -- NPC: clear its row so the 10s-empty clock cannot arm the
                -- old 15s sleep and interpose between 1Hz rechecks. The
                -- pilot's own npcSleepMaxMs cap is the bound instead. NPCs
                -- that never enter pilot sleep keep the old mechanism.
                S.idle:clear(npcId)
            end
            return
    end

    if probing then
        S.pendingReservations[npcId]={selected=selected,jobId=jobId,entry=entry,createdAt=now}
        if now>=(S.leisureStops[npcId] or 0) then
            S.leisureStops[npcId]=now+Config.socialRoundMs
            if Probe.leisureWorkReady then Probe.leisureWorkReady(npcId,jobId) end
        end
        S.careWaking[npcId]=true
        S.idle:clear(npcId)
        S.dispatchDirty=true
        S.nextWake=math.min(S.nextWake,now+Config.wakeMs)
        return
    end
    Reservations.claimSelected(actor,npcId,now,selected,jobId,entry)
end

-- One faulty carrier must not abort the whole dispatch pass. Each decision is
-- isolated; its error is rate-limited per worker so a stuck one cannot flood
-- the log every pass.
local function safeDecide(actor,npcId,now,binding,entry)
    local ok,err=pcall(decide,actor,npcId,now,binding,entry)
    if ok then
        if S.workerFaults[npcId] then S.workerFaults[npcId]=nil end
        return
    end
    local row=S.workerFaults[npcId]
    local count=(row and row.count or 0)+1
    local at=row and row.at
    if not at or now-at>=WORKER_FAULT_LOG_MS then
        S.workerFaults[npcId]={at=now,count=count}
        Log.write('DISPATCH','WORKER_FAULT npc='..tostring(npcId)..' count='..count..' error='..tostring(err))
    else
        row.count=count
    end
end

return {safeDecide=safeDecide}
