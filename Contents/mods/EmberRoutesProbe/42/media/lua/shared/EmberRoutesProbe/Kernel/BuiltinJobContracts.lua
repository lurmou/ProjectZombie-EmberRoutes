-- Built-in domain composition. Lazy Record loads avoid initialization cycles.
local C=require 'EmberRoutesProbe/Kernel/JobContracts'
local M={scopeBlockedReason='CRAFT_SCOPE_RECONCILE_REQUIRED'}
local installed=false
local function record(name) return require('EmberRoutesProbe/'..name) end
function M.install()
    if installed then return end
    local function add(kind,contract) assert(C.register(kind,contract)) end
    add('COOKING',{
	validate=function(j) return record('Cooking/CookingRecord').valid(j) end,
	transition=function(a,b) return record('Cooking/CookingRecord').transition(a,b),'COOKING_TRANSITION_INVALID' end,
	transferValid=function(a,b) return record('Cooking/CookingRecord').transferValid(a,b) end,
	transferReason='COOKING_HANDOFF_CHANGED',tokenBucket='cooking',capacityMutable=true,
	-- validate/transferValid return booleans only; the codes below are the
	-- only codes this contract's callbacks emit.
	errorCodes={
	    COOKING_TRANSITION_INVALID='cooking transition rejected by CookingRecord',
	    COOKING_HANDOFF_CHANGED='cooking handoff changed the job, transfer rejected',
	},
    })
    -- validate returns a boolean only: no codes to declare.
    add('FIELD_WORK',{validate=function(j) return record('Field/FieldRecord').valid(j) end,tokenBucket='field',capacityMutable=true,errorCodes={}})
    add('ACTIVITY',{validate=function(j) return record('Activity/ActivityRecord').valid(j) end,tokenBucket='activity',errorCodes={}})
    -- JobStore historically validates only the SELF_CARE envelope; its domain
    -- adapter validates SelfCareRecord at execution/recovery. Keep that contract.
    -- No callbacks, no codes.
    add('SELF_CARE',{persistentPersonal=true,tokenBucket='personal',errorCodes={}})
    add('CRAFT',{
	validate=function(j)
	    if j.payload.format==4 then return record('Crafting/CraftJobRecord').valid(j) end
	    -- Admission only for return-only retirement; no execution contract for retired formats.
	    return j.payload.format==1 or j.payload.format==2 or j.payload.format==3
	end,
	transition=function(a,b)
	    return a.payload.format~=4 or record('Crafting/CraftJobRecord').transition(a,b),'CRAFT_TRANSITION_INVALID'
	end,
	blocksScope=function(j)
	    local a=j.payload.executor=='PRODUCTION' and j.payload.nativeAttempt
	    return a and a.state~='APPLIED'
	end,
	-- CRAFT_SCOPE_RECONCILE_REQUIRED is the code JobStore surfaces when this
	-- contract's blocksScope holds a scope; the value itself stays on this
	-- module (M.scopeBlockedReason) because JobStore reads it there.
	errorCodes={
	    CRAFT_TRANSITION_INVALID='craft transition rejected by CraftJobRecord',
	    CRAFT_SCOPE_RECONCILE_REQUIRED='craft scope blocked until reconcile',
	    CLAIM_IDENTITY_COLLISION='identity collision pauses the job (job.reason)',
	},
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
	errorCodes={
	    HAUL_TRANSITION_INVALID='haul transition rejected by HaulJobRecord',
	    CLAIM_IDENTITY_COLLISION='identity collision pauses the job (job.reason)',
	},
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
