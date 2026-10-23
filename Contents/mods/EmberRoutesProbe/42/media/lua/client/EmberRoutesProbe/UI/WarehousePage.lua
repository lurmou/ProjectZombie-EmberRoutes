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
local Table=require "EmberRoutesProbe/UI/WarehouseList"
local Details=require "EmberRoutesProbe/UI/WarehouseDetails"
local Summary=require "EmberRoutesProbe/UI/Summary"
local Rows=require "EmberRoutesProbe/UI/WarehouseRows"
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
---@field itemList EmberRoutesCachedList
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
        {{basis=h*4+p},{basis=h+p},{grow=1},{basis=h+p},{basis=h},{basis=h+p}},
        {direction="column",padding=p,gap=p/2}))
    self.summary=Summary.new(regions[1],{
        {id="loaded",label=text("loaded")},{id="unloaded",label=text("unloaded")},{id="private",label=text("private")},
        {id="missing",label=text("missing")},{id="limited",label=text("limited")},{id="items",label=text("instanceCount")}},h,p,
        {READY=text("summaryReady"),PARTIAL=text("summaryPartial"),UPDATING=text("summaryUpdating"),ERROR=text("summaryError")})
    self.controls=Controls.new(self,regions[2])
    self.search,self.categories,self.categoryIds=self.controls.search,self.controls.category,self.controls.categoryIds
    local columns=assert(Layout.axis(regions[3],{{grow=3},{grow=2}},{gap=p}))
    local parts=assert(Layout.axis(columns[1],{{basis=h+p/2},{grow=1}},{direction="column"}))
    self.itemList=Cached.create(self,parts[2],EmberRoutesWarehousePage.selectItem,
        Table.style(self.presentation,function(row) return row.label end))
    self.itemList.emberMetric="ui.items"
    Theme.list(self.itemList) self:addChild(self.itemList)
    local tableColumns=Table.columns(self.itemList,true)
    self.listTitles={{x=parts[1].x+tableColumns.name,y=parts[1].y,label=getText("IGUI_Name")},
        {x=self.itemList.x+self.itemList.width-h-p-getTextManager():MeasureStringX(UIFont.Small,text("quantity")),
        y=parts[1].y,label=text("quantity")}}
    self.details=Details.new(self,columns[2],self.presentation)
    self.sourceList=self.details.list
    Input.focus(self,self.itemList)
    local pages=assert(Layout.axis(regions[4],{{grow=1},{grow=3},{grow=1}},{gap=p}))
    self.pageX,self.pageY,self.pageWidth=pages[2].x,pages[2].y+p/2,pages[2].width
    for i,callback in ipairs({EmberRoutesWarehousePage.previous,EmberRoutesWarehousePage.nextPage}) do
        local r=pages[i==1 and 1 or 3]
        local button=ISButton:new(r.x,r.y,r.width,r.height,text(i==1 and "previous" or "next"),self,callback)
        button:initialise() Theme.button(button) self:addChild(button)
        if i==1 then self.previousButton=button else self.nextButton=button end
    end
    self.hintY=regions[5].y
    self.hintLines=Text.wrapLimited(text("shortHint"),regions[5].width,UIFont.Small,1)
    local foot=assert(Layout.axis(regions[6],{{grow=1.3},{grow=1.3},{grow=0.8}},{gap=p}))
    for i,definition in ipairs({{text("refresh"),EmberRoutesWarehousePage.refresh},
            {text("edit"),EmberRoutesWarehousePage.editArea},{text("help"),EmberRoutesWarehousePage.help}}) do
        local r=foot[i]
        local button=ISButton:new(r.x,r.y,r.width,r.height,definition[1],self,definition[2])
        button:initialise() Theme.button(button,i==1) self:addChild(button)
        if i==1 then self.refreshButton=button end
        if i==3 then self.helpButton=button button.tooltip=text("coverageHint") end
    end
end
function EmberRoutesWarehousePage:activate()
    Lifecycle.mount(self,function(callback) return Index.watch(self.entry.id,callback) end,
        function(snapshot) self:receive(snapshot) end)
end
function EmberRoutesWarehousePage:deactivate()
    if self.active then
        local selection=self.store.value.selection
        self.resume={fullType=selection and selection.fullType,page=self.actualPage,scroll=self.itemList:getYScroll()}
    end
    Lifecycle.unmount(self)
    if self.helpModal then self.helpModal:destroy() self.helpModal=nil end
    Tooltip.clear(self.itemList) Tooltip.clear(self.sourceList) Tooltip.clear(self.search)
    Tooltip.clear(self.helpButton) Tooltip.clear(self.controls.sort) Tooltip.clear(self.details.locate)
    self.locator:clear()
    for _,combo in ipairs({self.categories,self.controls.sort}) do
        if combo.expanded then combo:hidePopup() combo.expanded=false end
    end
    self.search:unfocus()
end
function EmberRoutesWarehousePage:dispose()
    if self.disposed then return end
    self.disposed=true self:deactivate() self.presentation:clear()
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
    self.details:setItem(row)
    self:project(self.store.value,{snapshot=true})
end
function EmberRoutesWarehousePage:focusContent()
    Input.focus(self,self.focusedList or self.itemList)
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
    local restore=self.resume and snapshot.state=="READY"
    local selection=self.store.value.selection
    if restore then
        self.actualPage=self.resume.page
        selection=false
        for _,row in ipairs(copy.rows) do
            if row.fullType==self.resume.fullType then selection=row break end
        end
    end
    self.store:setState({snapshot=copy,selection=selection})
    if restore then self.resume=nil end
        self.pinnedItems=self.pinnedItems or {}
    for _,r in ipairs(copy.rows) do
        if self.pinnedItems[r.fullType] then r.pinned=true end
    end
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
                missing=c.missing,limited=c.limited,items=c.items})
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
            self.itemList.selected=1 self.itemList:setYScroll(0) self.itemList.smoothScrollTargetY=nil
        end
        local anchor=not explicit and snapshot.selection and snapshot.selection.fullType or nil
        local measured=Metrics.begin("ui.query")
        local rows,page,pages,total=self.query:page(snapshot.snapshot.rows,snapshot.search,snapshot.category,
            explicit and snapshot.page or self.actualPage,snapshot.sort,anchor)
        Metrics.finish("ui.query",measured)
        self.actualPage,self.pages=page,pages
        local condition=self.categories.options[self.categories.selected].." / "..self.controls.sort.options[self.controls.sort.selected]
        self.pageCaption=table.concat(Text.wrapLimited(text("page")..page.."/"..pages.." | "..text("types")..total.." | "..condition,
            self.pageWidth,UIFont.Small,1),"")
        Theme.enable(self.previousButton,page>1) Theme.enable(self.nextButton,page<pages)
        Theme.enable(self.controls.clear,snapshot.search~="")
        Theme.enable(self.refreshButton,snapshot.snapshot.state~="UPDATING",true)
        if self.notice~="" then self.hintLines=Text.wrapLimited(text("shortHint"),self.width-self.pad*2,UIFont.Small,1) end
        self.notice=""
        local selection=Cached.reconcile(self.itemList,rows,function(row)
            return row.label.."\n"..text("quantity")..": "..(row.pending and "..." or tostring(row.count)).."\n"..row.fullType
        end,function(row) return row.fullType end,not explicit)
        if self.resume and snapshot.snapshot.state=="READY" then
            for i,entry in ipairs(self.itemList.items) do
                if entry.item.value.fullType==self.resume.fullType then
                    self.itemList.selected=i selection=entry.item.value break
                end
            end
            local total=0 for _,entry in ipairs(self.itemList.items) do total=total+entry.height end
            self.itemList:setYScroll(math.max(math.min(0,self.resume.scroll),math.min(0,self.itemList.height-total)))
        end
        local empty=snapshot.snapshot.state=="UPDATING" and "waitingItems" or "noItems"
        Table.empty(self,self.itemList,snapshot.snapshot.state=="ERROR" and text(snapshot.snapshot.reason or "ERROR") or text(empty))
        self.syncingPage=true self.store:setState({page=page,selection=selection}) self.syncingPage=false
        if #rows==0 then self.details:setItem(nil) end
    end
    if changed.selection then
        self.details:setItem(snapshot.selection or nil)
    end
end
function EmberRoutesWarehousePage:queryChanged()
    if not self.active or not self.itemList then return end
    self.store:setState({search=self.search:getText(),category=self.categoryIds[self.categories.selected] or false,page=1,
        sort=self.controls.sortIds[self.controls.sort.selected]})
end
function EmberRoutesWarehousePage:clearSearch() self.search:setText("") self:queryChanged() end
function EmberRoutesWarehousePage:focusList(list) Input.focus(self,list) end
function EmberRoutesWarehousePage:isListFocused(list) return self.active and Input.active(self,list) end
function EmberRoutesWarehousePage:onListActivate(list) Input.activate(self,list) end
function EmberRoutesWarehousePage:onListFocus(list,direction)
    if (list==self.itemList and direction==-1) or (list==self.sourceList and direction==1) then
        self.owner:nextTab(direction)
    else Input.other(self,list) end
end
function EmberRoutesWarehousePage:selectSource(source) self.details.selectedSource=source end
function EmberRoutesWarehousePage:locateSource()
    local source=self.details.selectedSource
    if not source then return end
    local position,reason=self.locator:locate(source.id)
    self.notice=text(reason)..(position and (" "..position.x..", "..position.y.." | z="..position.z) or "")
    self.hintLines=Text.wrapLimited(self.notice,self.width-self.pad*2,UIFont.Small,1)
end
function EmberRoutesWarehousePage:selectItem(row) self.store:setState({selection=row}) end
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
            target:focusList(target.focusedList or target.itemList)
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
function EmberRoutesWarehousePage:onListJoypad(button)
    if button==Joypad.XButton then self:refresh()
    elseif button==Joypad.YButton then
        self.categories.selected=self.categories.selected%#self.categoryIds+1 self:queryChanged()
    elseif button==Joypad.LBumper then self:previous()
    elseif button==Joypad.RBumper then self:nextPage()
    elseif button==Joypad.LStickButton then self:clearSearch()
    elseif button==Joypad.RStickButton then
        self.controls.sort.selected=self.controls.sort.selected%#self.controls.sortIds+1 self:queryChanged()
    end
end
function EmberRoutesWarehousePage:prerender()
    ISPanel.prerender(self)
    if not self.active then return end
    local measured=Metrics.begin("ui.panel")
    self.summary:draw(self)
    for _,title in ipairs(self.listTitles) do Theme.text(self,title.label,title.x,title.y,Theme.muted) end
    self.details:draw()
    self:drawText(self.pageCaption,self.pageX,self.pageY,0.9,0.85,0.65,1,UIFont.Small)
    for i,line in ipairs(self.hintLines) do self:drawText(line,self.pad,self.hintY+(i-1)*self.fontHeight,0.65,0.74,0.8,1,UIFont.Small) end
    Metrics.finish("ui.panel",measured)
end
return EmberRoutesWarehousePage
