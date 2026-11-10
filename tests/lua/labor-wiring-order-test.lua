-- Built-in labor wiring snapshot: what each registry holds after the real
-- registration code runs, in registration order. Registration order is the
-- stable categories() enumeration only: fan-out follows each provider's
-- explicit defaultPriority field (cleaning 2, the 3s, toolReturn 4), and
-- pendingScore takes the highest score, so neither depends on the order
-- below. Recovery order is the cold-load restore sequence.
-- Domain dependencies are load-only stubs; nothing here dispatches work.
-- Usage: lua tests/lua/labor-wiring-order-test.lua [snapshot-out.txt]
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;"..package.path
local function stub(name,t) package.loaded['EmberRoutesProbe/'..name]=t or {} end
for _,n in ipairs({'Warehouse/ContainerRegistry','Settlement/SettlementLedger','Settlement/SettlementGeometry',
    'Runtime/Driver','Runtime/TaskRuntime','Work/Work','Settlement/Companion','Crafting/Production',
    'Crafting/ProductionRecipe','Crafting/CraftSurfaces','Work/LaborSignals','Work/WorkSelector',
    'Kernel/TaskDirectory','Work/OrderStore','Work/OrderQuery','Kernel/Log','Kernel/Boot','Runtime/TaskJobs',
    'Kernel/JobStore','Runtime/PlanningWake','Kernel/TickConfig','Kernel/RuntimeMetrics',
    'Kernel/RuntimeGate','Crafting/ProductionYield','Crafting/CraftStations',
    'Cooking/CookingOrders','Logistics/DeliveryService','Logistics/LogisticsService','Work/LaborStore',
    'Field/ToolReturnService','Crafting/CraftProbe','Crafting/CraftingService'}) do stub(n) end
for _,n in ipairs({'Work/PrecheckQueue','Work/IdleDiscovery','Kernel/DispatchMetrics'}) do
    stub(n,{new=function() return {} end})
end
-- Recovery producers are stubs that name themselves, so the snapshot shows
-- which module each kind restores with and the order restore runs them in.
local restored={}
local recoveryModules={'SelfCare/SelfCareJobRecovery','Cooking/CookingJobRecovery','Activity/ActivityJobRecovery',
    'Field/FieldJobRecovery','Crafting/CraftJobRecovery','Hauling/HaulJobRecovery'}
local recoveryName={}
for _,n in ipairs(recoveryModules) do
    local restore=function() restored[#restored+1]=n end
    recoveryName[restore]=n
    stub(n,{restore=restore})
end

local out={}
local function emit(s) out[#out+1]=s end
local function keys(t,want)
    local list={}
    for k,v in pairs(t) do if want==nil or type(v)==want then list[#list+1]=tostring(k) end end
    table.sort(list)
    return table.concat(list,',')
end

local Contracts=require 'EmberRoutesProbe/Kernel/JobContracts'
local contractOrder={}
local rawContract=Contracts.register
Contracts.register=function(kind,contract) contractOrder[#contractOrder+1]=kind return rawContract(kind,contract) end
local Recovery=require 'EmberRoutesProbe/Work/LaborRecovery'
local recoveryOrder={}
local rawRecovery=Recovery.register
Recovery.register=function(kind,restore)
    recoveryOrder[#recoveryOrder+1]=kind..' '..tostring(recoveryName[restore])
    return rawRecovery(kind,restore)
end
local Monitors=require 'EmberRoutesProbe/Runtime/TaskMonitorProviders'
local monitorOrder={}
local rawMonitor=Monitors.register
Monitors.register=function(def) monitorOrder[#monitorOrder+1]=def.providerType..' '..keys(def,'function') return rawMonitor(def) end

local Providers=require 'EmberRoutesProbe/Work/PublicWorkProviders'
require 'EmberRoutesProbe/Work/PublicWork'
for i,c in ipairs(Providers.categories()) do
    local p=Providers.get(c)
    emit('category '..i..' '..c..' defaultPriority='..tostring(p.defaultPriority)..' hooks='..keys(p,'function'))
end
require('EmberRoutesProbe/Work/BuiltinLaborRecovery').install()
for i,k in ipairs(contractOrder) do emit('contract '..i..' '..k..' fields='..keys(Contracts.get(k))) end
for i,r in ipairs(recoveryOrder) do emit('recovery '..i..' '..r) end
Recovery.restore({current={taskJobs={byId={}}}})
for i,n in ipairs(restored) do emit('restore '..i..' '..n) end
require 'EmberRoutesProbe/Warehouse/OrderMonitorService'
for i,m in ipairs(monitorOrder) do emit('monitor '..i..' '..m) end

-- Manifest declarations agree with what the modules register.
local Manifest=require 'EmberRoutesProbe/Work/LaborManifest'
local kinds={}
for _,e in ipairs(Manifest.jobKinds) do
    kinds[e.kind]=true
    assert(Contracts.get(e.kind) and Contracts.get(e.kind).restoreClaims,'manifest kind lacks contract or recovery: '..e.kind)
    if e.monitor then assert(e.monitor().providerType==e.kind,'monitor providerType differs from its kind: '..e.kind) end
end
for _,e in ipairs(Manifest.categories) do
    assert(e.provider().category==e.category,'provider category differs from manifest: '..e.category)
    assert(e.providerType==nil or kinds[e.providerType],'category providerType is not a manifest kind: '..e.category)
end

if arg and arg[1] then
    local f=assert(io.open(arg[1],'w')) f:write(table.concat(out,'\n'),'\n') f:close()
end
-- P4 contract changes (hooks moved out of the PublicWork kernel; order unchanged):
-- field shells gained 'retained' (was the kernel's direct FieldWork check);
-- cooking gained 'command' and 'retireUnclaimed', crafting 'orderCommanded' and
-- 'orderRetired' (were Service.command and Service.retireSettled).
local expected={
    'category 1 crafting defaultPriority=3 hooks=bumpGeneration,calculateSkillScore,cancel,capacityBlocked,claim,cleanupOrder,discover,evaluations,hasPrechecks,hasWork,holdSelection,idle,orderCommanded,orderRetired,pending,pendingScore,precheck,reconcile,reset,retained,scanStatus,step,waiting',
    'category 2 hauling defaultPriority=3 hooks=advance,blocksDecision,claim,discover,hasWork,reconcile,reset,retained',
    'category 3 cooking defaultPriority=3 hooks=advance,claim,command,discover,hasWork,idle,reconcile,retained,retire,retireUnclaimed',
    'category 4 cleaning defaultPriority=2 hooks=advance,claim,discover,hasWork,observeDemand,reconcile,retained',
    'category 5 farming defaultPriority=3 hooks=advance,claim,discover,hasWork,reconcile,retained',
    'category 6 lumberjack defaultPriority=3 hooks=advance,claim,discover,hasWork,reconcile,retained',
    'category 7 forager defaultPriority=3 hooks=advance,claim,discover,hasWork,reconcile,retained',
    'category 8 toolReturn defaultPriority=4 hooks=advance,beforeClaim,claim,discover,hasWork,reconcile,retained',
    'contract 1 COOKING fields=capacityMutable,errorCodes,restoreClaims,tokenBucket,transferReason,transferValid,transition,validate',
    'contract 2 FIELD_WORK fields=capacityMutable,errorCodes,restoreClaims,tokenBucket,validate',
    'contract 3 ACTIVITY fields=errorCodes,restoreClaims,tokenBucket,validate',
    'contract 4 SELF_CARE fields=errorCodes,persistentPersonal,restoreClaims,tokenBucket',
    'contract 5 CRAFT fields=blocksScope,errorCodes,identityCollision,restoreClaims,transition,validate',
    'contract 6 HAUL fields=capacityMutable,errorCodes,identityCollision,restoreClaims,transition,validate',
    'recovery 1 SELF_CARE SelfCare/SelfCareJobRecovery',
    'recovery 2 COOKING Cooking/CookingJobRecovery',
    'recovery 3 ACTIVITY Activity/ActivityJobRecovery',
    'recovery 4 FIELD_WORK Field/FieldJobRecovery',
    'recovery 5 CRAFT Crafting/CraftJobRecovery',
    'recovery 6 HAUL Hauling/HaulJobRecovery',
    'restore 1 SelfCare/SelfCareJobRecovery',
    'restore 2 Cooking/CookingJobRecovery',
    'restore 3 Activity/ActivityJobRecovery',
    'restore 4 Field/FieldJobRecovery',
    'restore 5 Crafting/CraftJobRecovery',
    'restore 6 Hauling/HaulJobRecovery',
    'monitor 1 COOKING command,project',
    'monitor 2 FIELD_WORK project',
}
for i=1,math.max(#out,#expected) do
    assert(out[i]==expected[i],'wiring drift at line '..i..': got '..tostring(out[i])..' expected '..tostring(expected[i]))
end
-- P1 registry: every built-in provider carries retained, and fan-out follows
-- the explicit defaultPriority field, not registration order.
local fanout={}
for _,p in ipairs(Providers.all()) do fanout[#fanout+1]=p.category..':'..tostring(p.defaultPriority) end
assert(table.concat(fanout,',')=='cleaning:2,cooking:3,crafting:3,farming:3,forager:3,hauling:3,lumberjack:3,toolReturn:4',
    'fan-out order must follow explicit defaultPriority, got '..table.concat(fanout,','))
for _,c in ipairs(Providers.categories()) do
    assert(type(Providers.get(c).retained)=='function','registered provider lacks retained: '..c)
    assert(type(Providers.get(c).defaultPriority)=='number','registered provider lacks defaultPriority: '..c)
end
print('PASS '..#out..' built-in wiring entries in recorded order')
