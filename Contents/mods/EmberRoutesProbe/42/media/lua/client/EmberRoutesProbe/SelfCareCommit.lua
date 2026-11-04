-- SELF_CARE intent mapping only; business evidence belongs to callers.
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Store=require 'EmberRoutesProbe/LaborStore'
local M={}
function M.update(id,revision,patch)
    local available,diagnosis=require('EmberRoutesProbe/LaborKernelAvailability').validate()
    if not available then return false,'KERNEL_UNAVAILABLE',diagnosis end
    local live=Jobs.current():get(id)
    if not live or live.providerType~='SELF_CARE' then return false,'INVALID_REQUEST' end
    if live.revision~=revision then return false,'STALE_REVISION' end
    local payload=patch.payload or live.payload
    local before,after,add,remove={},{},{},{}
    local token=Store.getToken(id)
    -- After finishPersonal the recurring identity has no token. Rebuild its
    -- existing (empty) claim fact before requesting transactional additions.
    local changed=false local declared={}
    for _,key in ipairs(live.payload.claims) do declared[key]=true end
    for _,key in ipairs(payload.claims) do if not declared[key] then changed=true end declared[key]=nil end
    for _ in pairs(declared) do changed=true break end
    if not token and changed then
        local why
        token,why=Store.claimPersonal(live)
        if not token then return false,'CLAIM_FAILURE',why end
    end
    for _,key in ipairs(token and token.resources or live.payload.claims) do before[key]=true end
    for _,key in ipairs(payload.claims) do
        after[key]=true if not before[key] then add[#add+1]=key end
    end
    for key in pairs(before) do if not after[key] then remove[#remove+1]=key end end
    return Store.mutateJob(id,revision,payload,{state=patch.state,effects=patch.effects,
        obligations=patch.obligations,addKeys=add,removeKeys=remove})
end
return M
