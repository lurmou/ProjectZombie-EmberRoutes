-- EmberRoutes UI Tooltip Infrastructure
--
-- Responsibilities:
-- 1. B42.21 mouse-coordinate correction.
-- 2. Screen-edge clamping.
-- 3. Explicit widget ownership registration.
-- 4. Owner hierarchy tracking.
-- 5. Separate dismiss and unregister lifecycle.
-- 6. Safe restoration of wrapped native methods.
--
-- No business-specific child-field traversal.
-- No per-frame temporary table allocation for method forwarding.

---@class EmberRoutesTooltipManager
local Manager = {}

local owners = {}
local registry = {}

local MAX_OWNER_NODES = 64

----------------------------------------------------------------
-- Owner hierarchy
----------------------------------------------------------------

local function ownerLinks(node)
    if type(node) ~= "table" then
        return nil, nil
    end

    local parent = node.parent
    local owner = node.owner

    if parent == node then parent = nil end
    if owner == node or owner == parent then owner = nil end

    return parent, owner
end

-- Build an iterative, cycle-safe owner ancestry list.
--
-- Both parent and owner are considered because:
-- - ISUI controls use parent.
-- - Some composed UI components use owner.
--
-- The traversal is bounded to avoid malformed ownership graphs.
local function collectOwnerChain(root)
    local result = {}
    local seen = {}
    local pending = {}

    if root == nil then
        return result
    end

    pending[#pending + 1] = root

    while #pending > 0 do
        local node = pending[#pending]
        pending[#pending] = nil

        if node ~= nil and not seen[node] then
            if #result >= MAX_OWNER_NODES then
                error("TooltipManager: owner hierarchy exceeds limit")
            end

            seen[node] = true
            result[#result + 1] = node

            local parent, owner = ownerLinks(node)
            if parent ~= nil then pending[#pending + 1] = parent end
            if owner ~= nil then pending[#pending + 1] = owner end
        end
    end

    return result
end

local function sameOwnerChain(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function detachOwners(widget, entry)
    local chain = entry.owners or {}
    for i = 1, #chain do
        local owner = chain[i]
        local set = owners[owner]
        if set then
            set[widget] = nil
            local empty = true
            for _ in pairs(set) do
                empty = false
                break
            end
            if empty then
                owners[owner] = nil
            end
        end
    end
    entry.owners = {}
end

local function attachOwners(widget, entry, chain)
    for i = 1, #chain do
        local owner = chain[i]
        local set = owners[owner]
        if not set then
            set = {}
            owners[owner] = set
        end
        set[widget] = true
    end
    entry.owners = chain
end

----------------------------------------------------------------
-- Native method Hook
----------------------------------------------------------------

-- This helper preserves every native return value, including nils,
-- without allocating a temporary result table on every prerender.
--
-- Important:
-- native(self, ...) is the final argument expression below.
-- Lua therefore forwards all of its return values.
local function afterNative(widget, ...)
    Manager.position(widget)
    return ...
end

local function restoreHook(widget, entry)
    if not entry then return end

    local method = entry.method
    local wrapper = entry.wrapper

    -- Never overwrite a method installed by another system.
    if method and wrapper and widget[method] == wrapper then
        widget[method] = entry.original
    end

    entry.method = nil
    entry.original = nil
    entry.wrapper = nil
end

local function installHook(widget, entry, method)
    local native = widget[method]

    entry.method = method
    entry.original = nil
    entry.wrapper = nil

    if type(native) ~= "function" then
        return
    end

    local wrapper = function(self, ...)
        return afterNative(self, native(self, ...))
    end

    entry.original = native
    entry.wrapper = wrapper
    widget[method] = wrapper
end

----------------------------------------------------------------
-- Positioning
----------------------------------------------------------------

---Position tooltip anchor for B42.21 local mouse coordinates.
---Preserves explicitly positioned tooltips.
---@param widget table
function Manager.position(widget)
    local tooltip = widget and widget.tooltipUI
    if not tooltip then return end
    if type(tooltip.getIsVisible) ~= "function" or not tooltip:getIsVisible() then
        return
    end
    if tooltip.followMouse == false then
        return
    end
    if tooltip.desiredX and tooltip.desiredY then
        return
    end

    local mouseX = type(getMouseX) == "function" and getMouseX() or 0
    local mouseY = type(getMouseY) == "function" and getMouseY() or 0
    local x = mouseX + 32
    local y = mouseY + 10

    local core = type(getCore) == "function" and getCore()
    if core then
        local sw = core:getScreenWidth()
        local sh = core:getScreenHeight()
        local tw = type(tooltip.getWidth) == "function" and tooltip:getWidth() or 200
        local th = type(tooltip.getHeight) == "function" and tooltip:getHeight() or 50
        tw = tonumber(tw) or 200
        th = tonumber(th) or 50
        if type(sw) == "number" and x + tw > sw then
            x = math.max(0, mouseX - tw - 10)
        end
        if type(sh) == "number" and y + th > sh then
            y = math.max(0, sh - th - 10)
        end
    end

    if type(tooltip.setX) == "function" then tooltip:setX(x) end
    if type(tooltip.setY) == "function" then tooltip:setY(y) end
end

----------------------------------------------------------------
-- Registration
----------------------------------------------------------------

---Register a widget and its lifecycle owner.
---@param widget table
---@param config table?
---@return table?
function Manager.register(widget, config)
    if not widget then return nil end
    config = config or {}

    local method = config.method or "prerender"
    local owner = config.owner
    if owner == nil then
        owner = widget.parent or widget.owner
    end

    -- Calculate before mutating the current registration.
    local nextOwners = collectOwnerChain(owner)

    local entry = registry[widget]
    local isNew = entry == nil
    if not entry then
        entry = { owners = {} }
    end

    -- Changing the hooked method must restore the previous one first.
    if entry.method ~= method then
        restoreHook(widget, entry)
    end

    -- If another system replaced our wrapper, do not overwrite it
    -- during unregister. On explicit re-registration, wrap the
    -- currently installed method instead.
    if entry.method == method and entry.wrapper and widget[method] ~= entry.wrapper then
        entry.original = nil
        entry.wrapper = nil
    end

    if entry.method ~= method or not entry.wrapper then
        installHook(widget, entry, method)
    end

    if isNew then
        registry[widget] = entry
    end

    -- Owner transfer must remove all old ancestry links first.
    if not sameOwnerChain(entry.owners, nextOwners) then
        detachOwners(widget, entry)
        attachOwners(widget, entry, nextOwners)
    end

    if config.text ~= nil then
        Manager.update(widget, config.text)
    end

    return widget
end

---Backward-compatible TooltipAnchor.attach.
---@param widget table
---@param method string?
---@param owner table?
function Manager.attach(widget, method, owner)
    if not widget then return nil end
    return Manager.register(widget, {
        method = method or "prerender",
        owner = owner
    })
end

----------------------------------------------------------------
-- Tooltip content
----------------------------------------------------------------

---Update tooltip text or dynamic data.
---@param widget table
---@param textOrData string|function
function Manager.update(widget, textOrData)
    if not widget then return end

    if type(textOrData) == "function" then
        widget.tooltip = textOrData(widget)
    else
        widget.tooltip = tostring(textOrData or "")
    end

    local tooltip = widget.tooltipUI
    if tooltip and type(tooltip.getIsVisible) == "function" and tooltip:getIsVisible() and type(tooltip.setName) == "function" then
        tooltip:setName(widget.tooltip)
    end
end

----------------------------------------------------------------
-- Dismiss
----------------------------------------------------------------

---Hide a widget tooltip without unregistering the widget.
---@param widget table?
function Manager.clear(widget)
    if not widget then return end

    local tooltip = widget.tooltipUI
    if not tooltip then return end

    if type(tooltip.setVisible) == "function" then
        tooltip:setVisible(false)
    end
    if type(tooltip.removeFromUIManager) == "function" then
        tooltip:removeFromUIManager()
    end
end

---Dismiss every tooltip owned by this owner or its descendants.
---
---IMPORTANT:
---This preserves registry entries and native method hooks.
---Use during deactivate/unmount, not permanent destruction.
---@param owner table?
---@return number
function Manager.dismissOwner(owner)
    if owner == nil then return 0 end

    local list = owners[owner]
    local count = 0

    if list then
        for widget in pairs(list) do
            Manager.clear(widget)
            count = count + 1
        end
    end

    -- The owner itself may also be a registered widget.
    if registry[owner] and not (list and list[owner]) then
        Manager.clear(owner)
        count = count + 1
    end

    return count
end

----------------------------------------------------------------
-- Permanent unregister
----------------------------------------------------------------

---Unregister a widget permanently.
---
---Restores its native method only if our wrapper is still installed.
---Removes all owner references and registry references.
---@param widget table?
---@return boolean
function Manager.unregister(widget)
    if not widget then return false end

    local entry = registry[widget]

    -- Still dismiss a tooltip even if it was never registered.
    Manager.clear(widget)

    if not entry then return false end

    restoreHook(widget, entry)
    detachOwners(widget, entry)
    registry[widget] = nil

    return true
end

---Permanently unregister all widgets owned by this owner
---or any explicitly linked descendant.
---
---Unlike dismissOwner, this removes registration and Hook state.
---@param owner table?
---@return number
function Manager.unregisterOwner(owner)
    if owner == nil then return 0 end

    local list = owners[owner]
    local widgets = {}
    local seen = {}

    -- Copy first because unregister mutates owners.
    if list then
        for widget in pairs(list) do
            if not seen[widget] then
                seen[widget] = true
                widgets[#widgets + 1] = widget
            end
        end
    end

    -- Also unregister the owner itself if it is a widget.
    if registry[owner] and not seen[owner] then
        seen[owner] = true
        widgets[#widgets + 1] = owner
    end

    for i = 1, #widgets do
        Manager.unregister(widgets[i])
    end

    if not registry[owner] then
        Manager.clear(owner)
    end

    return #widgets
end

----------------------------------------------------------------
-- Compatibility
----------------------------------------------------------------

---Legacy API.
---
---Historically clearOwner meant temporary tooltip cleanup.
---Keep that behavior to avoid breaking page deactivate callers.
function Manager.clearOwner(owner)
    return Manager.dismissOwner(owner)
end

----------------------------------------------------------------
-- Global shutdown / world teardown
----------------------------------------------------------------

---Permanently unregister every managed widget.
---@return number
function Manager.clearAll()
    local widgets = {}
    for widget in pairs(registry) do
        widgets[#widgets + 1] = widget
    end

    for i = 1, #widgets do
        Manager.unregister(widgets[i])
    end

    owners = {}
    registry = {}
    return #widgets
end

return Manager
