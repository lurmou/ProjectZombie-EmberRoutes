-- PublicOrderDialogLifecycle.lua - EmberRoutes UI
-- Lifecycle: Escape/Return key handling and symmetric close -- releases
-- the catalog and preview watches, clears tooltips and the dialog
-- reference on the owner dashboard.
-- Moved verbatim from PublicOrderDialog.lua (P1 split); behaviour unchanged.
-- Attached to EmberRoutesPublicOrderDialog by PublicOrderDialog.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the dialog module).

require 'ISUI/ISCollapsableWindow'
local Lifecycle = require 'EmberRoutesProbe/UI/PageLifecycle'
local Tooltip = require 'EmberRoutesProbe/UI/TooltipManager'

---@param Page EmberRoutesPublicOrderDialog
local function attach(Page)
function Page:isKeyConsumed(key)
    if self.disposed then return false end
    return key==Keyboard.KEY_ESCAPE or key==Keyboard.KEY_RETURN
end

function Page:onKeyPress(key)
    if self.disposed then return end
    if key==Keyboard.KEY_ESCAPE then
        self:close()
    elseif key==Keyboard.KEY_RETURN then
        if not self.submitting and self.actionButton and self.actionButton.enable ~= false then
            if self.search and self.search:isFocused() then
                self.search:unfocus()
                return
            end
            if self.activeTab=='order' then
                self:submitOrder()
            else
                self:submitRule()
            end
        end
    end
end

function Page:close()
    if self.disposed then return end
    Lifecycle.dispose(self)
    self.disposed=true
    self.submitting=false
    self.catalogToken=nil
    if self.releaseCatalog then self.releaseCatalog() self.releaseCatalog=nil end
    if self.cancelPreview then self.cancelPreview() self.cancelPreview=nil end
    if self.presentation then self.presentation:clear() end
    if self.recipeCombo.closePopup then self.recipeCombo:closePopup() elseif self.recipeCombo.hidePopup then self.recipeCombo:hidePopup() end
    if self.surfaceCombo.closePopup then self.surfaceCombo:closePopup() elseif self.surfaceCombo.hidePopup then self.surfaceCombo:hidePopup() end
    Tooltip.clear(self.recipeCombo)
    Tooltip.clear(self.surfaceCombo)
    Tooltip.clear(self.quantity)
    Tooltip.clear(self.batch)
    Tooltip.unregisterOwner(self)
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if self.owner.publicDialog==self then self.owner.publicDialog=nil end
end
end

return attach
