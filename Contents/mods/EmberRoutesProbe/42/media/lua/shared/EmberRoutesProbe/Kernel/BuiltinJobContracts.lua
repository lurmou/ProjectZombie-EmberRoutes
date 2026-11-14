-- Built-in domain composition. Lazy Record loads avoid initialization cycles.
local C=require 'EmberRoutesProbe/Kernel/JobContracts'
local Domains=require 'EmberRoutesProbe/Kernel/DomainRegistry'
local M={}
local installed=false
local function record(name) return require('EmberRoutesProbe/'..name) end
-- Metadata is declared alongside each domain contract. Client code resolves
-- these fixed internal module references; shared code never loads client Lua.
function M.install()
    if installed then return end
    local function add(kind,contract,metadata)
        local names={COOKING='Cooking',HAUL='Hauling',CRAFT='Crafting',SELF_CARE='SelfCare',FIELD_WORK='Field'}
        local domain=names[kind]
        if contract and domain then
            local evidence=require('EmberRoutesProbe/'..domain..'/JobObligationContract')
            for code in pairs(evidence.errorCodes) do contract.errorCodes[code]=evidence.errorCodes[code] end
            contract.obligationRecord=evidence.record
            contract.obligationGuard=evidence.references
            contract.validateObligationOperation=evidence.operation
            contract.retireObligation=evidence.retire
        end
        return Domains.register(kind,contract,metadata)
    end
    add('COOKING',{schemaVersion=1,
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
    },{providers={{order=3,category='cooking',module='EmberRoutesProbe/Cooking/CookingProvider'}}})
    -- validate returns a boolean only: no codes to declare.
    add('FIELD_WORK',{schemaVersion=1,validate=function(j) return record('Field/FieldRecord').valid(j) end,tokenBucket='field',capacityMutable=true,errorCodes={}},
        {providers={{order=4,category='cleaning',module='EmberRoutesProbe/Field/CleaningProvider'},
            {order=5,category='farming',module='EmberRoutesProbe/Field/FarmingProvider'},
            {order=6,category='lumberjack',module='EmberRoutesProbe/Field/LumberjackProvider'},
            {order=7,category='forager',module='EmberRoutesProbe/Field/ForagerProvider'}}})
    add('ACTIVITY',{schemaVersion=1,validate=function(j) return record('Activity/ActivityRecord').valid(j) end,tokenBucket='activity',errorCodes={}})
    add('SELF_CARE',{schemaVersion=1,persistentPersonal=true,tokenBucket='personal',
        validate=function(j) return record('SelfCare/SelfCareRecord').valid(j) end,errorCodes={}})
    add('CRAFT',{schemaVersion=1,
	validate=function(j)
	    return j.payload.format==4 and record('Crafting/CraftJobRecord').valid(j)
	end,
	transition=function(a,b)
	    return record('Crafting/CraftJobRecord').transition(a,b),'CRAFT_TRANSITION_INVALID'
	end,
	blocksScope=function(j)
	    local a=j.payload.executor=='PRODUCTION' and j.payload.nativeAttempt
	    return a and a.state~='APPLIED'
	end,
	scopeBlockedReason='CRAFT_SCOPE_RECONCILE_REQUIRED',
	errorCodes={
	    CRAFT_TRANSITION_INVALID='craft transition rejected by CraftJobRecord',
	    CRAFT_SCOPE_RECONCILE_REQUIRED='craft scope blocked until reconcile',
	    CLAIM_IDENTITY_COLLISION='identity collision pauses the job (job.reason)',
	},
    },{providers={{order=1,category='crafting',module='EmberRoutesProbe/Crafting/CraftingProvider'}},
        retirement='EmberRoutesProbe/Crafting/CraftRetirement'})
    add('HAUL',{schemaVersion=1,
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
    },{providers={{order=2,category='hauling',module='EmberRoutesProbe/Hauling/HaulingProvider'}},
        retirement='EmberRoutesProbe/Hauling/HaulRetirement'})
    add('TOOL_RETURN',nil,{providers={{order=8,category='toolReturn',module='EmberRoutesProbe/Field/ToolReturnProvider'}}})
    local function collision(job)
	local p=job.payload
	p.state,p.reason,p.uncertain='PAUSED','CLAIM_IDENTITY_COLLISION',true
    end
    C.get('CRAFT').identityCollision=collision
    C.get('HAUL').identityCollision=collision
    Domains.seal()
    installed=true
end
return M
