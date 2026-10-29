local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Selector=require "EmberRoutesProbe/UI/SettlementSelector"
local Dashboard=require "EmberRoutesProbe/SettlementDashboard"
local Menu={}
local Metrics=require "EmberRoutesProbe/WarehouseMetrics"
local Geometry=require "EmberRoutesProbe/SettlementGeometry"
local Logistics=require "EmberRoutesProbe/LogisticsMenu"
local LifeZones=require "EmberRoutesProbe/LifeZoneMenu"
local MembershipText=require "EmberRoutesProbe/MembershipText"
local MembershipService=require "EmberRoutesProbe/MembershipService"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
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
    local createOpt=menu:addOption(text("create"),actor,Menu.create)
    local insideEntries={}
    local outsideEntries={}
    local factionId=Ledger.data().factionId
    for _,entry in ipairs(Ledger.list()) do
        if entry.factionId==factionId then
            if Geometry.inside(entry,actor:getX(),actor:getY()) then
                insideEntries[#insideEntries+1]=entry
            else
                outsideEntries[#outsideEntries+1]=entry
            end
        end
    end
    if #insideEntries>0 and createOpt then
        createOpt.notAvailable=true
        if ISToolTip and ISToolTip.new then
            local tip=ISToolTip:new()
            tip:initialise()
            tip.description=text("alreadyInside")
            createOpt.toolTip=tip
        end
    end
    for _,entry in ipairs(insideEntries) do
        Logistics.fill(actor,menu,entry)
        LifeZones.fill(actor,menu,entry)
        -- 集结点：仅在玩家身处该据点内且右键点击在领地内时提供（由外层 fillMenu 传入 square 时调用，
        -- 此处不重复；fillMenu 主块已移除独立的集结点块，统一由此入口产生）
        menu:addOption(text("management").." - "..entry.name,actor,Menu.open,entry.id)
    end
    if #insideEntries==0 and #outsideEntries<=1 then
        for _,entry in ipairs(outsideEntries) do
            menu:addOption(text("management").." - "..entry.name.." ("..text("OUTSIDE_SETTLEMENT")..")",
                actor,Menu.open,entry.id)
        end
    elseif #outsideEntries>0 then
        local otherOpt=menu:addOption(text("other"),nil,nil)
        local otherMenu=ISContextMenu:getNew(menu)
        menu:addSubMenu(otherOpt,otherMenu)
        for _,entry in ipairs(outsideEntries) do
            otherMenu:addOption(text("management").." - "..entry.name.." ("..text("OUTSIDE_SETTLEMENT")..")",
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
-- 集结点设置：由 fillMenu 通过 square 参数显式调用，不在 fill() 内部遍历地图以保持职责清晰
function Menu.returnPoint(actor,menu,square)
    for _,entry in ipairs(Ledger.list()) do
        if Geometry.inside(entry,square:getX(),square:getY()) then
            local target,revision=entry.id,entry.revision
            local point={x=square:getX()+0.5,y=square:getY()+0.5,z=square:getZ()}
            menu:addOption(MembershipText.reason("SET_RETURN_POINT").." - "..entry.name,actor,function(a)
                local ok,why=MembershipService.setReturnPoint(a,target,point,revision)
                a:Say(MembershipText.reason(ok and "RETURN_POINT_SET" or why))
            end)
        end
    end
end
return Menu
