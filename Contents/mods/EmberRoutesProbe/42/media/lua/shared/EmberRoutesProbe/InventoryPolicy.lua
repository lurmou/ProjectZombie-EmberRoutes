-- Business planners choose routes. This module never changes physical assets.
local Policy = { tags = {}, order = {} }
function Policy.registerTag(id, definition)
    assert(type(id) == "string" and id:match("^[%w_]+$") and not Policy.tags[id], "TAG_ID_INVALID_OR_DUPLICATED")
    assert(type(definition) == "table" and type(definition.read) == "boolean" and type(definition.write) == "boolean",
        "TAG_CAPABILITIES_REQUIRED")
    Policy.tags[id] = { read=definition.read, write=definition.write }
    Policy.order[#Policy.order+1] = id
end
function Policy.access(tag, intent)
    local definition = Policy.tags[tag]
    if not definition then return false end
    if intent == "take" then return definition.read end
    if intent == "put" then return definition.write end
    return false
end
for _, id in ipairs({ "inbox", "food", "weapons", "tools", "medical", "scrap", "outbox" }) do
    Policy.registerTag(id, { read=true, write=true })
end
Policy.registerTag("private", { read=false, write=false })
function Policy.planExplicit(container, eligible)
    local items, seen = {}, {}
    local contents = container:getItems()
    if contents:size() > 2000 then return nil, "SOURCE_SCAN_LIMIT" end
    for i = 0, contents:size()-1 do
        local item = contents:get(i)
        if eligible(item) then
            if seen[item:getID()] then return nil, "ITEM_ID_DUPLICATED" end
            seen[item:getID()] = true
            items[#items+1] = item:getID()
            if #items > 30 then return nil, "TASK_LIMIT_30" end
        end
    end
    if #items == 0 then return nil, "NO_ELIGIBLE_ITEMS" end
    return items
end
return Policy
