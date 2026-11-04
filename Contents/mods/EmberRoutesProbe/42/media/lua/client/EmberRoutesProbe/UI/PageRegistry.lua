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
---@field group string
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

-- isTab denotes a group-local page button; child views retain parentTab.
PageRegistry.groups = {
    {id='settlement',titleKey='group_settlement',defaultTab='activities'},
    {id='warehouse',titleKey='tab_warehouse',defaultTab='warehouse'},
    {id='personnel',titleKey='tab_personnel',defaultTab='personnel'},
    {id='work',titleKey='group_work',defaultTab='crafting'}
}

function PageRegistry.getGroup(id)
    for _,group in ipairs(PageRegistry.groups) do if group.id==id then return id end end
    local def=PageRegistry.get(id)
    if def and def.parentTab then return PageRegistry.getGroup(def.parentTab) end
    return def and def.group
end

function PageRegistry.getGroupTabIds(group,actor,entry)
    local result={}
    for _,id in ipairs(PageRegistry.getTabIds(actor,entry)) do
        if PageRegistry.getGroup(id)==group then result[#result+1]=id end
    end
    return result
end

-- Navigation accepts stable identifiers only, never entities or command parameters.
function PageRegistry.validateContext(context)
    if context==nil then return true end
    if type(context)~='table' then return false end
    if context.returnTab=='warehouse' and type(context.filterProduct)=='string' and context.filterProduct~='' then
        for key in pairs(context) do if key~='returnTab' and key~='filterProduct' then return false end end
        return true
    end
    local allowed={npcId=true,orderId=true,problemId=true,itemId=true,zoneId=true,category=true,view=true}
    local count=0
    for key,value in pairs(context) do
        if not allowed[key] or (type(value)~='string' and type(value)~='number') or value=='' then return false end
        count=count+1
    end
    return count==1
end

-- Default built-in Page Registrations:
PageRegistry.register({
    id = "warehouse",
    group = "warehouse",
    module = "WarehousePage",
    isTab = true,
    titleKey = "tab_warehouse",
    tooltipKey = "tabNavigation",
    order = 10,
    footerText = function() return getText("IGUI_EmberRoutesProbe_Monitor_warehouseFooter") end
})

PageRegistry.register({
    id = "personnel",
    group = "personnel",
    module = "PersonnelPage",
    isTab = true,
    titleKey = "tab_personnel",
    tooltipKey = "tabNavigation",
    order = 30,
    footerText = function() return getText("IGUI_EmberRoutesProbe_Personnel_priorityLegend") end
})

PageRegistry.register({
    id = "policies",
    group = "settlement",
    module = "WorkPolicyPage",
    parentTab = "settlement",
    isTab = true,
    titleKey = "tab_policies",
    tooltipKey = "tabNavigation",
    order = 35,
    footerText = function() return getText("IGUI_EmberRoutesProbe_Policy_footer") end
})

PageRegistry.register({
    id = "activities",
    group = "settlement",
    module = "ActivityPage",
    isTab = true,
    titleKey = "tab_activities",
    tooltipKey = "tabNavigation",
    order = 38,
    footerText = function() return getText("IGUI_EmberRoutesProbe_Activity_footer") end
})

PageRegistry.register({
    id = "defense",
    group = "settlement",
    module = "DefensePage",
    isTab = true,
    titleKey = "tab_defense",
    tooltipKey = "tabNavigation",
    order = 40,
    footerText = function() return getText("IGUI_EmberRoutesProbe_Defense_alertHint") end
})

PageRegistry.register({
    id = "logistics",
    group = "personnel",
    module = "LogisticsPage",
    parentTab = "personnel",
    titleKey = "tab_logistics",
    isTab = true,
    order = 50,
    footerText = function() return getText("IGUI_EmberRoutesProbe_Monitor_compatFooter") end
})

PageRegistry.register({
    id = "crafting",
    group = "work",
    module = "CraftingPage",
    parentTab = "work",
    titleKey = "tab_crafting",
    isTab = true,
    order = 60,
    footerText = function() return getText("IGUI_EmberRoutesProbe_Monitor_compatFooter") end
})

return PageRegistry
