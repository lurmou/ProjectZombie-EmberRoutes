-- SettlementOverviewOrders.lua - EmberRoutes UI
-- Order list state and interaction: 1s viewport heartbeat, filter
-- reconciliation, grouped-asset and drawer-height caches, row-height
-- updates, cumulative hit-testing / virtual drawer buttons, and the
-- injured-jump capsule + list mouse forwarding.
-- Attached to EmberRoutesSettlementOverviewPage by SettlementOverviewPage.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the page module). Moved verbatim from the
-- pre-split SettlementOverviewPage.lua (P1-9); behaviour unchanged.

local Cached = require 'EmberRoutesProbe/UI/CachedList'
local Cards = require 'EmberRoutesProbe/UI/OrderMonitorCards'
local SemanticBadge = require 'EmberRoutesProbe/UI/SemanticBadge'
local EmptyState = require 'EmberRoutesProbe/UI/EmptyState'
local WorkCommandAdapter = require 'EmberRoutesProbe/Work/WorkCommandAdapter'
local InlineCardDrawer = require 'EmberRoutesProbe/UI/InlineCardDrawer'
local C = require 'EmberRoutesProbe/UI/SettlementOverviewConstants'
local Clock = require 'EmberRoutesProbe/Kernel/Clock'

---@param Page EmberRoutesSettlementOverviewPage
local function attach(Page)
    function Page:update()
        ISPanel.update(self)
        if not self.active or self.disposed then return end
        -- Low-frequency 1.0s viewport heartbeat for intermediate native action polling
        local now = Clock.nowMs()
        if not self._lastCadencePulse or (now - self._lastCadencePulse) >= 1000 then
            self._lastCadencePulse = now
            self:refresh()
        end
    end

    function Page:updateFilteredList()
        if not self.orderList then return end
        local filter = self.activeFilter
        local works = self.store.value.works or {}
        local filtered = {}

        for _, item in ipairs(works) do
            local match = false
            if filter == 'all' then
                match = true
            elseif filter == 'blocked' and item.state == 'blocked' then
                match = true
            elseif filter == 'working' and (item.state == 'working' or item.state == 'running') then
                match = true
            elseif filter == 'waiting' and item.state ~= 'blocked' and item.state ~= 'working' and item.state ~= 'running' then
                match = true
            end

            if match then
                filtered[#filtered + 1] = item
            end
        end

        -- Reconcile into CachedList (Full domain signature for real-time custody & stage reactivity)
        Cached.reconcile(self.orderList, filtered, function(w)
            local sig = w.row and Cards.signature(w.row) or tostring(w.state or "idle")
            return tostring(w.key or w.id) .. ":" .. sig
        end, function(w)
            return tostring(w.key or w.id or w.title or w.name or "order")
        end, true)

        self:updateOrderRowHeights()
    end

    function Page:getGroupedAssets(row)
        if not row or not row.assets or #row.assets == 0 then return nil end
        local sig = tostring(row.phase or '') .. ":" .. tostring(row.delivered or 0) .. ":" .. tostring(row.reason or '')
        for _, a in ipairs(row.assets) do
            sig = sig .. "|" .. tostring(a.id or '') .. ":" .. tostring(a.custodyState or '') .. ":" .. tostring(a.delivered == true)
        end
        if row._cachedAssetSig == sig and row._groupedAssets then
            return row._groupedAssets
        end
        local grouped, list = {}, {}
        for _, asset in ipairs(row.assets) do
            local status = Cards.assetStatus(row, asset)
            local key = (asset.fullType or asset.displayName or '?') .. ':' .. (asset.kind or '') .. ':' .. status
            local group = grouped[key]
            if not group then
                local fullType = asset.fullType
                local getName = _G.getItemNameFromFullType
                local name = (fullType and type(getName) == "function" and getName(fullType))
                    or fullType or asset.displayName or getText('IGUI_EmberRoutesProbe_Monitor_unknownItem')
                local badgeDesc = SemanticBadge.resolve(status)
                group = {
                    asset = asset,
                    fullType = fullType,
                    name = name,
                    status = status,
                    badge = badgeDesc,
                    count = 0,
                    kind = asset.kind
                }
                grouped[key] = group
                list[#list + 1] = group
            end
            group.count = group.count + 1
        end
        local alerts = {RECONCILE = true, MISSING = true, DISCREPANCY = true}
        table.sort(list, function(a, b)
            local aa, bb = alerts[a.status] == true, alerts[b.status] == true
            if aa ~= bb then return aa end
            return tostring(a.name) < tostring(b.name)
        end)
        for _, g in ipairs(list) do
            local countStr = (g.count and g.count > 1) and (' x ' .. tostring(g.count)) or ' x 1'
            g.displayName = (g.name or '') .. countStr
        end
        row._cachedAssetSig = sig
        row._groupedAssets = list
        return list
    end

    function Page:getDrawerHeight(item)
        if not item then return 160 end
        local row = item.row or {}
        local assets = self:getGroupedAssets(row)
        if item._cachedDrawerH and item._cachedDrawerAssets == assets and item._cachedDrawerAssetSig == (row and row._cachedAssetSig) then
            return item._cachedDrawerH
        end

        -- 1. Top Section Height (padding + locStr + stage steps track)
        local locH = 22
        local trackH = (row._cachedTrack and row._cachedTrack.height) or (self.fontHeight * 3 + self.pad)
        local topH = 8 + locH + trackH + 8

        -- 2. Middle Content Height (assets / progress / recipe)
        local contentH = 0
        if assets and #assets > 0 then
            local count = math.min(3, #assets)
            local extra = (#assets > 3) and 20 or 0
            contentH = count * 24 + extra
        elseif row.targetCount and row.targetCount > 0 then
            contentH = 24
        elseif row.recipeName then
            contentH = 20
        else
            contentH = 10
        end

        -- 3. Bottom Action Bar Height (Divider + View Dossier & Stop Body buttons)
        local npcId = item.npcId or row.npcId
        local canStop = (row.kind == 'FIELD_WORK' and row.jobId ~= nil and row.generation ~= nil and not row.closed and row.carrierAvailable and row.bucket == 'active') or (row.canPause == true)
        local bottomBarH = 16
        if npcId or canStop then
            bottomBarH = 14 + 1 + 8 + 22 + 10 -- gap(14) + divider(1) + margin(8) + btnH(22) + bottomMargin(10)
        end

        local h = topH + contentH + bottomBarH
        item._cachedDrawerH = h
        item._cachedDrawerAssets = assets
        item._cachedDrawerAssetSig = row and row._cachedAssetSig
        return h
    end

    ---Keeps the list viewport at the full allocated layout height.
    function Page:applyListHeight()
        if not self.listBounds or not self.orderList then return end
        local fullH = self.listMaxHeight or self.listBounds.height
        self.orderList:setHeight(fullH)
        if self.orderList.vscroll then
            self.orderList.vscroll:setX(self.listBounds.width - 6)
            self.orderList.vscroll:setWidth(6)
            self.orderList.vscroll:setHeight(fullH)
        end
    end

    ---Updates existing row heights without clearing or reflowing list items (ProjectRemnants parity).
    function Page:updateOrderRowHeights()
        if not self.orderList or not self.orderList.items then return end
        local totalH = 0
        for _, entry in ipairs(self.orderList.items) do
            local item = entry.item and (entry.item.value or entry.item)
            local isExpanded = item and (self.expandedKey == (item.key or item.id))
            local drawerH = isExpanded and self:getDrawerHeight(item) or 0
            entry.height = isExpanded and (C.BASE_CARD_H + drawerH) or C.BASE_CARD_H
            totalH = totalH + entry.height
        end
        self.orderList:setScrollHeight(totalH)
        self.listContentH = totalH
        self:applyListHeight()
    end

    function Page:onListMouseDown(list, lx, ly)
        if not list.items or #list.items == 0 then
            if EmptyState.hitTest(list, lx, ly) then
                if self.owner and self.owner.selectTab then
                    self.owner:selectTab('workPolicy')
                    return true
                end
            end
            return false
        end

        local yScroll = list:getYScroll()
        local targetY = ly - yScroll
        local curY = 0
        local clickedRow = -1
        local rowTop = 0

        for i, entry in ipairs(list.items) do
            local h = entry.height or C.BASE_CARD_H
            if targetY >= curY and targetY < curY + h then
                clickedRow = i
                rowTop = curY
                break
            end
            curY = curY + h
        end

        if clickedRow == -1 then return false end

        local entry = list.items[clickedRow]
        local item = entry.item and (entry.item.value or entry.item)
        if not item then return false end

        local localY = targetY - rowTop

        -- 1. Click on card header (localY <= C.BASE_CARD_H) toggles drawer expansion
        if localY <= C.BASE_CARD_H then
            local targetKey = item.key or item.id
            if self.expandedKey == targetKey then
                self.expandedKey = nil
                self.expandedOrderId = nil
            else
                self.expandedKey = targetKey
                self.expandedOrderId = targetKey
            end
            list.selected = clickedRow
            self:updateOrderRowHeights()
            return true
        end

        -- 2. Click inside expanded drawer (localY > C.BASE_CARD_H): Virtual Buttons
        if self.expandedKey == (item.key or item.id) then
            local drawerLocalY = localY - C.BASE_CARD_H
            local hasScroll = list.isVScrollBarVisible and list:isVScrollBarVisible()
            local cardW = list:getWidth() - (hasScroll and 6 or 0)
            local padX = 10
            local tm = getTextManager()
            local btnH = 22
            local drawerH = self:getDrawerHeight(item)
            local btnY = item._cachedBtnY or (drawerH - btnH - 8)
            local curX = cardW - padX

            local row = item.row or {}
            local npcId = item.npcId or row.npcId

            -- Hit test: Dossier button
            if npcId then
                local label = getText('IGUI_EmberRoutesProbe_Overview_viewDossier')
                local bw = self._cachedDossierW or ((tm and tm:MeasureStringX(UIFont.Small, label) or 72) + 20)
                curX = curX - bw
                if InlineCardDrawer.hitTest(lx, drawerLocalY, curX, btnY, bw, btnH) then
                    if self.owner and self.owner.selectTab then
                        self.owner:selectTab('personnel', {npcId = npcId})
                    elseif self.owner and self.owner.activateTab then
                        self.owner:activateTab('personnel')
                    end
                    return true
                end
                curX = curX - 8
            end

            -- Hit test: Stop-body preemption button
            local caps = WorkCommandAdapter.capabilities(row)
            if caps.stopBody or caps.stop then
                local label = getText('IGUI_EmberRoutesProbe_Distributed_stopBody')
                local bw = self._cachedStopW or ((tm and tm:MeasureStringX(UIFont.Small, label) or 80) + 20)
                curX = curX - bw
                if InlineCardDrawer.hitTest(lx, drawerLocalY, curX, btnY, bw, btnH) then
                    local cmd = caps.stopBody and 'stopBody' or 'stop'
                    WorkCommandAdapter.command(self.actor, self.entry.id, row, cmd)
                    self:refresh()
                    return true
                end
            end
        end

        return false
    end

    function Page:onMouseDown(x, y)
        -- Check 1: Injured personnel 1-click jump capsule
        local jump = self.cachedInjuredJump
        if jump and x >= jump.x and x <= jump.x + jump.width and y >= jump.y and y <= jump.y + jump.height then
            if self.owner and self.owner.selectTab then
                self.owner:selectTab('personnel', {npcId = jump.npcId})
            end
            return true
        end

        -- Check 2: Forward to orderList if called on page
        local list = self.orderList
        if list and list:getIsVisible() then
            local lx, ly = x - list.x, y - list.y
            if lx >= 0 and lx < list.width and ly >= 0 and ly < list.height then
                return list:onMouseDown(lx, ly)
            end
        end

        return ISPanel.onMouseDown(self, x, y)
    end
end

return attach
