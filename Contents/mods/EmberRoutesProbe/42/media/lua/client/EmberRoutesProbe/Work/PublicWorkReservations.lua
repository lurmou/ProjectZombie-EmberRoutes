-- Reservation handling for PublicWork (split of PublicWork.lua).
-- Pending reservations, the one provider-claim path, and the
-- per-pass reservation advance (expiry / withdrawal / self-care /
-- labor-switch re-checks).
local S=require 'EmberRoutesProbe/Work/PublicWorkState'
local Eligibility=require 'EmberRoutesProbe/Work/PublicWorkEligibility'
local Providers=require 'EmberRoutesProbe/Work/PublicWorkProviders'
local Config=require 'EmberRoutesProbe/Kernel/TickConfig'
local Driver=require 'EmberRoutesProbe/Runtime/Driver'
local Probe=require 'EmberRoutesProbe/Kernel/Boot'
local Signals=require 'EmberRoutesProbe/Work/LaborSignals'
local Log=require 'EmberRoutesProbe/Kernel/Log'
local Wake=require 'EmberRoutesProbe/Runtime/PlanningWake'
local Clock = require 'EmberRoutesProbe/Kernel/Clock'

local function cancelReservation(npcId,reason)
    local res=S.pendingReservations[npcId]
    if res then
        S.pendingReservations[npcId]=nil
        if S.directory then
            S.directory:release(res.selected.key,res.jobId,{effects='KNOWN',obligationsCleared=true})
        end
        if reason then
            S.cool({id=res.selected.key},npcId,{watch=Wake.capture(res.entry)},reason,Clock.nowMs())
        end
    end
end
-- The one provider-claim path for direct decisions and promoted reservations.
-- A failed claim releases its offer only on the provider's rollback declaration.
local function claimSelected(actor,npcId,now,selected,jobId,entry)
    S.idle:clear(npcId)
    Providers.cancelPending(npcId)
    Providers.beforeClaim(selected,npcId)
    local result,declaration
    local provider=Providers.get(selected.category)
    if provider and provider.claim then
        result,declaration=provider.claim(selected,npcId,jobId,{actor=actor,entry=entry,now=now,directory=S.directory,
            releaseOffer=function(k,j,p) return S.directory:release(k,j,p) end})
    else
        -- No provider code ran for this offer, so nothing exists to roll back.
        declaration=Providers.CLAIM_ROLLED_BACK
    end
    local retained
    if result~='QUEUED' and result~='STARTED' then
        S.workerBackoff[npcId]=(S.workerBackoff[npcId] or 0)+1
        S.cool({id=selected.key},npcId,{watch=Wake.capture(entry)},result,now)
        retained=Providers.settleFailedClaim(S.directory,selected.key,jobId,declaration)
    else
        S.workerBackoff[npcId]=nil
        S.metrics.claims=S.metrics.claims+1
    end
    Signals.changed(npcId)
    Log.write('DISPATCH','npc='..npcId..' offer='..selected.key..' job='..jobId..' result='..tostring(result)
        ..(retained and ' OFFER_RETAINED reason='..retained or ''))
end
local function advanceReservations(now,actor)
    for npcId,res in pairs(S.pendingReservations) do
        local TaskJobs=require 'EmberRoutesProbe/Runtime/TaskJobs'
        local personalJob=TaskJobs and TaskJobs.current():forNpc(npcId,'SELF_CARE')[1]
        if now-res.createdAt>Config.reservationExpiryMs then
            cancelReservation(npcId,'RESERVATION_TIMEOUT')
            S.workerBackoff[npcId]=(S.workerBackoff[npcId] or 0)+1
        elseif S.directory and S.directory.isWithdrawn and S.directory:isWithdrawn(res.selected.key) then
            cancelReservation(npcId,'OFFER_WITHDRAWN')
        elseif personalJob and personalJob.payload and personalJob.payload.step=='ACTING'
            and personalJob.payload.kind~='LEISURE' and personalJob.payload.kind~='STUDY' then
            cancelReservation(npcId,'URGENT_SELF_CARE')
        else
            local binding,entry=Eligibility.eligible(actor,npcId,res.selected.scopeId or res.entry.id)
            local probing=Probe.careProbeWork and Probe.careProbeWork(npcId)
            if binding and not probing then
                S.pendingReservations[npcId]=nil
                -- The reservation's own entry, as before; the fresh one only gates eligibility.
                claimSelected(actor,npcId,now,res.selected,res.jobId,res.entry)
            else
                local bind=Driver.bindId(actor,npcId)
                local fatal=not bind or not bind.handle or Driver.suspended(bind.handle)
                    or (require('EmberRoutesProbe/SelfCare/HealthAssessment').canWork and not require('EmberRoutesProbe/SelfCare/HealthAssessment').canWork(bind.handle))
                    or (require('EmberRoutesProbe/Activity/ActivityAttendance').blocksOrdinary and require('EmberRoutesProbe/Activity/ActivityAttendance').blocksOrdinary(npcId))
                if fatal then
                    cancelReservation(npcId,'WORKER_FATAL_INELIGIBLE')
                else
                    S.dispatchDirty=true
                    S.nextWake=math.min(S.nextWake,now+Config.wakeMs)
                end
            end
        end
    end
end

return {cancelReservation=cancelReservation, claimSelected=claimSelected, advanceReservations=advanceReservations}
