-- Standard Craft Job Record Validator.
-- Validates format=4 CRAFT jobs within the standard Job Envelope.
-- Fully defensive: any corrupted structure returns false without throwing exceptions.
local Validate = require 'EmberRoutesProbe/Validate'
local R = {}

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
    if p.released == true then return {} end
    local okYield, ProductionYield = pcall(require, 'EmberRoutesProbe/ProductionYield')
    if okYield and ProductionYield and ProductionYield.assetFree and ProductionYield.assetFree(p) then
        return {}
    end

    local res = {}
    if p.benchId and p.phase ~= 'CONFIRMED' and p.phase ~= 'RETURNING' and p.phase ~= 'DONE' then
        res[#res+1] = "craft-surface:" .. tostring(p.benchId)
    end
    if type(p.materials) == 'table' then
        for _, m in ipairs(p.materials) do
            if type(m) == 'table' and Validate.itemId(m.id) and not m.consumed then
                res[#res+1] = "item:" .. m.id
            end
        end
    end
    if type(p.tools) == 'table' then
        for _, t in ipairs(p.tools) do
            if type(t) == 'table' and Validate.itemId(t.id) then
                res[#res+1] = "item:" .. t.id
            end
        end
    end
    if type(p.outputs) == 'table' then
        for _, o in ipairs(p.outputs) do
            if type(o) == 'table' and Validate.itemId(o.id) and not o.delivered then
                res[#res+1] = "item:" .. o.id
            end
        end
    end
    if type(p.held) == 'table' then
        for _, h in ipairs(p.held) do
            if type(h) == 'table' and Validate.itemId(h.id) then
                res[#res+1] = "item:" .. h.id
            end
        end
    end
    return res
end

function R.valid(job)
    -- 1. Envelope & Payload basic check
    if type(job) ~= 'table' or job.providerType ~= 'CRAFT' or type(job.payload) ~= 'table' then
        return false
    end
    local p = job.payload
    if p.executor~=nil then
	if p.executor~='PRODUCTION' or p.id~=job.id or p.npcId~=job.npcId
	    or not require('EmberRoutesProbe/CraftRecord').validProduction(job.npcId,p)
	    or p.sequence~=p.generation then return false end
	local a=p.nativeAttempt
	if a~=nil then
	    if type(a)~='table' or a.format~=1 or not Validate.stringId(a.id)
		or not Validate.integer(a.sequence,0) or (a.state~='COMMITTING' and a.state~='APPLIED' and a.state~='UNKNOWN') then return false end
	    if (a.state=='COMMITTING' or a.state=='UNKNOWN') and (p.released or job.state=='DONE' or job.state=='CANCELLED' or job.effects~='UNKNOWN' or job.obligations.business~=true) then return false end
	    if a.state=='APPLIED' and (type(a.observation)~='table' or a.observation.complete~=true or a.observation.attemptId~=a.id) then return false end
	end
    end

    -- 2. Format & scalar types
    if p.format ~= 4 or not Validate.integer(p.sequence, 0) then return false end
    if not Validate.stringId(p.recipeId) or not Validate.integer(p.target, 1) or not Validate.integer(p.produced, 0) then
        return false
    end
    if p.target > 10030 or p.produced > p.target then return false end
    if p.benchId ~= nil and not Validate.stringId(p.benchId) then return false end
    if p.released ~= nil and type(p.released) ~= 'boolean' then return false end

    -- 3. Strict array structural validation (preventing ipairs宕╂簝 on non-array tables)
    if not isDenseArray(p.claims, 256) then return false end
    for _, k in ipairs(p.claims) do
        if type(k) ~= 'string' or #k == 0 or #k > 256 then return false end
    end

    if p.materials ~= nil then
        if not isDenseArray(p.materials, 64) then return false end
        for _, m in ipairs(p.materials) do
            if type(m) ~= 'table' or not Validate.itemId(m.id) then return false end
            if m.consumed ~= nil and type(m.consumed) ~= 'boolean' then return false end
        end
    end

    if p.tools ~= nil then
        if not isDenseArray(p.tools, 32) then return false end
        for _, t in ipairs(p.tools) do
            if type(t) ~= 'table' or not Validate.itemId(t.id) then return false end
        end
    end

    if p.outputs ~= nil then
        if not isDenseArray(p.outputs, 128) then return false end
        for _, o in ipairs(p.outputs) do
            if type(o) ~= 'table' or not Validate.itemId(o.id) then return false end
            if o.delivered ~= nil and type(o.delivered) ~= 'boolean' then return false end
        end
    end

    if p.held ~= nil then
        if not isDenseArray(p.held, 256) then return false end
        for _, h in ipairs(p.held) do
            if type(h) ~= 'table' or not Validate.itemId(h.id) then return false end
        end
    end

    -- 4. Terminal state invariants
    if job.state == 'DONE' or job.state == 'CANCELLED' then
        if #p.claims > 0 or p.released ~= true then return false end
    end

    -- 5. activeClaims consistency check
    local expected = R.activeClaims(p)
    if #p.claims ~= #expected then return false end
    local seen = {}
    for _, k in ipairs(p.claims) do seen[k] = true end
    for _, k in ipairs(expected) do
        if not seen[k] then return false end
    end

    return true
end

function R.transition(old,new)
    if old.payload.executor=='PRODUCTION' then
	if new.payload.executor~='PRODUCTION' then return false end
	local a,b=old.payload.nativeAttempt,new.payload.nativeAttempt
	if a and (a.state=='COMMITTING' or a.state=='UNKNOWN') then
	    if not b or a.id~=b.id then return false end
	end
    end
    return true
end
return R
