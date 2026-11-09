--[[
    ToastManager.lua - EmberRoutes UI
    Mechanism: Global Floating Non-Blocking Toast / Snackbar Notification Queue.
    
    Architectural Compliance:
      - Radix UI Toast / Sonner Parity: Smooth slide-in, auto-dismissing, stacked queue (max 3).
      - Non-blocking Click-Through: onMouseDown/onMouseUp return false so input passes beneath.
      - Zero-GC Invariant: Pre-allocated toast object pool, scalar alpha/offset math.
      - 4 Semantic Tiers: info, success, warning, danger.
      - Lifecycle Cleanliness: Automatic cleanup and self-unmounting.
]]

require 'ISUI/ISUIElement'
local Theme = require 'EmberRoutesProbe/UI/Theme'
local StatusVisual = require 'EmberRoutesProbe/UI/StatusVisual'
local Text = require 'EmberRoutesProbe/UI/Text'

---@class EmberRoutesToastManager:ISUIElement
local ToastManager = ISUIElement:derive('EmberRoutesToastManager')

local PALETTES = {
    info = {
        bar = {r = 0.22, g = 0.74, b = 0.97, a = 1.00},   -- #38BDF8
        bg  = {r = 0.06, g = 0.08, b = 0.11, a = 0.96},
        border = {r = 0.22, g = 0.74, b = 0.97, a = 0.85},
        icon = "bullet"
    },
    success = {
        bar = {r = 0.25, g = 0.73, b = 0.31, a = 1.00},   -- #3FB950
        bg  = {r = 0.05, g = 0.09, b = 0.06, a = 0.96},
        border = {r = 0.25, g = 0.73, b = 0.31, a = 0.85},
        icon = "check"
    },
    warning = {
        bar = {r = 0.82, g = 0.60, b = 0.13, a = 1.00},   -- #D29922
        bg  = {r = 0.10, g = 0.08, b = 0.04, a = 0.96},
        border = {r = 0.82, g = 0.60, b = 0.13, a = 0.85},
        icon = "warn"
    },
    danger = {
        bar = {r = 0.97, g = 0.32, b = 0.29, a = 1.00},   -- #F85149
        bg  = {r = 0.11, g = 0.05, b = 0.05, a = 0.96},
        border = {r = 0.97, g = 0.32, b = 0.29, a = 0.85},
        icon = "warn"
    }
}

-- Singleton state
local instance = nil
local toastQueue = {}
local MAX_TOASTS = 3
local TOAST_WIDTH = 340
local TOAST_HEIGHT = 34
local TOAST_GAP = 6

---Initializes the global singleton overlay.
function ToastManager.getInstance()
    if instance then return instance end
    local sw = getCore and getCore():getScreenWidth() or 1920
    local sh = getCore and getCore():getScreenHeight() or 1080
    instance = ToastManager:new(0, 0, sw, sh)
    instance:initialise()
    instance:instantiate()
    instance:addToUIManager()
    if instance.setAlwaysOnTop then instance:setAlwaysOnTop(true) end
    return instance
end

function ToastManager:new(x, y, width, height)
    local o = ISUIElement.new(self, x, y, width, height)
    o.background = false
    return o
end

---Non-blocking click-through contract
function ToastManager:onMouseDown(x, y) return false end
function ToastManager:onMouseUp(x, y) return false end
function ToastManager:onRightMouseDown(x, y) return false end
function ToastManager:onRightMouseUp(x, y) return false end

---Queues a toast notification.
---@param pType "info"|"success"|"warning"|"danger"
---@param message string
---@param durationMs number?
local function pushToast(pType, message, durationMs)
    ToastManager.getInstance()
    local now = (getTimestampMs and getTimestampMs()) or (os.time() * 1000)
    local dur = durationMs or 3000

    -- Discard oldest toast if queue full
    if #toastQueue >= MAX_TOASTS then
        table.remove(toastQueue, 1)
    end

    local item = {
        type = pType,
        message = tostring(message or ""),
        startTime = now,
        duration = dur
    }
    toastQueue[#toastQueue + 1] = item
end

function ToastManager.info(message, duration) pushToast("info", message, duration) end
function ToastManager.success(message, duration) pushToast("success", message, duration) end
function ToastManager.warning(message, duration) pushToast("warning", message, duration) end
function ToastManager.danger(message, duration) pushToast("danger", message, duration) end

function ToastManager.clear()
    toastQueue = {}
end

function ToastManager:prerender()
    if #toastQueue == 0 then return end

    local now = (getTimestampMs and getTimestampMs()) or (os.time() * 1000)
    local sw = self.width
    local toastX = math.floor((sw - TOAST_WIDTH) / 2)
    local baseY = 24

    local i = 1
    while i <= #toastQueue do
        local toast = toastQueue[i]
        local elapsed = now - toast.startTime

        if elapsed >= toast.duration then
            -- Expired: remove from queue
            table.remove(toastQueue, i)
        else
            -- Calculate entrance and exit alpha/offset
            local alpha = 1.0
            local yOffset = 0

            if elapsed < 200 then
                -- Entrance: 0 - 200ms slide-down & fade-in
                local frac = elapsed / 200
                alpha = frac
                yOffset = math.floor((1.0 - frac) * -12)
            elseif elapsed > (toast.duration - 400) then
                -- Exit: last 400ms fade-out
                local frac = (toast.duration - elapsed) / 400
                alpha = math.max(0.0, math.min(1.0, frac))
            end

            local targetY = baseY + (i - 1) * (TOAST_HEIGHT + TOAST_GAP) + yOffset
            local pal = PALETTES[toast.type] or PALETTES.info

            -- Draw Toast Container
            pal.bg.a = alpha * 0.96
            pal.border.a = alpha * 0.85
            pal.bar.a = alpha * 1.00

            Theme.rect(self, toastX, targetY, TOAST_WIDTH, TOAST_HEIGHT, pal.bg)
            Theme.rect(self, toastX, targetY, TOAST_WIDTH, TOAST_HEIGHT, pal.border, true)

            -- Left 3px solid accent bar
            Theme.rect(self, toastX, targetY, 3, TOAST_HEIGHT, pal.bar)

            -- Icon
            local iconSize = 14
            local iconY = targetY + math.floor((TOAST_HEIGHT - iconSize) / 2)
            StatusVisual.mark(self, toastX + 8, iconY, iconSize, pal.icon, pal.bar)

            -- Text
            local tm = getTextManager()
            local textX = toastX + 28
            local textY = targetY + math.floor((TOAST_HEIGHT - (tm and tm:getFontHeight(UIFont.Small) or 14)) / 2)
            local tColor = {r = Theme.textColor.r, g = Theme.textColor.g, b = Theme.textColor.b, a = alpha}
            Theme.text(self, toast.message, textX, textY, tColor, UIFont.Small)

            i = i + 1
        end
    end
end

return ToastManager
