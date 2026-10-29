-- Macro eligibility only. Never grants a body, consumes an asset or changes identity.
local P={}
local purposes={WORK=true,LEISURE=true,STUDY=true,SELF_CARE=true,RECOVERY=true,RETURN=true}
local function inside(entry,o)
    if not o or type(o.x)~='number' or type(o.y)~='number' then return false end
    for _,a in ipairs(entry.areas or {}) do
        if o.x>=a.x and o.y>=a.y and o.x<a.x+a.w and o.y<a.y+a.h then return true end
    end
    return false
end
function P.evaluate(row,entry,purpose,observation,expected)
    local result={allowed=false,reason='NO_MEMBERSHIP',revision=row and row.revision,
        settlementId=row and row.settlementId,context=row and row.context,entryRevision=entry and entry.revision}
    local function reject(reason) result.reason=reason return result end
    if not purposes[purpose] then return reject('INVALID_PURPOSE') end
    if expected~=nil and (not row or row.revision~=expected) then return reject('STALE_MEMBERSHIP') end
    if purpose=='SELF_CARE' or purpose=='RECOVERY' then
        result.allowed=true result.reason=nil
        result.sharedResources=row~=nil and not row.retired and entry~=nil and entry.factionId==row.factionId
            and (row.context=='SETTLEMENT' or row.context=='WAIT') and inside(entry,observation) or false
        return result
    end
    if not row or not row.settlementId then return result end
    if row.retired then return reject('NPC_RETIRED') end
    if purpose=='RETURN' then
        if row.context~='RETURN' and row.context~='SETTLEMENT' then return reject('CONTEXT_'..row.context) end
    elseif row.context~='SETTLEMENT' then return reject('CONTEXT_'..row.context) end
    if row.pendingCommand then return reject('COMMAND_PENDING') end
    if not entry or entry.id~=row.settlementId then return reject('TARGET_LOST') end
    if entry.factionId~=row.factionId then return reject('ACCESS_DENIED') end
    if observation and observation.scopeId and observation.scopeId~=row.settlementId then return reject('SCOPE_MISMATCH') end
    if purpose~='RETURN' and not inside(entry,observation) then return reject('OUTSIDE_SETTLEMENT') end
    result.allowed=true result.reason=nil return result
end
P.inside=inside
return P
