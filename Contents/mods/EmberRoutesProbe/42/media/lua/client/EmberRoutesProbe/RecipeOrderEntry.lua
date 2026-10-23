-- Extend the installed recipe panel's existing table layout, retaining its
-- original builder and callbacks. No per-frame catalogue or inventory scan.
require 'Entity/ISUI/CraftRecipe/ISCraftRecipePanel'
require 'ISUI/ISButton'
local Probe=require 'EmberRoutesProbe/Boot'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Recipe=require 'EmberRoutesProbe/ProductionRecipe'
local original=ISCraftRecipePanel.createDynamicChildren

function ISCraftRecipePanel:createDynamicChildren()
    original(self)
    if not Probe.ready or not Probe.publicDispatch or not Probe.hasJava() then return end
    local native=self:getRecipe() if not native then return end
    local id=EmberRoutesProbeJava.recipeKey(native)
    if not Recipe.read(id) then return end
    local actor=self.player
    local scopes=Ledger.at(actor:getX(),actor:getY())
    if #scopes~=1 or not Ledger.view(actor,scopes[1].id) then return end
    local scopeEntry=scopes[1]
    local scopeId=scopeEntry.id

    local button=ISButton:new(0,0,0,getTextManager():getFontHeight(UIFont.Small)*2,
        getText('IGUI_EmberRoutesProbe_Public_createOrder'),self,function()
            local h=getTextManager():getFontHeight(UIFont.Small)
            local adapterOwner={
                actor=actor,
                entry=scopeEntry,
                fontHeight=h,
                pad=math.ceil(h*0.6),
                valid=function() return Ledger.view(actor,scopeId)~=nil end,
                selectTab=function() end,
                close=function() end
            }
            local PublicDialog=require('EmberRoutesProbe/UI/PublicOrderDialog')
            PublicDialog.open(adapterOwner,{recipeId=id,recipeName=native:getTranslationName()})
        end)
    button:initialise() button:instantiate()
    local row=self.rootTable:addRow()
    self.rootTable:setElement(0,row:index(),button)
    self:xuiRecalculateLayout()
end
return true
