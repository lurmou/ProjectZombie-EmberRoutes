-- WarehousePageInteraction.lua - EmberRoutes UI
-- Item/list interaction: pin, focus, select, locate, context menu, joypad, help.
-- Attached to EmberRoutesWarehousePage by WarehousePage.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the page module). Moved verbatim from the
-- pre-split WarehousePage.lua (p1-split-warehousepage); behaviour unchanged.

require "ISUI/ISModalDialog"
local Input=require "EmberRoutesProbe/UI/WarehouseInput"
local Text=require "EmberRoutesProbe/UI/Text"

local function text(key) return getText("IGUI_EmberRoutesProbe_Settlement_"..key) end

local function attach(Page)
    function Page:togglePin(row)
        if not row or not row.fullType then return end
        self.pinnedItems=self.pinnedItems or {}
        local newState=not self.pinnedItems[row.fullType]
        self.pinnedItems[row.fullType]=newState
        row.pinned=newState
        local curRows=self.store.value.snapshot.rows or {}
        for _,r in ipairs(curRows) do
            if r.fullType==row.fullType then r.pinned=newState end
        end
        if self.query and self.query.invalidate then self.query:invalidate() else self.query.rows=nil end
        self.details:setItem(row)
        self:project(self.store.value,{snapshot=true})
    end

    function Page:focusContent()
        Input.focus(self,self.focusedList or self.itemGrid)
    end

    function Page:focusList(list) Input.focus(self,list) end

    function Page:isListFocused(list) return self.active and Input.active(self,list) end

    function Page:onListActivate(list) Input.activate(self,list) end

    function Page:onListFocus(list,direction)
        if (list==self.itemGrid and direction==-1) or (list==self.sourceList and direction==1) then
            self.owner:nextTab(direction)
        else Input.other(self,list) end
    end

    function Page:selectSource(source)
        self.details.selectedSource=source
        if self.details and self.details.updateCartButton then
            self.details:updateCartButton()
        end
    end

    function Page:locateSource()
        local source=self.details.selectedSource
        if not source then return end
        local position,reason=self.locator:locate(source.id)
        self.notice=text(reason)..(position and (" "..position.x..", "..position.y.." | z="..position.z) or "")
        self.hintLines=Text.wrapLimited(self.notice,self.width-self.pad*2,UIFont.Small,1)
    end

    function Page:selectItem(row)
        self.store:setState({selection=row})
        if self.itemGrid and row then
            for i,c in ipairs(self.itemGrid.cells) do
                if c.row.fullType==row.fullType then self.itemGrid.selected=i break end
            end
        end
    end

    function Page:previous() self.store:setState({page=math.max(1,self.actualPage-1)}) end

    function Page:nextPage() self.store:setState({page=math.min(self.pages,self.actualPage+1)}) end

    function Page:onListKey(key,list) Input.key(self,key,list) end

    function Page:isItemCraftable(fullType)
        if not fullType then return false end
        if self.itemGrid and self.itemGrid.cells then
            for _,cell in ipairs(self.itemGrid.cells) do
                if cell.fullType==fullType and cell.craftable~=nil then
                    return cell.craftable
                end
            end
        end
        local okCat,Catalog=pcall(require,"EmberRoutesProbe/Crafting/CraftingCatalog")
        if okCat and Catalog and Catalog.productionIndex then
            local okIdx,_,byType=pcall(Catalog.productionIndex)
            if okIdx and byType then return byType[fullType]~=nil end
        end
        return false
    end

    function Page:onMiddleClickItem(row,shiftDown)
        if not row or not row.fullType then return false end
        if self:isItemCraftable(row.fullType) then
            if self.owner and self.owner.openPublicOrder then
                self.owner:openPublicOrder({productType=row.fullType})
                return true
            end
        else
            local feedback=getText("IGUI_EmberRoutesProbe_Warehouse_notCraftable")
            local HaloTextHelper=_G.HaloTextHelper
            if HaloTextHelper and HaloTextHelper.addBadText and self.actor then
                HaloTextHelper.addBadText(self.actor,feedback)
            end
            self.notice=feedback
            self.hintLines=Text.wrapLimited(feedback,self.width-self.pad*2,UIFont.Small,1)
            return false
        end
        return false
    end

    function Page:onMiddleClickSource(source,shiftDown)
        local row=self.details and self.details.row
        if not row or not row.fullType or not source then return end
        local delta=shiftDown and -1 or 1
        self:addToDeliveryCart(row,delta,source)
        return true
    end

    function Page:openItemContextMenu(row,screenX,screenY)
        if not row then return end
        require "ISUI/ISContextMenu"
        local playerNum=self.actor:getIndex()
        local menu=ISContextMenu.get(playerNum,screenX,screenY)

        local hasSources=row.sources and #row.sources>0
        local locateOpt=menu:addOption(text("locate"),self,function()
            self:locateSource()
        end)
        locateOpt.tooltip=text(hasSources and "locateHint" or "chooseSource")
        if not hasSources then locateOpt.notAvailable=true end

        if row.fullType and self.owner and self.owner.openPublicOrder then
            local orderOpt=menu:addOption(getText("IGUI_EmberRoutesProbe_Public_createOrder"),self,function()
                self.owner:openPublicOrder({productType=row.fullType})
            end)
            orderOpt.tooltip=getText("IGUI_EmberRoutesProbe_Public_createOrder")
        end

        local inCart=self.deliveryCart and self.deliveryCart[row.fullType]~=nil
        local cartLabel=inCart and text("removeFromCart") or text("addToCart")
        local cartOpt=menu:addOption(cartLabel,self,function()
            if inCart then self:removeFromDeliveryCart(row.fullType) else self:addToDeliveryCart(row,1) end
        end)
        cartOpt.tooltip=text("cartTitle")

        local pinLabel=text(row.pinned and "unpin" or "pin")
        local pinOpt=menu:addOption(pinLabel,self,function()
            self:togglePin(row)
        end)
        pinOpt.tooltip=text("pinHint")
    end

    function Page:onListJoypad(button)
            if button==Joypad.YButton then

            self.categories:selectNext() self:queryChanged()
        elseif button==Joypad.LBumper then
            if self.itemGrid then self.itemGrid:onMouseWheel(-4) end
        elseif button==Joypad.RBumper then
            if self.itemGrid then self.itemGrid:onMouseWheel(4) end
        elseif button==Joypad.LStickButton then self:clearSearch()
        elseif button==Joypad.RStickButton then
            self.controls.sort:selectNext() self:queryChanged()
        end
    end

    function Page:help()
        if self.helpModal then return end
        local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
        local modalW,modalH=400,240
        local modal=ISModalDialog:new((sw-modalW)/2,(sh-modalH)/2,modalW,modalH,
            getText('IGUI_EmberRoutesProbe_Settlement_coverageHint')..'\n\n'..getText('IGUI_EmberRoutesProbe_Settlement_shortHint'),false,self,function(_,btn)
                self.helpModal=nil
            end)
        modal:initialise()
        modal:addToUIManager()
        self.helpModal=modal
    end
end

return attach
