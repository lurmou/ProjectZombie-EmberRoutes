-- Central registry for Job Policy Definitions.
-- Each work category (cleaning, cooking, etc.) registers its schema, default values,
-- UI fields, and custom validators here.
local Registry = {
    defs = {},
    order = {}
}

---@class JobPolicyField
---@field key string Identifier within the policy table
---@field editor string Editor widget type ('toggle', 'slider', 'zone_dropdown', etc.)
---@field label string Translation key for label
---@field tooltip string? Translation key for tooltip
---@field min number? (for slider/stepper)
---@field max number? (for slider/stepper)
---@field step number? (for slider/stepper)
---@field unit string? (for slider/stepper, e.g. "sq", "days")
---@field options table[]? (for enum/dropdown)

---@class JobPolicyDefinition
---@field category string Category identifier (e.g. 'cleaning', 'cooking')
---@field titleKey string Translation key for display title
---@field descKey string? Translation key for category description
---@field order number? Sort order in navigation list
---@field getDefaults fun():table Returns default key-value pairs
---@field getFields fun(settlementId:string?):JobPolicyField[] Returns field definitions
---@field validate fun(draft:table):boolean, string? Custom validation hook

---@param def JobPolicyDefinition
function Registry.register(def)
    if type(def) ~= 'table' or type(def.category) ~= 'string' or #def.category < 1 then
        return false, 'INVALID_POLICY_DEF'
    end
    if not Registry.defs[def.category] then
        Registry.order[#Registry.order + 1] = def.category
    end
    Registry.defs[def.category] = def
    table.sort(Registry.order, function(a, b)
        local orderA = Registry.defs[a].order or 100
        local orderB = Registry.defs[b].order or 100
        return orderA < orderB
    end)
    return true
end

---@param category string
---@return JobPolicyDefinition?
function Registry.get(category)
    return Registry.defs[category]
end

---@return string[] List of registered category names in order
function Registry.categories()
    local list = {}
    for i, cat in ipairs(Registry.order) do list[i] = cat end
    return list
end

---@return JobPolicyDefinition[]
function Registry.all()
    local list = {}
    for _, cat in ipairs(Registry.order) do
        list[#list + 1] = Registry.defs[cat]
    end
    return list
end

return Registry
