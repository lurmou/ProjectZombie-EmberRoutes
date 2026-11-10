-- Built-in labor wiring: which module each registry loads, in which order.
-- Wiring only; behavior stays in the named modules. Loaders are thunks with
-- literal requires, so reading this file loads no domain module and the
-- static architecture check still resolves every path.
-- tests/lua/labor-wiring-order-test.lua pins both orders below.
local M={}

-- Public work categories, in registration order. That order is only the stable
-- enumeration behind PublicWorkProviders.categories() (UI lists, saved
-- priority sets). Scheduling fan-out follows each provider's explicit
-- defaultPriority field, and the pendingScore tie takes the highest score;
-- neither depends on the order below.
-- providerType names the TaskJobs kind the claim creates (jobKinds below);
-- nil means the category creates no TaskJob of its own.
M.categories={
    {category='crafting',providerType='CRAFT',provider=function() return require 'EmberRoutesProbe/Crafting/CraftingProvider' end},
    {category='hauling',providerType='HAUL',provider=function() return require 'EmberRoutesProbe/Hauling/HaulingProvider' end},
    {category='cooking',providerType='COOKING',provider=function() return require 'EmberRoutesProbe/Cooking/CookingProvider' end},
    {category='cleaning',providerType='FIELD_WORK',provider=function() return require 'EmberRoutesProbe/Field/CleaningProvider' end},
    {category='farming',providerType='FIELD_WORK',provider=function() return require 'EmberRoutesProbe/Field/FarmingProvider' end},
    {category='lumberjack',providerType='FIELD_WORK',provider=function() return require 'EmberRoutesProbe/Field/LumberjackProvider' end},
    {category='forager',providerType='FIELD_WORK',provider=function() return require 'EmberRoutesProbe/Field/ForagerProvider' end},
    -- Tool return runs as a LaborStore work record, not a TaskJob.
    {category='toolReturn',provider=function() return require 'EmberRoutesProbe/Field/ToolReturnProvider' end},
}

-- TaskJobs kinds, in LaborRecovery.restore order (the cold-load sequence).
-- Each kind's JobContracts entry stays in Kernel/BuiltinJobContracts: it is
-- shared code loaded by JobStore and must keep its lazy record loads.
M.jobKinds={
    {kind='SELF_CARE',recovery=function() return require 'EmberRoutesProbe/SelfCare/SelfCareJobRecovery' end},
    {kind='COOKING',recovery=function() return require 'EmberRoutesProbe/Cooking/CookingJobRecovery' end,
        monitor=function() return require 'EmberRoutesProbe/Cooking/CookingMonitor' end},
    {kind='ACTIVITY',recovery=function() return require 'EmberRoutesProbe/Activity/ActivityJobRecovery' end},
    {kind='FIELD_WORK',recovery=function() return require 'EmberRoutesProbe/Field/FieldJobRecovery' end,
        monitor=function() return require 'EmberRoutesProbe/Field/FieldWorkMonitor' end},
    {kind='CRAFT',recovery=function() return require 'EmberRoutesProbe/Crafting/CraftJobRecovery' end},
    {kind='HAUL',recovery=function() return require 'EmberRoutesProbe/Hauling/HaulJobRecovery' end},
}
return M
