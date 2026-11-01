-- EmberRoutes UI Tooltip Infrastructure
-- Handles B42.21 mouse offset anchoring, screen-edge bounds clamping,
-- and hierarchical owner-based cascading lifecycle cleanup on page unmount.

---@class EmberRoutesTooltipManager
local Manager = {}

---@type table<table, table<table, boolean>> Map of owner -> { [widget] = true }
local owners = {}

---@type table<table, table> Map of widget -> { owner = table, method = string, original = function }
local registry = {}

---Position anchor for B42.21 lists/text entries which assign local mouse coordinates.
---Also clamps coordinates to stay within screen boundaries.
---@param widget table
function Manager.position(widget)
    ---@type ISToolTip?
    local tooltip = widget and widget.tooltipUI
    if tooltip and tooltip:getIsVisible() and tooltip.followMouse ~= false
            and not (tooltip.desiredX and tooltip.desiredY) then
        local x = getMouseX() + 32
        local y = getMouseY() + 10
        local core = type(getCore) == "function" and getCore()
        if core then
            local sw = core:getScreenWidth()
            local sh = core:getScreenHeight()
            local tw = tooltip:getWidth() or 200
            local th = tooltip:getHeight() or 50
            if x + tw > sw then x = math.max(0, getMouseX() - tw - 10) end
            if y + th > sh then y = math.max(0, sh - th - 10) end
        end
        tooltip:setX(x)
        tooltip:setY(y)
    end
end

---Register a widget with an optional owner and configuration for lifecycle management.
---@param widget table
---@param config table? Table with { owner = table, method = string, text = string|function }
function Manager.register(widget, config)
    if not widget then return end
    config = config or {}
    local method = config.method or "prerender"
    local owner = config.owner or widget.parent or widget.owner

    if owner then
        owners[owner] = owners[owner] or {}
        owners[owner][widget] = true
    end

    if not registry[widget] then
        registry[widget] = { owner = owner, method = method }
        local native = widget[method]
        if type(native) == "function" then
            widget[method] = function(self, ...)
                local res = native(self, ...)
                Manager.position(self)
                return res
            end
        end
    else
        if owner then registry[widget].owner = owner end
    end

    if config.text then
        Manager.update(widget, config.text)
    end
end

---Backward-compatible attach function matching TooltipAnchor.attach.
---@param widget table
---@param method string? Default "prerender"
---@param owner table? Optional owner for automatic cascading cleanup
function Manager.attach(widget, method, owner)
    if not widget then return end
    method = method or "prerender"
    owner = owner or widget.parent or widget.owner
    Manager.register(widget, { method = method, owner = owner })
end

---Update tooltip text or dynamic data on a widget.
---@param widget table
---@param textOrData string|function
function Manager.update(widget, textOrData)
    if not widget then return end
    if type(textOrData) == "function" then
        widget.tooltip = textOrData(widget)
    else
        widget.tooltip = tostring(textOrData or "")
    end
    if widget.tooltipUI and widget.tooltipUI:getIsVisible() and widget.tooltipUI.setName then
        widget.tooltipUI:setName(widget.tooltip)
    end
end

---Clean up and dismiss a single widget's tooltip.
---@param widget table?
function Manager.clear(widget)
    if not widget then return end
    local tooltip = widget.tooltipUI
    if tooltip then
        tooltip:setVisible(false)
        if tooltip.removeFromUIManager then
            tooltip:removeFromUIManager()
        end
    end
end

---Cascading cleanup of all tooltips registered to a given owner (e.g. page or window).
---Call this in page:deactivate() or during page unmount.
---@param owner table?
function Manager.clearOwner(owner)
    if not owner then return end
    local list = owners[owner]
    if list then
        for widget in pairs(list) do
            Manager.clear(widget)
            if registry[widget] and registry[widget].owner == owner then
                registry[widget].owner = nil
            end
        end
        owners[owner] = nil
    end

    -- Deep cascading cleanup for known child components/lists/controls
    if owner.details then
        Manager.clearOwner(owner.details)
        if type(owner.details) == "table" then
            if owner.details.locate then Manager.clear(owner.details.locate) end
            if owner.details.pinButton then Manager.clear(owner.details.pinButton) end
            if owner.details.cartButton then Manager.clear(owner.details.cartButton) end
            if owner.details.maintainStock then Manager.clear(owner.details.maintainStock) end
            if owner.details.heroPanel then Manager.clear(owner.details.heroPanel) end
            if owner.details.list then Manager.clear(owner.details.list) end
        end
    end
    if owner.controls then
        Manager.clearOwner(owner.controls)
        if type(owner.controls) == "table" and owner.controls.sort then
            Manager.clear(owner.controls.sort)
        end
    end
    if owner.itemGrid then Manager.clear(owner.itemGrid) end
    if owner.sourceList then Manager.clear(owner.sourceList) end
    if owner.orderList then Manager.clear(owner.orderList) end
    if owner.search then Manager.clear(owner.search) end
    if owner.helpButton then Manager.clear(owner.helpButton) end
    if owner.cartButton then Manager.clear(owner.cartButton) end
    if owner.buttons and type(owner.buttons) == "table" then
        for _, btn in pairs(owner.buttons) do Manager.clear(btn) end
    end
    if owner.priorityHeaders and type(owner.priorityHeaders) == "table" then
        for _, btn in ipairs(owner.priorityHeaders) do Manager.clear(btn) end
    end
    if owner.skillsList then Manager.clear(owner.skillsList) end
    if owner.recipesList then Manager.clear(owner.recipesList) end

    -- Fallback safety: if owner itself has a tooltipUI, clear it directly
    Manager.clear(owner)
end

---Global cleanup for shutdown or world reload.
function Manager.clearAll()
    for owner in pairs(owners) do
        Manager.clearOwner(owner)
    end
    owners = {}
    for widget in pairs(registry) do
        Manager.clear(widget)
    end
    registry = {}
end

return Manager
