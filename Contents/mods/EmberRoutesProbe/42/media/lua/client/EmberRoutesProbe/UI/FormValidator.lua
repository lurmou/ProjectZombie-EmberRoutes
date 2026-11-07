-- Pure declarative form validator.
-- Evaluates a key-value data table against a field schema definition without allocating runtime objects.
local FormValidator = {}

---Validates a data table against a declarative schema.
---@param data table Key-value data to validate
---@param schema table Map of field names to validation rule specifications
---@return boolean ok True if all fields pass validation
---@return string|nil error First error message if validation failed
---@return string|nil field Field key that failed validation
function FormValidator.validate(data, schema)
    if not schema then return true end
    data = data or {}

    for field, rule in pairs(schema) do
        local val = data[field]
        local msg = rule.message or ("INVALID_FIELD: " .. tostring(field))

        -- 1. Required check
        if rule.required then
            if val == nil or val == false or (type(val) == "string" and val:match("^%s*$")) then
                return false, msg, field
            end
        end

        -- If value is present, run type and range constraints
        if val ~= nil and val ~= "" then
            -- 2. Type check
            if rule.type then
                if type(val) ~= rule.type then
                    return false, msg, field
                end
            end

            -- 3. Number constraints
            if type(val) == "number" then
                if rule.integer and math.floor(val) ~= val then
                    return false, msg, field
                end
                if rule.min and val < rule.min then
                    return false, msg, field
                end
                if rule.max and val > rule.max then
                    return false, msg, field
                end
            end

            -- 4. String constraints
            if type(val) == "string" then
                if rule.min and #val < rule.min then
                    return false, msg, field
                end
                if rule.max and #val > rule.max then
                    return false, msg, field
                end
                if rule.pattern and not val:match(rule.pattern) then
                    return false, msg, field
                end
            end

            -- 5. Custom validator function
            if rule.validator and type(rule.validator) == "function" then
                local ok, customMsg = rule.validator(val, data)
                if not ok then
                    return false, customMsg or msg, field
                end
            end
        end
    end

    return true, nil, nil
end

return FormValidator
