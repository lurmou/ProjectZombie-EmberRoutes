package.path="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local Filter = require "EmberRoutesProbe/StorageFilter"
local Editor = require "EmberRoutesProbe/FilterEditor"

local count = 0
local function check(val, msg)
    count = count + 1
    assert(val, msg)
end

local config = Filter.new()
local descriptions = {
    { fullType = "Base.Apple", node = "food.perishable" },
    { fullType = "Base.Pistol", node = "weapons.guns" },
    { fullType = "Base.Nails", node = "materials" }
}

local model = Editor.new(config, descriptions)

-- 1. By default when collapsed is empty, all rows are shown (backward compatibility)
local fullRows = Editor.rows(model)
local foundApple = false
for _, r in ipairs(fullRows) do
    if r.kind == "type" and r.id == "Base.Apple" then foundApple = true end
end
check(foundApple, "full uncollapsed model shows all child items")

-- 2. Collapse "food" category
Editor.toggleCollapse(model, "food")
check(Editor.isCollapsed(model, "food") == true, "food group is now collapsed")

local collapsedRows = Editor.rows(model)
local foundAppleAfter = false
local foundFoodChild = false
for _, r in ipairs(collapsedRows) do
    if r.kind == "type" and r.id == "Base.Apple" then foundAppleAfter = true end
    if r.kind == "group" and r.id == "food.perishable" then foundFoodChild = true end
end
check(not foundAppleAfter, "apple item is hidden when food is collapsed")
check(not foundFoodChild, "food.perishable subcategory is hidden when food is collapsed")

-- 3. Expand "food" category
Editor.toggleCollapse(model, "food")
check(Editor.isCollapsed(model, "food") == false, "food group is now expanded")

local reexpandedRows = Editor.rows(model)
local foundAppleReopened = false
local foundFoodChildReopened = false
for _, r in ipairs(reexpandedRows) do
    if r.kind == "type" and r.id == "Base.Apple" then foundAppleReopened = true end
    if r.kind == "group" and r.id == "food.perishable" then foundFoodChildReopened = true end
end
check(foundAppleReopened, "apple item reappears when food is expanded")
check(foundFoodChildReopened, "food.perishable subcategory reappears when food is expanded")

-- 4. Collapse all roots with children (Simulate clean UI initial view)
for _, id in ipairs(Filter.order) do
    local node = Filter.nodes[id]
    if node and not node.parent and node.hasChildren then
        model.collapsed[id] = true
    end
end

local cleanRows = Editor.rows(model)
local rootCount = 0
for _, r in ipairs(cleanRows) do
    if r.kind == "group" and r.depth == 0 then
        rootCount = rootCount + 1
        if r.hasChildren then
            check(r.collapsed == true, "root with children has collapsed=true flag for UI [+] rendering")
        end
    end
end
check(rootCount >= 8, "clean view exposes only top-level macro domains")
check(#cleanRows < 20, "collapsed view produces ultra-compact list under 20 rows")

print("PASS " .. count .. " collapsible tree and editor rows assertions succeeded.")
