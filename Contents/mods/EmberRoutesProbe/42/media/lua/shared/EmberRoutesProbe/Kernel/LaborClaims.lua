-- Claims graph writes have one implementation in Java, including recovery.
-- Lua adapts the call/return protocol and keeps read-only queries
-- (valid, canShrink, available*); it owns no write path.
local Claims={}
local methods={} methods.__index=methods
local function command(self,operation,args)
    local bridge=EmberRoutesProbeJava and EmberRoutesProbeJava.claimsCommand
    assert(bridge,'CLAIMS_JAVA_REQUIRED')
    return bridge(self,operation,args)
end
function Claims.new(nextClaimSeq)
    return setmetatable(command(nil,'NEW',{nextClaimSeq=nextClaimSeq}).result,methods)
end
-- Cache invalidation only; this never releases an owner or a capacity promise.
function methods:forgetToken(taskId)
    command(self,'FORGET_TOKEN',{taskId=taskId})
end
function methods:acquireNew(taskId,generation,resources,envelope)
    local result=command(self,'ACQUIRE_NEW',{taskId=taskId,generation=generation,resources=resources,envelope=envelope})
    if result.ok then return result.result end
    return nil,result.result
end
function methods:acquire(taskId,generation,resources,envelope)
    local result=command(self,'ACQUIRE',{taskId=taskId,generation=generation,resources=resources,envelope=envelope})
    if result.ok then return result.result end
    return nil,result.result
end
function methods:quarantine(key)
    local result=command(self,'QUARANTINE',{key=key})
    return result.ok,result.result
end
function methods:restoreQuarantine(key,record)
    local result=command(self,'RESTORE_QUARANTINE',{key=key,record=record})
    return result.ok,result.result
end
function methods:unquarantine(key,resolution)
    local result=command(self,'UNQUARANTINE',{key=key,resolution=resolution})
    return result.ok,result.result
end
function methods:releaseQuarantineCapacity(key)
    local result=command(self,'RELEASE_QUARANTINE_CAPACITY',{key=key})
    return result.ok,result.result
end
function methods:shrink(token,resources)
    local result=command(self,'SHRINK',{token=token,resources=resources})
    return result.ok,result.result
end
function methods:replace(token,resources)
    local result=command(self,'REPLACE',{token=token,resources=resources})
    return result.ok,result.result
end
function methods:extend(token,resources)
    local result=command(self,'EXTEND',{token=token,resources=resources})
    return result.ok,result.result
end
function methods:reserve(token,key,itemId,amount,free)
    local result=command(self,'RESERVE',{token=token,key=key,itemId=itemId,amount=amount,free=free})
    return result.ok,result.result
end
function methods:reserveMany(token,key,weights,free)
    local result=command(self,'RESERVE_MANY',{token=token,key=key,weights=weights,free=free})
    return result.ok,result.result
end
function methods:restore(token,key,itemId,amount)
    local result=command(self,'RESTORE',{token=token,key=key,itemId=itemId,amount=amount})
    return result.ok
end
function methods:restoreWork(token,key,amount)
    local result=command(self,'RESTORE_WORK',{token=token,key=key,amount=amount})
    return result.ok
end
function methods:release(token)
    local result=command(self,'RELEASE',{token=token})
end
function methods:releaseCapacity(token,itemId)
    local result=command(self,'RELEASE_CAPACITY',{token=token,itemId=itemId})
end
function methods:valid(token,key) return token and self.owners[key]==token end

-- Non-destructive validation for shrink operations.
function methods:canShrink(token, releasedKeys)
    if not token or type(releasedKeys) ~= 'table' then return false, 'STALE_CLAIM' end
    local owned, drop = {}, {}
    for _, key in ipairs(token.resources) do
        if self.owners[key] ~= token then return false, 'STALE_CLAIM' end
        owned[key] = true
    end
    for _, key in ipairs(releasedKeys) do
        if drop[key] then return false, 'RESOURCE_SET_CHANGED' end
        drop[key] = true
        if not owned[key] then
            local owner = self.owners[key]
            local isMyQuarantine = false
            if owner and owner.kind == "SYSTEM_QUARANTINE" then
                -- 1. Exact runtime token object identity:
                if owner.originalToken and owner.originalToken == token then
                    isMyQuarantine = true
                -- 2. Exact non-reusable persistent claim identity:
                elseif owner.originalClaimId ~= nil and token.claimId ~= nil
                    and token.claimId == owner.originalClaimId then
                    isMyQuarantine = true
                end
                -- Note: taskId == owner.originalTaskId alone is strictly rejected!
            end
            if not isMyQuarantine then
                return false, 'RESOURCE_SET_CHANGED'
            end
        end
    end
    local bucket = token.capacityKey and self.capacity[token.capacityKey]
    local claim = bucket and bucket.entries[token.taskId]
    if token.capacityKey and (not claim or claim.token ~= token) then return false, 'STALE_CLAIM' end
    return true
end
function methods:available(key,free)
    return math.max(0,free-(self.capacity[key] and self.capacity[key].total or 0))
end
function methods:availableWork(token,key,free)
    local bucket=self.capacity[key] local claim=bucket and token and bucket.entries[token.taskId]
    local own=claim and claim.token==token and claim.workAmount or 0
    return math.max(0,free-(bucket and bucket.total or 0)+own)
end
function methods:availableFor(token,key,itemId,free)
    local bucket=self.capacity[key] local claim=bucket and token and bucket.entries[token.taskId]
    local own=claim and claim.token==token and claim.items[itemId] or 0
    return self:available(key,free)+own
end
return Claims
