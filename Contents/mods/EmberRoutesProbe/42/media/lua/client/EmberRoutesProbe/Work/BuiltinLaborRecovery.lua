-- Built-in recovery composition, in LaborManifest.jobKinds reconstruction order.
local M={}
local installed=false
function M.install()
    if installed then return end
    require('EmberRoutesProbe/Kernel/BuiltinJobContracts').install()
    local R=require 'EmberRoutesProbe/Work/LaborRecovery'
    for _,e in ipairs(require('EmberRoutesProbe/Work/LaborManifest').jobKinds) do R.register(e.kind,e.recovery().restore) end
    installed=true
end
return M
