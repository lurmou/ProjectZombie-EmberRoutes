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
local filterGlyphs={active='●',waiting='▲',paused='❚❚',attention='◆',closed='✔'}

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
    o.filters=filters
    o.store=State.new({snapshot={rows={}},selection=false,filter='open',detailMode=false,expanded=false})
    return o
end

function EmberRoutesOrderMonitorPage:initialise() ISPanel.initialise(self) end

function EmberRoutesOrderMonitorPage:createChildren()
    ISPanel.createChildren(self)
    local h,p=self.fontHeight,self.pad

    -- No toolbar above the dossier: filters and secondary actions belong to the index.
    local regions=assert(Layout.axis({x=0,y=0,width=self.width,height=self.height},
        {{grow=1},{basis=h+p},{basis=h*1.5+p}},
        {direction='column',padding=p,gap=p/2}))
    local split=Layout.split(regions[1],h,p)
    self.narrow=split.compact
    local columns={split.index,split.main}
    local index=assert(Layout.axis(columns[1],{{basis=h*4+p},{grow=1},{basis=h+p},{basis=h+p}},
        {direction='column',gap=p/2}))
    local top={index[1],index[3],index[4],index[4]}
    self.filterChips=FilterChips:new(top[1].x,top[1].y,top[1].width,top[1].height,function(id)
        self.store:setState({filter=id})
    end)
    self.filterChips.variant='dossier'
    self:addChild(self.filterChips)

    local function button(key,label,r,fn,isPrimary)
        local caption=require('EmberRoutesProbe/UI/Text').wrapLimited(label,r.width-p*2,UIFont.Small,1)[1]
        local b=ISButton:new(r.x,r.y,r.width,r.height,caption,self,fn)
        b.tooltip=label
        b:initialise()
        Theme.button(b,isPrimary)
        Tooltip.attach(b,'prerender',self)
        self:addChild(b)
        self.buttons[key]=b
    end

    button('create',getText('IGUI_EmberRoutesProbe_Public_createOrder'),top[2],function()
        self.owner:openPublicOrder()
    end,true)

    button('details',text('details'),{x=columns[2].x,y=regions[2].y,width=h*6,height=h+p},function()
        self.store:setState({detailMode=not self.store.value.detailMode})
        self:focusContent()
    end)

    button('refresh',text('refresh'),top[4],function()
        self:refresh()
    end)

    self.indexControls={self.filterChips,self.buttons.create,self.buttons.refresh}
    self.orderList=Cached.create(self,index[2],function(_,row)
        self.store:setState({selection=row.id})
    end,Cards.rows())
    Theme.dossierList(self.orderList)
    self.orderList.emberEmptyLines=require('EmberRoutesProbe/UI/Text').wrap(text('empty'),columns[1].width-p*2,UIFont.Small)
    self:addChild(self.orderList)

    self.details=Cards.details(self,columns[2])
    self.buttons.details:setVisible(self.narrow)

    -- Bottom Actions: Stop / Resume / Return (Cancel)
    local actions=assert(Layout.axis({x=columns[2].x,y=regions[2].y,width=columns[2].width,height=regions[2].height},
        {{grow=1},{grow=1},{grow=1},{grow=1}},{gap=p/2}))
    self.buttons.details:setX(actions[1].x)
    self.buttons.details:setWidth(actions[1].width)
    for _,key in ipairs({'stop','resume','return'}) do
        button(key,text('button_'..key),actions[key=='return' and 3 or 2],function() self:command(key) end,key=='resume')
    end

    button('expand',text('expand'),actions[4],function()
        self.store:setState({expanded=not self.store.value.expanded})
    end)
    self.noticeBounds=regions[3]
end

function EmberRoutesOrderMonitorPage:filterChanged(combo)
    self.store:setState({filter=self.filters[combo.selected] or 'open'})
end

local function contextRow(rows,context,demandMode)
    for _,row in ipairs(rows or {}) do
        if (demandMode and context.problemId and row.id==context.problemId)
            or (not demandMode and context.orderId and row.orderId==context.orderId) then return row end
    end
end

function EmberRoutesOrderMonitorPage:resolveContext(context)
    -- DemandPage inherits this adapter, but uses its independent read-only service.
    local demandMode=self.demandMode or self.Type=='EmberRoutesDemandPage'
    local service=self.service or (demandMode and require 'EmberRoutesProbe/DemandMonitorService') or Service
    local row=contextRow(service.status(self.actor,self.entry.id).rows,context,demandMode)
    return row and row.id, row and nil or "TARGET_NOT_FOUND"
end

function EmberRoutesOrderMonitorPage:applyContext(context)
    if not self.active then return false end
    local row=contextRow(self.store.value.snapshot.rows,context,self.demandMode)
    if not row then return false end
    self.store:setState({selection=row.id,filter=row.closed and 'closed' or 'open'})
    for i,entry in ipairs(self.orderList.items) do
        if entry.item.value.id==row.id then self.orderList:ensureVisible(i) break end
    end
    return true
end

function EmberRoutesOrderMonitorPage:activate()
    if self.active or self.disposed then return end
    self.portraits={}
    self.portraitRetryAt=0
    local received=false
    local mounted=Lifecycle.mount(self,function(callback) return (self.service or Service).watch(self.actor,self.entry.id,callback) end,function(snapshot)
        received=true
        if snapshot.reason=='WORLD_RESET' then self.owner:close() return end
        self.store:setState({snapshot=snapshot})
    end)
    if mounted and self.active then
        local scope=self.activationScope
        scope:watch(Theme.watch,function()
            self:project(self.store.value)
        end)
        local Personnel=require 'EmberRoutesProbe/PersonnelService'
        local dirty=scope:wrapCallback(function(id)
            if self.portraits[id] then
                self.portraits[id]=Personnel.portrait(self.actor,self.entry.id,id,true,self)
                self.details:set(self.selected,self.store.value.expanded)
            end
        end)
        if Personnel.watchPortrait then scope:watch(Personnel.watchPortrait,dirty) end
        scope:defer(function()
            for id in pairs(self.portraits) do if Personnel.releasePortrait then Personnel.releasePortrait(id,self) end end
            self.portraits={}
            self.details:set(nil,false)
        end)
        if not received then self:refresh() end
    end
end

-- Only failed selected portraits retry, at most once per second while visible.
function EmberRoutesOrderMonitorPage:update()
    ISPanel.update(self)
    if not self.active or self.narrow and not self.store.value.detailMode then return end
    local now=getTimestampMs and getTimestampMs() or 0
    if now<(self.portraitRetryAt or 0) then return end
    self.portraitRetryAt=now+1000
    local Personnel=require 'EmberRoutesProbe/PersonnelService'
    local changed=false
    for id,snapshot in pairs(self.portraits or {}) do
        if not snapshot.texture and Personnel.portrait then
            local nextSnapshot=Personnel.portrait(self.actor,self.entry.id,id,false,self)
            if nextSnapshot~=snapshot then self.portraits[id]=nextSnapshot changed=true end
        end
    end
    if changed and self.activationScope:isCurrent() then self.details:set(self.selected,self.store.value.expanded) end
end

function EmberRoutesOrderMonitorPage:refresh()
    if self.active then self.store:setState({snapshot=(self.service or Service).status(self.actor,self.entry.id)}) end
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
        local chipOptions={}
        for _,key in ipairs(self.filters) do
            if key=='open' or key==value.filter or counts[key]>0 then
            chipOptions[#chipOptions+1]={id=key,label=self.demandMode
                and getText('IGUI_EmberRoutesProbe_Demand_filter_'..key) or text('filter_'..key),
                count=counts[key],glyph=filterGlyphs[key],alert=key=='attention' and counts.attention>0}
            end
        end
        self.filterChips:setOptions(chipOptions, value.filter)
    end

    local rows={}
    for _,row in ipairs(value.snapshot.rows) do
        if value.filter=='open' and not row.closed or row.bucket==value.filter then rows[#rows+1]=row end
    end
    local chosen=Cached.reconcile(self.orderList,rows,Cards.signature,function(row) return row.id end,true,Theme.revision)
    local selected
    for i,row in ipairs(rows) do if row.id==value.selection then selected=row self.orderList.selected=i break end end
    selected=selected or chosen
    if type(selected)~='table' then selected=nil end
    if (selected and selected.id or false)~=value.selection then self.store:setState({selection=selected and selected.id or false,expanded=false}) return end
    self.selected=selected
    local Personnel=require 'EmberRoutesProbe/PersonnelService'
    local nextPortraits={}
    local portraitCount=0
    for _,r in ipairs(selected and (#(selected.children or {})>0 and selected.children or {selected}) or {}) do
        if r.npcId and Personnel.portrait and portraitCount<16 and (not self.narrow or value.detailMode)
            and (value.expanded or #(selected.children or {})<=1) then
            portraitCount=portraitCount+1
            nextPortraits[r.npcId]=Personnel.portrait(self.actor,self.entry.id,r.npcId,false,self)
        end
    end
    for id in pairs(self.portraits or {}) do
        if not nextPortraits[id] and Personnel.releasePortrait then Personnel.releasePortrait(id,self) end
    end
    self.portraits=nextPortraits
    self.details:set(selected,value.expanded)
    for _,key in ipairs({'stop','resume','return'}) do
        local allowed=selected and not selected.readOnly and
            ((key=='stop' and selected.canPause==true and not selected.canResume)
            or (key=='resume' and selected.canResume==true) or (key=='return' and selected.canCancel==true))
        self.buttons[key]:setVisible(allowed==true and (key~='return' or value.expanded))
    end
    for _,control in ipairs(self.indexControls) do control:setVisible(not self.narrow or not value.detailMode) end
    self.buttons.create:setVisible(not self.demandMode and (not self.narrow or not value.detailMode))
    self.buttons.expand:setVisible(selected~=nil)
    self.buttons.expand:setTitle(text(value.expanded and 'collapse' or 'expand'))
    self.orderList:setVisible(not self.narrow or not value.detailMode)
    self.details.list:setVisible(not self.narrow or value.detailMode)
    self.buttons.details:setTitle(text(value.detailMode and 'backToList' or 'details'))
    Theme.enable(self.buttons.details,selected~=nil)
    Theme.enable(self.buttons.stop,selected and selected.canPause or false)
    Theme.enable(self.buttons.resume,selected and selected.canResume or false,true)
    Theme.enable(self.buttons['return'],selected and selected.canCancel or false)
    for _,button in pairs(self.buttons) do Theme.dossierButton(button,button==self.buttons.resume or button==self.buttons.stop) end
    Theme.dossierList(self.orderList)
    Theme.dossierList(self.details.list)
    self.noticeLines=require('EmberRoutesProbe/UI/Text').wrapLimited(self.notice or Cards.reason(value.snapshot.reason) or '',
        self.noticeBounds.width,UIFont.Small,2)
    if self.owner.setFooter then self.owner:setFooter(self.demandMode
        and getText('IGUI_EmberRoutesProbe_Demand_footer',tostring(#rows)) or text('summary',#rows,#value.snapshot.rows)) end
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
    local result=(self.service or Service).command(self.actor,self.entry.id,row.id,row.generation,action)
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
