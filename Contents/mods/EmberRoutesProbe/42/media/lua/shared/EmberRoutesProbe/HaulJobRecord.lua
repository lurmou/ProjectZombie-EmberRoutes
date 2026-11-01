-- Standard Haul Job Record Validator.
-- Validates format=3 HAUL jobs within the standard Job Envelope.
-- Fully defensive: any corrupted structure returns false without throwing exceptions.
local Validate = require 'EmberRoutesProbe/Validate'
local R = {}

local validCustodyStates = {
    UNCOLLECTED = true,
    CARRIED = true,
    RECONCILE = true,
    DELIVERED = true,
    WITHDRAWN = true
}

local function isDenseArray(t, maxLen)
    if type(t) ~= 'table' then return false end
    local count = 0
    for k, _ in pairs(t) do
        if type(k) ~= 'number' or k ~= math.floor(k) or k < 1 then return false end
        count = count + 1
    end
    if count > (maxLen or 256) then return false end
    for i = 1, count do
        if t[i] == nil then return false end
    end
    return true
end

function R.activeClaims(p)
    if type(p) ~= 'table' then return {} end
    local res = {}
    if p.format == 3 and type(p.manifest) == 'table' then
        for _, l in ipairs(p.manifest) do
            if type(l) == 'table' and Validate.itemId(l.itemId) then
                if l.custodyState ~= 'DELIVERED' and l.custodyState ~= 'WITHDRAWN' then
                    res[#res+1] = "item:" .. l.itemId
                end
            end
        end
    end
    return res
end

function R.valid(job)
    -- 1. Envelope & Payload basic check
    if type(job) ~= 'table' or job.providerType ~= 'HAUL' or type(job.payload) ~= 'table' then
        return false
    end
    local p = job.payload
    if p.executor~=nil then
	if p.executor~='ENTITY' or p.id~=job.id or p.npcId~=job.npcId
	    or not require('EmberRoutesProbe/HaulManifest').valid(p) or p.sequence~=p.generation then return false end
    end

    -- 2. Format & scalar types
    if p.format ~= 3 or not Validate.integer(p.sequence, 0) then return false end
    if not Validate.stringId(p.source) or not Validate.stringId(p.destination) then
        return false
    end

    -- 3. Strict claims array validation
    if not isDenseArray(p.claims, 256) then return false end
    for _, k in ipairs(p.claims) do
        if type(k) ~= 'string' or #k == 0 or #k > 256 then return false end
    end

    -- 4. Strict manifest array validation
    if not isDenseArray(p.manifest, 64) or #p.manifest < 1 then return false end
    local seenItems = {}
    for _, l in ipairs(p.manifest) do
        if type(l) ~= 'table' or not Validate.itemId(l.itemId) then return false end
        if seenItems[l.itemId] then return false end
        seenItems[l.itemId] = true
        if not validCustodyStates[l.custodyState] then return false end
        if l.sourceId ~= nil and not Validate.stringId(l.sourceId) then return false end
    end

    -- 5. Reservation validation
    if p.reservation ~= nil then
        if type(p.reservation) ~= 'table' then return false end
        local res = p.reservation
        if res.format ~= 1 and res.format ~= 2 then return false end
        if not Validate.stringId(res.key) then return false end
        if res.format == 2 then
            if type(res.items) ~= 'table' then return false end
            for itemId, amt in pairs(res.items) do
                if not Validate.itemId(itemId) or type(amt) ~= 'number' or amt < 0 then return false end
            end
        else
            if not Validate.itemId(res.itemId) or type(res.amount) ~= 'number' or res.amount < 0 then return false end
        end
    end

    -- 6. Terminal state invariants
    if job.state == 'DONE' or job.state == 'CANCELLED' then
        if #p.claims > 0 or p.reservation ~= nil then
            return false
        end
    end

    -- 7. activeClaims consistency check (non-terminal)
    if job.state ~= 'DONE' and job.state ~= 'CANCELLED' then
        local expected = R.activeClaims(p)
        if #p.claims ~= #expected then return false end
        local seen = {}
        for _, k in ipairs(p.claims) do seen[k] = true end
        for _, k in ipairs(expected) do
            if not seen[k] then return false end
        end
    end

    return true
end

function R.transition(old,new)
    if old.payload.executor=='ENTITY' then
	if new.payload.executor~='ENTITY' then return false end
	local a,b=old.payload.activeAttempt,new.payload.activeAttempt
	if a and b and a.attemptId~=b.attemptId then return false end
	if old.payload.controlUncertain and not new.payload.controlUncertain then return false end
    end
    return true
end
return R
