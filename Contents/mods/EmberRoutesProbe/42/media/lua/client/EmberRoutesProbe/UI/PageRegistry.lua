-- EmberRoutes UI Pluggable Page Registry
-- Decouples page registration, tab ordering, and lifecycle from SettlementDashboard.
local PageRegistry = {
    pages = {},
    order = {}
}

---@class EmberRoutesPageDefinition
---@field id string
---@field module string
---@field isTab boolean?
---@field titleKey string?
---@field tooltipKey string?
---@field order number?
---@field parentTab string?
---@field footerText (string|fun(page:any):string)?
---@field visible (fun(actor:any, entry:any):boolean)?

---@param def EmberRoutesPageDefinition
function PageRegistry.register(def)
    assert(def.id and def.module, "Page definition requires id and module")
    PageRegistry.pages[def.id] = def
    if def.isTab ~= false then
        local found = false
        for _, id in ipairs(PageRegistry.order) do
            if id == def.id then found = true break end
        end
        if not found then
            table.insert(PageRegistry.order, def.id)
        end
        table.sort(PageRegistry.order, function(a, b)
            local orderA = PageRegistry.pages[a].order or 100
            local orderB = PageRegistry.pages[b].order or 100
            return orderA < orderB
        end)
    end
end

---@param id string
---@return EmberRoutesPageDefinition?
function PageRegistry.get(id)
    return PageRegistry.pages[id]
end

---@param id string
---@return string?
function PageRegistry.getModule(id)
    local def = PageRegistry.pages[id]
    return def and def.module or nil
end

---@param actor any
---@param entry any
---@return string[]
function PageRegistry.getTabIds(actor, entry)
    local tabs = {}
    for _, id in ipairs(PageRegistry.order) do
        local def = PageRegistry.pages[id]
        if def and def.isTab ~= false then
            if not def.visible or def.visible(actor, entry) then
                tabs[#tabs + 1] = id
            end
        end
    end
    return tabs
end

---@param id string
---@param page any
---@return string?
function PageRegistry.getFooter(id, page)
    local def = PageRegistry.pages[id]
    if not def then return nil end
    if type(def.footerText) == "function" then
        return def.footerText(page)
    elseif type(def.footerText) == "string" then
        return def.footerText
    end
    return nil
end

-- Default built-in Page Registrations:
PageRegistry.register({
    id = "warehouse",
    module = "WarehousePage",
    isTab = true,
    titleKey = "tab_warehouse",
    tooltipKey = "tabNavigation",
    order = 10,
    footerText = function() return getText("IGUI_EmberRoutesProbe_Monitor_warehouseFooter") end
})

PageRegistry.register({
    id = "orders",
    module = "OrderMonitorPage",
    isTab = true,
    titleKey = "tab_orders",
    tooltipKey = "tabNavigation",
    order = 20,
    footerText = nil -- Orders page self-updates its own footer
})

PageRegistry.register({
    id = "personnel",
    module = "PersonnelPage",
    isTab = true,
    titleKey = "tab_personnel",
    tooltipKey = "tabNavigation",
    order = 30,
    footerText = function() return getText("IGUI_EmberRoutesProbe_Personnel_priorityLegend") end
})

PageRegistry.register({
    id = "defense",
    module = "DefensePage",
    isTab = true,
    titleKey = "tab_defense",
    tooltipKey = "tabNavigation",
    order = 40,
    footerText = function() return getText("IGUI_EmberRoutesProbe_Defense_alertHint") end
})

PageRegistry.register({
    id = "logistics",
    module = "LogisticsPage",
    isTab = false, -- Sub-view / child of orders
    parentTab = "orders",
    order = 50,
    footerText = function() return getText("IGUI_EmberRoutesProbe_Monitor_compatFooter") end
})

PageRegistry.register({
    id = "crafting",
    module = "CraftingPage",
    isTab = false, -- Sub-view / child of orders
    parentTab = "orders",
    order = 60,
    footerText = function() return getText("IGUI_EmberRoutesProbe_Monitor_compatFooter") end
})

return PageRegistry
