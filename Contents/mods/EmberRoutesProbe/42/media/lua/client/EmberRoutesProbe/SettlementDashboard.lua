require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Layout=require "EmberRoutesProbe/UI/Layout"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Tooltip=require "EmberRoutesProbe/UI/TooltipAnchor"
local Metrics=require "EmberRoutesProbe/WarehouseMetrics"
local Registry=require "EmberRoutesProbe/UI/PageRegistry"

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
---@field tabs string[]
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
    o.tabs=Registry.getTabIds(actor,entry)
    return o
end

function EmberRoutesSettlementDashboard:initialise() ISCollapsableWindow.initialise(self) end

function EmberRoutesSettlementDashboard:createChildren()
    ISCollapsableWindow.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local bar=self:titleBarHeight() local width=h*6
    self.activityButton=ISButton:new(self.width-width-bar*3,0,width,bar,
        getText('IGUI_EmberRoutesProbe_Activity_title'),self,function(owner)
            if owner:valid() then require('EmberRoutesProbe/UI/ActivityDialog').open(owner) end
        end)
    self.activityButton:initialise() Theme.button(self.activityButton,false) self:addChild(self.activityButton)
    self.title=require('EmberRoutesProbe/UI/Text').wrapLimited(self.title,
        math.max(h*4,self.width-2*(width+bar*3)),UIFont.Small,1)[1] or self.title
    local regions=assert(Layout.axis({x=0,y=self:titleBarHeight(),width=self.width,height=self.height-self:titleBarHeight()},
        {{basis=h+p},{grow=1},{basis=h}},{direction="column",padding=p,gap=p/2}))
    self.pageBounds=regions[2]
    self.footerBounds=regions[3]

    self.tabs=Registry.getTabIds(self.actor,self.entry)
    local tracks={}
    for _ in ipairs(self.tabs) do tracks[#tracks+1]={grow=1} end
    local top=assert(Layout.axis(regions[1],tracks,{gap=p/2}))
    for i,id in ipairs(self.tabs) do
        local r=top[i]
        local def=Registry.get(id)
        local titleKey=def and def.titleKey or ("tab_"..id)
        local button=ISButton:new(r.x,r.y,r.width,r.height,text(titleKey),self,EmberRoutesSettlementDashboard.tabClicked)
        button.internal=id
        button:initialise()
        Theme.styleButton(button,false,id==self.initialTab)
        button.tooltip=text(def and def.tooltipKey or "tabNavigation")
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
    local module=Registry.getModule(id)
    if not module then return end
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
        page=require("EmberRoutesProbe/UI/"..module):new(self,self.pageBounds)
        page:initialise()
        self.pages[id]=page
        self:addChild(page)
    end
    self.activeTab=id
    page:setVisible(true)
    page:activate()
    if self.disposed or self.activeTab~=id then return end

    local def=Registry.get(id)
    local parentTab=def and def.parentTab
    for key,button in pairs(self.tabButtons) do
        local chosen=(key==id) or (parentTab and key==parentTab)
        Theme.styleButton(button,chosen,chosen)
    end

    local footer=Registry.getFooter(id,page)
    if footer then
        self:setFooter(footer)
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
    local def=Registry.get(self.activeTab)
    if def and def.parentTab then
        self:selectTab(def.parentTab)
        return
    end
    local tabs=self.tabs or Registry.getTabIds(self.actor,self.entry)
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
    if self.activityDialog then self.activityDialog:close() end
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
