local Tooltip=require "EmberRoutesProbe/UI/TooltipAnchor"
require "ISUI/ISPanel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "ISUI/ISButton"
require "ISUI/ISModalDialog"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Index=require "EmberRoutesProbe/WarehouseIndex"
local Query=require "EmberRoutesProbe/WarehouseQuery"
local Controls=require "EmberRoutesProbe/UI/WarehouseControls"
local Input=require "EmberRoutesProbe/UI/WarehouseInput"
local Locator=require "EmberRoutesProbe/WarehouseLocator"
local Selector=require "EmberRoutesProbe/UI/SettlementSelector"
local Cached=require "EmberRoutesProbe/UI/CachedList"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Presentation=require "EmberRoutesProbe/UI/ItemPresentation"
local Details=require "EmberRoutesProbe/UI/WarehouseDetails"
local Summary=require "EmberRoutesProbe/UI/CompactSummaryStrip"
local Rows=require "EmberRoutesProbe/UI/WarehouseRows"
local CartDrawer=require "EmberRoutesProbe/UI/DeliveryCartDrawer"
local Layout=require "EmberRoutesProbe/UI/Layout"
local Text=require "EmberRoutesProbe/UI/Text"
local State=require "EmberRoutesProbe/UI/State"
local Metrics=require "EmberRoutesProbe/WarehouseMetrics"
---@class EmberRoutesWarehousePage:ISPanel
---@field actor IsoPlayer
---@field entry EmberRoutesSettlement
---@field fontHeight number
---@field pad number
---@field store EmberRoutesUIStore
---@field summary table
---@field presentation table
---@field details table
---@field helpButton ISButton
---@field helpModal ISModalDialog?
---@field hintLines string[]
---@field itemNames table<string,string>
---@field itemGrid table
---@field sourceList EmberRoutesCachedList
---@field search ISTextEntryBox
---@field categories ISComboBox
---@field categoryIds table
---@field actualPage integer
---@field pages integer
---@field pageCaption string
---@field pageX number
---@field pageY number
---@field hintY number
---@field listTitles table[]
---@field unsubscribe function?
---@field release function?
---@field controls table
---@field query table
---@field locator table
---@field focusedList EmberRoutesCachedList?
---@field previousButton ISButton
---@field nextButton ISButton
---@field refreshButton ISButton
---@field pageWidth number
---@field syncingPage boolean?
---@field notice string
---@field owner EmberRoutesSettlementDashboard
---@field active boolean?
---@field disposed boolean?
---@field resume table?
EmberRoutesWarehousePage=ISPanel:derive("EmberRoutesWarehousePage")
local Lifecycle=require "EmberRoutesProbe/UI/PageLifecycle"
local function text(key) return getText("IGUI_EmberRoutesProbe_Settlement_"..key) end
---@param owner EmberRoutesSettlementDashboard
---@param bounds table
---@return EmberRoutesWarehousePage
function EmberRoutesWarehousePage:new(owner,bounds)
    local actor,entry=owner.actor,owner.entry
    local h=getTextManager():getFontHeight(UIFont.Small)
    ---@type EmberRoutesWarehousePage
    local o=ISPanel.new(self,bounds.x,bounds.y,bounds.width,bounds.height)
    o.owner=owner o.background=false
    o.actor,o.entry,o.fontHeight,o.pad=actor,entry,h,math.ceil(h*0.6)
    o.backgroundColor=Theme.window
    o.borderColor=Theme.border o.presentation=Presentation.new()
    o.store=State.new({snapshot={state="UPDATING",rows={},counts={}},search="",category=false,page=1,sort="default",selection=false})
    o.itemNames={} o.actualPage=1 o.pages=1 o.pageCaption=""
    o.query=Query.new() o.locator=Locator.new(actor,entry.id) o.notice="" o.pinnedItems={}
    o.deliveryCart={} o.deliveryCartCount=0 o.deliveryCartTotalUnits=0 o.deliveryCartWeight=0 o.cartDrawerOpen=false
    return o
end
function EmberRoutesWarehousePage:initialise() ISPanel.initialise(self) end
function EmberRoutesWarehousePage:createChildren()
    ISPanel.createChildren(self)
    local h=self.fontHeight
    local compact=self.height<h*24
    if compact then self.pad=math.ceil(h*0.35) end
    local p=self.pad
    local regions=assert(Layout.axis({x=0,y=0,width=self.width,height=self.height},
        {{basis=math.floor(h*1.6+p/2)},{basis=h+p},{grow=1},{basis=h+p}},
        {direction="column",padding=p,gap=p/2}))
    self.summary=Summary.new(regions[1],h,p)
    self.controls=Controls.new(self,regions[2])
    self.search,self.categories,self.categoryIds=self.controls.search,self.controls.category,self.controls.categoryIds
    local columns=assert(Layout.axis(regions[3],{{grow=3},{grow=2}},{gap=p}))
    local Grid=require "EmberRoutesProbe/UI/WarehouseGrid"
    self.itemGrid=Grid.new(self,columns[1],EmberRoutesWarehousePage.selectItem,self.presentation)
    self:addChild(self.itemGrid)
    self.details=Details.new(self,columns[2],self.presentation)
    self.sourceList=self.details.list
    Input.focus(self,self.itemGrid)

    local footBounds={x=columns[1].x,y=regions[4].y,width=columns[1].width,height=regions[4].height}
    local foot=assert(Layout.axis(footBounds,{{grow=1.0},{grow=1.0},{grow=1.2},{grow=0.6}},{gap=p}))
    for i,definition in ipairs({
            {text("refresh"),EmberRoutesWarehousePage.refresh},
            {text("edit"),EmberRoutesWarehousePage.editArea},
            {getText("IGUI_EmberRoutesProbe_Warehouse_autoZoneBtn"),EmberRoutesWarehousePage.autoZoneSettlement},
            {text("help"),EmberRoutesWarehousePage.help}}) do
        local r=foot[i]
        local button=ISButton:new(r.x,r.y,r.width,r.height,definition[1],self,definition[2])
        button:initialise() Theme.button(button,i==1) self:addChild(button)
        if i==1 then self.refreshButton=button end
		if i==3 then button.tooltip=getText("IGUI_EmberRoutesProbe_Warehouse_autoZoneTooltip") Tooltip.attach(button,"prerender",self) end
		if i==4 then self.helpButton=button button.tooltip=text("coverageHint").."\n\n"..text("shortHint") Tooltip.attach(button,"prerender",self) end
    end
    local cartBtn=ISButton:new(columns[2].x,regions[4].y,columns[2].width,regions[4].height,
        getText('IGUI_EmberRoutesProbe_Warehouse_cartButton','0'),self,EmberRoutesWarehousePage.toggleCartDrawer)
    cartBtn:initialise() Theme.button(cartBtn) self:addChild(cartBtn)
    cartBtn.tooltip=getText('IGUI_EmberRoutesProbe_Warehouse_cartEmptyHint') self.cartButton=cartBtn
    Tooltip.attach(cartBtn,"prerender",self)

    local p2=self.summary.pills[2]
    self.containerPillBtn=ISButton:new(p2.x,p2.y,p2.width,p2.height,"",self,function()
        self:openContainerInspector()
    end)
    self.containerPillBtn:initialise()
    self.containerPillBtn.background=false
    self.containerPillBtn.backgroundColor={r=0,g=0,b=0,a=0}
    self.containerPillBtn.backgroundColorMouseOver={r=1,g=1,b=1,a=0.08}
    self.containerPillBtn.borderColor={r=0,g=0,b=0,a=0}
    self.containerPillBtn.tooltip=getText("IGUI_EmberRoutesProbe_Settlement_summaryMergedClickHint")
    self:addChild(self.containerPillBtn)
    Tooltip.attach(self.containerPillBtn,"prerender",self)
end
function EmberRoutesWarehousePage:activate()
    self.deliveryMiddleDown=type(isMouseButtonDown)=='function' and isMouseButtonDown(2) or false
    Lifecycle.mount(self,function(callback) return Index.watch(self.entry.id,callback) end,
        function(snapshot) self:receive(snapshot) end)
end
function EmberRoutesWarehousePage:deactivate()
    if self.active and (not self.resume or self.store.value.snapshot.state=="READY") then
        local selection=self.store.value.selection
        self.resume={fullType=selection and selection.fullType,page=self.actualPage,
            gridScroll=self.itemGrid and self.itemGrid.scrollY or 0}
    end
    Lifecycle.unmount(self)
    self.deliveryMiddleDown=nil
    if self.details then self.details:setVisible(true) end
    if self.cartDrawer then self.cartDrawer:dispose() self.cartDrawer=nil self.cartDrawerOpen=false end
    if self.containerInspectorDialog then self.containerInspectorDialog:close() self.containerInspectorDialog=nil end
    if self.cartButton then self.cartButton:setVisible(true) end
    if self.helpModal then self.helpModal:destroy() self.helpModal=nil end
    Tooltip.dismissOwner(self)
    self.locator:clear()
    for _,combo in ipairs({self.categories,self.controls.sort}) do
        if combo.expanded then combo:hidePopup() combo.expanded=false end
    end
    if self.search and self.search.unfocus then self.search:unfocus() end
end
function EmberRoutesWarehousePage:dispose()
    if self.disposed then return end
    self.disposed=true
    if self.cartDrawer then self.cartDrawer:dispose() self.cartDrawer=nil self.cartDrawerOpen=false end
    self:deactivate()
    Tooltip.unregisterOwner(self)
    self.presentation:clear()
end
function EmberRoutesWarehousePage:close() self.owner:close() end
function EmberRoutesWarehousePage:togglePin(row)
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
function EmberRoutesWarehousePage:focusContent()
    Input.focus(self,self.focusedList or self.itemGrid)
end
function EmberRoutesWarehousePage:receive(snapshot)
    if not self.active then return end
    local measured=Metrics.begin("ui.update")
    local copy={state=snapshot.state,counts=snapshot.counts,reason=snapshot.reason,revision=snapshot.revision,retain=snapshot.retain,rows={}}
    copy.rows=Rows.project(snapshot,self.store.value.snapshot.rows,function(fullType)
        local label=self.itemNames[fullType]
        if not label then
            local resolve=_G.getItemNameFromFullType
            label=type(resolve)=="function" and resolve(fullType) or fullType
            if not label or label=="" then label=fullType end
            self.itemNames[fullType]=label
        end
        return label
    end)
    if not self.resume and self.itemGrid and snapshot.state=='UPDATING' and not snapshot.retain then
        local selection=self.store.value.selection
        self.resume={fullType=selection and selection.fullType,page=self.actualPage,
            gridScroll=self.itemGrid.scrollY}
    end
    local restore=self.resume and snapshot.state=="READY"
    local selection=self.store.value.selection
    if restore then
        self.actualPage=self.resume.page
        selection=false
        for _,row in ipairs(copy.rows) do
            if row.fullType==self.resume.fullType then selection=row break end
        end
    end
    self.pinnedItems=self.pinnedItems or {}
    for _,r in ipairs(copy.rows) do
        if self.pinnedItems[r.fullType] then r.pinned=true end
    end
    self.store:setState({snapshot=copy,selection=selection})
    if restore then self.resume=nil end
    Metrics.finish("ui.update",measured)
end
function EmberRoutesWarehousePage:project(snapshot,changed)
    if not self.active then return end
    if changed.snapshot then
        local s=snapshot.snapshot
        local c=s.counts or {}
        local capRatio=c.usedWeight and c.totalCapacity and c.totalCapacity>0 and c.usedWeight/c.totalCapacity or nil
        if s.state=="READY" then
            self.summary:setValues({loaded=c.loaded.."/"..c.containers,unloaded=c.unloaded,private=c.private,
                missing=c.missing,limited=c.limited,items=c.items}, s.rows and #s.rows or nil)
            self.summary:setCoverage(c.usedWeight or c.loaded,c.totalCapacity or c.containers)
        elseif s.state~="UPDATING" or not s.retain then self.summary:setValues(nil) self.summary:setCoverage(nil,nil) end
        local note=""
        if s.state=="ERROR" and s.reason then note=text(s.reason)
        elseif s.state=="READY" and c and (c.fullCount or capRatio) then
            if c.fullCount and c.fullCount>0 then note="▲ "..c.fullCount.." "..text("limited")
            elseif capRatio then note=text(capRatio>0.8 and "capacityWarning" or "capacityAdequate").." ("..math.floor(capRatio*100).."%)" end
        end
        self.summary:setStatus(s.state,note)
    end
    if not self.syncingPage and (changed.snapshot or changed.search or changed.category or changed.sort or changed.page) then
        local explicit=changed.search or changed.category or changed.sort or changed.page
        if explicit then
            if self.itemGrid then self.itemGrid.scrollY=0 end
        end
        local measured=Metrics.begin("ui.query")
        local rows,_,_,total=self.query:all(snapshot.snapshot.rows,snapshot.search,snapshot.category,snapshot.sort)
        Metrics.finish("ui.query",measured)
        local allCount=#(snapshot.snapshot.rows or {})
        local isFiltered=(snapshot.search~="" or snapshot.category~=false)
        self.badgeStats={matched=total,total=allCount,isFiltered=isFiltered}
        if self.controls.clear then Theme.enable(self.controls.clear,snapshot.search~="") end
        Theme.enable(self.refreshButton,snapshot.snapshot.state~="UPDATING",true)
        if self.notice~="" then self.hintLines=Text.wrapLimited(text("shortHint"),self.width-self.pad*2,UIFont.Small,1) end
        self.notice=""

        local selection=nil
        if self.resume and snapshot.snapshot.state=="READY" then
            for _,row in ipairs(rows) do
                if row.fullType==self.resume.fullType then
                    selection=row
                    break
                end
            end
        end
        if not selection and snapshot.selection then
            for _,row in ipairs(rows) do
                if row.fullType==snapshot.selection.fullType then
                    selection=row
                    break
                end
            end
        end
        if not selection and #rows>0 then
            selection=rows[1]
        end

        if self.itemGrid then
            self.itemGrid:setRows(rows,selection)
            if self.resume and snapshot.snapshot.state=='READY' then
                self.itemGrid.scrollY=math.max(0,math.min(self.resume.gridScroll or 0,self.itemGrid.maxScrollY))
            end
            local gridEmpty=snapshot.snapshot.state=="UPDATING" and "waitingItems" or "noItems"
            self.itemGrid.emptyLabel=snapshot.snapshot.state=="ERROR" and text(snapshot.snapshot.reason or "ERROR") or text(gridEmpty)
        end
        self.syncingPage=true self.store:setState({page=snapshot.page or 1,selection=selection}) self.syncingPage=false
        if #rows==0 then self.details:setItem(nil) end
    end
    if changed.selection then
        self.details:setItem(snapshot.selection or nil)
    end
end
function EmberRoutesWarehousePage:queryChanged()
    if not self.active or not self.itemGrid then return end
    self.resume=nil
    self.store:setState({search=self.search:getText(),category=self.categoryIds[self.categories.selected] or false,page=1,
        sort=self.controls.sortIds[self.controls.sort.selected]})
end
function EmberRoutesWarehousePage:clearSearch() self.search:setText("") self:queryChanged() end
function EmberRoutesWarehousePage:focusList(list) Input.focus(self,list) end
function EmberRoutesWarehousePage:isListFocused(list) return self.active and Input.active(self,list) end
function EmberRoutesWarehousePage:onListActivate(list) Input.activate(self,list) end
function EmberRoutesWarehousePage:onListFocus(list,direction)
    if (list==self.itemGrid and direction==-1) or (list==self.sourceList and direction==1) then
        self.owner:nextTab(direction)
    else Input.other(self,list) end
end
function EmberRoutesWarehousePage:selectSource(source)
    self.details.selectedSource=source
    if self.details and self.details.updateCartButton then
        self.details:updateCartButton()
    end
end
function EmberRoutesWarehousePage:locateSource()
    local source=self.details.selectedSource
    if not source then return end
    local position,reason=self.locator:locate(source.id)
    self.notice=text(reason)..(position and (" "..position.x..", "..position.y.." | z="..position.z) or "")
    self.hintLines=Text.wrapLimited(self.notice,self.width-self.pad*2,UIFont.Small,1)
end
function EmberRoutesWarehousePage:selectItem(row)
    self.store:setState({selection=row})
    if self.itemGrid and row then
        for i,c in ipairs(self.itemGrid.cells) do
            if c.row.fullType==row.fullType then self.itemGrid.selected=i break end
        end
    end
end
function EmberRoutesWarehousePage:previous() self.store:setState({page=math.max(1,self.actualPage-1)}) end
function EmberRoutesWarehousePage:nextPage() self.store:setState({page=math.min(self.pages,self.actualPage+1)}) end
function EmberRoutesWarehousePage:onListKey(key,list) Input.key(self,key,list) end
function EmberRoutesWarehousePage:help()
    if self.helpModal then return end
    local w=math.min(self.width,self.fontHeight*36)
    local message=table.concat(Text.wrap(text("summaryNote").."\n\n"..text("coverageHint"),w-self.pad*4,UIFont.Small),"\n")
    local modal=ISModalDialog:new(self:getAbsoluteX()+(self.width-w)/2,self:getAbsoluteY()+self.fontHeight*2,w,0,message,false,self,
        function(target)
            target.helpModal=nil
            target:focusList(target.focusedList or target.itemGrid)
        end,self.actor:getIndex())
    -- Vanilla confirmation dialogs resume game speed on destroy. Read-only help
    -- owns only its UI lifetime and must preserve the player's pause/speed state.
    function modal:destroy() self:setVisible(false) self:removeFromUIManager() end
    self.helpModal=modal modal:initialise() modal:addToUIManager()
    if self.actor:getJoypadBind()~=-1 then setJoypadFocus(self.actor:getIndex(),modal) end
end
function EmberRoutesWarehousePage:refresh()
    if self.store.value.snapshot.state=="UPDATING" then return end
    if Ledger.authorized(self.actor) then Index.refresh(self.entry.id) end
end
function EmberRoutesWarehousePage:editArea()
    local actor,entry=self.actor,Ledger.get(self.entry.id)
    self:close()
    Selector.open(actor,entry,function(updated) require("EmberRoutesProbe/SettlementDashboard").open(actor,updated.id) end)
end
function EmberRoutesWarehousePage:autoZoneSettlement()
    local actor,entry=self.actor,Ledger.get(self.entry.id)
    if not actor or not entry then return end
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    local modalW,modalH=380,140
    local prompt=getText("IGUI_EmberRoutesProbe_Warehouse_autoZonePrompt")
    local modal=ISModalDialog:new((sw-modalW)/2,(sh-modalH)/2,modalW,modalH,prompt,true,self,function(_,button)
        if button.internal=="YES" then
            local Batch=require "EmberRoutesProbe/BatchStoragePainting"
            local containers=Batch.scanSettlement(entry)
            if #containers==0 then
                actor:Say(getText("IGUI_EmberRoutesProbe_Warehouse_autoZoneEmpty"))
                return
            end
            local result=Batch.apply(containers,"auto",actor)
            local msg=getText("IGUI_EmberRoutesProbe_Warehouse_autoZoneSuccess",tostring(result.updated))
            actor:Say(msg)
            self:refresh()
        end
    end)
    modal:initialise()
    modal:addToUIManager()
    if actor:getJoypadBind()~=-1 then setJoypadFocus(actor:getIndex(),modal) end
end
local function getItemWeight(fullType)
    local sm=type(getScriptManager)=="function" and getScriptManager()
    if sm then
        local s=sm:getItem(fullType)
        if s and s.getActualWeight then return s:getActualWeight() end
    end
    return 1.0
end

local function getItemStep(fullType)
    local w=getItemWeight(fullType)
    if w>=1.5 then return 1
    elseif w>=0.3 then return 5
    else return 20 end
end

function EmberRoutesWarehousePage:onMiddleClickItem(row,shiftDown)
    if not row or not row.fullType then return end
    local delta=shiftDown and -1 or 1
    self:addToDeliveryCart(row,delta)
    return true
end

function EmberRoutesWarehousePage:onMiddleClickSource(source,shiftDown)
    local row=self.details and self.details.row
    if not row or not row.fullType or not source then return end
    local delta=shiftDown and -1 or 1
    self:addToDeliveryCart(row,delta,source)
    return true
end

function EmberRoutesWarehousePage:addToDeliveryCart(row,delta,preferredSource)
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
        local sourceName=src and (src.customName and src.customName~='' and src.customName or src.kind or src.displayType or '仓库')
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

function EmberRoutesWarehousePage:removeFromDeliveryCart(cartKey)
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

function EmberRoutesWarehousePage:clearDeliveryCart()
    self.deliveryCart={}
    self.deliveryFeedback=nil
    self.deliveryFeedbackError=false
    self:updateDeliveryCartTotals()
    if self.cartDrawer and self.cartDrawer:isVisible() then
        self.cartDrawer:refresh()
    end
end

function EmberRoutesWarehousePage:updateDeliveryCartTotals()
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

function EmberRoutesWarehousePage:updateCartButtonVisual()
    if not self.cartButton then return end
    self.cartButton:setTitle(getText('IGUI_EmberRoutesProbe_Warehouse_cartButton',tostring(self.deliveryCartTotalUnits or 0)))
    self.cartButton.tooltip=getText('IGUI_EmberRoutesProbe_Warehouse_cartEmptyHint')
end

function EmberRoutesWarehousePage:toggleCartDrawer(forceState)
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

function EmberRoutesWarehousePage:openContainerInspector()
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

function EmberRoutesWarehousePage:dispatchDeliveryCart()
    if not self.deliveryCart or self.deliveryCartCount==0 then return end
    if not self.owner:valid() then self.owner:close() return end
    local items={}
    for cartKey,itm in pairs(self.deliveryCart) do
        items[#items+1]={
            fullType=itm.fullType,
            quantity=itm.count,
            sourceId=itm.source and itm.source.id or nil
        }
    end

    local PublicWork=require "EmberRoutesProbe/PublicWork"
    local result="DELIVERY_UNAVAILABLE"
    if PublicWork and PublicWork.createDeliveryOrder then
        self.deliveryRequestId=self.deliveryRequestId or require('EmberRoutesProbe/ContainerRegistry').id()
        result=PublicWork.createDeliveryOrder(self.actor,self.entry.id,items,self.deliveryRequestId)
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
        self.deliveryFeedback=getText('IGUI_EmberRoutesProbe_Warehouse_'..key)
        self:toggleCartDrawer(true)
        if _G.HaloTextHelper and HaloTextHelper.addBadText then HaloTextHelper.addBadText(self.actor,self.deliveryFeedback) end
    end
end

function EmberRoutesWarehousePage:openItemContextMenu(row,screenX,screenY)
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
        if inCart then self:removeFromDeliveryCart(row.fullType) else self:onMiddleClickItem(row,false) end
    end)
    cartOpt.tooltip=text("cartTitle")

    local pinLabel=text(row.pinned and "unpin" or "pin")
    local pinOpt=menu:addOption(pinLabel,self,function()
        self:togglePin(row)
    end)
    pinOpt.tooltip=text("pinHint")
end
function EmberRoutesWarehousePage:onListJoypad(button)
    if button==Joypad.XButton then self:refresh()
    elseif button==Joypad.YButton then
        self.categories.selected=self.categories.selected%#self.categoryIds+1 self:queryChanged()
    elseif button==Joypad.LBumper then
        if self.itemGrid then self.itemGrid:onMouseWheel(-4) end
    elseif button==Joypad.RBumper then
        if self.itemGrid then self.itemGrid:onMouseWheel(4) end
    elseif button==Joypad.LStickButton then self:clearSearch()
    elseif button==Joypad.RStickButton then
        self.controls.sort.selected=self.controls.sort.selected%#self.controls.sortIds+1 self:queryChanged()
    end
end
function EmberRoutesWarehousePage:update()
    ISPanel.update(self)
    Input.delivery(self)
end
function EmberRoutesWarehousePage:prerender()
    ISPanel.prerender(self)
    if not self.active then return end
    local measured=Metrics.begin("ui.panel")
    self.summary:draw(self)
    if self.details then self.details:draw() end
    Metrics.finish("ui.panel",measured)
end
return EmberRoutesWarehousePage
