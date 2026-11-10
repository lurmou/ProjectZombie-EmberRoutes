-- SettlementOverviewPresentation.lua - EmberRoutes UI
-- Presentation cache projection (zero-GC): precomputes every string,
-- measurement, colour and bound the prerender pass draws, so render
-- itself allocates nothing.
-- Attached to EmberRoutesSettlementOverviewPage by SettlementOverviewPage.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the page module). Moved verbatim from the
-- pre-split SettlementOverviewPage.lua (P1-9); behaviour unchanged.

local Theme = require 'EmberRoutesProbe/UI/Theme'
local SemanticBadge = require 'EmberRoutesProbe/UI/SemanticBadge'
local MechanicalRoller = require 'EmberRoutesProbe/UI/MechanicalRoller'
local SupplyEstimate = require 'EmberRoutesProbe/Warehouse/SupplyEstimate'
local C = require 'EmberRoutesProbe/UI/SettlementOverviewConstants'

local function attach(Page)
    ---Precomputes all strings, measurements and colors in state updates to guarantee Zero-GC in render.
    function Page:updatePresentationCache()
        local h, p = self.fontHeight, self.pad
        local left = self.leftBounds
        local stockBounds = self.leftStockBounds
        local vitalsBounds = self.leftVitalsBounds
        if not left or not left.width or left.width <= 0 or not stockBounds or not vitalsBounds then return end

        local cardGap = p
        local vitalsH = vitalsBounds.height
        local stockH  = stockBounds.height
        local stockY  = stockBounds.y

        local vitals = self.store.value.vitals
        local hasInjury = (vitals.injured > 0 or vitals.infected > 0)
        local cardW = left.width - p * 2

        -- 1. Population headline: the number itself is the mechanical odometer,
        --    so the text keeps only its label (no duplicated readout).
        local popY = left.y + h + math.floor(p / 2)
        self.cachedVitalsHeader = {
            popText = getText('IGUI_EmberRoutesProbe_Overview_population'),
            x = left.x + p,
            y = popY
        }
        local rollerW = MechanicalRoller.measureWidth(3, C.ROLLER_OPTS.digitWidth, C.ROLLER_OPTS.gap)
        self.cachedPopRoller = {
            x = left.x + left.width - p - rollerW,
            y = popY - 4
        }

        -- 2. Dual Indicators: Work & Leisure Badges (Scheme B - Layer 1, SemanticBadge reuse)
        local badgeGap = 6
        local badgeW = math.floor((cardW - badgeGap) / 2)
        local badgeH = h + 4
        local badgeY = popY + h + math.floor(p * 0.5)

        local workLabel = tostring(vitals.working) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_working')
        local leisureLabel = tostring(vitals.idle) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_leisure')

        local workBadge = SemanticBadge.resolve('WORK', workLabel)
        workBadge.x = left.x + p
        workBadge.y = badgeY
        workBadge.width = badgeW
        workBadge.height = badgeH

        local leisureBadge = SemanticBadge.resolve('LEISURE', leisureLabel)
        leisureBadge.x = left.x + p + badgeW + badgeGap
        leisureBadge.y = badgeY
        leisureBadge.width = badgeW
        leisureBadge.height = badgeH

        self.cachedWorkBadge = workBadge
        self.cachedLeisureBadge = leisureBadge

        -- 3. Comparative Ratio Bar: Work vs Leisure (Scheme B - Layer 2, StatMeter.drawSplitBar reuse)
        local splitBarY = badgeY + badgeH + math.floor(p * 0.5)
        local splitBarH = 14
        local workRatio = vitals.population > 0 and math.min(1.0, vitals.working / vitals.population) or 0

        self.cachedWorkforceSplit = {
            x = left.x + p,
            y = splitBarY,
            width = cardW,
            height = splitBarH,
            ratio = workRatio,
            opts = {
                isEmpty = (vitals.population <= 0),
                colorA = Theme.accent or {r = 0.25, g = 0.75, b = 1.00, a = 1.0},
                colorB = Theme.status.READY or {r = 0.35, g = 0.88, b = 0.60, a = 1.0}
            }
        }

        -- 4. Injured Settler 1-Click Jump Capsule
        if hasInjury and vitals.firstInjuredId then
            local jumpY = splitBarY + splitBarH + math.floor(p * 0.5)
            local jumpText = getText('IGUI_EmberRoutesProbe_Overview_locateInjured')
            local jumpTextW = getTextManager():MeasureStringX(UIFont.Small, jumpText)
            local tx = left.x + p + math.floor((cardW - jumpTextW) / 2)
            local markSize = 10
            self.cachedInjuredJump = {
                x = left.x + p,
                y = jumpY,
                width = cardW,
                height = h + 4,
                text = jumpText,
                tx = tx,
                ty = jumpY + 2,
                markSize = markSize,
                leadX = tx - markSize - 6,
                trailX = tx + jumpTextW + 6,
                markY = jumpY + math.floor((h + 4 - markSize) / 2),
                npcId = vitals.firstInjuredId
            }
        else
            self.cachedInjuredJump = nil
        end

        -- Card 2: Core Stockpile Inventory & Survival Projections with Mini-Gauges
        local stock = self.store.value.stockpile or SupplyEstimate.calculate({}, 0)
        local tm = getTextManager()

        local stockDefs = {
            {
                key = 'food',
                label = getText('IGUI_EmberRoutesProbe_Overview_foodSecurity'),
                valText = stock.hasPopulation
                    and (string.format("%.1f", stock.foodDays) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_unitDays') .. " (" .. tostring(stock.totalFoodCount) .. getText('IGUI_EmberRoutesProbe_Overview_unitPortion') .. ")")
                    or ("-- " .. getText('IGUI_EmberRoutesProbe_Overview_unitDays') .. " (" .. tostring(stock.totalFoodCount) .. getText('IGUI_EmberRoutesProbe_Overview_unitPortion') .. ")"),
                fillRatio = math.max(0, math.min(1.0, stock.foodDays / SupplyEstimate.SATURATION_DAYS)),
                isCritical = (stock.hasPopulation and stock.foodDays < 2.0 or stock.totalFoodCount <= 0),
                isWarning = (stock.hasPopulation and stock.foodDays < 5.0),
                defaultColor = C.STOCK_COLORS.meals
            },
            {
                key = 'water',
                label = getText('IGUI_EmberRoutesProbe_Overview_waterSecurity'),
                valText = stock.hasPopulation
                    and (string.format("%.1f", stock.waterDays) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_unitDays') .. " (" .. tostring(stock.waterCount) .. getText('IGUI_EmberRoutesProbe_Overview_unitPortion') .. ")")
                    or ("-- " .. getText('IGUI_EmberRoutesProbe_Overview_unitDays') .. " (" .. tostring(stock.waterCount) .. getText('IGUI_EmberRoutesProbe_Overview_unitPortion') .. ")"),
                fillRatio = math.max(0, math.min(1.0, stock.waterDays / SupplyEstimate.SATURATION_DAYS)),
                isCritical = (stock.hasPopulation and stock.waterDays < 2.0 or stock.waterCount <= 0),
                isWarning = (stock.hasPopulation and stock.waterDays < 5.0),
                defaultColor = C.STOCK_COLORS.water
            },
            {
                key = 'medical',
                label = getText('IGUI_EmberRoutesProbe_Overview_medical'),
                valText = tostring(stock.medicalCount) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_unitPortion'),
                fillRatio = math.max(0, math.min(1.0, stock.medicalCount / 30.0)),
                isCritical = (stock.medicalCount <= 0),
                isWarning = false,
                defaultColor = C.STOCK_COLORS.medical
            },
            {
                key = 'wood',
                label = getText('IGUI_EmberRoutesProbe_Overview_wood'),
                valText = tostring(stock.woodCount) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_unitCount'),
                fillRatio = math.max(0, math.min(1.0, stock.woodCount / 100.0)),
                isCritical = (stock.woodCount <= 0),
                isWarning = false,
                defaultColor = C.STOCK_COLORS.wood
            }
        }

        local stockGauges = {}
        local sy = stockY + h + p
        local iconSize = 14
        local iconGap = 5
        local labelColW = math.floor(cardW * 0.38)
        local barW = math.floor(cardW * 0.28)
        local barH = 8

        for _, st in ipairs(stockDefs) do
            local valWidth = tm and tm:MeasureStringX(UIFont.Small, st.valText) or 60
            local barColor = st.isCritical and Theme.status.ERROR
                          or (st.isWarning and Theme.status.UPDATING or st.defaultColor)

            stockGauges[#stockGauges + 1] = {
                key = st.key,
                iconX = left.x + p,
                iconY = sy + math.floor((h - iconSize) / 2),
                iconSize = iconSize,
                label = st.label,
                labelX = left.x + p + iconSize + iconGap,
                valText = st.valText,
                valX = left.x + cardW + p - valWidth,
                valColor = st.isCritical and Theme.status.ERROR or Theme.textColor,
                barX = left.x + p + labelColW + 4,
                barY = sy + math.floor((h - barH) / 2),
                barW = barW,
                barH = barH,
                fraction = st.fillRatio,
                meterOpts = {
                    mode = "progress",
                    threshold = 0.2,
                    color = barColor
                },
                y = sy
            }
            sy = sy + h + math.floor(p * 0.6)
        end
        self.cachedStockpileLines = stockGauges

        local badgeText, badgeColor
        if not stock.hasPopulation then
            badgeText = getText('IGUI_EmberRoutesProbe_Overview_badgeEmpty')
            badgeColor = Theme.status.MUTED
        elseif stock.status == "CRITICAL" then
            badgeText = getText('IGUI_EmberRoutesProbe_Overview_badgeCritical')
            badgeColor = Theme.status.ERROR
        elseif stock.status == "WARNING" then
            badgeText = getText('IGUI_EmberRoutesProbe_Overview_badgeWarning')
            badgeColor = Theme.status.UPDATING

        else
            badgeText = getText('IGUI_EmberRoutesProbe_Overview_badgeSecure')
            badgeColor = Theme.status.READY
        end

        local vitalsBadgeText, vitalsBadgeColor
        if hasInjury then
            vitalsBadgeText = "^ " .. tostring(vitals.injured + vitals.infected) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_injured')
            vitalsBadgeColor = Theme.status.ERROR
        else
            vitalsBadgeText = getText('IGUI_EmberRoutesProbe_Overview_settlementStable')
            vitalsBadgeColor = Theme.status.READY
        end

        self.cardVitalsOptions = self.cardVitalsOptions or {
            title = getText('IGUI_EmberRoutesProbe_Overview_vitalsTitle'),
            frameStyle = 'briefing'
        }
        self.cardVitalsOptions.title = getText('IGUI_EmberRoutesProbe_Overview_vitalsTitle')
        self.cardVitalsOptions.badge = vitalsBadgeText
        self.cardVitalsOptions.badgeColor = vitalsBadgeColor

        self.cardStockpileOptions = self.cardStockpileOptions or {
            title = getText('IGUI_EmberRoutesProbe_Overview_stockpileTitle'),
            frameStyle = 'briefing'
        }
        self.cardStockpileOptions.title = getText('IGUI_EmberRoutesProbe_Overview_stockpileTitle')
        self.cardStockpileOptions.badge = badgeText
        self.cardStockpileOptions.badgeColor = badgeColor

        local burnText = stock.hasPopulation
            and getText('IGUI_EmberRoutesProbe_Overview_dailyBurn',
                string.format("%.1f", stock.foodDailyDemand),
                string.format("%.1f", stock.waterDailyDemand),
                tostring(stock.population))
            or getText('IGUI_EmberRoutesProbe_Overview_noSettlersBurn')

        local breakdownText = getText('IGUI_EmberRoutesProbe_Overview_stockBreakdown',
            tostring(stock.mealsCount), tostring(stock.cropsCount))

        local footerY1 = math.max(sy + 4, stockY + stockH - p - h * 2 - 2)
        local footerY2 = footerY1 + h

        self.cachedStockpileFooter = {
            burnText = burnText,
            breakdownText = breakdownText,
            x = left.x + p,
            y1 = footerY1,
            y2 = footerY2,
            burnColor = Theme.muted or Theme.textColor,
            breakdownColor = Theme.muted or Theme.textColor
        }

        -- 5. Production drive strip: text, measurement and badge resolution are
        -- derived here so prerender stays a pure draw pass (no JNI measurement,
        -- no string concatenation, no table allocation per frame).
        local db = self.rightDriveBounds
        if db then
            local driveTitle = getText('IGUI_EmberRoutesProbe_Overview_driveTitle')
            local titleW = tm and tm:MeasureStringX(UIFont.Small, driveTitle) or 70
            local activeDesc
            if self.cachedData.workingCount > 0 then
                activeDesc = "  " .. tostring(self.cachedData.workingCount) .. " "
                    .. getText('IGUI_EmberRoutesProbe_Overview_driveActiveWorkers')
            end
            -- The filter chip is the single red "blocked" entry point. The drive
            -- badge reports only the mechanical running / standby state, so a
            -- blocked order no longer paints the same alert twice.
            local tone = self.cachedData.workingCount > 0 and 'PROCESSING' or 'WAITING'
            local label = self.cachedData.workingCount > 0
                and getText('IGUI_EmberRoutesProbe_Overview_driveRunning')
                or getText('IGUI_EmberRoutesProbe_Overview_driveIdle')
            self.cachedDriveStrip = {
                x = db.x, y = db.y, width = db.width, height = db.height,
                titleText = driveTitle,
                gearCx = db.x + 18,
                gearCy = db.y + math.floor(db.height / 2),
                titleX = db.x + 40,
                titleY = db.y + math.floor((db.height - h) / 2),
                descText = activeDesc,
                descX = db.x + 40 + titleW,
                badge = SemanticBadge.resolve(tone, label),
                badgeX = db.x + db.width - 92,
                badgeY = db.y + math.floor((db.height - 18) / 2)
            }
        else
            self.cachedDriveStrip = nil
        end

        -- 6. Readiness / alert card: the radial dial needs >= 72px, so it lives
        --    here rather than in the 28px drive header. Leftover height that used
        --    to be an empty stretched card now carries alert details or an empty state.
        local ab = self.leftAlertsBounds
        if ab then
            self.cardAlertsOptions = self.cardAlertsOptions or {frameStyle = 'briefing'}
            self.cardAlertsOptions.title = getText('IGUI_EmberRoutesProbe_Overview_readinessTitle')
            local radius = 36
            local headerH = h + math.max(4, math.floor(h * 0.4))
            local counts = self.store.value.counts or {}
            local blockedN = counts.blocked or 0
            local injuredN = (vitals.injured or 0) + (vitals.infected or 0)
            local lines = {}
            if blockedN > 0 then
                lines[#lines + 1] = {text = getText('IGUI_EmberRoutesProbe_Overview_alertBlocked', tostring(blockedN)), color = Theme.status.ERROR}
            end
            if injuredN > 0 then
                lines[#lines + 1] = {text = getText('IGUI_EmberRoutesProbe_Overview_alertInjured', tostring(injuredN)), color = Theme.status.UPDATING}
            end
            if #lines == 0 then
                lines[1] = {text = getText('IGUI_EmberRoutesProbe_Overview_noAlerts'), color = Theme.muted}
            end
            for i, line in ipairs(lines) do
                line.x = ab.x + p + radius * 2 + p * 2
                line.y = ab.y + headerH + 12 + (i - 1) * (h + 6)
            end
            self.cachedAlerts = {
                x = ab.x, y = ab.y, width = ab.width, height = ab.height,
                opts = self.cardAlertsOptions,
                dialCx = ab.x + p + radius + 4,
                dialCy = ab.y + headerH + radius + 4,
                dialRadius = radius, dialOpts = C.DIAL_OPTS,
                hintText = getText('IGUI_EmberRoutesProbe_Overview_readinessHint'),
                hintX = ab.x + p + 4,
                hintY = ab.y + headerH + radius * 2 + 10,
                lines = lines
            }
        else
            self.cachedAlerts = nil
        end

        self.cachedEndRule = nil
    end
end

return attach
