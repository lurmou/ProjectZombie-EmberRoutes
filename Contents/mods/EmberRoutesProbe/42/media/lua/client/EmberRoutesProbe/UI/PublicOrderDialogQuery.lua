-- PublicOrderDialogQuery.lua - EmberRoutes UI
-- Catalog query: paged recipe catalogue watch (with the direct-recipe
-- injection fast-path) and stock-rule loading for the selected recipe.
-- Moved verbatim from PublicOrderDialog.lua (P1 split); behaviour unchanged.
-- Attached to EmberRoutesPublicOrderDialog by PublicOrderDialog.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the dialog module).

local Crafting = require 'EmberRoutesProbe/Crafting/CraftingService'
local Public = require 'EmberRoutesProbe/Work/PublicWork'
local Recipe = require 'EmberRoutesProbe/Crafting/ProductionRecipe'
local Theme = require 'EmberRoutesProbe/UI/Theme'

local function attach(Page)
function Page:query()
    if self.releaseCatalog then self.releaseCatalog() self.releaseCatalog=nil end
    if self.disposed then return end

    -- Fast-path for direct recipe injection (from vanilla crafting menu or direct context)
    if self.context.recipeId then
        local targetId=self.context.recipeId
        local cooking=require('EmberRoutesProbe/Cooking/CookingOrders').describe(targetId)
        local spec=cooking or Recipe.read(targetId)
        if spec then
            local desc=cooking or Recipe.describe(spec)
            self.rows={desc}
            self.recipeCombo:setOptions({{id=targetId,label=desc.name or spec.name}},targetId)
            self.selectedRecipe=targetId
            self.context.recipeId=nil
            self.page=1
            self.totalPages=1
            if self.previous then self.previous:setVisible(false) end
            if self.next then self.next:setVisible(false) end
            self:loadRule()
            self:describe()
            return
        end
    end

    local activation=self.activationScope
    local token={}
    self.catalogToken=token
    local release=Crafting.watchCatalog(self.actor,self.entry.id,{search=self.search:getText(),category=false,unsupported=false,page=self.page,size=12},function(snapshot)
        if not activation:isCurrent() or self.catalogToken~=token then return end
        if not self.owner:valid() then self:close() return end
        self.rows=snapshot.rows or {}
        local recipeOptions={}
        local targetRecipeId=self.context.recipeId or self.selectedRecipe
        for i,row in ipairs(self.rows) do
            table.insert(recipeOptions,{id=row.id,label=row.name})
            if not targetRecipeId and self.context.productType and row.product==self.context.productType then
                targetRecipeId=row.id
            end
        end
        self.recipeCombo:setOptions(recipeOptions,targetRecipeId or (self.rows[1] and self.rows[1].id or false))
        local chosen=self.recipeCombo:getSelectedData() or false
        if chosen~=self.selectedRecipe then
            self.preferences={}
        end
        self.selectedRecipe=chosen
        self.context.recipeId=nil
        self:loadRule()
        self.page=snapshot.page or 1
        self.totalPages=snapshot.pages or 1
        local hasMultiplePages = self.totalPages > 1
        if self.previous then
            self.previous:setVisible(hasMultiplePages)
            Theme.enable(self.previous,self.page>1)
        end
        if self.next then
            self.next:setVisible(hasMultiplePages)
            Theme.enable(self.next,self.page<self.totalPages)
        end
        self:describe()
    end)
    if self.disposed or self.catalogToken~=token then
        if release then release() end
    else
        self.releaseCatalog=release
    end
end

function Page:loadRule()
    local row=self.rows[self.recipeCombo.selected]
    if not row or self.ruleProduct==row.product then return end
    self.ruleProduct=row.product
    local rule=Public.rule(self.entry.id,row.product)
    local minVal=rule and rule.minimum or 0
    local batchVal=rule and rule.batch or 10
    if self.minimumStepper then self.minimumStepper:setValue(minVal) else self.minimum:setText(tostring(minVal)) end
    if self.batchStepper then self.batchStepper:setValue(batchVal) else self.batch:setText(tostring(batchVal)) end
end
end

return attach
