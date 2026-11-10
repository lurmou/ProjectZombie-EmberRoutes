-- SettlementOverviewOrderRow.lua - EmberRoutes UI
-- Order row drawing: route label projection (named area + compass bearing)
-- and the base order card plus its seam-welded expanding drawer.
-- Attached to EmberRoutesSettlementOverviewPage by SettlementOverviewPage.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the page module). Moved verbatim from the
-- pre-split SettlementOverviewPage.lua (P1-9); behaviour unchanged.

local Theme = require 'EmberRoutesProbe/UI/Theme'
local Cards = require 'EmberRoutesProbe/UI/OrderMonitorCards'
local StatusVisual = require 'EmberRoutesProbe/UI/StatusVisual'
local SemanticBadge = require 'EmberRoutesProbe/UI/SemanticBadge'
local StatMeter = require 'EmberRoutesProbe/UI/StatMeter'
local InlineCardDrawer = require 'EmberRoutesProbe/UI/InlineCardDrawer'
local C = require 'EmberRoutesProbe/UI/SettlementOverviewConstants'

local function attach(Page)
    ---Project a world route into a user-facing named area plus a compass bearing.
    ---Raw tile coordinates are an internal identifier, never player-facing copy.
    function Page:formatRouteLabel(item, row)
        local cached = row._cachedLocStr
        if cached ~= nil then return cached or nil end

        local scope = self.entry and self.entry.id
        local fallback = (self.entry and type(self.entry.name) == 'string' and self.entry.name ~= '' and self.entry.name)
            or getText('IGUI_EmberRoutesProbe_Overview_routeAreaFallback')

        local function nameOf(point)
            if type(point) == 'string' and point ~= '' then return point end
            if type(point) == 'table' and type(point.x) == 'number' and type(point.y) == 'number' then
                return C.areaNameAt(scope, point.x, point.y, point.z) or fallback
            end
            return nil
        end

        local tLoc = item.targetLocation or row.targetLocation
        local source = row.source or item.source
        local destination = row.destination or item.destination
        local target = nameOf(tLoc) or nameOf(destination)
        if not target and (item.category == 'farming' or row.workCategory == 'farming') then
            target = getText('IGUI_EmberRoutesProbe_Public_farming')
        end

        local detail = ''
        local to = destination
        if type(tLoc) == 'table' and tLoc.x and tLoc.y then to = tLoc end
        if type(source) == 'table' and type(to) == 'table'
            and type(source.x) == 'number' and type(source.y) == 'number'
            and type(to.x) == 'number' and type(to.y) == 'number' then
            local dx, dy = to.x - source.x, to.y - source.y
            if dx ~= 0 or dy ~= 0 then
                local tiles = tostring(math.floor(math.sqrt(dx * dx + dy * dy) + 0.5))
                detail = getText('IGUI_EmberRoutesProbe_Overview_routeBearing',
                    C.DIRECTION_LABELS[C.compassOf(dx, dy)],
                    getText('IGUI_EmberRoutesProbe_Overview_routeTiles', tiles))
            end
        end

        local sourceName = nameOf(source)
        local result
        if target then
            result = getText('IGUI_EmberRoutesProbe_Overview_routeTarget', target, detail)
        elseif sourceName then
            result = getText('IGUI_EmberRoutesProbe_Overview_routeSource', sourceName)
        end
        row._cachedLocStr = result or false
        return result
    end

    function Page:drawOrderRow(list, y, entry)
        local item = entry.item and (entry.item.value or entry.item)
        if not item then return y + (entry.height or C.BASE_CARD_H) end

        local hasScroll = list.isVScrollBarVisible and list:isVScrollBarVisible()
        local cardW = list:getWidth() - (hasScroll and 6 or 0)
        local isExpanded = (self.expandedKey == (item.key or item.id))
        local drawerH = isExpanded and self:getDrawerHeight(item) or 0
        local targetH = isExpanded and (C.BASE_CARD_H + drawerH) or C.BASE_CARD_H
        entry.height = targetH

        -- 1. Draw Base Order Card Header & Outer Border
        local isSelected = (list.selected == entry.index)
        local bgA = isSelected and 0.88 or 0.65
        local bgCol = {r = 0.08, g = 0.10, b = 0.13, a = bgA}
        local borderCol = isSelected and Theme.accent or Theme.border

        Theme.rect(list, 0, y, cardW, C.BASE_CARD_H, bgCol)
        if not isExpanded then
            Theme.rect(list, 0, y, cardW, C.BASE_CARD_H, borderCol, true)
        else
            -- Unified continuous outer container frame wrapping header + drawer in one piece
            Theme.rect(list, 0, y, cardW, targetH, borderCol, true)
        end

        -- Status accent pill
        local stCol = (item.state == 'working' and Theme.status.SUCCESS)
                   or (item.state == 'blocked' and Theme.status.ERROR)
                   or (item.state == 'paused'  and Theme.status.WARNING)
                   or Theme.status.MUTED
        Theme.rect(list, 2, y + 2, 4, C.BASE_CARD_H - 4, stCol)

        -- Titles & Worker (Zero-GC Cached Strings & Measured Dimensions)
        local tm = getTextManager()
        local title = item.title or getText("IGUI_EmberRoutesProbe_Overview_noOrders")
        Theme.text(list, title, 14, y + 8, Theme.textColor, UIFont.Small)

        local row = item.row or {}
        if row.targetCount and row.targetCount > 0 then
            if item._cachedCountText == nil or item._cachedTargetCount ~= row.targetCount then
                item._cachedTargetCount = row.targetCount
                item._cachedCountText = tostring(row.targetCount) .. " " .. getText("IGUI_EmberRoutesProbe_Overview_unitCount")
                item._cachedCountW = tm and tm:MeasureStringX(UIFont.Small, item._cachedCountText) or 24
                item._cachedTitleW = tm and tm:MeasureStringX(UIFont.Small, title) or (#title * 8)
                item._cachedCountX = 14 + item._cachedTitleW + 8
            end
            local countX = item._cachedCountX
            local countW = item._cachedCountW
            if countX + countW + 12 < cardW - 130 then
                Theme.rect(list, countX, y + 7, countW + 12, 16, Theme.control)
                Theme.rect(list, countX, y + 7, countW + 12, 16, Theme.border, true)
                Theme.text(list, item._cachedCountText, countX + 6, y + 8, Theme.muted, UIFont.Small)
            end
        end

        if item._cachedWorkerText == nil or item._cachedWorkerName ~= item.workerName then
            item._cachedWorkerName = item.workerName
            item._cachedWorkerText = item.workerName
                and (getText("IGUI_EmberRoutesProbe_Overview_worker") .. ": " .. item.workerName)
                or getText("IGUI_EmberRoutesProbe_Distributed_unassigned")
        end
        local workerCol = item.workerInjured and Theme.status.ERROR or {r = 0.65, g = 0.72, b = 0.80, a = 0.90}
        Theme.text(list, item._cachedWorkerText, 14, y + 28, workerCol, UIFont.Small)
        if not isExpanded then
            local assets = self:getGroupedAssets(row)
            if assets and #assets > 0 and assets[1] then
                local firstAsset = assets[1]
                local assetSummary = firstAsset.displayName or firstAsset.name
                if assetSummary then
                    local workerW = tm and tm:MeasureStringX(UIFont.Small, item._cachedWorkerText) or (#item._cachedWorkerText * 8)
                    local assetX = 14 + workerW + 14
                    if assetX + 60 < cardW - 130 then
                        -- 1px geometric divider instead of a visible pipe character.
                        Theme.rect(list, assetX - 8, y + 31, 1, 10, Theme.border)
                        Theme.text(list, assetSummary, assetX, y + 28, Theme.muted, UIFont.Small)
                    end
                end
            end
        end

        -- Semantic Status Badge (Cached resolution)
        if item._cachedState ~= item.state or not item._cachedBadge then
            local stateKey = 'IGUI_EmberRoutesProbe_Distributed_' .. (item.state or 'idle')
            local stateLabel = (getTextOrNull and getTextOrNull(stateKey)) or (getText and getText(stateKey)) or (item.state or 'idle')
            local mappedTone = (item.state == 'working' and 'PROCESSING')
                            or (item.state == 'blocked' and 'DISCREPANCY')
                            or (item.state == 'paused'  and 'PAUSED')
                            or 'WAITING'
            item._cachedBadge = SemanticBadge.resolve(mappedTone, stateLabel)
            item._cachedState = item.state
        end
        local padX = 10
        local inW = cardW - padX * 2
        SemanticBadge.draw(list, cardW - padX - 86, y + math.floor((C.BASE_CARD_H - 18) / 2), 76, 18, item._cachedBadge)

        -- Expand indicator: geometric chevron from the shared status visual module.
        local markSize = 10
        StatusVisual.mark(list, cardW - padX - 6, y + 10, markSize,
            isExpanded and "chevronUp" or "chevronDown", Theme.accent)

        -- 2. If Expanded: Draw Unified Integrated Drawer
        if isExpanded then
            local shelfY = y + C.BASE_CARD_H
            local shelfH = drawerH
            local bgDrawer = {r = 0.05, g = 0.07, b = 0.09, a = 0.95}

            -- Drawer container background (seamlessly inset within outer continuous border)
            Theme.rect(list, 1, shelfY, cardW - 2, shelfH - 1, bgDrawer)

            -- Subtle inner soft divider line (inset, low contrast, zero harsh yellow border)
            Theme.rect(list, padX, shelfY, inW, 1, {r = borderCol.r, g = borderCol.g, b = borderCol.b, a = 0.18})

            local curY = shelfY + 8

            -- A. Route information projected to a named area + compass bearing.
            local locStr = self:formatRouteLabel(item, row)
            if locStr then
                Theme.text(list, locStr, padX + 4, curY, {r = 0.85, g = 0.90, b = 0.95, a = 0.95}, UIFont.Small)
                curY = curY + 22
            else
                curY = curY + 16
            end

            -- B. Pipeline Lifecycle Steps (StatusVisual PREPARE -> WORK -> COLLECT -> DELIVER or domain stages)
            local stages = (row.stages and #row.stages > 0) and Cards.stageNames(row) or C.STAGE_LABELS
            local currentPhase = row.phase or (item.state == 'working' and 'WORK' or 'PREPARE')
            local stageIdx = (row.stages and #row.stages > 0) and Cards.phaseIndex(row)
                or (C.STAGE_INDEX[currentPhase] or (currentPhase == 'COLLECT' and 3 or (currentPhase == 'DELIVER' and 4 or (item.state == 'working' and 2 or 1))))
            local visualState = (item.state == 'blocked') and 'blocked' or ((item.state == 'paused') and 'paused' or 'active')
            local trackSig = tostring(stageIdx) .. ":" .. tostring(visualState) .. ":" .. tostring(inW)
            if row.stages then
                for _, s in ipairs(row.stages) do
                    trackSig = trackSig .. "|" .. tostring(s.key) .. ":" .. tostring(s.status) .. ":" .. tostring(s.progress)
                end
            end
            if row._cachedTrackSig ~= trackSig or not row._cachedTrack then
                row._cachedTrackSig = trackSig
                local kinds
                if row.stages and #row.stages > 0 then
                    kinds = {}
                    for _, s in ipairs(row.stages) do
                        kinds[#kinds + 1] = C.CUSTOM_STAGE_GLYPHS[s.labelKey or ""]
                    end
                else
                    kinds = C.DEFAULT_STAGE_GLYPHS
                end
                row._cachedTrack = StatusVisual.steps(stages, inW, self.fontHeight, self.pad, stageIdx, visualState, kinds)
            end
            StatusVisual.drawSteps(list, padX, curY, row._cachedTrack)
            curY = curY + row._cachedTrack.height + 6

            -- C. BOM Items Material Table OR Progress Bar
            local assets = self:getGroupedAssets(row)
            if assets and #assets > 0 then
                local maxItems = math.min(3, #assets)
                local podH = maxItems * 24 + ((#assets > 3) and 20 or 0)
                Theme.rect(list, padX, curY, inW, podH, {r = 0.06, g = 0.08, b = 0.11, a = 0.80})
                Theme.rect(list, padX, curY, inW, podH, {r = 0.20, g = 0.28, b = 0.38, a = 0.50}, true)
                for i = 1, maxItems do
                    local g = assets[i]
                    local icon = self.itemIcons and self.itemIcons:icon(g.fullType)
                    if icon then
                        list:drawTextureScaledAspect(icon, padX + 8, curY + 2, 18, 18, 1, 1, 1, 1)
                    end
                    Theme.text(list, g.displayName, padX + 32, curY + 4, Theme.textColor, UIFont.Small)
                    SemanticBadge.draw(list, cardW - padX - 98, curY + 2, 90, 18, g.badge)
                    curY = curY + 24
                end
                if #assets > 3 then
                    if not row._cachedMoreText or row._cachedMoreCount ~= (#assets - 3) then
                        row._cachedMoreCount = #assets - 3
                        row._cachedMoreText = "+ " .. tostring(row._cachedMoreCount) .. " " .. getText('IGUI_EmberRoutesProbe_Overview_unitCount') .. "..."
                    end
                    Theme.text(list, row._cachedMoreText, padX + 32, curY + 2, Theme.muted, UIFont.Small)
                    curY = curY + 20
                end
            elseif row.targetCount and row.targetCount > 0 then
                local curCount = row.deliveredCount or 0
                local fillRatio = math.max(0, math.min(1.0, curCount / row.targetCount))
                local progPrefix = getText('IGUI_EmberRoutesProbe_Overview_progress') .. ": "
                Theme.text(list, progPrefix, padX, curY, Theme.muted, UIFont.Small)
                local pfw = tm and tm:MeasureStringX(UIFont.Small, progPrefix) or 60
                local barW = math.min(200, inW - pfw - 140)
                local progLabel = tostring(curCount) .. " / " .. tostring(row.targetCount)
                StatMeter.draw(list, padX + pfw + 4, curY + 2, barW, 12, fillRatio, {
                    mode = "progress",
                    label = progLabel,
                    labelW = tm and tm:MeasureStringX(UIFont.Small, progLabel) or (#progLabel * 8)
                })
                curY = curY + 24
            elseif row.recipeName then
                if not row._cachedRecipeProgress then
                    row._cachedRecipeProgress = getText('IGUI_EmberRoutesProbe_Overview_progress') .. ": " .. tostring(row.recipeName)
                end
                Theme.text(list, row._cachedRecipeProgress, padX, curY, Theme.muted, UIFont.Small)
                curY = curY + 20
            end

            -- D. Virtual Action Buttons Dock (View Dossier & Stop Body Preemption)
            curY = curY + 8
            local btnH = 22
            local divY = curY
            Theme.rect(list, padX, divY, inW, 1, {r = borderCol.r, g = borderCol.g, b = borderCol.b, a = 0.18})
            local btnY = divY + 8
            item._cachedBtnY = btnY - shelfY

            -- Left: Colonist Identity Telemetry (Balances the dock)
            local npcId = item.npcId or row.npcId
            local workerName = item.workerName or (npcId and self:getNpcName(npcId))
            if workerName then
                StatusVisual.glyph(list, padX + 2, btnY + 4, 14, 'person', Theme.muted)
                Theme.text(list, workerName, padX + 20, btnY + 4, Theme.textColor, UIFont.Small)
            end

            local curX = cardW - padX

            if npcId then
                if not self._cachedDossierW then
                    self._cachedDossierLabel = getText('IGUI_EmberRoutesProbe_Overview_viewDossier')
                    local tw = tm and tm:MeasureStringX(UIFont.Small, self._cachedDossierLabel) or 72
                    self._cachedDossierTextW = tw
                    self._cachedDossierW = tw + 20
                end
                local bw = self._cachedDossierW
                local tw = self._cachedDossierTextW or (bw - 20)
                curX = curX - bw
                InlineCardDrawer.drawButton(list, curX, btnY, bw, btnH, self._cachedDossierLabel,
                    tw, self.fontHeight, Theme.control, Theme.border, Theme.textColor)
                curX = curX - 8
            end

            local canStop = (row.kind == 'FIELD_WORK' and row.jobId ~= nil and row.generation ~= nil and not row.closed and row.carrierAvailable and row.bucket == 'active') or (row.canPause == true)
            if canStop then
                if not self._cachedStopW then
                    self._cachedStopLabel = getText('IGUI_EmberRoutesProbe_Distributed_stopBody')
                    local tw = tm and tm:MeasureStringX(UIFont.Small, self._cachedStopLabel) or 80
                    self._cachedStopTextW = tw
                    self._cachedStopW = tw + 20
                end
                local bw = self._cachedStopW
                local tw = self._cachedStopTextW or (bw - 20)
                curX = curX - bw
                InlineCardDrawer.drawButton(list, curX, btnY, bw, btnH, self._cachedStopLabel,
                    tw, self.fontHeight, Theme.control, Theme.status.ERROR, Theme.status.ERROR)
            end
        end

        return y + targetH
    end
end

return attach
