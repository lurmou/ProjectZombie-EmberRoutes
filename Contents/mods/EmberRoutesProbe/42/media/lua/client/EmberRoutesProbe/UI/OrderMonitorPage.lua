require 'ISUI/ISPanel'
require 'ISUI/ISButton'
require 'ISUI/ISComboBox'
require 'ISUI/ISModalDialog'
local Service=require 'EmberRoutesProbe/OrderMonitorService'
local Layout=require 'EmberRoutesProbe/UI/Layout'
local State=require 'EmberRoutesProbe/UI/State'
local Cached=require 'EmberRoutesProbe/UI/CachedList'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Lifecycle=require 'EmberRoutesProbe/UI/PageLifecycle'
local Tooltip=require 'EmberRoutesProbe/UI/TooltipAnchor'
local FilterChips=require 'EmberRoutesProbe/UI/FilterChips'
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
---@field filterChips EmberRoutesFilterChips
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
---@field cancelModal ISModalDialog?
EmberRoutesOrderMonitorPage=ISPanel:derive('EmberRoutesOrderMonitorPage')

---@param owner EmberRoutesSettlementDashboard
---@param bounds {x:number,y:number,width:number,height:number}
---@return EmberRoutesOrderMonitorPage
function EmberRoutesOrderMonitorPage:new(owner,bounds)
    local o=ISPanel.new(self,bounds.x,bounds.y,bounds.width,bounds.height)
    o.owner,o.actor,o.entry=owner,owner.actor,owner.entry
    o.fontHeight,o.pad=owner.fontHeight,owner.pad
    o.background=false
    o.buttons={}
    o.store=State.new({snapshot={rows={}},selection=false,filter='open',detailMode=false})
    return o
end

function EmberRoutesOrderMonitorPage:initialise() ISPanel.initialise(self) end

function EmberRoutesOrderMonitorPage:createChildren()
    ISPanel.createChildren(self)
    local h,p=self.fontHeight,self.pad

    -- Clean vertical 4-part layout (Top Bar -> Work Area -> Bottom Actions -> Notice)
    local regions=assert(Layout.axis({x=0,y=0,width=self.width,height=self.height},
        {{basis=h+p},{grow=1},{basis=h+p},{basis=h*1.5+p}},
        {direction='column',padding=p,gap=p/2}))

    -- Top bar: Filter chips + [Create Order] button + [Details] + [Refresh]
    local top=assert(Layout.axis(regions[1],{{grow=1},{basis=h*7},{basis=h*4},{basis=h*4}},{gap=p/2}))
    self.filterChips=FilterChips:new(top[1].x,top[1].y,top[1].width,top[1].height,function(id)
        self.store:setState({filter=id})
    end)
    local defaultChips={}
    for _,key in ipairs(filters) do
        defaultChips[#defaultChips+1]={id=key,label=text('filter_'..key)}
    end
    self.filterChips:setOptions(defaultChips,'open')
    self:addChild(self.filterChips)

    local function button(key,label,r,fn,isPrimary)
        local caption=require('EmberRoutesProbe/UI/Text').wrapLimited(label,r.width-p*2,UIFont.Small,1)[1]
        local b=ISButton:new(r.x,r.y,r.width,r.height,caption,self,fn)
        b.tooltip=label
        b:initialise()
        Theme.button(b,isPrimary)
        Tooltip.attach(b,'prerender')
        self:addChild(b)
        self.buttons[key]=b
    end

    button('create',getText('IGUI_EmberRoutesProbe_Public_createOrder'),top[2],function()
        self.owner:openPublicOrder()
    end,true)

    button('details',text('details'),top[3],function()
        self.store:setState({detailMode=not self.store.value.detailMode})
        self:focusContent()
    end)

    button('refresh',text('refresh'),top[4],function()
        self:refresh()
    end)

    -- Middle Area: Order List & Detail Panel
    self.narrow=regions[2].width<h*40
    local columns=self.narrow and {regions[2],regions[2]}
        or assert(Layout.axis(regions[2],{{grow=2},{grow=3}},{gap=p}))
    self.orderList=Cached.create(self,columns[1],function(_,row)
        self.store:setState({selection=row.id})
    end,Cards.rows())
    Theme.list(self.orderList)
    self.orderList.emberEmptyLines=require('EmberRoutesProbe/UI/Text').wrap(text('empty'),columns[1].width-p*2,UIFont.Small)
    self:addChild(self.orderList)

    self.details=Cards.details(self,columns[2])
    self.buttons.details:setVisible(self.narrow)

    -- Bottom Actions: Stop / Resume / Return (Cancel)
    local actions=assert(Layout.axis(regions[3],{{grow=1},{grow=1},{grow=2}},{gap=p/2}))
    for i,key in ipairs({'stop','resume','return'}) do
        button(key,text('button_'..key),actions[i],function() self:command(key) end,key=='resume')
    end

    self.noticeBounds=regions[4]
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
    local counts = {open=0, active=0, waiting=0, paused=0, attention=0, closed=0}
    for _, r in ipairs(value.snapshot.rows or {}) do
        if not r.closed then counts.open = counts.open + 1 end
        if r.bucket and counts[r.bucket] ~= nil then
            counts[r.bucket] = counts[r.bucket] + 1
        end
    end
    if self.filterChips then
        local chipOptions = {
            {id='open', label=text('filter_open'), count=counts.open},
            {id='active', label=text('filter_active'), count=counts.active, glyph='●'},
            {id='waiting', label=text('filter_waiting'), count=counts.waiting, glyph='▲'},
            {id='paused', label=text('filter_paused'), count=counts.paused, glyph='❚❚'},
            {id='attention', label=text('filter_attention'), count=counts.attention, glyph='◆', alert=(counts.attention > 0)},
            {id='closed', label=text('filter_closed'), count=counts.closed, glyph='✔'},
        }
        self.filterChips:setOptions(chipOptions, value.filter)
    end

    local rows={}
    for _,row in ipairs(value.snapshot.rows) do
        if value.filter=='open' and not row.closed or row.bucket==value.filter then rows[#rows+1]=row end
    end
    local chosen=Cached.reconcile(self.orderList,rows,Cards.signature,function(row) return row.id end,true)
    local selected
    for i,row in ipairs(rows) do if row.id==value.selection then selected=row self.orderList.selected=i break end end
    selected=selected or chosen
    if (selected and selected.id or false)~=value.selection then self.store:setState({selection=selected and selected.id or false}) return end
    self.selected=selected
    self.details:set(selected)
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
    local row=type(self.selected)=='table' and self.selected or nil
    if not self.active or not row then return end
    if not self.owner:valid() then self.owner:close() return end
    if action=='return' then
        self:promptCancel(row)
        return
    end
    self:executeCommand(action,row)
end

function EmberRoutesOrderMonitorPage:promptCancel(row)
    if self.cancelModal then return end
    row=type(row)=='table' and row or (type(self.selected)=='table' and self.selected or nil)
    if not row then return end
    local count=row.produced or row.delivered or 0
    local message=string.format(getTextOrNull('IGUI_EmberRoutesProbe_Order_cancelConfirm') or 'IGUI_EmberRoutesProbe_Order_cancelConfirm',tostring(count))
    local w=math.min(self.width,self.fontHeight*28)
    local absX=self.getAbsoluteX and self:getAbsoluteX() or self.x or 0
    local absY=self.getAbsoluteY and self:getAbsoluteY() or self.y or 0
    local x=absX+(self.width-w)/2
    local y=absY+self.fontHeight*3
    local modal=ISModalDialog:new(x,y,w,0,message,true,self,
        EmberRoutesOrderMonitorPage.onConfirmCancel,self.actor:getIndex(),row)
    function modal:destroy()
        self:setVisible(false)
        self:removeFromUIManager()
    end
    self.cancelModal=modal
    modal:initialise()
    modal:addToUIManager()
    if self.actor:getJoypadBind()~=-1 then
        setJoypadFocus(self.actor:getIndex(),modal)
    end
end

function EmberRoutesOrderMonitorPage:onConfirmCancel(button,row)
    self.cancelModal=nil
    local confirmed=false
    if button==true or button=='YES' then
        confirmed=true
    elseif type(button)=='table' then
        confirmed=(button.internal=='YES' or button.internal=='OK' or button.internal==true)
    end
    if not confirmed then return end
    self:executeCommand('return',row)
end

function EmberRoutesOrderMonitorPage:executeCommand(action,row)
    row=row or self.selected
    if not self.active or not row then return end
    if not self.owner:valid() then self.owner:close() return end
    local result=Service.command(self.actor,self.entry.id,row.id,row.generation,action)
    self.notice=Cards.reason(result)
    self:refresh()
end

function EmberRoutesOrderMonitorPage:deactivate()
    Lifecycle.unmount(self)
    if self.cancelModal then
        self.cancelModal:destroy()
        self.cancelModal=nil
    end
    Tooltip.clearOwner(self)
end

function EmberRoutesOrderMonitorPage:dispose()
    self.disposed=true
    self:deactivate()
end

function EmberRoutesOrderMonitorPage:close() self.owner:close() end

function EmberRoutesOrderMonitorPage:focusList(list) self.focusedList=list end
function EmberRoutesOrderMonitorPage:isListFocused(list) return not self.focusedList or self.focusedList==list end

function EmberRoutesOrderMonitorPage:focusContent()
    self.focusedList=self.narrow and self.store.value.detailMode and self.details.list or self.orderList
    if self.actor:getJoypadBind()~=-1 then setJoypadFocus(self.actor:getIndex(),self.focusedList) end
end

function EmberRoutesOrderMonitorPage:onListActivate()
    if self.narrow then
        self.store:setState({detailMode=not self.store.value.detailMode})
        self:focusContent()
    end
end

return EmberRoutesOrderMonitorPage