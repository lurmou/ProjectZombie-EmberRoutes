-- SettlementOverviewRender.lua - EmberRoutes UI
-- Prerender: kinetic micro-motion advance (gears / odometer / dial) and the
-- left-card / drive-strip draw pass, plus the edit-area and auto-zone
-- docked actions.
-- Attached to EmberRoutesSettlementOverviewPage by SettlementOverviewPage.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the page module). Moved verbatim from the
-- pre-split SettlementOverviewPage.lua (P1-9); behaviour unchanged.

local Theme = require 'EmberRoutesProbe/UI/Theme'
local CardPanel = require 'EmberRoutesProbe/UI/CardPanel'
local StatMeter = require 'EmberRoutesProbe/UI/StatMeter'
local StatusVisual = require 'EmberRoutesProbe/UI/StatusVisual'
local SemanticBadge = require 'EmberRoutesProbe/UI/SemanticBadge'
local MechanicalGears = require 'EmberRoutesProbe/UI/MechanicalGears'
local MechanicalRoller = require 'EmberRoutesProbe/UI/MechanicalRoller'
local RadialDial = require 'EmberRoutesProbe/UI/RadialDial'
local Toast = require 'EmberRoutesProbe/UI/ToastManager'
local C = require 'EmberRoutesProbe/UI/SettlementOverviewConstants'

---@param Page EmberRoutesSettlementOverviewPage
local function attach(Page)
    function Page:prerender()
        ISPanel.prerender(self)
        local h, p = self.fontHeight, self.pad
        local left = self.leftBounds
        local stockBounds = self.leftStockBounds
        local vitalsBounds = self.leftVitalsBounds
        if not left or not stockBounds or not vitalsBounds then return end

        -- 1. Advance every mechanism that is drawn in this same pass. No update
        --    without a matching draw, and no hand-written interpolation here.
        MechanicalGears.update(self.gearsState, self.cachedData.workingCount > 0, 1.0)
        MechanicalRoller.update(self.popRollerState, self.cachedData.popCount)
        RadialDial.update(self.defenseDialState, self.cachedData.defenseRatio)

        -- 2. Render Left Pane Card 1: Settlement Vitals (100% matched to screenshot)
        local cardGap = p
        local vitalsH = vitalsBounds.height
        local stockH  = stockBounds.height
        local stockY  = stockBounds.y

        CardPanel.draw(self, left.x, left.y, left.width, vitalsH, self.cardVitalsOptions)

        if self.cachedVitalsHeader then
            local head = self.cachedVitalsHeader
            Theme.text(self, head.popText, head.x, head.y, Theme.textColor, UIFont.Small)
        end
        if self.cachedPopRoller then
            local r = self.cachedPopRoller
            MechanicalRoller.draw(self, r.x, r.y, self.popRollerState, C.ROLLER_OPTS)
        end

        if self.cachedWorkBadge then
            local b = self.cachedWorkBadge
            SemanticBadge.draw(self, b.x, b.y, b.width, b.height, b)
        end

        if self.cachedLeisureBadge then
            local b = self.cachedLeisureBadge
            SemanticBadge.draw(self, b.x, b.y, b.width, b.height, b)
        end

        if self.cachedWorkforceSplit then
            local s = self.cachedWorkforceSplit
            StatMeter.drawSplitBar(self, s.x, s.y, s.width, s.height, s.ratio, s.opts)
        end

        if self.cachedInjuredJump then
            local j = self.cachedInjuredJump
            Theme.rect(self, j.x, j.y, j.width, j.height, C.INJURY_JUMP_BG)
            Theme.rect(self, j.x, j.y, j.width, j.height, Theme.status.ERROR, true)
            Theme.text(self, j.text, j.tx, j.ty, Theme.status.ERROR, UIFont.Small)
            StatusVisual.mark(self, j.leadX, j.markY, j.markSize, "chevronUp", Theme.status.ERROR)
            StatusVisual.mark(self, j.trailX, j.markY, j.markSize, "transit", Theme.status.ERROR)
        end

        -- 3. Render Left Pane Card 2: Core Stockpile Reserves (100% matched to screenshot)
        CardPanel.draw(self, left.x, stockY, left.width, stockH, self.cardStockpileOptions)

        for _, item in ipairs(self.cachedStockpileLines or {}) do
            if item.key then
                StatusVisual.icon(self, item.iconX, item.iconY, item.iconSize, item.key)
            end
            Theme.text(self, item.label, item.labelX, item.y, Theme.textColor, UIFont.Small)
            StatMeter.draw(self, item.barX, item.barY, item.barW, item.barH, item.fraction, item.meterOpts)
            Theme.text(self, item.valText, item.valX, item.y, item.valColor, UIFont.Small)
        end

        if self.cachedStockpileFooter then
            local foot = self.cachedStockpileFooter
            Theme.text(self, foot.burnText, foot.x, foot.y1, foot.burnColor, UIFont.Small)
            Theme.text(self, foot.breakdownText, foot.x, foot.y2, foot.breakdownColor, UIFont.Small)
        end
        if self.leftActionBounds then
            Theme.rect(self, left.x, self.leftActionBounds.y - math.floor(self.pad / 2), left.width, 1, {r = 0.25, g = 0.35, b = 0.45, a = 0.40})
        end

        -- 3b. Readiness / alert card: 16-segment radial dial plus alert detail
        --     rows or an explicit empty state. This is what the leftover height
        --     used to waste as an empty stretched stockpile card.
        local a = self.cachedAlerts
        if a then
            CardPanel.draw(self, a.x, a.y, a.width, a.height, a.opts)
            RadialDial.draw(self, a.dialCx, a.dialCy, a.dialRadius,
                self.defenseDialState.current, a.dialOpts)
            Theme.text(self, a.hintText, a.hintX, a.hintY, Theme.muted, UIFont.Small)
            for _, line in ipairs(a.lines) do
                Theme.text(self, line.text, line.x, line.y, line.color, UIFont.Small)
            end
        end

        -- 4. Render Right Top Pane: Production Drive & Logistics Pipeline (Slim 28px Status Strip)
        local d = self.cachedDriveStrip
        if d then
            Theme.rect(self, d.x, d.y, d.width, d.height, C.DRIVE_STRIP_BG)
            Theme.rect(self, d.x, d.y, d.width, d.height, Theme.border, true)

            -- Mini kinetic gear indicator (radius 7px, centered at y + 14)
            MechanicalGears.draw(self, d.gearCx or (d.x + 18), d.gearCy or (d.y + 14), self.gearsState, C.DRIVE_GEAR_OPTS)

            Theme.text(self, d.titleText, d.titleX, d.titleY, Theme.textColor, UIFont.Small)
            if d.descText then
                Theme.text(self, d.descText, d.descX, d.titleY, Theme.muted, UIFont.Small)
            end
            SemanticBadge.draw(self, d.badgeX, d.badgeY, 84, 18, d.badge)
        end
    end


    function Page:onEditArea()
        local actor = self.actor
        local entry = self.entry
        if not actor or not entry then return end
        local Ledger = require "EmberRoutesProbe/Settlement/SettlementLedger"
        local freshEntry = Ledger.get(entry.id) or entry
        local Selector = require "EmberRoutesProbe/UI/SettlementSelector"
        if self.owner and self.owner.close then self.owner:close() end
        Selector.open(actor, freshEntry, function(updated)
            require("EmberRoutesProbe/UI/SettlementDashboard").open(actor, updated.id)
        end)
    end

    function Page:onAutoZone()
        local actor = self.actor
        local entry = self.entry
        if not actor or not entry then return end
        local Ledger = require "EmberRoutesProbe/Settlement/SettlementLedger"
        local freshEntry = Ledger.get(entry.id) or entry
        local prompt = getText("IGUI_EmberRoutesProbe_Warehouse_autoZonePrompt")
        local Modal = require "EmberRoutesProbe/UI/ModalDialog"
        Modal.confirm(actor, {
            title = getText("IGUI_EmberRoutesProbe_Warehouse_autoZoneBtn"),
            message = prompt,
            width = 420,
            height = 160,
            onConfirm = function()
                local Batch = require "EmberRoutesProbe/Warehouse/BatchStoragePainting"
                local containers = Batch.scanSettlement(freshEntry)
                if #containers == 0 then
                    Toast.show(getText("IGUI_EmberRoutesProbe_Warehouse_autoZoneEmpty"), "warning")
                    actor:Say(getText("IGUI_EmberRoutesProbe_Warehouse_autoZoneEmpty"))
                    return
                end
                local result = Batch.apply(containers, "auto", actor)
                local msg = getText("IGUI_EmberRoutesProbe_Warehouse_autoZoneSuccess", tostring(result.updated))
                Toast.show(msg, "success")
                actor:Say(msg)
            end
        })
    end
end

return attach
