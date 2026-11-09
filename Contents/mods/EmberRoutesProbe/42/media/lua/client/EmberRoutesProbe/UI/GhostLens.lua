--[[
    GhostLens.lua - EmberRoutes UI Infrastructure
    X-Ray peek and transparency lens for management dialogs.
    Allows players to temporarily see through modal windows to the world underneath.
]]
local Theme = require "EmberRoutesProbe/UI/Theme"
local Visual = require "EmberRoutesProbe/UI/StatusVisual"
local Tooltip = require "EmberRoutesProbe/UI/TooltipManager"

local GhostLens = {}

-- Pre-allocated immutable color structures (Zero-GC)
local GHOST_BG = { r = 0.05, g = 0.07, b = 0.09, a = 0.08 }
local GHOST_BORDER = { r = 0.35, g = 0.75, b = 0.88, a = 0.45 }
local HINT_COLOR = { r = 0.75, g = 0.88, b = 0.98, a = 0.92 }

local activeHighlights = {}

local function text(key)
    return getTextOrNull and (getTextOrNull("IGUI_EmberRoutesProbe_Filter_" .. key) or getTextOrNull(key)) or key
end

---Activates ghost / X-Ray mode on a window.
---@param window ISCollapsableWindow|ISPanel
---@param targetPosition table? Optional {x, y, z} world tile coordinates to illuminate
function GhostLens.activate(window, targetPosition)
    if not window or window.isGhosting then return end
    window.isGhosting = true

    -- 1. Snapshot previous appearance and child visibilities
    local saved = {
        bg = window.backgroundColor,
        border = window.borderColor,
        childVis = {},
        targetPos = targetPosition
    }

    if window.children then
        for _, child in pairs(window.children) do
            if child ~= window._ghostBtn then
                saved.childVis[child] = child:isVisible()
                child:setVisible(false)
            end
        end
    end
    window._ghostSaved = saved

    -- 2. Apply ultra-transparent ghost theme
    window.backgroundColor = GHOST_BG
    window.borderColor = GHOST_BORDER

    -- 3. World entity halo highlight
    if targetPosition and targetPosition.x and targetPosition.y and Events and Events.OnRenderTick then
        local actor = window.actor or (window.owner and window.owner.actor) or (type(getPlayer) == "function" and getPlayer())
        local playerIdx = actor and actor.getIndex and actor:getIndex() or 0
        local p = targetPosition

        local function highlightTick()
            if not window.isGhosting then
                Events.OnRenderTick.Remove(highlightTick)
                return
            end
            if type(_G.addAreaHighlightForPlayer) == "function" then
                _G.addAreaHighlightForPlayer(playerIdx, p.x, p.y, p.x + 1, p.y + 1, p.z or 0, 0.85, 0.72, 0.30, 0.75)
            end
        end

        saved.highlightTick = highlightTick
        Events.OnRenderTick.Add(highlightTick)
    end
end

---Restores the window to full opacity and original child visibilities.
---@param window ISCollapsableWindow|ISPanel
function GhostLens.restore(window)
    if not window or not window.isGhosting then return end
    window.isGhosting = false

    local saved = window._ghostSaved
    if saved then
        -- 1. Restore child visibilities exactly as they were
        if window.children and saved.childVis then
            for child, wasVisible in pairs(saved.childVis) do
                child:setVisible(wasVisible == true)
            end
        end

        -- 2. Restore colors
        window.backgroundColor = saved.bg or Theme.window
        window.borderColor = saved.border or Theme.border

        -- 3. Clean up ground highlight
        if saved.highlightTick and Events and Events.OnRenderTick then
            Events.OnRenderTick.Remove(saved.highlightTick)
        end
        window._ghostSaved = nil
    end
end

---Frame-level guard called in window:prerender(). Checks if mouse was released outside.
---@param window ISCollapsableWindow|ISPanel
function GhostLens.update(window)
    if not window or not window.isGhosting then return end
    if type(_G.isMouseButtonDown) == "function" and not _G.isMouseButtonDown(0) then
        GhostLens.restore(window)
    end
end

---Renders centered hint HUD when ghost mode is active.
---@param window ISCollapsableWindow|ISPanel
function GhostLens.drawHint(window)
    if not window or not window.isGhosting then return end
    local msg = text("ghostHint")
    local fh = window.fontHeight or 16
    local cx = math.floor(window.width / 2)
    local cy = math.floor(window.height / 2 - fh)
    local tm = getTextManager()
    local strW = tm and tm:MeasureStringX(UIFont.Medium or UIFont.Small, msg) or 200
    local pad = 12

    -- Pill badge backdrop
    window:drawRect(cx - strW / 2 - pad, cy - 4, strW + pad * 2, fh + 12, 0.50, 0.05, 0.08, 0.12)
    window:drawRectBorder(cx - strW / 2 - pad, cy - 4, strW + pad * 2, fh + 12, 0.80, GHOST_BORDER.r, GHOST_BORDER.g, GHOST_BORDER.b)
    window:drawTextCentre(msg, cx, cy, HINT_COLOR.r, HINT_COLOR.g, HINT_COLOR.b, HINT_COLOR.a, UIFont.Medium or UIFont.Small)
end

---Creates a standardized GhostLens icon button and attaches it to the window header.
---@param window ISCollapsableWindow
---@param x number
---@param y number
---@param size number
---@param getTargetPosFn function? Optional callback returning {x, y, z}
---@return ISButton
function GhostLens.attachHeaderButton(window, x, y, size, getTargetPosFn)
    local btn = ISButton:new(x, y, size, size, "", window, nil)
    btn:initialise()
    btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    btn.backgroundColorMouseOver = { r = 1, g = 1, b = 1, a = 0.12 }
    btn.tooltip = text("ghostLens")

    btn.render = function(self)
        ISButton.render(self)
        local iconColor = self.mouseOver and Theme.accent or Theme.muted
        local isize = math.max(12, math.min(18, self.width - 4))
        local ix = math.floor((self.width - isize) / 2)
        local iy = math.floor((self.height - isize) / 2)
        Visual.icon(self, ix, iy, isize, "eye", iconColor)
    end

    btn.onMouseDown = function(self, mx, my)
        local pos = getTargetPosFn and getTargetPosFn()
        GhostLens.activate(window, pos)
        return true
    end

    btn.onMouseUp = function(self, mx, my)
        GhostLens.restore(window)
        return true
    end

    btn.onMouseUpOutside = function(self, mx, my)
        GhostLens.restore(window)
        return true
    end

    window._ghostBtn = btn
    window:addChild(btn)
    Tooltip.register(btn, { method = "render", owner = window })
    return btn
end

return GhostLens
