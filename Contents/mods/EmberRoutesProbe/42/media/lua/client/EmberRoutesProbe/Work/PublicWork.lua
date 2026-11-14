-- One ordinary-work selector/claim coordinator. Providers discover/evaluate;
-- TaskRuntime alone grants bodies and LaborStore alone grants physical assets.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Ledger=require 'EmberRoutesProbe/Settlement/SettlementLedger'
local Geometry=require 'EmberRoutesProbe/Settlement/SettlementGeometry'
local Clock = require 'EmberRoutesProbe/Kernel/Clock'
-- Posting filter for decide, loaded here so decide never loads it mid-tick.
-- MembershipPosting only loads SettlementZones and ContainerRegistry, so
-- this adds no load cycle with PublicWork.
local PostingFilter=require 'EmberRoutesProbe/Settlement/MembershipPosting'
local Driver=require 'EmberRoutesProbe/Runtime/Driver'
local Runtime=require 'EmberRoutesProbe/Runtime/TaskRuntime'
local Work=require 'EmberRoutesProbe/Work/Work'
local Companion=require 'EmberRoutesProbe/Settlement/Companion'
local Production=require 'EmberRoutesProbe/Crafting/Production'
local Recipe=require 'EmberRoutesProbe/Crafting/ProductionRecipe'
local Surfaces=require 'EmberRoutesProbe/Crafting/CraftSurfaces'
local Signals=require 'EmberRoutesProbe/Work/LaborSignals'
local Selector=require 'EmberRoutesProbe/Work/WorkSelector'
local NeedsObserver=require 'EmberRoutesProbe/SelfCare/NeedsObserver'
local NeedsPolicy=require 'EmberRoutesProbe/SelfCare/NeedsPolicy'
local MedicalCare=require 'EmberRoutesProbe/SelfCare/MedicalCare'
local Directory=require 'EmberRoutesProbe/Kernel/TaskDirectory'
local Providers=require 'EmberRoutesProbe/Work/PublicWorkProviders'
-- Persisted order document and its schema checks, kept apart from the scheduler
-- so domain code can read orders without depending on dispatch internals.
local OrderStore=require 'EmberRoutesProbe/Work/OrderStore'
-- Read-only order projection; the command side below forwards to it.
local OrderQuery=require 'EmberRoutesProbe/Work/OrderQuery'
local Log=require 'EmberRoutesProbe/Kernel/Log'
local Probe=require 'EmberRoutesProbe/Kernel/Boot'
local TaskJobs=require 'EmberRoutesProbe/Runtime/TaskJobs'
local JobStore=require 'EmberRoutesProbe/Kernel/JobStore'
local Metrics=require 'EmberRoutesProbe/Kernel/DispatchMetrics'
local Wake=require 'EmberRoutesProbe/Runtime/PlanningWake'
local Config=require 'EmberRoutesProbe/Kernel/TickConfig'
local Constants=require 'EmberRoutesProbe/Kernel/Constants'
local Perf=require 'EmberRoutesProbe/Kernel/RuntimeMetrics'
local Gate=require 'EmberRoutesProbe/Kernel/RuntimeGate'
-- Load order only: these provider trees have loaded here since before the
-- manifest; moving them would reorder module load side effects (unverified).
require 'EmberRoutesProbe/Hauling/HaulingProvider'
require 'EmberRoutesProbe/Crafting/CraftingProvider'
local IdleDiscovery=require 'EmberRoutesProbe/Work/IdleDiscovery'
local CraftYield=require 'EmberRoutesProbe/Crafting/ProductionYield'

-- Split of PublicWork.lua (1065 lines): the dispatch engine now lives in
-- PublicWorkState (shared state + load), PublicWorkOrders (order/rule
-- API), PublicWorkEligibility, PublicWorkReservations, PublicWorkDecide,
-- PublicWorkStock, PublicWorkReconcile and PublicWorkTick. This file
-- keeps the module assembly, the provider registration loop and the
-- Probe wiring; no behaviour changed.
local S=require 'EmberRoutesProbe/Work/PublicWorkState'
local Service=S.Service
local Reservations=require 'EmberRoutesProbe/Work/PublicWorkReservations'
require 'EmberRoutesProbe/Work/PublicWorkOrders'
require 'EmberRoutesProbe/Work/PublicWorkEligibility'
require 'EmberRoutesProbe/Work/PublicWorkDecide'
require 'EmberRoutesProbe/Work/PublicWorkStock'
require 'EmberRoutesProbe/Work/PublicWorkReconcile'
require 'EmberRoutesProbe/Work/PublicWorkTick'

if Signals.watch then
    Signals.watch(function(id)
        S.dispatchDirty=true
        if id then S.idle:clear(id) S.workerBackoff[id]=nil else S.workerBackoff={} end
    end)
end

function Service.prepareRecovery() S.load() end

function Service.available()
    if S.faultWorld==Registry.data() then return false,'DISPATCH_BLOCKED' end
    -- During the cooldown the dispatcher is isolated too, so public mutation
    -- stays blocked even though the world has not been locked permanently.
    if S.faultUntil and Clock.nowMs()<S.faultUntil then return false,'DISPATCH_BLOCKED' end
    if not Probe.ready or not Probe.runtimeReady then return false,Probe.failureCode or 'ADMISSION_CLOSED' end
    return true
end
function Service.rule(scope,product)
    local r=S.load().rules[scope..':'..product] if not r then return nil end
    local copy={} for k,v in pairs(r) do copy[k]=v end return copy
end

local function assertRegister(def)
    local ok,err=Providers.register(def)
    if not ok then error('PROVIDER_REGISTRATION_FAILED:'..tostring(err)..':'..tostring(type(def)=='table' and def.category or '?')) end
end
require('EmberRoutesProbe/Kernel/BuiltinJobContracts').install()
for _,e in ipairs(require('EmberRoutesProbe/Kernel/DomainRegistry').providerEntries()) do
    local provider=require(e.module)
    assert(provider.category==e.category,'PROVIDER_CATEGORY_MISMATCH:'..e.category)
    assertRegister(provider)
end

function Service.metrics() return S.metrics:snapshot() end
-- Diagnostic/test seam: recheck time of a sleeping NPC, nil when awake.
function Service.sleeping(npcId) local s=S.sleeping[npcId] return s and s.untilTime or nil end

function Service.hasReservation(npcId)
    return S.pendingReservations[npcId]~=nil
end
function Service.cancelReservation(npcId)
    Reservations.cancelReservation(npcId,'MANUAL_CANCEL')
end

-- NOTE (F-01): `Probe.publicDispatch` is a "PublicWork has loaded" flag, not a
-- runtime feature toggle. Setting it here (module-load side effect, alongside
-- installing the real dispatch entry `Probe.tickPublicWork`) is the only place
-- in production code that writes it, and nothing ever writes it back to
-- false/nil -- so in production it is always true once this file loads. The
-- `false`/nil branches guarded by it only exist for tests (stub Boot tables).
-- There is no private fallback: the private dispatch paths were deleted
-- (F-05), so if this line never runs the flag stays nil and public dispatch
-- simply never engages -- preparePublic/publicOffer fail closed and
-- LogisticsService.start reports DRIVER_UNAVAILABLE.
Probe.publicDispatch=true Probe.tickPublicWork=Service.tick
Probe.hasPendingWork=Service.hasReservation
Probe.cancelReservation=Service.cancelReservation
return Service
