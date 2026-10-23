require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Layout=require "EmberRoutesProbe/UI/Layout"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Tooltip=require "EmberRoutesProbe/UI/TooltipAnchor"
local Metrics=require "EmberRoutesProbe/WarehouseMetrics"
local tabs={"warehouse","orders","personnel","defense"}
local modules={
    warehouse="WarehousePage",
    orders="OrderMonitorPage",
    personnel="PersonnelPage",
    defense="DefensePage",
    logistics="LogisticsPage",
    crafting="CraftingPage"
}
local opened
local function text(key) return getText("IGUI_EmberRoutesProbe_Settlement_"..key) end

---@class EmberRoutesSettlementDashboard:ISCollapsableWindow
---@field actor IsoPlayer
---@field entry EmberRoutesSettlement
---@field world table
---@field pages table
---@field tabButtons table
---@field pageBounds table
---@field activeTab string?
---@field initialTab string
---@field disposed boolean?
---@field fontHeight number
---@field pad number
---@field nextCheck number
EmberRoutesSettlementDashboard=ISCollapsableWindow:derive("EmberRoutesSettlementDashboard")

---@param actor IsoPlayer
---@param entry EmberRoutesSettlement
---@param tabId string?
---@return EmberRoutesSettlementDashboard
function EmberRoutesSettlementDashboard:new(actor,entry,tabId)
    local h=getTextManager():getFontHeight(UIFont.Small)
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    local w,height=math.min(sw*0.92,h*48),math.min(sh*0.94,h*32)
    ---@type EmberRoutesSettlementDashboard
    local o=ISCollapsableWindow.new(self,(sw-w)/2,(sh-height)/2,w,height)
    o.actor,o.entry,o.world=actor,entry,Ledger.data()
    o.fontHeight,o.pad=h,math.ceil(h*0.6)
    o.title=text("management").." - "..entry.name
    o.resizable=false
    o.backgroundColor,o.borderColor=Theme.window,Theme.border
    o.pages={}
    o.tabButtons={}
    o.nextCheck=0
    o.initialTab=tabId or "warehouse"
    return o
end

function EmberRoutesSettlementDashboard:initialise() ISCollapsableWindow.initialise(self) end

function EmberRoutesSettlementDashboard:createChildren()
    ISCollapsableWindow.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local regions=assert(Layout.axis({x=0,y=self:titleBarHeight(),width=self.width,height=self.height-self:titleBarHeight()},
        {{basis=h+p},{grow=1},{basis=h}},{direction="column",padding=p,gap=p/2}))
    self.pageBounds=regions[2]
    self.footerBounds=regions[3]

    local tracks={}
    for _ in ipairs(tabs) do tracks[#tracks+1]={grow=1} end
    local top=assert(Layout.axis(regions[1],tracks,{gap=p/2}))
    for i,id in ipairs(tabs) do
        local r=top[i]
        local button=ISButton:new(r.x,r.y,r.width,r.height,text("tab_"..id),self,EmberRoutesSettlementDashboard.tabClicked)
        button.internal=id
        button:initialise()
        Theme.styleButton(button,false,id==self.initialTab)
        button.tooltip=text("tabNavigation")
        Tooltip.attach(button,"prerender")
        self:addChild(button)
        self.tabButtons[id]=button
    end

    self:setWantKeyEvents(true)
end

function EmberRoutesSettlementDashboard:valid()
    return not self.disposed and self.world==Ledger.data() and getSpecificPlayer(self.actor:getIndex())==self.actor
        and Ledger.authorized(self.actor) and Ledger.view(self.actor,self.entry.id)~=nil
end

function EmberRoutesSettlementDashboard:selectTab(id)
    if not modules[id] then return end
    if not self:valid() then self:close() return end
    if id==self.activeTab then
        if self.pages[id] and self.pages[id].focusContent then self.pages[id]:focusContent() end
        return
    end
    if self.publicDialog then self.publicDialog:close() end
    if self.priorityDialog then self.priorityDialog:close() end
    local previous=self.activeTab and self.pages[self.activeTab]
    self.activeTab=nil
    if previous then previous:deactivate() previous:setVisible(false) end
    local page=self.pages[id]
    if not page then
        local module=modules[id]
        page=require("EmberRoutesProbe/UI/"..module):new(self,self.pageBounds)
        page:initialise()
        self.pages[id]=page
        self:addChild(page)
    end
    self.activeTab=id
    page:setVisible(true)
    page:activate()
    if self.disposed or self.activeTab~=id then return end
    for key,button in pairs(self.tabButtons) do
        local chosen=key==id or key=='orders' and (id=='crafting' or id=='logistics')
        Theme.styleButton(button,chosen,chosen)
    end
    if id=='warehouse' then
        self:setFooter(getText('IGUI_EmberRoutesProbe_Monitor_warehouseFooter'))
    elseif id=='orders' then
        -- Orders page updates its own footer with order summary
    elseif id=='personnel' then
        self:setFooter(getText('IGUI_EmberRoutesProbe_Personnel_priorityHint'))
    elseif id=='defense' then
        self:setFooter(getText('IGUI_EmberRoutesProbe_Defense_alertHint'))
    else
        self:setFooter(getText('IGUI_EmberRoutesProbe_Monitor_compatFooter'))
    end
    if page.focusContent then page:focusContent() end
end

function EmberRoutesSettlementDashboard:setFooter(value)
    self.footerText=require('EmberRoutesProbe/UI/Text').wrapLimited(value,self.footerBounds.width,UIFont.Small,1)[1]
end

function EmberRoutesSettlementDashboard:prerender()
    ISCollapsableWindow.prerender(self)
    if self.footerText then Theme.text(self,self.footerText,self.footerBounds.x,self.footerBounds.y,Theme.muted) end
end

function EmberRoutesSettlementDashboard:tabClicked(button) self:selectTab(button.internal) end

function EmberRoutesSettlementDashboard:nextTab(direction)
    if self.activeTab=='logistics' or self.activeTab=='crafting' then
        self:selectTab('orders')
        return
    end
    local index=1
    for i,id in ipairs(tabs) do if id==self.activeTab then index=i break end end
    self:selectTab(tabs[(index-1+direction+#tabs)%#tabs+1])
end

function EmberRoutesSettlementDashboard:isKeyConsumed(key)
    return not self.disposed and (key==Keyboard.KEY_PRIOR or key==Keyboard.KEY_NEXT or key==Keyboard.KEY_ESCAPE)
end

function EmberRoutesSettlementDashboard:onKeyPress(key)
    if not self:isKeyConsumed(key) then return end
    if key==Keyboard.KEY_ESCAPE then self:close()
    else self:nextTab(key==Keyboard.KEY_PRIOR and -1 or 1) end
end

function EmberRoutesSettlementDashboard:update()
    ISCollapsableWindow.update(self)
    if self.disposed then return end
    local now=getTimestampMs()
    if now<self.nextCheck then return end
    self.nextCheck=now+1000
    if not self:valid() then self:close() end
end

function EmberRoutesSettlementDashboard:close()
    if self.disposed then return end
    self.disposed=true
    self.activeTab=nil
    if self.publicDialog then self.publicDialog:close() end
    if self.priorityDialog then self.priorityDialog:close() end
    if opened==self then opened=nil end
    for _,page in pairs(self.pages) do page:dispose() end
    for _,button in pairs(self.tabButtons) do Tooltip.clear(button) end
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if self.actor:getJoypadBind()~=-1 then setJoypadFocus(self.actor:getIndex(),nil) end
end

function EmberRoutesSettlementDashboard:openPublicOrder(context)
    local Public=require 'EmberRoutesProbe/PublicWork'
    local available,reason=Public.available()
    if not available then self.actor:Say(require('EmberRoutesProbe/UI/OrderMonitorCards').reason(reason)) return end
    if not self:valid() then self:close() return end
    if self.publicDialog then self.publicDialog:close() end
    self.publicDialog=require('EmberRoutesProbe/UI/PublicOrderDialog').open(self,context)
end

function EmberRoutesSettlementDashboard:openPriorities()
    self:selectTab('personnel')
end

function EmberRoutesSettlementDashboard.open(actor,id,tabId)
    if opened and not opened:valid() then opened:close() end
    if not Ledger.authorized(actor) then return nil,"DRIVER_UNAVAILABLE" end
    local entry,reason=Ledger.view(actor,id)
    if not entry then return nil,reason end
    if opened and opened.actor==actor and opened.entry.id==id and opened:valid() then
        local panel=opened
        panel:selectTab(tabId or "warehouse")
        if panel.disposed then return nil,"UI_SUBSCRIBER_ERROR" end
        panel:bringToTop()
        return panel
    end
    if opened then opened:close() end
    local measured=Metrics.begin("ui.open")
    local panel=EmberRoutesSettlementDashboard:new(actor,entry,tabId)
    opened=panel
    panel:initialise()
    panel:addToUIManager()
    panel:selectTab(panel.initialTab)
    Metrics.finish("ui.open",measured)
    if panel.disposed then return nil,"UI_SUBSCRIBER_ERROR" end
    return panel
end

return EmberRoutesSettlementDashboard
