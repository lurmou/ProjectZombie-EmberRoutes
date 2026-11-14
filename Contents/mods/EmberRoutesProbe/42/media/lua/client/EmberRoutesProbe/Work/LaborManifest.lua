-- Built-in labor wiring: which module each registry loads, in which order.
-- Wiring only; behavior stays in the named modules. Loaders are thunks with
-- literal requires, so reading this file loads no domain module and the
-- static architecture check still resolves every path.
-- tests/lua/labor-wiring-order-test.lua pins both orders below.
local M={}

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
