-- Headless list filter and query controller.
-- Maintains search query, category tag, and sort order without touching native widgets.
-- Performs in-place array population to achieve zero-GC frame budgets during list updates.
local ListFilter = {}
ListFilter.__index = ListFilter

---@class EmberRoutesListFilter
---@field query string Lowercase search query string
---@field tag string|boolean Active tag/filter identifier
---@field sortKey string|boolean Sort criteria identifier
---@field sortAsc boolean Sort direction
---@field searchFields table Array of field names to match on
---@field filterField string Field name to match tag on
---@field tagMatch function Custom tag matcher
---@field searchMatch function Custom search matcher
---@field sortComparator function Custom sorter

---Creates a new headless list filter controller.
---@param opts table|nil Configuration options
---@return EmberRoutesListFilter
function ListFilter.new(opts)
    opts = opts or {}
    local self = setmetatable({
        query = "",
        tag = opts.initialTag or "all",
        sortKey = opts.initialSort or false,
        sortAsc = opts.sortAsc ~= false,
        searchFields = opts.searchFields or { "name" },
        filterField = opts.filterField or "status",
        tagMatch = opts.tagMatch,
        searchMatch = opts.searchMatch,
        sortComparator = opts.sortComparator,
        dirty = true
    }, ListFilter)
    return self
end

---Sets the search query string. Trims and converts to lower-case for plain substring search.
---@param text string|nil
---@return boolean changed
function ListFilter:setQuery(text)
    local q = text and text:lower():match("^%s*(.-)%s*$") or ""
    if self.query ~= q then
        self.query = q
        self.dirty = true
        return true
    end
    return false
end

---Sets the active category or status tag.
---@param tag string|boolean
---@return boolean changed
function ListFilter:setTag(tag)
    tag = tag or "all"
    if self.tag ~= tag then
        self.tag = tag
        self.dirty = true
        return true
    end
    return false
end

---Sets the active sort criteria and direction.
---@param key string|boolean
---@param asc boolean|nil
---@return boolean changed
function ListFilter:setSort(key, asc)
    if asc == nil then asc = true end
    if self.sortKey ~= key or self.sortAsc ~= asc then
        self.sortKey = key
        self.sortAsc = asc
        self.dirty = true
        return true
    end
    return false
end

---Filters source array into outList in-place, avoiding GC allocation.
---@param source table Array of source items
---@param outList table Array to populate with matching items
---@return table outList The populated array
function ListFilter:apply(source, outList)
    outList = outList or {}
    for i = #outList, 1, -1 do
        outList[i] = nil
    end

    if not source then return outList end

    local q = self.query
    local hasQuery = #q > 0
    local tag = self.tag
    local hasTag = tag and tag ~= "all" and tag ~= ""

    local searchFields = self.searchFields
    local filterField = self.filterField
    local customSearch = self.searchMatch
    local customTag = self.tagMatch

    local count = 0
    for i = 1, #source do
        local item = source[i]
        local match = true

        -- 1. Tag filter
        if hasTag then
            if customTag then
                match = customTag(item, tag) == true
            else
                match = item[filterField] == tag
            end
        end

        -- 2. Query filter
        if match and hasQuery then
            if customSearch then
                match = customSearch(item, q) == true
            else
                local found = false
                for f = 1, #searchFields do
                    local val = item[searchFields[f]]
                    if val and tostring(val):lower():find(q, 1, true) then
                        found = true
                        break
                    end
                end
                match = found
            end
        end

        if match then
            count = count + 1
            outList[count] = item
        end
    end

    -- 3. Sort if specified
    if self.sortComparator and count > 1 then
        local comp = self.sortComparator
        local key = self.sortKey
        local asc = self.sortAsc
        table.sort(outList, function(a, b)
            return comp(a, b, key, asc)
        end)
    end

    self.dirty = false
    return outList
end

return ListFilter
