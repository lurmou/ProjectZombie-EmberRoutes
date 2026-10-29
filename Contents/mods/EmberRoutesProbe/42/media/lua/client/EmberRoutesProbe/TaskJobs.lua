-- One world-local store handle. Providers must not cache independent indexes.
local Store=require 'EmberRoutesProbe/JobStore'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local M={}
local world,ledger,service
function M.current()
    local root=Registry.data()
    if world~=root or ledger~=root.taskJobs then
        local opened,reason=Store.open(root)
        if not opened then error(reason) end
        world,ledger,service=root,root.taskJobs,opened
    end
    return service
end
return M
