require 'ISUI/ISPanel'
require 'ISUI/ISButton'
require 'ISUI/ISComboBox'
local Service=require 'EmberRoutesProbe/OrderMonitorService'
local Layout=require 'EmberRoutesProbe/UI/Layout'
local State=require 'EmberRoutesProbe/UI/State'
local Cached=require 'EmberRoutesProbe/UI/CachedList'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Lifecycle=require 'EmberRoutesProbe/UI/PageLifecycle'
local Tooltip=require 'EmberRoutesProbe/UI/TooltipAnchor'
local Cards=require 'EmberRoutesProbe/UI/OrderMonitorCards'
local text=Cards.text
local filters={'open','active','waiting','paused','attention','closed'}
---@class EmberRoutesOrderMonitorPage:ISPanel
---@field owner EmberRoutesSettlementDashboard
---@field actor IsoPlayer
---@field entry table
---@field fontHeight number
---@field pad number
---@field buttons table
---@field store table
---@field filterCombo ISComboBox
---@field narrow boolean
---@field orderList EmberRoutesCachedList
---@field details table
---@field selected table?
---@field focusedList EmberRoutesCachedList?
---@field notice string?
---@field noticeBounds table
---@field noticeLines table?
---@field active boolean?
---@field disposed boolean?
EmberRoutesOrderMonitorPage=ISPanel:derive('EmberRoutesOrderMonitorPage')
---@param owner EmberRoutesSettlementDashboard
---@param bounds {x:number,y:number,width:number,height:number}
---@return EmberRoutesOrderMonitorPage
function EmberRoutesOrderMonitorPage:new(owner,bounds)
    ---@type EmberRoutesOrderMonitorPage
    local o=ISPanel.new(self,bounds.x,bounds.y,bounds.width,bounds.height)
    o.owner,o.actor,o.entry=owner,owner.actor,owner.entry
    o.fontHeight,o.pad=owner.fontHeight,owner.pad o.background=false o.buttons={}
    o.store=State.new({snapshot={rows={}},selection=false,filter='open',detailMode=false})
    return o
end
function EmberRoutesOrderMonitorPage:initialise() ISPanel.initialise(self) end
function EmberRoutesOrderMonitorPage:createChildren()
    ISPanel.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local regions=assert(Layout.axis({x=0,y=0,width=self.width,height=self.height},
        {{basis=h+p},{basis=h+p},{grow=1},{basis=h+p},{basis=h*2+p}},
        {direction='column',padding=p,gap=p/2}))
    local top=assert(Layout.axis(regions[1],{{grow=1},{basis=h*6},{basis=h*5}},{gap=p/2}))
    self.filterCombo=ISComboBox:new(top[1].x,top[1].y,top[1].width,top[1].height,self,EmberRoutesOrderMonitorPage.filterChanged)
    self.filterCombo:initialise()
    for _,key in ipairs(filters) do self.filterCombo:addOption(text('filter_'..key)) end
    self:addChild(self.filterCombo)
    local function button(key,label,r,fn)
        local caption=require('EmberRoutesProbe/UI/Text').wrapLimited(label,r.width-p*2,UIFont.Small,1)[1]
        local b=ISButton:new(r.x,r.y,r.width,r.height,caption,self,fn)
        b.tooltip=label
        b:initialise() Theme.button(b) Tooltip.attach(b,'prerender') self:addChild(b) self.buttons[key]=b
    end
    button('details',text('details'),top[2],function() self.store:setState({detailMode=not self.store.value.detailMode}) self:focusContent() end)
    button('refresh',text('refresh'),top[3],function() self:refresh() end)
    local compat=assert(Layout.axis(regions[2],{{grow=1},{grow=1}},{gap=p/2}))
    button('crafting',getText('IGUI_EmberRoutesProbe_Public_createOrder'),compat[1],function() self.owner:openPublicOrder() end)
    button('logistics',getText('IGUI_EmberRoutesProbe_Public_priorities'),compat[2],function() self.owner:openPriorities() end)
    self.narrow=regions[3].width<h*40
    local columns=self.narrow and {regions[3],regions[3]}
        or assert(Layout.axis(regions[3],{{grow=2},{grow=3}},{gap=p}))
    self.orderList=Cached.create(self,columns[1],function(_,row) self.store:setState({selection=row.id}) end,Cards.rows())
    Theme.list(self.orderList)
    self.orderList.emberEmptyLines=require('EmberRoutesProbe/UI/Text').wrap(text('empty'),columns[1].width-p*2,UIFont.Small)
    self:addChild(self.orderList)
    self.details=Cards.details(self,columns[2])
    self.buttons.details:setVisible(self.narrow)
    local actions=assert(Layout.axis(regions[4],{{grow=1},{grow=1},{grow=2}},{gap=p/2}))
    for i,key in ipairs({'stop','resume','return'}) do
        button(key,text('button_'..key),actions[i],function() self:command(key) end)
    end
    self.noticeBounds=regions[5]
end
function EmberRoutesOrderMonitorPage:filterChanged(combo)
    self.store:setState({filter=filters[combo.selected] or 'open'})
end
function EmberRoutesOrderMonitorPage:activate()
    local mounted=Lifecycle.mount(self,function(callback) return Service.watch(self.actor,self.entry.id,callback) end,function(snapshot)
        if snapshot.reason=='WORLD_RESET' then self.owner:close() return end
        self.store:setState({snapshot=snapshot})
    end)
    if mounted and self.active then self:refresh() end
end
function EmberRoutesOrderMonitorPage:refresh()
    if self.active then self.store:setState({snapshot=Service.status(self.actor,self.entry.id)}) end
end
function EmberRoutesOrderMonitorPage:project(value)
    if not self.active then return end
    local rows={}
    for _,row in ipairs(value.snapshot.rows) do
        if value.filter=='open' and not row.closed or row.bucket==value.filter then rows[#rows+1]=row end
    end
    local chosen=Cached.reconcile(self.orderList,rows,Cards.signature,function(row) return row.id end,true)
    local selected
    for i,row in ipairs(rows) do if row.id==value.selection then selected=row self.orderList.selected=i break end end
    selected=selected or chosen
    if (selected and selected.id or false)~=value.selection then self.store:setState({selection=selected and selected.id or false}) return end
    self.selected=selected self.details:set(selected)
    self.orderList:setVisible(not self.narrow or not value.detailMode)
    self.details.list:setVisible(not self.narrow or value.detailMode)
    self.buttons.details:setTitle(text(value.detailMode and 'backToList' or 'details'))
    Theme.enable(self.buttons.details,selected~=nil)
    Theme.enable(self.buttons.stop,selected and selected.canPause or false)
    Theme.enable(self.buttons.resume,selected and selected.canResume or false,true)
    Theme.enable(self.buttons['return'],selected and selected.canCancel or false)
    self.noticeLines=require('EmberRoutesProbe/UI/Text').wrapLimited(self.notice or Cards.reason(value.snapshot.reason) or '',
        self.noticeBounds.width,UIFont.Small,2)
    if self.owner.setFooter then self.owner:setFooter(text('summary',#rows,#value.snapshot.rows)) end
end
function EmberRoutesOrderMonitorPage:command(action)
    local row=self.selected
    if not self.active or not row then return end
    if not self.owner:valid() then self.owner:close() return end
    local result=Service.command(self.actor,self.entry.id,row.id,row.generation,action)
    self.notice=Cards.reason(result) self:refresh()
end
function EmberRoutesOrderMonitorPage:deactivate()
    Lifecycle.unmount(self) Tooltip.clear(self.orderList) Tooltip.clear(self.details.list)
    if self.filterCombo.hidePopup then self.filterCombo:hidePopup() end
    for _,button in pairs(self.buttons) do Tooltip.clear(button) end
end
function EmberRoutesOrderMonitorPage:dispose() self.disposed=true self:deactivate() end
function EmberRoutesOrderMonitorPage:close() self.owner:close() end
function EmberRoutesOrderMonitorPage:focusList(list) self.focusedList=list end
function EmberRoutesOrderMonitorPage:isListFocused(list) return not self.focusedList or self.focusedList==list end
function EmberRoutesOrderMonitorPage:focusContent()
    self.focusedList=self.narrow and self.store.value.detailMode and self.details.list or self.orderList
    if self.actor:getJoypadBind()~=-1 then setJoypadFocus(self.actor:getIndex(),self.focusedList) end
end
function EmberRoutesOrderMonitorPage:onListActivate()
    if self.narrow then self.store:setState({detailMode=not self.store.value.detailMode}) self:focusContent() end
end
function EmberRoutesOrderMonitorPage:onListKey(key)
    if key==Keyboard.KEY_RETURN then self:onListActivate()
    elseif key==Keyboard.KEY_TAB then self.owner:nextTab(1) end
end
function EmberRoutesOrderMonitorPage:onListJoypad(button)
    if button==Joypad.XButton then self:command('resume')
    elseif button==Joypad.YButton then self:command('stop') end
end
function EmberRoutesOrderMonitorPage:prerender()
    ISPanel.prerender(self) if not self.active then return end
    for i,line in ipairs(self.noticeLines or {}) do Theme.text(self,line,self.noticeBounds.x,self.noticeBounds.y+(i-1)*self.fontHeight,Theme.muted) end
end
return EmberRoutesOrderMonitorPage
