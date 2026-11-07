-- Retirement-only exception for unsupported CRAFT payloads. Never executes work.
local M={}
function M.legacy(r) return type(r)=='table' and (r.format==1 or r.format==2 or r.format==3) end
function M.retained(r,j)
    return not r.released or r.uncertain or r.controlUncertain or r.phase=='COMMITTING' or j.effects=='UNKNOWN'
end
function M.records(current)
    local result={}
    for id,j in pairs(current.taskJobs and current.taskJobs.byId or {}) do
        if j.providerType=='CRAFT' and M.legacy(j.payload) then result[id]=j.payload end
    end
    return result
end
-- Preserve the old exact-original resource shape solely to discharge/retain custody.
function M.resources(r)
    local result,seen={},{}
    local function add(key) if key and not seen[key] then seen[key]=true result[#result+1]=key end end
    local function item(id) if type(id)=='number' then add('item:'..id) end end
    if r.benchId then add('craft-surface:'..tostring(r.benchId)) end
    if r.format==3 then
        local empty=true
        for _,name in ipairs({'materials','tools','outputs','held'}) do
            if type(r[name])=='table' then for _ in pairs(r[name]) do empty=false break end
            elseif r[name]~=nil then empty=false end
        end
        local y=r.activityYield
        if not r.uncertain and type(y)=='table' and y.kind=='MANUAL' and y.cleared==true
            and r.unitMade~=true and empty and r.activityContinuation~=nil
            and require('EmberRoutesProbe/Crafting/ProductionYield').continuation(r) then return {} end
        for _,name in ipairs({'materials','tools','outputs','held'}) do
            for _,entry in ipairs(type(r[name])=='table' and r[name] or {}) do
                if type(entry)=='table' then item(entry.id) end
            end
        end
    else
        item(r.materialId) item(r.toolId)
        for _,id in ipairs(type(r.outputIds)=='table' and r.outputIds or {}) do item(id) end
    end
    for _,key in ipairs(type(r.claims)=='table' and r.claims or {}) do if type(key)=='string' then add(key) end end
    return result
end
function M.restore(c)
    for id,r in pairs(M.records(c.current)) do
        local j=c.current.taskJobs.byId[id]
        local unknown=r.uncertain or r.controlUncertain or r.phase=='COMMITTING' or j.effects=='UNKNOWN'
        local keys=M.resources(r)
        local token
        if not r.released or unknown then
            if c.hasConflict(keys) then unknown=true r.reason='RESOURCE_COLLISION'
            else
                local claimId=c.ensureEntityClaimId(c.current,r,id)
                token=c.rebuilt:acquire(id,r.generation or 0,keys,{claimId=claimId})
                if not token then unknown=true r.reason='RESOURCE_COLLISION' end
            end
        end
        if unknown then
            r.released=false r.uncertain=true r.state='RECONCILE_REQUIRED'
            j.state,j.effects,j.obligations='RECONCILE_REQUIRED','UNKNOWN',{business=true}
            if token then c.newTokens[id]=token end
        else
            -- Acquire/release through the same Claims authority; never touch originals.
            if token then c.rebuilt:release(token) end
            r.released=true r.state='CANCELLED' r.phase='CANCELLED' r.reason='LEGACY_CRAFT_RETIRED'
            r.reservation=nil r.claims={}
            j.state,j.effects,j.obligations='CANCELLED','KNOWN',{}
        end
        -- This payload can only retain/discharge custody, never select an executor.
        r.executor=nil
        j.revision=j.revision+1
    end
end
return M
