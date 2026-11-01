-- Logical coordination only. Tokens fence callbacks; no world assets are changed.
local Claims={}
local methods={} methods.__index=methods

local SYSTEM_QUARANTINE_OWNER = {
    kind = "SYSTEM_QUARANTINE",
    ownerId = "SYSTEM_QUARANTINE",
    taskId = "SYSTEM_QUARANTINE",
    resources = {}
}

function Claims.new()
    return setmetatable({
        owners = {},
        capacity = {},
        tokensByTaskId = {},
        revision = 0
    }, methods)
end

function methods:quarantine(key)
    local previous = self.owners[key]
    local origTaskId = nil
    local origToken = nil
    local origGen = nil
    if previous and previous.kind ~= "SYSTEM_QUARANTINE" then
        origTaskId = previous.taskId
        origToken = previous
        origGen = previous.generation
        if previous.resources then
            local keep = {}
            for _, r in ipairs(previous.resources) do
                if r ~= key then
                    keep[#keep + 1] = r
                end
            end
            previous.resources = keep
        end
        if string.sub(key, 1, 5) == "item:" and previous.capacityKey then
            local itemId = tonumber(string.sub(key, 6))
            local capKey = previous.capacityKey
            local bucket = self.capacity[capKey]
            local claim = bucket and bucket.entries[previous.taskId]
            if claim and claim.items and claim.items[itemId] then
                local amt = claim.items[itemId]
                claim.items[itemId] = nil
                claim.count = claim.count - 1
                claim.amount = math.max(0, claim.amount - amt)
                if claim.count == 0 then
                    bucket.entries[previous.taskId] = nil
                    previous.capacityKey = nil
                    bucket.count = bucket.count - 1
                end
                bucket.quarantine = bucket.quarantine or {}
                bucket.quarantine[key] = {
                    amount = amt,
                    capacityKey = capKey,
                    itemId = itemId,
                    originalTaskId = origTaskId,
                    originalToken = origToken,
                    originalGeneration = origGen
                }
            end
        end
    elseif previous and previous.kind == "SYSTEM_QUARANTINE" then
        origTaskId = previous.originalTaskId
        origToken = previous.originalToken
        origGen = previous.originalGeneration
    end

    self.owners[key] = {
        kind = "SYSTEM_QUARANTINE",
        ownerId = "SYSTEM_QUARANTINE",
        taskId = "SYSTEM_QUARANTINE",
        resource = key,
        originalTaskId = origTaskId,
        originalToken = origToken,
        originalGeneration = origGen
    }
    self.revision = self.revision + 1
    return true
end

function methods:releaseQuarantineCapacity(key)
    for capKey, bucket in pairs(self.capacity) do
        if bucket.quarantine and bucket.quarantine[key] then
            local qEntry = bucket.quarantine[key]
            bucket.total = math.max(0, bucket.total - qEntry.amount)
            bucket.quarantine[key] = nil
            local hasQuarantine = false
            for _ in pairs(bucket.quarantine) do hasQuarantine = true break end
            if not hasQuarantine and bucket.count == 0 then
                self.capacity[capKey] = nil
            end
            return true, qEntry.amount
        end
    end
    return false
end

function methods:unquarantine(key)
    local current = self.owners[key]
    if current and current.kind == "SYSTEM_QUARANTINE" then
        self.owners[key] = nil
        self.revision = self.revision + 1
        if string.sub(key, 1, 5) == "item:" then
            self:releaseQuarantineCapacity(key)
        end
        return true
    end
    return false
end

function methods:acquireNew(taskId, generation, resources)
    if self.tokensByTaskId and self.tokensByTaskId[taskId] then
        return nil, "TASK_ALREADY_HAS_CLAIMS"
    end
    for _, token in pairs(self.owners) do
        if token.taskId == taskId then
            return nil, "TASK_ALREADY_HAS_CLAIMS"
        end
    end
    local seen = {}
    for _, key in ipairs(resources) do
        if seen[key] then return nil, "RESOURCE_DUPLICATED" end
        seen[key] = true
        local owner = self.owners[key]
        if owner then
            if owner.kind == "SYSTEM_QUARANTINE" then
                return nil, "RESOURCE_SYSTEM_QUARANTINED"
            end
            return nil, "ITEM_RESERVED"
        end
    end
    local token = { taskId = taskId, generation = generation, resources = resources }
    for _, key in ipairs(resources) do self.owners[key] = token end
    if self.tokensByTaskId then self.tokensByTaskId[taskId] = token end
    if #resources > 0 then self.revision = self.revision + 1 end
    return token
end

function methods:acquire(taskId,generation,resources)
    local seen,previous={},nil
    for _,key in ipairs(resources) do
        if seen[key] then return nil,"RESOURCE_DUPLICATED" end seen[key]=true
        local owner=self.owners[key]
        if owner then
            if owner.kind == "SYSTEM_QUARANTINE" then return nil, "RESOURCE_SYSTEM_QUARANTINED" end
            if owner.taskId~=taskId then return nil,"ITEM_RESERVED" end
        end
        previous=previous or owner
    end
    if previous then
        for _,key in ipairs(previous.resources) do if not seen[key] then return nil,"RESOURCE_SET_CHANGED" end end
        for _,key in ipairs(resources) do if self.owners[key]~=previous then return nil,"RESOURCE_SET_CHANGED" end end
    end
    local token={taskId=taskId,generation=generation,resources=resources}
    for _,key in ipairs(resources) do self.owners[key]=token end
    if self.tokensByTaskId then self.tokensByTaskId[taskId]=token end
    if not previous and #resources>0 then self.revision=self.revision+1 end
    if previous and previous.capacityKey then
        local bucket=self.capacity[previous.capacityKey]
        local claim=bucket and bucket.entries[taskId]
        if claim and claim.token==previous then
            claim.token=token token.capacityKey=previous.capacityKey
        end
    end
    return token
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
                if owner.originalToken and owner.originalToken == token then
                    isMyQuarantine = true
                elseif owner.originalTaskId and owner.originalGeneration ~= nil
                    and token.taskId == owner.originalTaskId and token.generation == owner.originalGeneration then
                    isMyQuarantine = true
                end
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

-- Validate the whole removal before touching owners, resources or capacity.
-- Supports releasing quarantined resources originally belonging to this token,
-- with deferred capacity release.
function methods:shrink(token, releasedKeys)
    local ok, reason = self:canShrink(token, releasedKeys)
    if not ok then return false, reason end

    local drop, keep = {}, {}
    for _, key in ipairs(releasedKeys) do drop[key] = true end
    for _, key in ipairs(token.resources) do
        if not drop[key] then keep[#keep + 1] = key end
    end

    for _, key in ipairs(releasedKeys) do
        if string.sub(key, 1, 5) == 'item:' then
            self:releaseCapacity(token, tonumber(string.sub(key, 6)))
        end
        local owner = self.owners[key]
        if owner == token then
            self.owners[key] = nil
        elseif owner and owner.kind == "SYSTEM_QUARANTINE" then
            local isMine = (owner.originalToken and owner.originalToken == token) or
                (owner.originalTaskId and owner.originalGeneration ~= nil and token.taskId == owner.originalTaskId and token.generation == owner.originalGeneration)
            if isMine then
                owner.originalTaskId = nil
                owner.originalToken = nil
                owner.originalGeneration = nil
                if string.sub(key, 1, 5) == 'item:' then
                    self:releaseQuarantineCapacity(key)
                end
            end
        end
    end

    token.resources = keep
    if #releasedKeys > 0 then self.revision = self.revision + 1 end
    return true
end
-- Validate both sets before mutation. Retained tools/surface never lose ownership.
function methods:replace(token,resources)
    if not token then return false,"STALE_CLAIM" end
    if token.capacityKey then
        local b=self.capacity[token.capacityKey] local c=b and b.entries[token.taskId]
        if not c or c.token~=token then return false,'STALE_CLAIM' end
    end
    local seen={}
    for _,key in ipairs(token.resources) do if self.owners[key]~=token then return false,"STALE_CLAIM" end end
    for _,key in ipairs(resources) do
        if seen[key] then return false,"RESOURCE_DUPLICATED" end seen[key]=true
        local owner=self.owners[key]
        if owner and owner~=token then
            if owner.kind=="SYSTEM_QUARANTINE" then return false,"RESOURCE_SYSTEM_QUARANTINED" end
            return false,"ITEM_RESERVED"
        end
    end
    local changed=false
    for _,key in ipairs(token.resources) do if not seen[key] then self.owners[key]=nil changed=true end end
    for _,key in ipairs(resources) do if not self.owners[key] then changed=true end self.owners[key]=token end
    if changed then self.revision=self.revision+1 end
    token.resources=resources return true
end
-- Add freshly created original outputs without releasing inputs/tools in between.
function methods:extend(token,resources)
    if not token then return false,"STALE_CLAIM" end
    local seen={}
    for _,key in ipairs(token.resources) do
        if self.owners[key]~=token then return false,"STALE_CLAIM" end seen[key]=true
    end
    local added={}
    for _,key in ipairs(resources) do
        if not seen[key] then
            local owner=self.owners[key]
            if owner and owner~=token then
                if owner.kind=="SYSTEM_QUARANTINE" then return false,"RESOURCE_SYSTEM_QUARANTINED" end
                return false,"ITEM_RESERVED"
            end
            added[#added+1]=key seen[key]=true
        end
    end
    for _,key in ipairs(added) do token.resources[#token.resources+1]=key self.owners[key]=token end
    if #added>0 then self.revision=self.revision+1 end
    return true
end
function methods:reserve(token,key,itemId,amount,free)
    if not token or not self:valid(token,"item:"..itemId) then return false,"STALE_CLAIM" end
    if type(amount)~="number" or amount~=amount or amount<0 or amount==math.huge then
        return false,"CAPACITY_UNAVAILABLE"
    end
    if type(free)~="number" or free~=free or free<0 or free==math.huge then
        return false,"CAPACITY_UNAVAILABLE"
    end
    if token.capacityKey and token.capacityKey~=key then return false,"CAPACITY_TARGET_CHANGED" end
    local bucket=self.capacity[key] or {entries={},total=0,count=0}
    local previous=bucket.entries[token.taskId]
    local oldWeight=previous and previous.items[itemId] or 0
    local proposed=bucket.total-oldWeight+amount
    if proposed>free then return false,"CAPACITY_RESERVED" end
    if not previous then bucket.count=bucket.count+1 end
    local claim=previous or {token=token,items={},amount=0,count=0}
    if claim.items[itemId]==nil then claim.count=claim.count+1 end
    claim.items[itemId]=amount claim.amount=claim.amount-oldWeight+amount claim.token=token
    bucket.entries[token.taskId]=claim bucket.total=proposed self.capacity[key]=bucket token.capacityKey=key
    return true
end
function methods:releaseCapacity(token,itemId)
    local key=token.capacityKey local bucket=key and self.capacity[key]
    local claim=bucket and bucket.entries[token.taskId]
    if claim and claim.token==token then
        local amount
        if itemId then amount=claim.items[itemId] else amount=claim.amount end
        if amount==nil then return end
        if itemId then claim.items[itemId]=nil claim.count=claim.count-1 else claim.count=0 end
        claim.amount=math.max(0,claim.amount-amount) bucket.total=math.max(0,bucket.total-amount)
        if claim.count==0 then
            bucket.entries[token.taskId]=nil token.capacityKey=nil bucket.count=bucket.count-1
            if bucket.count==0 then self.capacity[key]=nil end
        end
    end
end
function methods:release(token)
    if not token then return end
    local changed=false
    for _,key in ipairs(token.resources) do if self.owners[key]==token then self.owners[key]=nil changed=true end end
    if self.tokensByTaskId and token.taskId and self.tokensByTaskId[token.taskId]==token then
        self.tokensByTaskId[token.taskId]=nil
    end
    if changed then self.revision=self.revision+1 end
    self:releaseCapacity(token)
end
-- Loading conservative reservations does not assert that space still exists.
-- The native capacity check is repeated before every effect.
function methods:restore(token,key,itemId,amount)
    if not self:valid(token,"item:"..itemId) or type(key)~="string" or key==""
        or type(amount)~="number" or amount~=amount or amount<0 or amount==math.huge then return false end
    if token.capacityKey and token.capacityKey~=key then return false end
    local bucket=self.capacity[key] or {entries={},total=0,count=0}
    local previous=bucket.entries[token.taskId]
    if not previous then bucket.count=bucket.count+1 end
    local claim=previous or {token=token,items={},amount=0,count=0}
    local before=claim.items[itemId] or 0
    if claim.items[itemId]==nil then claim.count=claim.count+1 end
    claim.items[itemId]=amount claim.amount=claim.amount-before+amount
    bucket.total=bucket.total-before+amount bucket.entries[token.taskId]=claim
    self.capacity[key]=bucket token.capacityKey=key
    return true
end
function methods:available(key,free)
    return math.max(0,free-(self.capacity[key] and self.capacity[key].total or 0))
end
-- A stable batch promise, independent of food IDs that may be replaced by the
-- native recipe. Shares the SAME capacity buckets with hauling reservations.
function methods:restoreWork(token,key,amount)
    if not token or not self:valid(token,'cooking:capacity:'..token.taskId)
        or type(key)~='string' or type(amount)~='number' or amount<=0 or amount~=amount or amount==math.huge
        or token.capacityKey and token.capacityKey~=key then return false end
    local bucket=self.capacity[key] or {entries={},total=0,count=0}
    local claim=bucket.entries[token.taskId]
    if claim and (claim.token~=token or claim.count>0) then return false end
    if not claim then bucket.count=bucket.count+1 end
    claim=claim or {token=token,items={},count=0,amount=0}
    bucket.total=bucket.total-claim.amount+amount claim.amount=amount claim.workAmount=amount
    bucket.entries[token.taskId]=claim self.capacity[key]=bucket token.capacityKey=key
    return true
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
function methods:reserveMany(token,key,weights,free)
    if not token or type(key)~="string" or key=="" or (token.capacityKey and token.capacityKey~=key) or type(free)~="number" or free~=free
        or free<0 or free==math.huge then return false,"CAPACITY_UNAVAILABLE" end
    local bucket=self.capacity[key] local old=bucket and bucket.entries[token.taskId]
    local total,count=0,0
    for itemId,amount in pairs(weights) do
        count=count+1
        if count>30 or not self:valid(token,"item:"..itemId) or type(amount)~="number" or amount~=amount
            or amount<0 or amount==math.huge then return false,"STALE_CLAIM" end
        total=total+amount
    end
    if count==0 or (bucket and bucket.total or 0)-(old and old.amount or 0)+total>free then return false,"CAPACITY_RESERVED" end
    if old then for itemId in pairs(old.items) do if weights[itemId]==nil then return false,"RESOURCE_SET_CHANGED" end end end
    -- All validation precedes mutation; at most 30 already claimed resources.
    for itemId,amount in pairs(weights) do
        local ok,reason=self:restore(token,key,itemId,amount)
        if not ok then error(reason or "BATCH_RESERVATION_INVALID") end
    end
    return true
end
return Claims
