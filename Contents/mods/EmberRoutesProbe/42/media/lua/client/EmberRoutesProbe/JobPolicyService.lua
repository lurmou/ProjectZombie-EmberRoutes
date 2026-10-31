-- Settlement Job Policy Service.
-- Manages settlement-level operational policies for each work category.
-- Guarantees isolated drafts, immutable read DTOs, revision tracking,
-- and signals dirty state to dispatch layers upon commit.
local Ledger = require 'EmberRoutesProbe/SettlementLedger'
local Registry = require 'EmberRoutesProbe/JobPolicyRegistry'
local Signals = require 'EmberRoutesProbe/LaborSignals'

local Service = {}
local world, opened

local function getLedger()
    if not Ledger or type(Ledger.data) ~= 'function' then
        Ledger = require 'EmberRoutesProbe/SettlementLedger'
    end
    return Ledger
end

---Deep clone utility to guarantee complete draft isolation.
local function clone(val)
    if type(val) ~= 'table' then return val end
    local res = {}
    for k, v in pairs(val) do
        res[k] = clone(v)
    end
    return res
end

---Access the root jobPolicies store under settlement ModData.
local function data()
    local ledger = getLedger()
    local root = ledger.data()
    if root ~= world or root.jobPolicies ~= opened then
        local saved = root.jobPolicies
        if saved == nil then saved = { format = 1, revision = 0, byScope = {} } end
        if type(saved) ~= 'table' or saved.format ~= 1 then return nil, 'POLICY_FORMAT_UNSUPPORTED' end
        if type(saved.byScope) ~= 'table' or type(saved.revision) ~= 'number'
            or saved.revision < 0 or saved.revision ~= math.floor(saved.revision) or saved.revision == math.huge then
            return nil, 'POLICY_DATA_INVALID'
        end
        for scope, categories in pairs(saved.byScope) do
            if type(scope) ~= 'string' or type(categories) ~= 'table' then return nil, 'POLICY_DATA_INVALID' end
            for category, record in pairs(categories) do
                if type(category) ~= 'string' or type(record) ~= 'table' then return nil, 'POLICY_DATA_INVALID' end
            end
        end
        world, opened = root, saved
        root.jobPolicies = saved
    end
    return opened
end

---Get effective policy for a settlement and category.
---Fills in defaults from the JobPolicyRegistry if fields are unset.
---@param settlementId string
---@param category string
---@return table
function Service.get(settlementId, category)
    if not settlementId or not category then return {} end
    local def = Registry.get(category)
    local defaults = def and def.getDefaults and def.getDefaults() or {}
    local store, why = data()
    if not store then error(why) end -- Never execute defaults in place of unsupported saved policy.
    local scopeMap = store.byScope[settlementId]
    local existing = scopeMap and scopeMap[category]

    local effective = clone(defaults)
    if type(existing) == 'table' then
        for k, v in pairs(existing) do
            effective[k] = clone(v)
        end
    end
    return effective
end

---Get a fresh, fully isolated draft for UI editing.
---@param settlementId string
---@param category string
---@return table
function Service.getDraft(settlementId, category)
    local store, why = data()
    if not store then return nil, why end
    return clone(Service.get(settlementId, category))
end

---Commit an edited draft back to the settlement's policy store.
---Validates via the category's definition and strips unrecognized fields.
---@param actor any
---@param settlementId string
---@param category string
---@param draft table
---@return boolean, string?
function Service.save(actor, settlementId, category, draft)
    if not settlementId or type(settlementId) ~= 'string' then
        return false, 'INVALID_SETTLEMENT'
    end
    if not category or type(category) ~= 'string' then
        return false, 'INVALID_CATEGORY'
    end
    if type(draft) ~= 'table' then
        return false, 'INVALID_DRAFT'
    end

    -- Authorization check via Ledger
    local ledger = getLedger()
    local entry, reason = ledger.view(actor, settlementId)
    if not entry then return false, reason or 'UNAUTHORIZED' end
    local store, storeError = data()
    if not store then return false, storeError end

    local def = Registry.get(category)
    if not def then
        return false, 'UNKNOWN_CATEGORY'
    end

    -- Category-specific validation
    if def.validate then
        local ok, why = def.validate(draft)
        if not ok then
            return false, why or 'VALIDATION_FAILED'
        end
    end

    -- Sanitize: only accept declared fields
    local defaults = def.getDefaults and def.getDefaults() or {}
    local fields = def.getFields and def.getFields(settlementId) or {}
    local allowedKeys = {}
    for k in pairs(defaults) do allowedKeys[k] = true end
    for _, f in ipairs(fields) do allowedKeys[f.key] = true end

    local cleanRecord = {}
    for k, v in pairs(draft) do
        if allowedKeys[k] then
            -- Guarantee no Java objects or non-serializables
            local t = type(v)
            if t == 'boolean' or t == 'number' or t == 'string' then
                cleanRecord[k] = v
            elseif t == 'table' then
                cleanRecord[k] = clone(v)
            end
        end
    end

    -- Persist
    store.byScope[settlementId] = store.byScope[settlementId] or {}
    store.byScope[settlementId][category] = cleanRecord
    store.revision = (store.revision or 0) + 1

    -- Notify dispatch layer that policies changed
    Signals.changed()

    return true
end

return Service
