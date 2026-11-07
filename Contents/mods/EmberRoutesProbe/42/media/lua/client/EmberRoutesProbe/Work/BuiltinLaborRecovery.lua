-- Built-in recovery composition, in the existing reconstruction order.
local M={}
local installed=false
function M.install()
    if installed then return end
    require('EmberRoutesProbe/Kernel/BuiltinJobContracts').install()
    local R=require 'EmberRoutesProbe/Work/LaborRecovery'
    R.register('SELF_CARE',require('EmberRoutesProbe/SelfCare/SelfCareJobRecovery').restore)
    R.register('COOKING',require('EmberRoutesProbe/Cooking/CookingJobRecovery').restore)
    R.register('ACTIVITY',require('EmberRoutesProbe/Activity/ActivityJobRecovery').restore)
    R.register('FIELD_WORK',require('EmberRoutesProbe/Field/FieldJobRecovery').restore)
    R.register('CRAFT',require('EmberRoutesProbe/Crafting/CraftJobRecovery').restore)
    R.register('HAUL',require('EmberRoutesProbe/Hauling/HaulJobRecovery').restore)
    installed=true
end
return M
