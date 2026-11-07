-- Shared cold recovery sequence. Domain callbacks own record interpretation.
local C=require 'EmberRoutesProbe/Kernel/JobContracts'
local M={}
local order={}
function M.register(kind,restore)
    assert(type(restore)=='function' and not (C.get(kind) or {}).restoreClaims,'RECOVERY_CONTRACT_DUPLICATED')
    local contract=assert(C.get(kind),'JOB_CONTRACT_REQUIRED')
    contract.restoreClaims=restore order[#order+1]=kind
end
function M.restore(context)
    if not context.current.taskJobs or not context.current.taskJobs.byId then return end
    for _,kind in ipairs(order) do C.get(kind).restoreClaims(context) end
end
return M
