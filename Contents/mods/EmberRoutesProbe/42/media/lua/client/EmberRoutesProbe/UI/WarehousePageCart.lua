-- WarehousePageCart.lua - EmberRoutes UI
-- Delivery cart: add/remove/clear/totals, drawer, dispatch, container inspector.
-- Attached to EmberRoutesWarehousePage by WarehousePage.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the page module). Moved verbatim from the
-- pre-split WarehousePage.lua (p1-split-warehousepage); behaviour unchanged.

local Index=require "EmberRoutesProbe/Warehouse/WarehouseIndex"
local CartDrawer=require "EmberRoutesProbe/UI/DeliveryCartDrawer"

local function getItemWeight(fullType)
    local sm=type(getScriptManager)=="function" and getScriptManager()
    if sm then
        local s=(sm.getItem and sm:getItem(fullType)) or (sm.FindItem and sm:FindItem(fullType))
        if s and s.getActualWeight then return s:getActualWeight() end
    end
    return 1.0
end

local function attach(Page)
    function Page:addToDeliveryCart(row,delta,preferredSource)
        if not row or not row.fullType then return end
        self.deliveryFeedbackError=false
        if row.pending or row.count==false then
            self.deliveryFeedback=getText('IGUI_EmberRoutesProbe_Warehouse_cartStockUpdating')
            self:toggleCartDrawer(true) return
        end
        local ft=row.fullType
        local src=preferredSource
        local cartKey=src and (ft..':'..src.id) or ft
        local existing=self.deliveryCart[cartKey]
        local maxCount=src and (src.count or row.count) or (row.count or (existing and existing.maxCount) or 9999)
        local curCount=existing and existing.count or 0
        local newCount=curCount+delta
        if newCount>0 then newCount=math.min(newCount,maxCount) end
        if newCount==curCount then
            self.deliveryFeedback=getText('IGUI_EmberRoutesProbe_Warehouse_cartQuantityLimit')
            self:toggleCartDrawer(true) return
        end
        if newCount<=0 then
            self.deliveryCart[cartKey]=nil
        else
            newCount=math.min(newCount,maxCount)
            local icon=self.presentation and self.presentation:icon(ft) or nil
            local weight=getItemWeight(ft)
            local sourceName=src and (src.customName and src.customName~='' and src.customName or src.kind or src.displayType or '浠撳簱')
            local floorStr=src and (src.z==0 and getText('IGUI_EmberRoutesProbe_Settlement_floorGround') or ((src.z+1)..getText('IGUI_EmberRoutesProbe_Settlement_floorLevel'))) or nil
            local sourceLoc=src and ('('..src.x..','..src.y..')') or ''
            local sourceLabel=src and (sourceName..' '..floorStr..' '..sourceLoc) or nil
            self.deliveryCart[cartKey]={
                cartKey=cartKey,
                fullType=ft,
                label=row.label or (existing and existing.label) or ft,
                count=newCount,
                maxCount=maxCount,
                icon=icon,
                weight=weight,
                step=1,
                source=src and {id=src.id,name=sourceName,x=src.x,y=src.y,z=src.z} or (existing and existing.source) or nil,
                sourceLabel=sourceLabel or (existing and existing.sourceLabel) or nil
            }
        end
        self.deliveryFeedback=getText('IGUI_EmberRoutesProbe_Warehouse_cartItemUpdated',
            row.label or (existing and existing.label) or ft,tostring(math.max(0,newCount)))
        self:updateDeliveryCartTotals()
        self:toggleCartDrawer(true)
    end

    function Page:removeFromDeliveryCart(cartKey)
        if self.deliveryCart[cartKey] then
            self.deliveryFeedbackError=false
            self.deliveryCart[cartKey]=nil
            self.deliveryFeedback=getText('IGUI_EmberRoutesProbe_Warehouse_cartItemRemoved')
            self:updateDeliveryCartTotals()
            if self.cartDrawer and self.cartDrawer.getIsVisible and self.cartDrawer:getIsVisible() then
                self.cartDrawer:refresh()
            end
        end
    end

    function Page:clearDeliveryCart()
        self.deliveryCart={}
        self.deliveryFeedback=nil
        self.deliveryFeedbackError=false
        self:updateDeliveryCartTotals()
        if self.cartDrawer and self.cartDrawer:isVisible() then
            self.cartDrawer:refresh()
        end
    end

    function Page:updateDeliveryCartTotals()
        self.deliveryRequestId=nil
        local types,units,weight=0,0,0
        for _,item in pairs(self.deliveryCart) do
            types=types+1
            units=units+item.count
            weight=weight+(item.weight or 1.0)*item.count
        end
        self.deliveryCartCount=types
        self.deliveryCartTotalUnits=units
        self.deliveryCartWeight=weight
        if self.cartButton then
            self:updateCartButtonVisual()
        end
        if self.details and self.details.updateCartButton then
            self.details:updateCartButton()
        end
    end

    function Page:updateCartButtonVisual()
        if not self.cartButton then return end
        self.cartButton:setTitle(getText('IGUI_EmberRoutesProbe_Warehouse_cartButton',tostring(self.deliveryCartTotalUnits or 0)))
        self.cartButton.tooltip=getText('IGUI_EmberRoutesProbe_Warehouse_cartEmptyHint')
    end

    function Page:toggleCartDrawer(forceState)
        local newState
        if type(forceState) == "boolean" then
            newState = forceState
        else
            newState = not self.cartDrawerOpen
        end
        self.cartDrawerOpen = newState
        if newState then
            local dash = self.owner
            local w = math.min(360, math.max(300, math.floor(dash.width * 0.38)))
            local h = dash.height
            local x = dash:getX() + dash.width + 8
            local screenW = getCore():getScreenWidth()
            if x + w > screenW then x = math.max(8, dash:getX() - w - 8) end
            local y = dash:getY()

            if not self.cartDrawer then
                self.cartDrawer = CartDrawer:new(self, x, y, w, h)
            else
                self.cartDrawer:setX(x)
                self.cartDrawer:setY(y)
                self.cartDrawer:setWidth(w)
                self.cartDrawer:setHeight(h)
            end
            self.cartDrawer:addToUIManager()
            self.cartDrawer:setVisible(true)
            self.cartDrawer:bringToTop()
            self.cartDrawer:refresh()
        else
            if self.cartDrawer then
                self.cartDrawer:close()
            end
        end
    end

    function Page:openContainerInspector()
        if self.containerInspectorDialog then
            self.containerInspectorDialog:close()
            self.containerInspectorDialog = nil
            return
        end
        local containers = Index.containers(self.entry.id)
        local counts = self.store.value.snapshot and self.store.value.snapshot.counts or {}
        local ContainerInspector = require 'EmberRoutesProbe/UI/ContainerInspectorDialog'
        self.containerInspectorDialog = ContainerInspector:new(self, self.entry.id, containers, counts)
        self.containerInspectorDialog:addToUIManager()
        self.containerInspectorDialog:bringToTop()
    end

    function Page:dispatchDeliveryCart()
        if not self.deliveryCart or self.deliveryCartCount==0 then return end
        if not self.owner:valid() then self.owner:close() return end
        local items={}
        for cartKey,itm in pairs(self.deliveryCart) do
            items[#items+1]={
                fullType=itm.fullType,
                quantity=itm.count,
                sourceId=self.deliverySourceId or (itm.source and itm.source.id or nil)
            }
        end

        local PublicWork=require "EmberRoutesProbe/Work/PublicWork"
        local result="DELIVERY_UNAVAILABLE"
        if PublicWork and PublicWork.createDeliveryOrder then
            self.deliveryRequestId=self.deliveryRequestId or require('EmberRoutesProbe/Warehouse/ContainerRegistry').id()
            result=PublicWork.createDeliveryOrder(self.actor,self.entry.id,items,self.deliveryRequestId,self.deliveryDestinationId)
        end

        if result=="ORDER_CREATED" then
            self.deliveryRequestId=nil
            local HaloTextHelper=_G.HaloTextHelper
            if HaloTextHelper and HaloTextHelper.addGoodText then
                HaloTextHelper.addGoodText(self.actor,getText("IGUI_EmberRoutesProbe_Warehouse_cartDispatched"))
            end
            local sm=type(getSoundManager)=="function" and getSoundManager()
            if sm and self.actor and self.actor.getEmitter then
                self.actor:getEmitter():playSound("StoreItemPlayerInventory")
            end
            self:clearDeliveryCart()
            self:toggleCartDrawer(false)
        else
            self.deliveryFeedbackError=true
            local reasonKeys={ORDER_LIMIT='cartOrderLimit',INVALID_REQUEST='cartInvalidItems',REQUEST_CHANGED='cartInvalidItems',
                ACCESS_DENIED='cartAccessDenied',OUTSIDE_SETTLEMENT='cartAccessDenied',DRIVER_UNAVAILABLE='cartAccessDenied'}
            local key=reasonKeys[result] or 'cartRejected'
            if result=='DESTINATION_FILTER_REJECTED' or result=='DESTINATION_UNREGISTERED'
                or result=='DESTINATION_FULL' or result=='DESTINATION_UNREACHABLE' then
                self.deliveryFeedback=getText('IGUI_EmberRoutesProbe_WorkCode_'..result)
            else self.deliveryFeedback=getText('IGUI_EmberRoutesProbe_Warehouse_'..key) end
            self:toggleCartDrawer(true)
            if _G.HaloTextHelper and HaloTextHelper.addBadText then HaloTextHelper.addBadText(self.actor,self.deliveryFeedback) end
        end
    end
end

return attach
