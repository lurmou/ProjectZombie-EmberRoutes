-- Lazy registration avoids loading native action adapters in an unavailable runtime.
local P={category='cooking',defaultPriority=3}
local service
local function use()
    if not EmberRoutesProbeJava or not EmberRoutesProbeJava.carrierActive then return end
    service=service or require 'EmberRoutesProbe/CookingService'
    return service
end
function P.discover(env) local s=use() if s then return s.discover(env) end end
function P.claim(...) local s=use() return s and s.claim(...) or 'COOKING_UNAVAILABLE' end
function P.advance(env) local s=use() if s then return s.advance(env) end end
function P.reconcile() if service then return service.reconcile() end end
function P.hasWork() return service and service.hasWork() or false end
function P.retained(id) local s=use() return s and s.retained(id) or false end
function P.retire(limit) return service and service.retire(limit) or 0 end
function P.idle(id,entry,target)
    if target then
        local Probe=require 'EmberRoutesProbe/Boot'
        if Probe.idleStudy then Probe.idleStudy(id,entry,target) end
    end
end
return P
