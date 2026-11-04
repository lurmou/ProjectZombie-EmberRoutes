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
    o.groupButtons={}
    o.groupMemory={}
    o.nextCheck=0
    o.initialTab=tabId or "warehouse"
    o.tabs=Registry.getTabIds(actor,entry)
    return o
end

function EmberRoutesSettlementDashboard:initialise() ISCollapsableWindow.initialise(self) end

function EmberRoutesSettlementDashboard:createChildren()
    ISCollapsableWindow.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local bar=self:titleBarHeight()
    self.title=require('EmberRoutesProbe/UI/Text').wrapLimited(self.title,
        math.max(h*4,self.width-bar*3),UIFont.Small,1)[1] or self.title
    local regions=assert(Layout.axis({x=0,y=self:titleBarHeight(),width=self.width,height=self.height-self:titleBarHeight()},
        {{basis=(h+p)*2},{grow=1},{basis=h}},{direction="column",padding=p,gap=p/2}))
    self.pageBounds=regions[2]
    self.footerBounds=regions[3]

    self.tabs=Registry.getTabIds(self.actor,self.entry)
    local rows=assert(Layout.axis(regions[1],{{grow=1},{grow=1}},{direction="column",gap=p/2}))
    self.tabRow=rows[2]
    local tracks={}
    for _ in ipairs(Registry.groups) do tracks[#tracks+1]={grow=1} end
    local top=assert(Layout.axis(rows[1],tracks,{gap=p/2}))
    for i,group in ipairs(Registry.groups) do
        local r=top[i]
        local button=ISButton:new(r.x,r.y,r.width,r.height,text(group.titleKey),self,EmberRoutesSettlementDashboard.groupClicked)
        button.internal=group.id
        button:initialise()
        Theme.styleButton(button,false,false)
        button.tooltip=text("tabNavigation")
        Tooltip.attach(button,"prerender")
        self:addChild(button)
        self.groupButtons[group.id]=button
    end
    -- Keep one owned button per registered tab; only the current group's row is visible.
    for _,id in ipairs(self.tabs) do
        local def=Registry.get(id)
        local button=ISButton:new(0,0,1,1,text(def.titleKey),self,EmberRoutesSettlementDashboard.tabClicked)
        button.internal=id
        button:initialise()
        button:setVisible(false)
        button.tooltip=text(def.tooltipKey or "tabNavigation")
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

function EmberRoutesSettlementDashboard:selectGroup(id)
    for _,group in ipairs(Registry.groups) do
        if group.id==id then return self:selectTab(self.groupMemory[id] or group.defaultTab) end
    end
    return false,"UNKNOWN_GROUP"
end

function EmberRoutesSettlementDashboard:groupClicked(button) self:selectGroup(button.internal) end

function EmberRoutesSettlementDashboard:updateNavigation(id)
    local group=Registry.getGroup(id)
    self.activeGroup=group
    self.groupMemory[group]=id
    local tabs=Registry.getGroupTabIds(group,self.actor,self.entry)
    local tracks={}
    for _ in ipairs(tabs) do tracks[#tracks+1]={grow=1} end
    local bounds=assert(Layout.axis(self.tabRow,tracks,{gap=self.pad/2}))
    for key,button in pairs(self.tabButtons) do button:setVisible(false) end
    local def=Registry.get(id)
    for i,key in ipairs(tabs) do
        local button,r=self.tabButtons[key],bounds[i]
        button:setX(r.x) button:setY(r.y) button:setWidth(r.width) button:setHeight(r.height)
        button:setVisible(true)
        local chosen=key==id or key==def.parentTab
        Theme.styleButton(button,chosen,chosen)
    end
    for key,button in pairs(self.groupButtons) do Theme.styleButton(button,key==group,key==group) end
end

function EmberRoutesSettlementDashboard:selectTab(id,context)
    local module=Registry.getModule(id)
    if not module then return false,"UNKNOWN_TAB" end
    if not Registry.validateContext(context) then return false,"INVALID_CONTEXT" end
    local def=Registry.get(id)
    local visible=Registry.getTabIds(self.actor,self.entry)
    local found=false
    for _,tab in ipairs(visible) do if tab==(def.parentTab or id) then found=true break end end
    if not found then return false,"HIDDEN_TAB" end
    if not self:valid() then self:close() return end
    local page=self.pages[id]
    if context then
        local class=require("EmberRoutesProbe/UI/"..module)
        if not class.resolveContext then return false,"CONTEXT_UNSUPPORTED" end
        local target,reason=class.resolveContext(page or setmetatable({actor=self.actor,entry=self.entry},{__index=class}),context)
        if not target then return false,reason end
    end
    if id==self.activeTab then
        if context and not page:applyContext(context) then return false,"TARGET_NOT_FOUND" end
        if page and page.focusContent then page:focusContent() end
        return true
    end
    if self.publicDialog then self.publicDialog:close() end
    if self.priorityDialog then self.priorityDialog:close() end
    local previousId=self.activeTab
    local previous=self.activeTab and self.pages[self.activeTab]
    self.activeTab=nil
    if previous then previous:deactivate() previous:setVisible(false) end
    if not page then
        page=require("EmberRoutesProbe/UI/"..module):new(self,self.pageBounds)
        page:initialise()
        self.pages[id]=page
        self:addChild(page)
    end
    self.activeTab=id
    page:setVisible(true)
    page:activate()
    if self.disposed or self.activeTab~=id then return false,"UI_SUBSCRIBER_ERROR" end

    if context and not page:applyContext(context) then
        page:deactivate() page:setVisible(false) self.activeTab=nil
        if previousId then self:selectTab(previousId) end
        return false,"TARGET_NOT_FOUND"
    end
    self:updateNavigation(id)

    local footer=Registry.getFooter(id,page)
    if footer then
        self:setFooter(footer)
    end

    if page.focusContent then page:focusContent() end
    return true
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
    local tabs=Registry.getGroupTabIds(self.activeGroup,self.actor,self.entry)
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
    for _,page in pairs(self.pages) do
        if page.dispose then
            page:dispose()
        elseif page.deactivate then
            page:deactivate()
        end
        -- Explicitly release this page's entire tooltip subtree.
        Tooltip.unregisterOwner(page)
    end
    for _,button in pairs(self.tabButtons) do
        Tooltip.clear(button)
    end
    for _,button in pairs(self.groupButtons) do Tooltip.clear(button) end
    -- Final safety net for dashboard-owned widgets and dialogs.
    Tooltip.unregisterOwner(self)
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

function EmberRoutesSettlementDashboard.open(actor,id,tabId,context)
    if opened and not opened:valid() then opened:close() end
    if not Ledger.authorized(actor) then return nil,"DRIVER_UNAVAILABLE" end
    local entry,reason=Ledger.view(actor,id)
    if not entry then return nil,reason end
    if opened and opened.actor==actor and opened.entry.id==id and opened:valid() then
        local panel=opened
        local ok,navReason=panel:selectTab(tabId or panel.activeTab or "warehouse",context)
        if not ok then return nil,navReason end
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
    local ok,navReason=panel:selectTab(panel.initialTab,context)
    if not ok then panel:close() Metrics.finish("ui.open",measured) return nil,navReason end
    Metrics.finish("ui.open",measured)
    if panel.disposed then return nil,"UI_SUBSCRIBER_ERROR" end
    return panel
end

return EmberRoutesSettlementDashboard
