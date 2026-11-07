-- Lazy registration avoids loading native action adapters in an unavailable runtime.
local Gate = require 'EmberRoutesProbe/Kernel/RuntimeGate'
local P = { category = 'cleaning', defaultPriority = 2 }
local service
local function use()
    if not Gate.hasFieldOperations() then return end
    service = service or require 'EmberRoutesProbe/Field/CleaningService'
    return service
end
function P.discover(env) local s = use() if s then return s.discover(env) end end
function P.claim(...) local s = use() return s and s.claim(...) or 'CLEANING_UNAVAILABLE' end
function P.reconcile() if service then return service.reconcile() end end
function P.advance(env) local s = use() if s then return s.advance(env) end end
function P.hasWork() return service and service.hasWork() or false end
function P.observeDemand(actor,now,eligible,priorities)
    return require('EmberRoutesProbe/Field/FieldDemand').advance(actor,now,eligible,priorities)
end
return P
