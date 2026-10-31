-- Standard Craft Job Record Validator.
-- Validates format=4 CRAFT jobs within the standard Job Envelope.
local Validate = require 'EmberRoutesProbe/Validate'
local R = {}

function R.activeClaims(p)
    if not p or type(p) ~= 'table' then return {} end
    if p.released == true or require('EmberRoutesProbe/ProductionYield').assetFree(p) then
        return {}
    end
    local res = {}
    if p.benchId and p.phase ~= 'CONFIRMED' and p.phase ~= 'RETURNING' and p.phase ~= 'DONE' then
        res[#res+1] = "craft-surface:" .. p.benchId
    end
    for _, m in ipairs(p.materials or {}) do
        if not m.consumed then res[#res+1] = "item:" .. m.id end
    end
    for _, t in ipairs(p.tools or {}) do
        res[#res+1] = "item:" .. t.id
    end
    for _, o in ipairs(p.outputs or {}) do
        if not o.delivered then res[#res+1] = "item:" .. o.id end
    end
    for _, h in ipairs(p.held or {}) do
        res[#res+1] = "item:" .. h.id
    end
    return res
end

function R.valid(job)
    if type(job) ~= 'table' or job.providerType ~= 'CRAFT' or type(job.payload) ~= 'table' then
        return false
    end
    local p = job.payload
    if p.format ~= 4 or not Validate.integer(p.sequence, 0) or type(p.claims) ~= 'table' then
        return false
    end
    if not Validate.stringId(p.recipeId) or not Validate.integer(p.target, 1) or not Validate.integer(p.produced, 0) then
        return false
    end
    if p.benchId ~= nil and not Validate.stringId(p.benchId) then
        return false
    end
    if p.released ~= nil and type(p.released) ~= 'boolean' then
        return false
    end

    -- 终态严格无 claims
    if job.state == 'DONE' or job.state == 'CANCELLED' then
        if #p.claims > 0 or p.released ~= true then
            return false
        end
    end

    -- activeClaims 一致性检查
    local expected = R.activeClaims(p)
    if #p.claims ~= #expected then
        return false
    end
    local seen = {}
    for _, k in ipairs(p.claims) do seen[k] = true end
    for _, k in ipairs(expected) do
        if not seen[k] then return false end
    end

    return true
end

return R
