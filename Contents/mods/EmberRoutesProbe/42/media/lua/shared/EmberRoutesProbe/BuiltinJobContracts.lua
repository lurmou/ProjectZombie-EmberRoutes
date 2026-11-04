-- Built-in domain composition. Lazy Record loads avoid initialization cycles.
local C=require 'EmberRoutesProbe/JobContracts'
local M={scopeBlockedReason='CRAFT_SCOPE_RECONCILE_REQUIRED'}
local installed=false
local function record(name) return require('EmberRoutesProbe/'..name) end
function M.install()
    if installed then return end
    local function add(kind,contract) assert(C.register(kind,contract)) end
    add('COOKING',{
	validate=function(j) return record('CookingRecord').valid(j) end,
	transition=function(a,b) return record('CookingRecord').transition(a,b),'COOKING_TRANSITION_INVALID' end,
	transferValid=function(a,b) return record('CookingRecord').transferValid(a,b) end,
	transferReason='COOKING_HANDOFF_CHANGED',tokenBucket='cooking',capacityMutable=true,
    })
    add('FIELD_WORK',{validate=function(j) return record('FieldRecord').valid(j) end,tokenBucket='field',capacityMutable=true})
    add('ACTIVITY',{validate=function(j) return record('ActivityRecord').valid(j) end,tokenBucket='activity'})
    -- JobStore historically validates only the SELF_CARE envelope; its domain
    -- adapter validates SelfCareRecord at execution/recovery. Keep that contract.
    add('SELF_CARE',{persistentPersonal=true,tokenBucket='personal'})
    add('CRAFT',{
	validate=function(j)
	    if j.payload.format==4 then return record('CraftJobRecord').valid(j) end
	    -- Admission only for return-only retirement; no legacy execution contract.
	    return j.payload.format==1 or j.payload.format==2 or j.payload.format==3
	end,
	transition=function(a,b)
	    return a.payload.format~=4 or record('CraftJobRecord').transition(a,b),'CRAFT_TRANSITION_INVALID'
	end,
	blocksScope=function(j)
	    local a=j.payload.executor=='PRODUCTION' and j.payload.nativeAttempt
	    return a and a.state~='APPLIED'
	end,
    })
    add('HAUL',{
	validate=function(j)
	    local p=j.payload
	    if p.format~=3 then return false end
	    return record('Hauling/HaulJobRecord').valid(j)
	end,
	transition=function(a,b)
	    return a.payload.format~=3 or record('Hauling/HaulJobRecord').transition(a,b),'HAUL_TRANSITION_INVALID'
	end,
	capacityMutable=true,
    })
    local function collision(job)
	local p=job.payload
	p.state,p.reason,p.uncertain='PAUSED','CLAIM_IDENTITY_COLLISION',true
    end
    C.get('CRAFT').identityCollision=collision
    C.get('HAUL').identityCollision=collision
    installed=true
end
return M
