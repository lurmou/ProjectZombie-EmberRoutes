-- PersonnelPageLifecycle.lua - EmberRoutes UI
-- Page lifecycle and context: activation scope / work-overview watch,
-- symmetric unmount/dispose, dossier-drawer teardown and context
-- resolve/apply. Attached to EmberRoutesPersonnelPage by PersonnelPage.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the page module). Moved verbatim from
-- PersonnelPage.lua; behaviour unchanged.

local Lifecycle = require 'EmberRoutesProbe/UI/PageLifecycle'
local Tooltip = require 'EmberRoutesProbe/UI/TooltipManager'
local Crafting = require 'EmberRoutesProbe/Crafting/CraftingService'

---@param Page EmberRoutesPersonnelPage
local function attach(Page)
function Page:resolveContext(context)
    if not context.npcId then return nil,"CONTEXT_UNSUPPORTED" end
    for _,worker in ipairs(Crafting.status(self.actor,self.entry.id).workers or {}) do
        if worker.id==context.npcId then return worker.id end
    end
    return nil,"TARGET_NOT_FOUND"
end

function Page:applyContext(context)
    if not self.active then return false end
    for _,worker in ipairs(self.store.value.workers or {}) do
        if worker.id==context.npcId then
            self.store:setState({selected=worker})
            for i,entry in ipairs(self.matrixList.items) do
                if entry.item.value.id==worker.id then self.matrixList.selected=i self.matrixList:ensureVisible(i) break end
            end
            return true
        end
    end
    return false
end

function Page:activate()
    local mounted=Lifecycle.mount(self,function(callback)
        if Crafting.watch then
            return require('EmberRoutesProbe/Work/WorkOverviewService').watch(self.actor,self.entry.id,callback)
        end
        return function() end
    end,function(snapshot)
        if snapshot and snapshot.reason=="WORLD_RESET" then self.owner:close() return end
        self:refresh()
    end)
    if mounted then
        self.active=true
        if self.pageHost and self.activationScope and self.activationScope:isCurrent() then
            self.pageHost:setActivation(self.activationScope)
            self:syncLayoutAliases()
        end
        self:refresh()
    end
end

function Page:deactivate()
    if self.pageHost then self.pageHost:deactivate() end
    Lifecycle.unmount(self)
    self.batchResults=nil self.memberMenu=nil
    Tooltip.dismissOwner(self)
    if self.dossierDrawer then self.dossierDrawer:close() end
    if self.detailNpc then require('EmberRoutesProbe/Settlement/PersonnelService').release(self.detailNpc) self.detailNpc=nil end
end

function Page:dispose()
    self.disposed=true
    if self.dossierDrawer then self.dossierDrawer:dispose() self.dossierDrawer=nil end
    if self.pageHost then self.pageHost:dispose() end
    self:deactivate()
    Tooltip.unregisterOwner(self)
end

end

return attach
