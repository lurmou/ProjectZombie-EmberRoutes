-- Lazy registration avoids loading native action adapters in an unavailable runtime.
local Gate = require 'EmberRoutesProbe/Kernel/RuntimeGate'
local P = { category = 'forager', defaultPriority = 3 }
local service
local function use()
    if not Gate.hasFieldOperations() then return end
    service = service or require 'EmberRoutesProbe/Field/ForagerService'
    return service
end
function P.discover(env) local s = use() if s then return s.discover(env) end end
function P.claim(...)
    local s = use() if not s then return 'FORAGER_UNAVAILABLE', 'ROLLED_BACK' end
    local result, rollback = s.claim(...)
    return result or 'FORAGER_UNAVAILABLE', rollback
end
function P.reconcile() if service then return service.reconcile() end end
function P.advance(env) local s = use() if s then return s.advance(env) end end
function P.hasWork() return service and service.hasWork() or false end
-- Any unfinished FIELD_WORK job retains the worker. Not gated on field operations:
-- a saved job still holds its worker while the native adapters are closed.
function P.retained(id) return require('EmberRoutesProbe/Field/FieldWork').retained(id) end
return P
