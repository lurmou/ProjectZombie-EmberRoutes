--[[
    CardPanel.lua - EmberRoutes UI
    Unified survival-aesthetic card container.
    Eliminates dozens of repetitive manual Theme.rect calls, providing a consistent
    card style with header, icon slot, top-right status badge, and hover/selection states.
]]

require "ISUI/ISPanel"
local Theme = require "EmberRoutesProbe/UI/Theme"

---@class EmberRoutesCardPanel:ISPanel
---@field fontHeight number
---@field pad number
---@field title string?
---@field subtitle string?
---@field titleColor table?
---@field icon Texture?
---@field iconSize number
---@field badge string?
---@field badgeColor table?
---@field selected boolean
---@field hover boolean
---@field headerHeight number
---@field contentBounds {x:number, y:number, width:number, height:number}
local CardPanel = ISPanel:derive("EmberRoutesCardPanel")

---Static zero-GC draw function for drawing a card inside list rows or custom prerender loops.
---@param owner ISPanel
---@param x number
---@param y number
---@param width number
---@param height number
---@param opts table? {title=string, titleColor=table, icon=Texture, iconSize=number, badge=string, badgeColor=table, selected=boolean, hover=boolean, statusColor=table, headerHeight=number}
function CardPanel.draw(owner, x, y, width, height, opts)
    opts = opts or {}
    local isSelected = opts.selected or false
    local isHover = opts.hover or false

    -- 1. Card Background & Border
    local bg = isSelected and Theme.selected or (isHover and Theme.hover or Theme.panel)
    local border = isSelected and Theme.accent or (isHover and {r = 0.35, g = 0.45, b = 0.55, a = 0.9} or Theme.border)

    Theme.rect(owner, x, y, width, height, bg)
    Theme.rect(owner, x, y, width, height, border, true)

    -- 2. Left Accent Indicator (2~3px)
    local indicatorCol = opts.statusColor or (isSelected and Theme.accent or nil)
    if indicatorCol then
        Theme.rect(owner, x, y, 3, height, indicatorCol)
    end

    -- 3. Optional Header
    if opts.title and opts.title ~= "" then
        local tm = getTextManager()
        local h = tm:getFontHeight(UIFont.Small)
        local pad = math.max(4, math.floor(h * 0.4))
        local headerH = opts.headerHeight or (h + pad)

        -- Header divider line
        Theme.rect(owner, x + 3, y + headerH, width - 6, 1, {r = border.r, g = border.g, b = border.b, a = 0.35})

        local textX = x + pad + (indicatorCol and 2 or 0)
        local iconSize = opts.iconSize or h

        -- Icon
        if opts.icon then
            owner:drawTextureScaledAspect(opts.icon, textX, y + math.floor((headerH - iconSize) / 2), iconSize, iconSize, 1, 1, 1, 1)
            textX = textX + iconSize + pad / 2
        end

        -- Title
        local titleCol = opts.titleColor or Theme.gold
        Theme.text(owner, opts.title, textX, y + math.floor((headerH - h) / 2), titleCol)

        -- Top-right badge
        if opts.badge and opts.badge ~= "" then
            local bw = tm:MeasureStringX(UIFont.Small, opts.badge)
            local bx = x + width - bw - pad
            local bCol = opts.badgeColor or Theme.accent
            Theme.text(owner, opts.badge, bx, y + math.floor((headerH - h) / 2), bCol)
        end
    end
end

---Create an ISPanel CardPanel instance.
---@param x number
---@param y number
---@param width number
---@param height number
---@param opts table?
---@return EmberRoutesCardPanel
function CardPanel:new(x, y, width, height, opts)
    opts = opts or {}
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    o.fontHeight = getTextManager():getFontHeight(UIFont.Small)
    o.pad = math.ceil(o.fontHeight * 0.4)
    o.title = opts.title
    o.titleColor = opts.titleColor or Theme.gold
    o.icon = opts.icon
    o.iconSize = opts.iconSize or o.fontHeight
    o.badge = opts.badge
    o.badgeColor = opts.badgeColor or Theme.accent
    o.selected = opts.selected or false
    o.hover = opts.hover or false
    o.statusColor = opts.statusColor
    o.headerHeight = opts.title and (o.fontHeight + o.pad) or 0

    local contentY = o.headerHeight > 0 and (o.headerHeight + 2) or 0
    o.contentBounds = {
        x = o.pad,
        y = contentY + o.pad / 2,
        width = width - o.pad * 2,
        height = math.max(0, height - contentY - o.pad)
    }

    o:initialise()
    return o
end

function CardPanel:initialise()
    ISPanel.initialise(self)
end

function CardPanel:getContentBounds()
    return self.contentBounds
end

function CardPanel:setHeader(title, badge, icon, statusColor)
    self.title = title
    if badge ~= nil then self.badge = badge end
    if icon ~= nil then self.icon = icon end
    if statusColor ~= nil then self.statusColor = statusColor end
end

function CardPanel:setSelected(selected)
    self.selected = selected or false
end

function CardPanel:prerender()
    ISPanel.prerender(self)
    CardPanel.draw(self, 0, 0, self.width, self.height, {
        title = self.title,
        titleColor = self.titleColor,
        icon = self.icon,
        iconSize = self.iconSize,
        badge = self.badge,
        badgeColor = self.badgeColor,
        selected = self.selected,
        hover = self.hover,
        statusColor = self.statusColor,
        headerHeight = self.headerHeight
    })
end

return CardPanel
