-- Built-in recovery composition, in the existing reconstruction order.
local M={}
local installed=false
function M.install()
    if installed then return end
    require('EmberRoutesProbe/BuiltinJobContracts').install()
    local R=require 'EmberRoutesProbe/LaborRecovery'
    R.register('SELF_CARE',require('EmberRoutesProbe/SelfCareJobRecovery').restore)
    R.register('COOKING',require('EmberRoutesProbe/CookingJobRecovery').restore)
    R.register('ACTIVITY',require('EmberRoutesProbe/ActivityJobRecovery').restore)
    R.register('FIELD_WORK',require('EmberRoutesProbe/FieldJobRecovery').restore)
    R.register('CRAFT',require('EmberRoutesProbe/CraftJobRecovery').restore)
    R.register('HAUL',require('EmberRoutesProbe/Hauling/HaulJobRecovery').restore)
    installed=true
end
return M
