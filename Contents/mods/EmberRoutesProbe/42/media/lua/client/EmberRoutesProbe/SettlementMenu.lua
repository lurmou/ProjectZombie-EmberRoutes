local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Selector=require "EmberRoutesProbe/UI/SettlementSelector"
local Dashboard=require "EmberRoutesProbe/SettlementDashboard"
local Menu={}
local Metrics=require "EmberRoutesProbe/WarehouseMetrics"
local Geometry=require "EmberRoutesProbe/SettlementGeometry"
local Logistics=require "EmberRoutesProbe/LogisticsMenu"
local function text(key) return getText("IGUI_EmberRoutesProbe_Settlement_"..key) end
function Menu.create(actor)
    Selector.open(actor,nil,function(entry)
        local panel=Dashboard.open(actor,entry.id)
        if not panel then actor:Say(text("SETTLEMENT_SAVED").." "..text("OUTSIDE_SETTLEMENT")) end
    end)
end
function Menu.open(actor,id)
    local panel,reason=Dashboard.open(actor,id)
    if not panel then
        actor:Say(text(reason))
        if reason=="OUTSIDE_SETTLEMENT" then Selector.open(actor,Ledger.get(id)) end
    end
end
function Menu.fill(actor,menu)
    if not Ledger.authorized(actor) then return end
    menu:addOption(text("create"),actor,Menu.create)
    for _,entry in ipairs(Ledger.list()) do
        if entry.factionId==Ledger.data().factionId then
            Logistics.fill(actor,menu,entry)
            local inside=Geometry.inside(entry,actor:getX(),actor:getY())
            menu:addOption(text("management").." - "..entry.name..(inside and "" or " ("..text("OUTSIDE_SETTLEMENT")..")"),
                actor,Menu.open,entry.id)
        end
    end

end
function Menu.craftAt(actor,object)
    local Crafting=require "EmberRoutesProbe/CraftingService"
    local surface,reason=Crafting.selectSurface(actor,object)
    if surface then
        local panel=Dashboard.open(actor,surface.settlementId,"orders")
        if panel then panel:openPublicOrder({surfaceId=surface.id}) end
    else actor:Say(require("EmberRoutesProbe/CraftingText").reason(reason)) end
end
function Menu.craftSurfaces(actor,menu,objects)
    for _,object in ipairs(objects) do
        if object.isGenericCraftingSurface and object:isGenericCraftingSurface() then
            menu:addOption(getText("IGUI_EmberRoutesProbe_Crafting_useSurface"),actor,Menu.craftAt,object)
            return
        end
    end
end
function Menu.performance(actor)
    if Metrics.enabled then Metrics.stop() actor:Say(text("perfSaved"))
    elseif Metrics.start() then actor:Say(text("perfStarted"))
    else actor:Say(text("perfUnavailable")) end
end
return Menu
