-- PublicOrderDialogSubmit.lua - EmberRoutes UI
-- Submission: single-order creation and stock-rule saving, plus the
-- PublicOrderDialog.saveRule alias for the submitRule method.
-- Moved verbatim from PublicOrderDialog.lua (P1 split); behaviour unchanged.
-- Attached to EmberRoutesPublicOrderDialog by PublicOrderDialog.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the dialog module).

local Public = require 'EmberRoutesProbe/Work/PublicWork'
local Draft = require 'EmberRoutesProbe/Work/PublicOrderDraft'
local Theme = require 'EmberRoutesProbe/UI/Theme'

local function text(key,...) return getText('IGUI_EmberRoutesProbe_Public_'..key,...) end
local function submittingText()
    return getTextOrNull('IGUI_EmberRoutesProbe_Public_submitting') or 'IGUI_EmberRoutesProbe_Public_submitting'
end

---@param Page EmberRoutesPublicOrderDialog
local function attach(Page)
function Page:submitOrder()
    if self.disposed or self.submitting or not self.owner:valid() then
        if not self.owner:valid() then self:close() end
        return
    end
    if not self.actionButton or self.actionButton.enable == false then return end
    if not self.selectedRecipe then return end

    local qty=tonumber(self.quantity:getText())
    if not qty or qty<1 or qty>9999 or qty~=math.floor(qty) then return end

    self:describe()
    if self.submitted then return end
    self.submitting=true
    local oldTitle=text('submit')
    self.actionButton:setTitle(submittingText())
    Theme.enable(self.actionButton,false)

    local ok,result=pcall(function()
        return Public.create(self.actor,self.entry.id,self.selectedRecipe,math.floor(qty),
            self.surfaceCombo:getSelectedData() or false,self.requestId,self.preferences)
    end)

    if not ok then
        self.submitting=false
        self.notice=tostring(result)
        self.actionButton:setTitle(oldTitle)
        self:describe()
        return
    end

    Draft.result(self.actor,self.entry.id,self.requestId,result)
    self.submitting=false
    self.notice=require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)
    self.actionButton:setTitle(oldTitle)
    self:describe()
end

function Page:submitRule()
    if self.disposed or self.submitting or not self.owner:valid() then
        if not self.owner:valid() then self:close() end
        return
    end
    if not self.actionButton or self.actionButton.enable == false then return end
    if not self.selectedRecipe then return end

    local minVal=tonumber(self.minimum:getText())
    local batchVal=tonumber(self.batch:getText())
    if not minVal or minVal<0 or minVal>9999 or minVal~=math.floor(minVal) then return end
    if not batchVal or batchVal<1 or batchVal>9999 or batchVal~=math.floor(batchVal) then return end

    self.submitting=true
    local oldTitle=text('saveRule')
    self.actionButton:setTitle(submittingText())
    Theme.enable(self.actionButton,false)

    local ok,result=pcall(function()
        return Public.saveRule(self.actor,self.entry.id,self.selectedRecipe,math.floor(minVal),
            math.floor(batchVal),self.surfaceCombo:getSelectedData() or false,self.preferences)
    end)

    if not ok then
        self.submitting=false
        self.notice=tostring(result)
        self.actionButton:setTitle(oldTitle)
        self:describe()
        return
    end

    self.submitting=false
    self.notice=require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)
    self.actionButton:setTitle(oldTitle)
    self:describe()
end
Page.saveRule=Page.submitRule
end

return attach
