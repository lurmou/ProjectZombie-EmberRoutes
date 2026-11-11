-- PublicOrderDialogDescribe.lua - EmberRoutes UI
-- Derived state: batch conversion math, draft update / action-button
-- gating, precursor switching and the async blueprint preview watch.
-- Moved verbatim from PublicOrderDialog.lua (P1 split); behaviour unchanged.
-- Attached to EmberRoutesPublicOrderDialog by PublicOrderDialog.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the dialog module).

local Recipe = require 'EmberRoutesProbe/Crafting/ProductionRecipe'
local Catalog = require 'EmberRoutesProbe/Crafting/CraftingCatalog'
local Draft = require 'EmberRoutesProbe/Work/PublicOrderDraft'
local Theme = require 'EmberRoutesProbe/UI/Theme'

local function isEnglish()
    return getText('IGUI_EmberRoutesProbe_Public_targetQuantity') == 'Target Product Quantity'
end

---@param Page EmberRoutesPublicOrderDialog
local function attach(Page)
function Page:updateConversion()
    local row=self.rows and self.rows[self.recipeCombo.selected]
    if not row or not row.id then
        self.conversion=nil
        self.conversionFull=nil
        self.conversionLine1=nil
        self.conversionLine2=nil
        return
    end

    local spec=self.currentSpec or (row.id and Recipe.read(row.id) and Recipe.describe(Recipe.read(row.id))) or row
    local resultCount=(row and (row.resultCount or row.yield)) or (spec and (spec.resultCount or spec.yield)) or 1
    if not resultCount or resultCount<1 then resultCount=1 end
    self.resultCount=resultCount

    local targetQty
    if self.activeTab=='order' then
        targetQty=tonumber(self.quantity:getText()) or 1
    else
        targetQty=tonumber(self.batch:getText()) or 10
    end
    targetQty=math.max(1,math.floor(targetQty))
    self.targetQty=targetQty

    local executions=math.max(1,math.ceil(targetQty/resultCount))
    local expectedOutput=executions*resultCount
    local surplus=math.max(0,expectedOutput-targetQty)

    self.conversion={
        resultCount=resultCount,
        targetQty=targetQty,
        executions=executions,
        expectedOutput=expectedOutput,
        surplus=surplus
    }

    local isEN=isEnglish()
    local targetLabel
    if isEN then
        targetLabel=(self.activeTab=='order') and 'Target Need' or 'Batch Size'
        self.conversionFull=string.format('Per Batch Output: %d | %s: %d => Craft Runs: %d | Expected: %d (%d surplus)',
            resultCount,targetLabel,targetQty,executions,expectedOutput,surplus)
        self.conversionLine1=string.format('Per Batch Output: %d  |  %s: %d',resultCount,targetLabel,targetQty)
        self.conversionLine2=string.format('=> Craft Runs: %d  |  Expected: %d (%d surplus)',executions,expectedOutput,surplus)
    else
        local labelKey=(self.activeTab=='order') and 'IGUI_EmberRoutesProbe_Public_targetDemand' or 'IGUI_EmberRoutesProbe_Public_restockBatch'
        targetLabel=getTextOrNull(labelKey) or labelKey
        self.conversionFull=string.format(getTextOrNull('IGUI_EmberRoutesProbe_Public_conversionFull') or 'IGUI_EmberRoutesProbe_Public_conversionFull',
            resultCount,targetLabel,targetQty,executions,expectedOutput,surplus)
        self.conversionLine1=string.format(getTextOrNull('IGUI_EmberRoutesProbe_Public_conversionLine1') or 'IGUI_EmberRoutesProbe_Public_conversionLine1',
            resultCount,targetLabel,targetQty)
        self.conversionLine2=string.format(getTextOrNull('IGUI_EmberRoutesProbe_Public_conversionLine2') or 'IGUI_EmberRoutesProbe_Public_conversionLine2',
            executions,expectedOutput,surplus)
    end
end

function Page:describe()
    self:updateConversion()
    local row=self.rows[self.recipeCombo.selected]
    local quantity=tonumber(self.quantity:getText())
    if self.activeTab=='order' and row and quantity and quantity>=1 and quantity<=9999 and quantity==math.floor(quantity) then
        local surface=self.surfaceCombo:getSelectedData() or false
        if not row.surface then surface=nil end
        local d=Draft.update(self.actor,self.entry.id,row.id,quantity,surface,self.preferences,row.product)
        if self.requestId~=d.requestId then self.notice=nil end
        self.draft,self.requestId=d,d.requestId
        self.notice=d.result and require('EmberRoutesProbe/UI/OrderMonitorCards').reason(d.result) or self.notice
        self.submitted=d.result=='ORDER_CREATED'
    end
    if self.submitting then
        Theme.enable(self.actionButton,false)
        self:requestPreview()
        return
    end

    local row=self.rows[self.recipeCombo.selected]
    local n=tonumber(self.quantity:getText())
    if self.activeTab=='order' then
        local valid=row~=nil and n~=nil and n>=1 and n<=9999 and n==math.floor(n)
        Theme.enable(self.actionButton,valid and not self.submitted,true)
    else
        local minVal=tonumber(self.minimum:getText())
        local batchVal=tonumber(self.batch:getText())
        local validStock=minVal and minVal>=0 and minVal<=9999 and minVal==math.floor(minVal)
            and batchVal and batchVal>=1 and batchVal<=9999 and batchVal==math.floor(batchVal)
        Theme.enable(self.actionButton,row~=nil and validStock,true)
    end
    self:requestPreview()
end

function Page:switchPrecursor(product,nextRecipeId)
    self.preferences=self.preferences or {}
    self.preferences[product]=nextRecipeId
    self:describe()
end

function Page:requestPreview()
    self.previewToken=nil
    if self.cancelPreview then self.cancelPreview() self.cancelPreview=nil end
    local row=self.rows[self.recipeCombo.selected]
    if not row or not row.id then
        self.previewData=nil
        self:updateBlueprint()
        return
    end

    local qty=tonumber(self.quantity:getText()) or 1
    if self.activeTab=='stock' then
        qty=tonumber(self.batch:getText()) or 10
    end
    local surfaceId=self.surfaceCombo:getSelectedData() or false

    local activation=self.activationScope
    local token={} self.previewToken=token
    self.previewData=nil
    local spec=Recipe.read(row.id)
    self.currentSpec=row.cooking and Catalog.describe(row.id) or spec and Recipe.describe(spec) or row
    self:updateBlueprint()

    local release=require('EmberRoutesProbe/Work/PublicPreview').watch(self.actor,self.entry.id,row.id,qty,surfaceId,function(result)
        if not activation:isCurrent() or self.previewToken~=token then return end
        self.previewData=result
        if result.cooking and result.recipe then self.currentSpec=result.recipe end
        self:updateBlueprint()
    end,self.preferences)
    if not activation:isCurrent() or self.previewToken~=token then
        if release then release() end
    else self.cancelPreview=release end
end
end

return attach
