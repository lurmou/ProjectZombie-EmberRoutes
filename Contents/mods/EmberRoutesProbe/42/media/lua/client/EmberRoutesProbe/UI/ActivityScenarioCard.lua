-- Scenario Card widget for EmberRoutes Activity UI.
-- Renders a thematic scenario card with title, tag pill, purpose, hardware hint and expected benefits.
require 'ISUI/ISPanel'
local Theme = require 'EmberRoutesProbe/UI/Theme'
local Text = require 'EmberRoutesProbe/UI/Text'
local CardPanel = require 'EmberRoutesProbe/UI/CardPanel'

local Card = {}

local function getTextOr(key, fallback)
    local s = _G.getTextOrNull and _G.getTextOrNull(key)
    return s or fallback or key
end

local function t(key, ...)
    if _G.getText then
        return _G.getText('IGUI_EmberRoutesProbe_Activity_' .. key, ...)
    end
    return key
end

---Draws a single scenario card.
---@param owner ISPanel
---@param x number
---@param y number
---@param width number
---@param height number
---@param scenario table
---@param isSelected boolean
---@param isHover boolean
function Card.draw(owner, x, y, width, height, scenario, isSelected, isHover)
    local fh = owner.fontHeight or 18
    local pad = owner.pad or 8

    -- 1. Unified Card Chassis (Background, Border & Left Accent Indicator)
    local accentColor = isSelected and Theme.accent or (scenario.requiresSpeaker and { r = 0.85, g = 0.65, b = 0.25, a = 1 } or { r = 0.35, g = 0.75, b = 0.55, a = 1 })
    CardPanel.draw(owner, x, y, width, height, {
        selected = isSelected,
        hover = isHover,
        statusColor = accentColor
    })

    local cx = x + pad + 6
    local cy = y + pad / 2
    local cw = width - (pad * 2) - 12

    -- 2. Title & Tag
    local title = getTextOr(scenario.titleKey, scenario.id)
    Theme.text(owner, title, cx, cy, Theme.textColor, UIFont.Medium or UIFont.Small)

    local tag = getTextOr(scenario.tagKey, '')
    if #tag > 0 then
        local tagWidth = (getTextManager and getTextManager():MeasureStringX(UIFont.Small, tag) or (#tag * 8)) + 10
        local tagX = x + width - tagWidth - pad
        Theme.rect(owner, tagX, cy, tagWidth, fh + 2, { r = 0.15, g = 0.20, b = 0.25, a = 0.9 })
        Theme.rect(owner, tagX, cy, tagWidth, fh + 2, accentColor, true)
        Theme.text(owner, tag, tagX + 5, cy + 1, accentColor, UIFont.Small)
    end

    cy = cy + fh + 4

    -- 3. Purpose & Hardware Requirement
    local purpose = getTextOr(scenario.purposeKey, '')
    if #purpose > 0 then
        Theme.text(owner, purpose, cx, cy, Theme.accent, UIFont.Small)
        cy = cy + fh + 2
    end

    local hardware = getTextOr(scenario.hardwareHintKey, '')
    if #hardware > 0 then
        Theme.text(owner, hardware, cx, cy, Theme.muted, UIFont.Small)
        cy = cy + fh + 2
    end

    -- 4. Expected Benefits Banner
    local benefitKey = scenario.benefits and scenario.benefits.summaryKey
    local benefitStr = benefitKey and getTextOr(benefitKey, '') or ''
    if #benefitStr > 0 then
        local boxH = fh + 6
        local boxY = y + height - boxH - pad / 2
        Theme.rect(owner, cx, boxY, cw, boxH, { r = 0.12, g = 0.18, b = 0.14, a = 0.85 })
        Theme.rect(owner, cx, boxY, cw, boxH, { r = 0.25, g = 0.55, b = 0.35, a = 0.8 }, true)
        Theme.text(owner, t('expectedBenefitLabel') .. ': ' .. benefitStr, cx + 6, boxY + 3, { r = 0.45, g = 0.85, b = 0.55, a = 1 }, UIFont.Small)
    end
end

return Card
