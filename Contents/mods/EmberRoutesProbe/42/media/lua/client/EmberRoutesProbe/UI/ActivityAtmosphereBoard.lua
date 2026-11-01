-- Live Atmosphere Board widget for EmberRoutes Activity UI.
-- Renders the live gathering state, phase progress bar, resident presence cards,
-- and post-activity debrief without fake continuous progress or invented ETAs.

require 'ISUI/ISPanel'
local Theme = require 'EmberRoutesProbe/UI/Theme'
local Text = require 'EmberRoutesProbe/UI/Text'
local Presentation = require 'EmberRoutesProbe/UI/ActivityPresentation'

local Board = {}

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

---Draws the top atmosphere strip with phase progress and benefit notes.
---@param owner ISPanel
---@param x number
---@param y number
---@param width number
---@param height number
---@param detail table
function Board.drawStrip(owner, x, y, width, height, detail)
    local fh = owner.fontHeight or 18
    local pad = owner.pad or 8

    Theme.rect(owner, x, y, width, height, Theme.panel)
    Theme.rect(owner, x, y, width, height, Theme.border, true)

    local state = detail.state or 'CLOSED'
    local phaseName = Presentation.phaseText(state, detail.stage)
    local hoursNow = getGameTime():getWorldAgeHours()

    -- 1. Phase Header & Badge
    local badgeCol = state == 'RUNNING' and { r = 0.25, g = 0.75, b = 0.45, a = 1 }
        or state == 'GATHERING' and { r = 0.85, g = 0.65, b = 0.25, a = 1 }
        or state == 'CLOSED' and Theme.muted or { r = 0.45, g = 0.55, b = 0.65, a = 1 }

    Theme.rect(owner, x, y, 4, height, badgeCol)
    Theme.text(owner, t('currentPhase') .. ': ' .. phaseName, x + pad + 4, y + pad / 2, Theme.textColor, UIFont.Medium or UIFont.Small)

    -- Remaining countdown
    local timeText = ''
    if state == 'GATHERING' and detail.gatherDeadline then
        local remMin = math.max(0, math.floor((detail.gatherDeadline - hoursNow) * 60 + 0.5))
        timeText = t('gatherRemainingMin', remMin)
    elseif state == 'RUNNING' then
        local endH = detail.stage and detail.stage.sharedEnd or detail.endsAt or 0
        local remMin = math.max(0, math.floor((endH - hoursNow) * 60 + 0.5))
        timeText = t('durationRemainingMin', remMin)
    elseif state == 'CLOSED' then
        timeText = Presentation.outcomeText(detail.outcome)
    end

    if #timeText > 0 then
        local tw = (getTextManager and getTextManager():MeasureStringX(UIFont.Small, timeText) or (#timeText * 8)) + 12
        Theme.text(owner, timeText, x + width - tw, y + pad / 2, badgeCol, UIFont.Small)
    end

    -- 2. Progress Bar
    local barY = y + fh + pad / 2 + 2
    local barW = width - (pad * 2) - 8
    local barH = 6
    Theme.rect(owner, x + pad + 4, barY, barW, barH, { r = 0.15, g = 0.18, b = 0.22, a = 1 })

    local ratio = 0
    if state == 'GATHERING' then
        local totalGather = (detail.gatherDeadline or hoursNow) - (detail.createdAt or hoursNow)
        if totalGather > 0 then
            ratio = math.max(0, math.min(1, (hoursNow - (detail.createdAt or hoursNow)) / totalGather))
        end
    elseif state == 'RUNNING' then
        local startH = detail.startedAt or detail.createdAt or hoursNow
        local endH = detail.stage and detail.stage.sharedEnd or detail.endsAt or hoursNow
        if endH > startH then
            ratio = math.max(0, math.min(1, (hoursNow - startH) / (endH - startH)))
        end
    elseif state == 'CLOSED' then
        ratio = 1
    end

    if ratio > 0 then
        Theme.rect(owner, x + pad + 4, barY, math.floor(barW * ratio), barH, badgeCol)
    end

    -- 3. Benefit Status Strip (Strictly truthful)
    local noteY = barY + barH + 4
    local benefitNote = state == 'CLOSED' and (Presentation.outcomeText(detail.outcome) .. ' · ' .. t('benefitDebriefNotice'))
        or Presentation.benefitText(nil, state, nil)
    Theme.text(owner, benefitNote, x + pad + 4, noteY, { r = 0.45, g = 0.75, b = 0.55, a = 0.9 }, UIFont.Small)
end

---Draws a single resident card inside the live presence grid.
---@param owner ISPanel
---@param x number
---@param y number
---@param width number
---@param height number
---@param name string
---@param role string?
---@param member table
---@param isSpeaker boolean
---@param isOrganizer boolean
function Board.drawResidentCard(owner, x, y, width, height, name, role, member, isSpeaker, isOrganizer)
    local fh = owner.fontHeight or 18
    local pad = owner.pad or 8

    Theme.rect(owner, x, y, width, height, Theme.panel)
    Theme.rect(owner, x, y, width, height, Theme.border, true)

    local state = member.settled and 'SETTLED' or member.withdrawn and 'REJECTED' or member.joined and 'READY'
        or member.state == 'ACCEPTED' and 'ADMITTED' or member.attendanceState or 'WAIT'
    local badge = Presentation.statusBadge(state, member.reason)

    -- Status accent line
    local col = badge.badgeType == 'READY' and { r = 0.35, g = 0.75, b = 0.45, a = 1 }
        or badge.badgeType == 'ADMITTED' and { r = 0.25, g = 0.65, b = 0.85, a = 1 }
        or badge.badgeType == 'TRAVELLING' and { r = 0.35, g = 0.55, b = 0.75, a = 1 }
        or badge.badgeType == 'ALERT' and { r = 0.85, g = 0.35, b = 0.25, a = 1 }
        or Theme.muted
    Theme.rect(owner, x, y, 3, height, col)

    local cx = x + pad + 4
    local cy = y + 4

    -- 1. Name & Role
    local roleTag = isSpeaker and (' · ' .. t('speaker')) or isOrganizer and (' · ' .. t('organizer')) or (role and (' · ' .. role) or '')
    Theme.text(owner, name .. roleTag, cx, cy, Theme.textColor, UIFont.Small)

    -- Badge pill
    local badgeText = badge.text or ''
    local bw = (getTextManager and getTextManager():MeasureStringX(UIFont.Small, badgeText) or (#badgeText * 8)) + 8
    local bx = x + width - bw - pad
    Theme.rect(owner, bx, cy, bw, fh, { r = 0.12, g = 0.16, b = 0.20, a = 0.9 })
    Theme.rect(owner, bx, cy, bw, fh, col, true)
    Theme.text(owner, badgeText, bx + 4, cy, col, UIFont.Small)

    cy = cy + fh + 2

    -- 2. State description / blocking reason
    local desc = badge.desc or ''
    if #desc > 0 then
        Theme.text(owner, desc, cx, cy, Theme.muted, UIFont.Small)
        cy = cy + fh
    end

    -- 3. Accrued participation hours
    local minutes = math.floor((member.participationHours or 0) * 60 + 0.5)
    if minutes > 0 or member.joined then
        Theme.text(owner, t('participationHoursLabel', minutes), cx, cy, { r = 0.45, g = 0.85, b = 0.55, a = 1 }, UIFont.Small)
    end
end

return Board
