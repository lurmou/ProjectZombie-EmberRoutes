-- Separate admission: a missing kernel blocks commits, never whole-mod boot.
local M={available=false,diagnosis='KERNEL_NOT_VALIDATED'}
function M.validate()
    local bridge=EmberRoutesProbeJava
    for _,entry in ipairs({'laborMutate','laborCreate','laborCancel'}) do
        if not bridge or not bridge[entry] then
            M.available=false M.diagnosis='MISSING_JAVA_ENTRY:'..entry
            return false,M.diagnosis
        end
    end
    M.available=true M.diagnosis='AVAILABLE'
    return true,M.diagnosis
end
return M
