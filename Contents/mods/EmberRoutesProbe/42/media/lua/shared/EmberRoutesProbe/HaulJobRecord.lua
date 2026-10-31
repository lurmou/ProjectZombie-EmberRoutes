-- Standard Haul Job Record Validator.
-- Validates format=3 HAUL jobs within the standard Job Envelope.
local Validate = require 'EmberRoutesProbe/Validate'
local R = {}

function R.activeClaims(p)
    if not p or type(p) ~= 'table' then return {} end
    local res = {}
    if p.format == 3 and type(p.manifest) == 'table' then
        for _, l in ipairs(p.manifest) do
            if l.custodyState ~= 'DELIVERED' and l.custodyState ~= 'WITHDRAWN' then
                res[#res+1] = "item:" .. l.itemId
            end
        end
    end
    return res
end

function R.valid(job)
    if type(job) ~= 'table' or job.providerType ~= 'HAUL' or type(job.payload) ~= 'table' then
        return false
    end
    local p = job.payload
    if p.format ~= 3 or not Validate.integer(p.sequence, 0) or type(p.claims) ~= 'table' then
        return false
    end
    if not Validate.stringId(p.source) or not Validate.stringId(p.destination) or type(p.manifest) ~= 'table' then
        return false
    end
    if p.reservation ~= nil and type(p.reservation) ~= 'table' then
        return false
    end

    -- 终态严格无 claims 与容量预约
    if job.state == 'DONE' or job.state == 'CANCELLED' then
        if #p.claims > 0 or p.reservation ~= nil then
            return false
        end
    end

    -- activeClaims 一致性检查 (非终态)
    if job.state ~= 'DONE' and job.state ~= 'CANCELLED' then
        local expected = R.activeClaims(p)
        if #p.claims ~= #expected then
            return false
        end
        local seen = {}
        for _, k in ipairs(p.claims) do seen[k] = true end
        for _, k in ipairs(expected) do
            if not seen[k] then return false end
        end
    end

    return true
end

return R
