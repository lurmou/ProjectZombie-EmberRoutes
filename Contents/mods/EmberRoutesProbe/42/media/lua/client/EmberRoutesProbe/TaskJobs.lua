-- One world-local store handle. Providers must not cache independent indexes.
local Store=require 'EmberRoutesProbe/JobStore'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local M={}
local world,ledger,service
local listeners={}
local releaseStore
local function observing()
    for _ in pairs(listeners) do return true end
    return false
end
local function forward(scopeId,jobId,revision,providerType)
    for callback in pairs(listeners) do
        local ok=pcall(callback,scopeId,jobId,revision,providerType)
        if not ok then listeners[callback]=nil end
    end
end
local function bindObservers()
    if releaseStore then releaseStore() releaseStore=nil end
    if service and observing() then releaseStore=service:watch(forward) end
end
function M.current()
    local root=Registry.data()
    if world~=root or ledger~=root.taskJobs then
        local opened,reason=Store.open(root)
        if not opened then error(reason) end
        world,ledger,service=root,root.taskJobs,opened
        bindObservers()
    end
    return service
end
-- Subscribing never opens/migrates a ledger from a presentation path. The
-- authoritative current() binds the observer when a supported store exists.
function M.watch(callback)
    assert(type(callback)=='function','JOB_OBSERVER_REQUIRED')
    listeners[callback]=true
    if service and not releaseStore then bindObservers() end
    return function()
        listeners[callback]=nil
        if not observing() and releaseStore then releaseStore() releaseStore=nil end
    end
end
return M
