-- Shared dispatch state for PublicWork (split of PublicWork.lua).
-- One table holds every mutable value the old single closure kept as
-- locals, so the split modules below can share it without changing
-- behaviour. `Service` is the public table the split modules fill in;
-- PublicWork.lua returns it. No function here runs at require time
-- except building the table: all requires below were already loaded
-- by PublicWork.lua first, so load order is unchanged.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local OrderStore=require 'EmberRoutesProbe/Work/OrderStore'
local Providers=require 'EmberRoutesProbe/Work/PublicWorkProviders'
local Directory=require 'EmberRoutesProbe/Kernel/TaskDirectory'
local IdleDiscovery=require 'EmberRoutesProbe/Work/IdleDiscovery'
local Metrics=require 'EmberRoutesProbe/Kernel/DispatchMetrics'
local Signals=require 'EmberRoutesProbe/Work/LaborSignals'
local Wake=require 'EmberRoutesProbe/Runtime/PlanningWake'
local Config=require 'EmberRoutesProbe/Kernel/TickConfig'
local Perf=require 'EmberRoutesProbe/Kernel/RuntimeMetrics'

local S={}
S.idle=IdleDiscovery.new()
S.catalogEpoch,S.retryWake,S.idleStudyTargets={},{},{}
S.world,S.data,S.directory,S.cursor,S.nextTick,S.orderCursor=nil,nil,nil,0,0,0
-- Per-worker decision failures. Declared here because load() resets it.
S.workerFaults={}
S.nextPrecheck,S.nextWake,S.observedWake,S.dispatchDirty=0,0,nil,true
-- The wake counter costs a bridge call per read; polling it at the same cadence
-- as the dirty-driven wake path loses nothing, since that path waits 100 ms anyway.
S.nextWakePoll=0
-- Previous pass produced work or ran live prechecks. Drives the adaptive
-- discovery period; a quiet settlement does not need 500 ms scanning.
S.discoveryActive=false
-- Provider advance eligibility, decided on discovery passes and held between them.
S.providerDue=false
-- Responsibility sync and policy checks keep their own cadence instead of
-- riding every discovery frame.
S.nextReconcile,S.nextStock=0,0
-- Per-worker decision phase. A stable id hash spreads decision due times across
-- the discovery window, so one frame no longer runs several full provider
-- scans back to back. That concentration, not the per-scan cost, is what
-- produced the multi-hundred-millisecond peaks.
S.decideAt,S.decidePhase={},{}
S.Business,S.Members=nil,nil
S.workerBackoff={}
-- hauling state encapsulated in HaulingProvider
S.stockWatches,S.ruleCursor={},0
S.retryAt={}
S.metrics=Metrics.new()
S.readyWorkers={}
S.tickOps,S.tickSlices=0,0
-- A single failed pass isolates this world for a short cooldown and then
-- retries; only repeated consecutive failures lock dispatch for good. Locking
-- on the first exception turned one transient fault into a permanent outage.
S.faultWorld,S.faultUntil=nil,nil
S.faultCount=0
S.leisureStops,S.careWaking={},{}
S.pendingReservations={}
-- NPC sleep (P0 pilot, cross-game Factorio §1.3): sleeping[npcId] records
-- a quiet NPC's recheck time, entry stamp and discovery watch. A sleeping
-- NPC skips only the provider discovery pass; the gates above decide and
-- advanceReservations still run every pass. wakeSignal captures the
-- dispatch-dirty flag at advance() entry (advance clears it before the
-- decision loop), so a labor signal since the last pass wakes sleepers.
S.sleeping={}
S.wakeSignal=false
-- Enabled-rule projection with a stable id order; rebuilt only when the rule
-- set changes (saveRule bumps the revision) or the world root is replaced.
S.rulesCache={world=nil,revision=-1,list={}}
S.rulesRevision=0
S.Service={}

function S.decidePhaseMs(id)
    local phase=S.decidePhase[id]
    if phase then return phase end
    local acc=0
    for i=1,#id do acc=(acc*31+string.byte(id,i))%100003 end
    phase=acc%Config.discoveryMs
    S.decidePhase[id]=phase
    return phase
end

function S.business()
    S.Business=S.Business or require 'EmberRoutesProbe/Work/BusinessJobs'
    return S.Business
end

function S.load()
    local root=Registry.data()
    if root~=S.world then
        for _,release in pairs(S.stockWatches) do release() end S.stockWatches={} S.ruleCursor=0
        S.idle=IdleDiscovery.new() S.catalogEpoch,S.retryWake,S.idleStudyTargets={},{},{}
        S.data=OrderStore.load(root)
        S.world=root S.directory=Directory.new()
        Providers.resetWorld()
        S.retryAt={} S.leisureStops={} S.careWaking={} S.pendingReservations={} S.sleeping={} S.faultWorld=nil S.faultUntil=nil S.faultCount=0
        S.metrics=Metrics.new() S.readyWorkers={}
        S.cursor,S.nextTick,S.orderCursor=0,0,0
        S.nextPrecheck,S.nextWake,S.observedWake,S.dispatchDirty=0,0,nil,true
        S.nextWakePoll=0 S.discoveryActive=false S.providerDue=false S.workerFaults={}
        S.nextReconcile,S.nextStock=0,0
        S.decideAt,S.decidePhase={},{} S.workerBackoff={} S.Members=nil
    end
    return S.data
end

function S.requestFor(id)
    for _,r in ipairs(S.load().requests) do if r.requestId==id then return r end end
end
function S.sameRequest(o,scope,recipeId,quantity,surfaceId)
    return o.settlementId==scope and o.recipeId==recipeId and o.quantity==quantity and o.surfaceId==surfaceId
end

function S.signal(o,reason)
    if reason~=o.reason then o.reason=reason o.revision=o.revision+1 Signals.changed() end
end
function S.signalRule(rule,reason)
    if rule.reason~=reason then rule.reason=reason Signals.changed() end
end

function S.cool(o,npcId,e,reason,now)
    local count=0 local oldest,deadline
    for id,r in pairs(S.retryAt) do
        count=count+1 if not deadline or r.untilTime<deadline then oldest,deadline=id,r.untilTime end
    end
    if count>=512 then S.retryAt[oldest]=nil end
    S.retryAt[o.id..':'..npcId]={untilTime=now+8000+(o.sequence or 0)%8*997,watch=e.watch,reason=reason}
end
function S.retryReady(o,npcId,now)
    local r=S.retryAt[o.id..':'..npcId]
    if r and r.untilTime>now then S.retryWake[npcId]=math.min(S.retryWake[npcId] or math.huge,r.untilTime) end
    return not r or now>=r.untilTime or Wake.changed(r.watch)
end

-- Stage attribution exists only while a RuntimeMetrics session is active.
-- Outside a session every wrapper is a direct call: no clock, no allocation.
function S.measured(name,fn,...)
    if not Perf.active() then return fn(...) end
    local started=Perf.now()
    local a,b,c,d=fn(...)
    Perf.measureSpan(name,started)
    return a,b,c,d
end

return S
