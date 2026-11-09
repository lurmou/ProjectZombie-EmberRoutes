-- Modal Dialog Infrastructure.
-- Creates a full-screen blocking overlay with a centered card powered by LayoutHost.
-- Enforces mandatory user focus, blocks background world/dashboard interaction, and guarantees safe lifecycle cleanup.
require "ISUI/ISPanel"
require "ISUI/ISButton"
local LayoutHost = require "EmberRoutesProbe/UI/LayoutHost"
local PageLifecycle = require "EmberRoutesProbe/UI/PageLifecycle"
local Theme = require "EmberRoutesProbe/UI/Theme"

---@class EmberRoutesModalDialog:ISPanel
---@field cardX number
---@field cardY number
---@field cardWidth number
---@field cardHeight number
---@field contentHost EmberRoutesLayoutHost
local ModalDialog = ISPanel:derive("EmberRoutesModalDialog")

local function getOkText() return getTextOrNull("UI_Ok") or "确定" end
local function getCancelText() return getTextOrNull("UI_Cancel") or "取消" end

function ModalDialog:new(cardW, cardH, opts)
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local o = ISPanel.new(self, 0, 0, sw, sh)
    setmetatable(o, self)
    self.__index = self

    opts = opts or {}
    o.opts = opts
    o.title = opts.title or ""
    o.cardWidth = math.min(sw - 40, cardW or 480)
    o.cardHeight = math.min(sh - 40, cardH or 320)
    o.cardX = math.floor((sw - o.cardWidth) / 2)
    o.cardY = math.floor((sh - o.cardHeight) / 2)
    o.closeOnBackdropClick = opts.closeOnBackdropClick == true
    o.showFooter = opts.showFooter ~= false and (opts.onConfirm ~= nil or opts.onCancel ~= nil or opts.showFooter == true)
    o.confirmText = opts.confirmText or getOkText()
    o.cancelText = opts.cancelText or getCancelText()
    o.owner = opts.owner
    o.disposed = false
    o.background = false

    return o
end

function ModalDialog:initialise()
    ISPanel.initialise(self)
end

function ModalDialog:createChildren()
    ISPanel.createChildren(self)

    local cx, cy = self.cardX, self.cardY
    local cw, ch = self.cardWidth, self.cardHeight
    local titleH = 28
    local footerH = self.showFooter and 38 or 0
    local p = 12

    -- 1. Close button (X) in title bar
    local btnSize = 20
    self.closeButton = ISButton:new(cx + cw - btnSize - 6, cy + 4, btnSize, btnSize, "X", self, function()
        self:close("CLOSE_BUTTON")
    end)
    self.closeButton:initialise()
    Theme.button(self.closeButton)
    self:addChild(self.closeButton)

    -- 2. Footer buttons (Confirm & Cancel)
    if self.showFooter then
        local btnW = 84
        local btnH = 26
        local btnY = cy + ch - btnH - 6
        local btnGap = 8

        self.confirmButton = ISButton:new(cx + cw - btnW - p, btnY, btnW, btnH, self.confirmText, self, function()
            self:onConfirmClicked()
        end)
        self.confirmButton:initialise()
        Theme.button(self.confirmButton, not self.opts.danger)
        if self.opts.danger then
            self.confirmButton.borderColor = { r = 0.95, g = 0.35, b = 0.30, a = 1.0 }
            self.confirmButton.textColor = { r = 0.95, g = 0.35, b = 0.30, a = 1.0 }
        end
        self:addChild(self.confirmButton)

        self.cancelButton = ISButton:new(cx + cw - btnW * 2 - p - btnGap, btnY, btnW, btnH, self.cancelText, self, function()
            self:close("CANCEL")
        end)
        self.cancelButton:initialise()
        Theme.button(self.cancelButton, false)
        self:addChild(self.cancelButton)
    end

    -- 3. Content message or hosted LayoutHost
    local msg = self.opts.message or self.opts.prompt
    if msg and msg ~= "" then
        local Text = require "EmberRoutesProbe/UI/Text"
        self.messageLines = Text.wrapLimited(msg, cw - p * 2, UIFont.Small, 6)
    end

    local contentX = cx + p
    local contentY = cy + titleH + math.floor(p / 2)
    local contentW = cw - p * 2
    local contentH = ch - titleH - footerH - p

    self.contentHost = LayoutHost:new(contentX, contentY, contentW, contentH, { direction = "column" })
    self.contentHost:initialise()
    self:addChild(self.contentHost)

    if self.opts.content then
        local spec = self.opts.content(self.contentHost, self)
        if spec then
            local handles, err = self.contentHost:build(spec, self.opts.initialContext)
            assert(handles, err or "MODAL_BUILD_FAILED")
            self.handles = handles
        end
    end

    self.activationScope = PageLifecycle.createActivationScope(self)
    self.contentHost:setActivation(self.activationScope)
end

function ModalDialog:onConfirmClicked()
    if self.opts.onConfirm then
        local keepOpen = self.opts.onConfirm(self)
        if keepOpen == true then return end
    end
    self:close("CONFIRM")
end

function ModalDialog:prerender()
    -- Full-screen modal dimming backdrop (blocks clicks to world and dashboard)
    self:drawRect(0, 0, self.width, self.height, 0.60, 0, 0, 0)

    -- Card background & border
    local cx, cy, cw, ch = self.cardX, self.cardY, self.cardWidth, self.cardHeight
    Theme.rect(self, cx, cy, cw, ch, Theme.window)
    Theme.rect(self, cx, cy, cw, ch, Theme.border, true)

    -- Title bar divider and title text
    Theme.rect(self, cx, cy + 28, cw, 1, Theme.border)
    if self.title and #self.title > 0 then
        Theme.text(self, self.title, cx + 12, cy + 6, Theme.gold)
    end

    -- Footer divider
    if self.showFooter then
        Theme.rect(self, cx, cy + ch - 38, cw, 1, Theme.border)
    end

    -- Message / Prompt text
    if self.messageLines and #self.messageLines > 0 then
        local my = cy + 28 + 14
        local tm = getTextManager()
        local fontH = tm and tm:getFontHeight(UIFont.Small) or 14
        for _, line in ipairs(self.messageLines) do
            Theme.text(self, line, cx + 16, my, Theme.textColor, UIFont.Small)
            my = my + fontH + 4
        end
    end
end

function ModalDialog:onMouseDown(x, y)
    if self.disposed then return true end
    local cx, cy, cw, ch = self.cardX, self.cardY, self.cardWidth, self.cardHeight
    local inside = x >= cx and x <= cx + cw and y >= cy and y <= cy + ch
    if not inside and self.closeOnBackdropClick then
        self:close("BACKDROP")
    end
    return true -- Consume all mouse events to block background interaction
end

function ModalDialog:onMouseUp(x, y) return true end
function ModalDialog:onMouseMove(x, y) return true end

function ModalDialog:close(reason)
    if self.disposed then return end
    self.disposed = true

    if self.contentHost then
        self.contentHost:dispose()
        self.contentHost = nil
    end

    self:removeFromUIManager()

    if self.opts.onClose then
        self.opts.onClose(self, reason or "CLOSE")
    end
    if reason == "CANCEL" and self.opts.onCancel then
        self.opts.onCancel(self)
    end
end

---Displays a modal dialog overlay and returns the instance.
---@param opts table Modal options ({ title, width, height, content, onConfirm, onCancel, onClose, closeOnBackdropClick, confirmText, cancelText, showFooter, initialContext })
---@return EmberRoutesModalDialog
function ModalDialog.show(opts)
    opts = opts or {}
    local modal = ModalDialog:new(opts.width, opts.height, opts)
    modal:initialise()
    modal:instantiate()
    modal:addToUIManager()
    return modal
end

---Displays a standardized Flat 2.0 confirmation dialog.
---@param actor any IsoPlayer / IsoGameCharacter
---@param opts table Confirm options ({ title, message, onConfirm, onCancel, confirmText, cancelText, danger = boolean, width = number, height = number })
---@return EmberRoutesModalDialog
function ModalDialog.confirm(actor, opts)
    opts = opts or {}
    opts.showFooter = true
    opts.width = opts.width or 420
    opts.height = opts.height or 170
    opts.title = opts.title or getTextOrNull("UI_Confirm") or "请确认操作"
    opts.confirmText = opts.confirmText or getTextOrNull("UI_Yes") or "确认"
    opts.cancelText = opts.cancelText or getTextOrNull("UI_No") or "取消"
    local modal = ModalDialog.show(opts)
    if actor and actor.getJoypadBind and actor:getJoypadBind() ~= -1 and setJoypadFocus then
        setJoypadFocus(actor:getIndex(), modal)
    end
    return modal
end

return ModalDialog
