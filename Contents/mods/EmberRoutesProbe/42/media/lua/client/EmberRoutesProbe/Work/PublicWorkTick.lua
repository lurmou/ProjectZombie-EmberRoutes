-- Tick driver for PublicWork (split of PublicWork.lua).
-- Precheck adapters, the discovery/advance pass and the fault-counting
-- Service.tick entry. Discovery cadence, decision window and backoff
-- ladder are unchanged from the single-file version.
local S=require 'EmberRoutesProbe/Work/PublicWorkState'
local Service=S.Service
local Eligibility=require 'EmberRoutesProbe/Work/PublicWorkEligibility'
local Reservations=require 'EmberRoutesProbe/Work/PublicWorkReservations'
local Decide=require 'EmberRoutesProbe/Work/PublicWorkDecide'
local Reconcile=require 'EmberRoutesProbe/Work/PublicWorkReconcile'
local Stock=require 'EmberRoutesProbe/Work/PublicWorkStock'
local Providers=require 'EmberRoutesProbe/Work/PublicWorkProviders'
local Config=require 'EmberRoutesProbe/Kernel/TickConfig'
local Gate=require 'EmberRoutesProbe/Kernel/RuntimeGate'
local Runtime=require 'EmberRoutesProbe/Runtime/TaskRuntime'
local Probe=require 'EmberRoutesProbe/Kernel/Boot'
local Work=require 'EmberRoutesProbe/Work/Work'
local Log=require 'EmberRoutesProbe/Kernel/Log'
local Wake=require 'EmberRoutesProbe/Runtime/PlanningWake'
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'

local FAULT_RETRY_MS,FAULT_LIMIT=1000,5

-- Precheck adapters are hoisted: rebuilding seven closures on every 50 ms pass
-- was pure garbage with no behavioural benefit.
local function precheckEligible(a,id,scope) return Eligibility.eligible(a,id,scope) end
local function precheckHasCargo(a,id) return Work.hasCargo(a,id) end
local function precheckRecord(id) return Work.record(id) end
local function precheckPriorities(id) return Service.priorities(id) end
local function precheckReady(id) S.readyWorkers[#S.readyWorkers+1]=id end

local function advance(now,discover,providerDue,precheckDue)
    if not Probe.ready or not Probe.runtimeReady or not Probe.hasJava() or not Gate.isSinglePlayer() then return end
    local runtime=Runtime.current() if not runtime or not runtime:accepting() then return end
    S.load()
    if S.world.executionSave and S.world.executionSave.state=='BLOCKED' then return end
    local actor=getSpecificPlayer(0) if not actor or actor:isDead() then return end
    -- Captured before anything below clears dispatchDirty: a labor signal
    -- since the last discovery pass wakes sleeping NPCs at their recheck.
    S.wakeSignal=S.dispatchDirty
    S.measured('PublicWork.reservations',Reservations.advanceReservations,now,actor)
    S.measured('PublicWork.observe',Providers.observeDemand,actor,now,Eligibility.eligible,Service.priorities)
    if providerDue then
        for _,provider in ipairs(Providers.all()) do
            if provider.advance then S.measured('PublicWork.providerAdvance',provider.advance,{actor=actor,now=now,directory=S.directory}) end
        end
    end
    if precheckDue and Providers.hasPrechecks() then
	local ops,slices=S.measured('PublicWork.precheck',Providers.precheck,{
            actor=actor,now=now,orders=S.data.orders,
            eligible=precheckEligible,hasCargo=precheckHasCargo,record=precheckRecord,
            priorities=precheckPriorities,onReady=precheckReady,cool=S.cool,signal=S.signal
        })
        S.tickOps,S.tickSlices=ops,slices
        local ready=S.readyWorkers S.readyWorkers={}
        if #ready>1 then
            table.sort(ready,function(a,b)
                return Providers.pendingScore(a)>Providers.pendingScore(b)
            end)
        end
	for _,id in ipairs(ready) do if Providers.hasPending(id) then S.measured('PublicWork.decide',Decide.safeDecide,actor,id,now) end end
    end
    if not discover then return end
    S.nextWake=now+Config.discoveryWakeMs S.dispatchDirty=false
    S.nextTick=now+(S.discoveryActive and Config.discoveryMs or Config.discoveryIdleMs)
    if now>=S.nextReconcile then S.nextReconcile=now+Config.reconcileMs S.measured('PublicWork.reconcile',Reconcile.reconcile) end
    if now>=S.nextStock then S.nextStock=now+Config.stockMs S.measured('PublicWork.stock',Stock.stock,actor,now) end
    local startCursor=S.cursor
    local window=EmberRoutesProbeJava.workerDecisionWindow and EmberRoutesProbeJava.workerDecisionWindow(startCursor,16)
    local count=window and window.count or EmberRoutesProbeJava.workerCount() if count<1 or count>256 then S.discoveryActive=false return end
    S.cursor=(S.cursor+1)%count
    local decisions=0
    for _=1,math.min(16,count) do
        local id=window and window.ids[_] or EmberRoutesProbeJava.workerIdAt((startCursor+_-1)%count)
        local due=S.decideAt[id]
        if not due then due=now+S.decidePhaseMs(id) S.decideAt[id]=due end
        if now>=due then
            local binding,entry=Eligibility.eligible(actor,id)
            if binding then
                S.measured('PublicWork.decide',Decide.safeDecide,actor,id,now,binding,entry)
                decisions=decisions+1
                if decisions>=4 then break end
            end
            -- Carriers far from the player think less often instead of being
            -- dropped: this project has no meta simulation to keep them busy.
            local period=Config.discoveryMs
            if S.careWaking[id] then
                S.careWaking[id]=nil
                period=Config.wakeMs
                S.dispatchDirty=true
                S.nextWake=now+Config.wakeMs
            elseif S.sleeping[id] then
                -- A sleeping NPC rechecks at 1Hz, never on the backoff or
                -- remote ladder: stretching the recheck would break the
                -- wake bound, and the recheck itself is only gates plus a
                -- needs sample, no provider scan.
                period=Config.npcSleepRecheckMs
            else
                local backoff=S.workerBackoff[id] or 0
                if backoff>0 then
                    period=math.max(period,Config.backoffMs[math.min(backoff,3)])
                end
                local handle=binding and binding.handle
                if handle then
                    local radius=Config.workerRemoteRadius
                    local dx=handle:getX()-actor:getX() local dy=handle:getY()-actor:getY()
                    if dx*dx+dy*dy>radius*radius then period=math.max(period,Config.workerRemoteMs) end
                end
            end
            S.decideAt[id]=now+period
        end
    end
    -- Any decision this pass, or live precheck work, keeps the fast period.
    S.discoveryActive=decisions>0 or S.tickOps>0
end

function Service.tick()
    local now=getTimestampMs()
    if now>=S.nextWakePoll then
        S.nextWakePoll=now+Config.wakeMs
        local revision=Wake.revision and Wake.revision()
        if revision~=S.observedWake then S.observedWake=revision S.dispatchDirty=true end
    end
    for _ in pairs(S.pendingReservations) do
        S.dispatchDirty=true
        S.nextWake=math.min(S.nextWake,now+Config.wakeMs)
        break
    end
    local discover=now>=S.nextTick or (S.dispatchDirty and now>=S.nextWake)
    if not discover and now<S.nextPrecheck then return end
    local precheckDue=now>=S.nextPrecheck
    if precheckDue then
        S.nextPrecheck=now+Config.precheckMs
        -- hasWork walks every order of every provider. Re-evaluating it on all
        -- twenty 50 ms passes bought nothing: a provider only gains work through
        -- a signal, and that signal wakes discovery within 100 ms anyway. Decide
        -- it on discovery passes and keep advancing in between.
        if discover then
            S.providerDue=false
            for _,p in ipairs(Providers.all()) do
                if p.advance and p.hasWork and p.hasWork() then S.providerDue=true break end
            end
        end
    end
    if not discover and not S.providerDue and not Providers.hasPrechecks() then return end
    if S.faultWorld==Registry.data() then return end
    if S.faultUntil and now<S.faultUntil then return end
    S.tickOps,S.tickSlices=0,0
    local ok,reason=pcall(advance,now,discover,S.providerDue,precheckDue)
    S.metrics:record(getTimestampMs()-now,S.tickOps,S.tickSlices)
    if ok then
        S.faultCount=0 S.faultUntil=nil
    else
        S.faultCount=S.faultCount+1
        S.faultUntil=now+FAULT_RETRY_MS
        if S.faultCount>=FAULT_LIMIT then S.faultWorld=Registry.data() end
        Log.write('DISPATCH','DISPATCH_BLOCKED '..tostring(reason)..' failures='..S.faultCount
            ..(S.faultWorld and ' state=LOCKED' or ' state=RETRY'))
    end
end

return Service
