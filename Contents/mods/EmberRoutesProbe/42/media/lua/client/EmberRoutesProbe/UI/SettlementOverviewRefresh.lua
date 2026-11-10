-- SettlementOverviewRefresh.lua - EmberRoutes UI
-- Data refresh: vitals / work counts / stockpile projection from the
-- WorkOverview, Crafting and Personnel services into the page store,
-- plus the warehouse stockpile snapshot refresh.
-- Attached to EmberRoutesSettlementOverviewPage by SettlementOverviewPage.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the page module). Moved verbatim from the
-- pre-split SettlementOverviewPage.lua (P1-9); behaviour unchanged.
-- One deliberate fix while moving refresh(): isHauling/isCrafting are
-- now locals from the top of refresh() (see the comment there); the
-- pre-split file wrote them to _G. Behaviour is identical: the first
-- loop's values were dead before the split (see that comment).

local WorkOverviewService = require 'EmberRoutesProbe/Work/WorkOverviewService'
local CraftingService = require 'EmberRoutesProbe/Crafting/CraftingService'
local PersonnelService = require 'EmberRoutesProbe/Settlement/PersonnelService'
local SupplyEstimate = require 'EmberRoutesProbe/Warehouse/SupplyEstimate'

local function attach(Page)
    function Page:refresh()
        if not self.active or self.disposed then return end

        local overview = WorkOverviewService.status(self.actor, self.entry.id)
        local craftStatus = CraftingService.status(self.actor, self.entry.id)
        local rawWorkers = craftStatus.workers or {}
        local enriched = PersonnelService.enrichWorkers(self.actor, self.entry.id, rawWorkers)

        local vitals = {
            population = #enriched,
            working = 0,
            idle = 0,
            injured = 0,
            infected = 0,
            firstInjuredId = nil
        }

        -- Declared here (not below) so the worker loop writes locals, not _G:
        -- the pre-split file assigned these globals before the local
        -- declaration, leaking isHauling/isCrafting into _G. The first loop's
        -- values were dead there (shadowed by `local ... = false` before any
        -- read), so hoisting + resetting above changes no behaviour.
        local isHauling = false
        local isCrafting = false

        local byNpc = overview.byNpc or {}
        for _, w in ipairs(enriched) do
            local work = byNpc[w.id]
            if work and (work.state == 'working' or work.state == 'running') then
                vitals.working = vitals.working + 1
                if work.category == 'hauling' then isHauling = true end
                if work.category == 'crafting' then isCrafting = true end
            else
                vitals.idle = vitals.idle + 1
            end
            local isInjured = w.hasInjury or w.isBleeding
            if isInjured then
                vitals.injured = vitals.injured + 1
                if not vitals.firstInjuredId then vitals.firstInjuredId = w.id end
            end
            if w.isInfected then
                vitals.infected = vitals.infected + 1
                if not vitals.firstInjuredId then vitals.firstInjuredId = w.id end
            end
        end

        local works = overview.works or {}
        local counts = {all = #works, working = 0, waiting = 0, blocked = 0}
        -- Reset: the worker loop above only feeds vitals; drive state is
        -- recomputed from the work list below (as before the split).
        isHauling = false
        isCrafting = false

        for _, item in ipairs(works) do
            local row = item.row or {}
            if row.npcId then
                for _, w in ipairs(enriched) do
                    if w.id == row.npcId then
                        item.workerName = item.workerName or w.name
                        item.workerInjured = w.hasInjury or w.isBleeding
                        item.workerHealth = w.health
                        break
                    end
                end
            end

            if item.state == 'working' or item.state == 'running' then
                counts.working = counts.working + 1
                if item.category == 'hauling' then isHauling = true end
                if item.category == 'crafting' then isCrafting = true end
            elseif item.state == 'waiting' or not (row and row.npcId) then
                counts.waiting = counts.waiting + 1
            end

            if item.state == 'blocked' then
                counts.blocked = counts.blocked + 1
            end
        end

        local defenseRatio = vitals.population > 0
            and math.max(0, math.min(1.0, (vitals.population - vitals.injured - vitals.infected) / vitals.population))
            or 1.0

        self.cachedData.popCount = vitals.population
        self.cachedData.workingCount = vitals.working
        self.cachedData.idleCount = vitals.idle
        self.cachedData.injuredCount = vitals.injured
        self.cachedData.defenseRatio = defenseRatio
        self.cachedData.isHauling = isHauling
        self.cachedData.isCrafting = isCrafting

        -- First projection snaps the odometer; later population changes still roll.
        local roller = self.popRollerState
        if roller.current == 0 and roller.target == 0 then
            roller.current = vitals.population
            roller.target = vitals.population
        end

        local stockRows = (self.lastStockSnapshot and self.lastStockSnapshot.rows) or {}
        local currentStock = SupplyEstimate.calculate(stockRows, vitals.population)


        self.store:setState({
            works = works,
            vitals = vitals,
            counts = counts,
            stockpile = currentStock,
            revision = self.store.value.revision + 1
        })

        if self.filterChips then
            -- Chip geometry is measured text: rebuild only when labels or counts
            -- actually change, not on every 1s refresh.
            local chipKey = tostring(self.activeFilter) .. ":" .. counts.all .. ":" .. counts.working
                .. ":" .. counts.waiting .. ":" .. counts.blocked
            if chipKey ~= self.filterChipKey then
                self.filterChipKey = chipKey
                self.filterChips:setOptions({
                    {id = 'all',     label = getText('IGUI_EmberRoutesProbe_Overview_filterAll'),     count = counts.all},
                    {id = 'working', label = getText('IGUI_EmberRoutesProbe_Overview_filterWorking'), count = counts.working},
                    {id = 'waiting', label = getText('IGUI_EmberRoutesProbe_Overview_filterWaiting'), count = counts.waiting},
                    {id = 'blocked', label = getText('IGUI_EmberRoutesProbe_Overview_filterBlocked'), count = counts.blocked, alert = (counts.blocked > 0)}
                }, self.activeFilter)
            end
        end

        self:updatePresentationCache()
        self:updateFilteredList()
    end

    function Page:refreshStockpile(snapshot)
        if not self.active or self.disposed then return end
        self.lastStockSnapshot = snapshot or self.lastStockSnapshot
        local currentSnapshot = self.lastStockSnapshot
        if not currentSnapshot or not currentSnapshot.rows then return end

        local pop = (self.store and self.store.value and self.store.value.vitals and self.store.value.vitals.population) or 0
        local stock = SupplyEstimate.calculate(currentSnapshot.rows, pop)

        self.store:setState({
            stockpile = stock,
            revision = self.store.value.revision + 1
        })



        self:updatePresentationCache()
    end
end

return attach
