require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
local Ledger=require "EmberRoutesProbe/Settlement/SettlementLedger"
local Layout=require "EmberRoutesProbe/UI/Layout"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Tooltip=require "EmberRoutesProbe/UI/TooltipManager"
local Metrics=require "EmberRoutesProbe/Warehouse/WarehouseMetrics"
local Registry=require "EmberRoutesProbe/UI/PageRegistry"
local Clock = require "EmberRoutesProbe/Kernel/Clock"

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

EmberRoutesSettlementDashboard.PRESET_SIZES = {
    compact = { id = "compact", titleKey = "IGUI_EmberRoutesProbe_Size_Compact", w = 960, h = 600 },
    standard = { id = "standard", titleKey = "IGUI_EmberRoutesProbe_Size_Standard", w = 1140, h = 720 },
    large = { id = "large", titleKey = "IGUI_EmberRoutesProbe_Size_Large", w = 1360, h = 840 },
}
EmberRoutesSettlementDashboard.currentPreset = EmberRoutesSettlementDashboard.currentPreset or "standard"

---@param actor IsoPlayer
---@param entry EmberRoutesSettlement
---@param tabId string?
---@return EmberRoutesSettlementDashboard
function EmberRoutesSettlementDashboard:new(actor,entry,tabId)
    local h=getTextManager():getFontHeight(UIFont.Small)
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    local preset=EmberRoutesSettlementDashboard.PRESET_SIZES[EmberRoutesSettlementDashboard.currentPreset] or EmberRoutesSettlementDashboard.PRESET_SIZES.standard
    local w=math.min(sw-20,math.max(760,preset.w))
    local height=math.min(sh-20,math.max(520,preset.h))
    local posX=math.floor((sw-w)/2)
    local posY=math.floor((sh-height)/2)

    ---@type EmberRoutesSettlementDashboard
    local o=ISCollapsableWindow.new(self,posX,posY,w,height)
    o.actor,o.entry,o.world=actor,entry,Ledger.data()
    o.fontHeight,o.pad=h,math.ceil(h*0.6)
    o.title=text("management").." - "..entry.name
    o.resizable=false
    o.titlebarbkg=nil
    o.backgroundColor,o.borderColor=Theme.window,Theme.border
    o.pages={}
    o.tabButtons={}
    o.groupButtons={}
    o.groupMemory={}
    o.nextCheck=0
    o.initialTab=tabId or "overview"
    o.tabs=Registry.getTabIds(actor,entry)
    return o
end

function EmberRoutesSettlementDashboard:initialise() ISCollapsableWindow.initialise(self) end

function EmberRoutesSettlementDashboard:setX(x)
    local oldX = self.x or x
    ISCollapsableWindow.setX(self, x)
    local dx = x - oldX
    if dx ~= 0 and self.activeTab and self.pages[self.activeTab] then
        local page = self.pages[self.activeTab]
        if page.dossierDrawer and page.dossierDrawer:getIsVisible() then
            page.dossierDrawer:setX(page.dossierDrawer.x + dx)
        end
        if page.cartDrawer and page.cartDrawer:getIsVisible() then
            page.cartDrawer:setX(page.cartDrawer.x + dx)
        end
    end
end

function EmberRoutesSettlementDashboard:setY(y)
    local oldY = self.y or y
    ISCollapsableWindow.setY(self, y)
    local dy = y - oldY
    if dy ~= 0 and self.activeTab and self.pages[self.activeTab] then
        local page = self.pages[self.activeTab]
        if page.dossierDrawer and page.dossierDrawer:getIsVisible() then
            page.dossierDrawer:setY(page.dossierDrawer.y + dy)
        end
        if page.cartDrawer and page.cartDrawer:getIsVisible() then
            page.cartDrawer:setY(page.cartDrawer.y + dy)
        end
    end
end

function EmberRoutesSettlementDashboard:toggleSizePreset()
    local order={"compact","standard","large"}
    local nextPreset="standard"
    for i,p in ipairs(order) do
        if p==EmberRoutesSettlementDashboard.currentPreset then
            nextPreset=order[(i%#order)+1]
            break
        end
    end
    EmberRoutesSettlementDashboard.currentPreset=nextPreset
    self:applyPresetSize(nextPreset)
end

function EmberRoutesSettlementDashboard:applyPresetSize(presetId)
    local preset=EmberRoutesSettlementDashboard.PRESET_SIZES[presetId] or EmberRoutesSettlementDashboard.PRESET_SIZES.standard
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    local w=math.min(sw-20,math.max(760,preset.w))
    local height=math.min(sh-20,math.max(520,preset.h))
    local posX=math.floor((sw-w)/2)
    local posY=math.floor((sh-height)/2)

    self:setX(posX)
    self:setY(posY)
    self:setWidth(w)
    self:setHeight(height)

    local bar=self:titleBarHeight()
    local h,p=self.fontHeight,self.pad
    if self.closeButton then
        self.closeButton:setX(self.width-bar+2)
        self.closeButton:setY(2)
        self.closeButton:setWidth(bar-4)
        self.closeButton:setHeight(bar-4)
    end
    if self.sizeButton then
        local sizeBtnW=math.floor(h*5.5)
        self.sizeButton:setX(self.width-bar-sizeBtnW-4)
        self.sizeButton:setY(2)
        self.sizeButton:setWidth(sizeBtnW)
        self.sizeButton:setHeight(bar-4)
        self.sizeButton:setTitle(getText(preset.titleKey))
    end

    local regions=assert(Layout.axis({x=0,y=bar,width=self.width,height=self.height-bar},
        {{basis=(h+p)*2},{grow=1},{basis=h}},{direction="column",padding=p,gap=p/2}))
    self.pageBounds=regions[2]
    self.basePageBounds={x=regions[2].x,y=regions[2].y,width=regions[2].width,height=regions[2].height}
    self.footerBounds=regions[3]

    local rows=assert(Layout.axis(regions[1],{{grow=1},{grow=1}},{direction="column",gap=p/2}))
    self.tabRow=rows[2]
    local tracks={}
    for _ in ipairs(Registry.groups) do tracks[#tracks+1]={grow=1} end
    local top=assert(Layout.axis(rows[1],tracks,{gap=p/2}))
    for i,group in ipairs(Registry.groups) do
        local r=top[i]
        local button=self.groupButtons[group.id]
        if button then
            button:setX(r.x) button:setY(r.y) button:setWidth(r.width) button:setHeight(r.height)
        end
    end

    if self.activeTab then
        self:updateNavigation(self.activeTab)
        local page=self.pages[self.activeTab]
        if page then
            local single=#Registry.getGroupTabIds(Registry.getGroup(self.activeTab),self.actor,self.entry)==1
            local lift=single and (self.tabRow.height+self.pad/2) or 0
            page:setX(self.basePageBounds.x)
            page:setY(self.basePageBounds.y-lift)
            page:setWidth(self.basePageBounds.width)
            page:setHeight(self.basePageBounds.height+lift)
            if page.onResize then page:onResize() end
        end
    end
end

function EmberRoutesSettlementDashboard:createChildren()
    ISCollapsableWindow.createChildren(self)
    if self.setResizable then self:setResizable(false) else self.resizable = false end
    if self.resizeWidget then self.resizeWidget:setVisible(false) end
    if self.resizeWidget2 then self.resizeWidget2:setVisible(false) end

    local h,p=self.fontHeight,self.pad
    local bar=self:titleBarHeight()

    if self.collapseButton then self.collapseButton:setVisible(false) end
    if self.pinButton then self.pinButton:setVisible(false) end

    if self.closeButton then
        self.closeButton:setX(self.width-bar+2)
        self.closeButton:setY(2)
        self.closeButton:setWidth(bar-4)
        self.closeButton:setHeight(bar-4)
    end

    local preset=EmberRoutesSettlementDashboard.PRESET_SIZES[EmberRoutesSettlementDashboard.currentPreset] or EmberRoutesSettlementDashboard.PRESET_SIZES.standard
    local sizeBtnW=math.floor(h*5.5)
    self.sizeButton=ISButton:new(self.width-bar-sizeBtnW-4,2,sizeBtnW,bar-4,getText(preset.titleKey),self,EmberRoutesSettlementDashboard.toggleSizePreset)
    self.sizeButton:initialise()
    Theme.styleButton(self.sizeButton,false,false)
    self.sizeButton.tooltip=getText("IGUI_EmberRoutesProbe_Size_Tooltip")
    Tooltip.register(self.sizeButton,{method="prerender"})
    self:addChild(self.sizeButton)

    local regions=assert(Layout.axis({x=0,y=bar,width=self.width,height=self.height-bar},
        {{basis=(h+p)*2},{grow=1},{basis=h}},{direction="column",padding=p,gap=p/2}))
    self.pageBounds=regions[2]
    self.basePageBounds={x=regions[2].x,y=regions[2].y,width=regions[2].width,height=regions[2].height}
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
        Tooltip.register(button,{method="prerender"})
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
        Tooltip.register(button,{method="prerender"})
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
    local definition=Registry.get(id)
    self.groupMemory[group]=definition.isTab==false and definition.parentTab or id
    local tabs=Registry.getGroupTabIds(group,self.actor,self.entry)
    if #tabs==1 then tabs={} end
    local tracks={}
    for _ in ipairs(tabs) do tracks[#tracks+1]={grow=1} end
    local bounds=#tracks>0 and assert(Layout.axis(self.tabRow,tracks,{gap=self.pad/2})) or {}
    for key,button in pairs(self.tabButtons) do button:setVisible(false) end
    local def=Registry.get(id)
    for i,key in ipairs(tabs) do
        local button,r=self.tabButtons[key],bounds[i]
        button:setX(r.x) button:setY(r.y) button:setWidth(r.width) button:setHeight(r.height)
        button:setVisible(true)
        local chosen=key==id or def.isTab==false and key==def.parentTab
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
    for _,tab in ipairs(visible) do if tab==(def.isTab==false and def.parentTab or id) then found=true break end end
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
        local b=self.basePageBounds
        local single=#Registry.getGroupTabIds(Registry.getGroup(id),self.actor,self.entry)==1
        local lift=single and (self.tabRow.height+self.pad/2) or 0
        page=require("EmberRoutesProbe/UI/"..module):new(self,{x=b.x,y=b.y-lift,width=b.width,height=b.height+lift})
        page:initialise()
        self.pages[id]=page
        self:addChild(page)
    end
    local single=#Registry.getGroupTabIds(Registry.getGroup(id),self.actor,self.entry)==1
    local lift=single and (self.tabRow.height+self.pad/2) or 0
    page:setX(self.basePageBounds.x)
    page:setY(self.basePageBounds.y-lift)
    page:setWidth(self.basePageBounds.width)
    page:setHeight(self.basePageBounds.height+lift)
    if page.onResize then page:onResize() end
    self.activeTab=id
    page:setVisible(true)
    if page.prepareContext then page:prepareContext(context) end
    page:activate()
    if self.disposed or self.activeTab~=id then return false,"UI_SUBSCRIBER_ERROR" end

    if context and not page:applyContext(context) then
        page:deactivate() page:setVisible(false) self.activeTab=nil
        if previousId then self:selectTab(previousId) end
        return false,"TARGET_NOT_FOUND"
    end
    self:updateNavigation(id)


    if page.focusContent then page:focusContent() end
    return true
end

function EmberRoutesSettlementDashboard:projectAlerts(snapshot)
    local counts,targets={},{}
    for _,alert in ipairs(snapshot.alerts or {}) do
        counts[alert.kind]=(counts[alert.kind] or 0)+1 targets[alert.kind]=targets[alert.kind] or alert
    end
    self.alertTargets=targets
    self.alertCounts=counts
end


function EmberRoutesSettlementDashboard:prerender()
    local bar=self:titleBarHeight()
    local h,p=self.fontHeight,self.pad
    local winW=self.width
    local winH=self.height

    -- 1. Window Background and Clean Border
    self:drawRect(0,0,winW,winH,self.backgroundColor.a,self.backgroundColor.r,self.backgroundColor.g,self.backgroundColor.b)
    self:drawRectBorder(0,0,winW,winH,self.borderColor.a,self.borderColor.r,self.borderColor.g,self.borderColor.b)

    -- 2. CleanUI Style Pure Dark Title Bar & Subtle Divider
    local cb = Theme.cardHeader or Theme.panel
    self:drawRect(1,1,winW-2,bar-1,cb.a or 1.0,cb.r,cb.g,cb.b)
    local bs = Theme.borderSubtle or Theme.border
    self:drawRect(0,bar,winW,1,bs.a or 0.85,bs.r,bs.g,bs.b)

    -- 3. Clean Title (No side accent line)
    Theme.text(self,self.title,p,math.floor((bar-h)/2),Theme.textColor)

end

function EmberRoutesSettlementDashboard:tabClicked(button) self:selectTab(button.internal) end

function EmberRoutesSettlementDashboard:nextTab(direction)
    local def=Registry.get(self.activeTab)
    if def and def.isTab==false and def.parentTab then
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
    if key==Keyboard.KEY_ESCAPE and self.activeTab=="crafting" then self.pages.crafting:returnWarehouse() return end
    if key==Keyboard.KEY_ESCAPE then self:close()
    else self:nextTab(key==Keyboard.KEY_PRIOR and -1 or 1) end
end

function EmberRoutesSettlementDashboard:update()
    ISCollapsableWindow.update(self)
    if self.disposed then return end
    local now=Clock.nowMs()
    if now<self.nextCheck then return end
    self.nextCheck=now+1000
    if not self.nextOverview or now>=self.nextOverview then
        self.nextOverview=now+5000
        self:projectAlerts(require('EmberRoutesProbe/Work/WorkOverviewService').status(self.actor,self.entry.id))
    end
    if not self:valid() then self:close() end
end

function EmberRoutesSettlementDashboard:close()
    if self.disposed then return end
    require('EmberRoutesProbe/UI/PageLifecycle').unmount(self)
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
    local Public=require 'EmberRoutesProbe/Work/PublicWork'
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
        local ok,navReason=panel:selectTab(tabId or panel.activeTab or "overview",context)
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
