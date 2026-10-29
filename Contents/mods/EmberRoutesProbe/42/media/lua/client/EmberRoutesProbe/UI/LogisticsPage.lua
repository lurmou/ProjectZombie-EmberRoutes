require "ISUI/ISPanel"
require "ISUI/ISTickBox"
require "ISUI/ISButton"
local Service=require "EmberRoutesProbe/LogisticsService"
local Commands=require "EmberRoutesProbe/LogisticsMenu"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Layout=require "EmberRoutesProbe/UI/Layout"
local State=require "EmberRoutesProbe/UI/State"
local Cached=require "EmberRoutesProbe/UI/CachedList"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Text=require "EmberRoutesProbe/UI/Text"
local Tooltip=require "EmberRoutesProbe/UI/TooltipAnchor"
local Presentation=require "EmberRoutesProbe/UI/LogisticsPresentation"
local Cards=require "EmberRoutesProbe/UI/LogisticsCards"
local Visual=require "EmberRoutesProbe/UI/StatusVisual"
local text=require("EmberRoutesProbe/LogisticsText").get
---@class EmberRoutesLogisticsPage:ISPanel
---@field actor IsoPlayer
---@field entry EmberRoutesSettlement
---@field world table
---@field fontHeight number
---@field pad number
---@field store EmberRoutesUIStore
---@field presentation table
---@field workerList EmberRoutesCachedList
---@field details table
---@field modes ISTickBox[]
---@field buttons table<string,ISButton>
---@field release function?
---@field unsubscribe function?
---@field statusLines string[]
---@field noticeLines string[]
---@field heading table
---@field noticeBounds table
---@field syncing boolean?
---@field nextCheck number
---@field focusedList EmberRoutesCachedList?
---@field columnTitles table[]
---@field disposed boolean?
---@field owner EmberRoutesSettlementDashboard
---@field active boolean?
---@field headerBadges table[]
EmberRoutesLogisticsPage=ISPanel:derive("EmberRoutesLogisticsPage")
local Lifecycle=require "EmberRoutesProbe/UI/PageLifecycle"
---@param owner EmberRoutesSettlementDashboard
---@param bounds table
---@return EmberRoutesLogisticsPage
function EmberRoutesLogisticsPage:new(owner,bounds)
    local actor,entry=owner.actor,owner.entry
    local h=getTextManager():getFontHeight(UIFont.Small)
    ---@type EmberRoutesLogisticsPage
    local o=ISPanel.new(self,bounds.x,bounds.y,bounds.width,bounds.height)
    o.owner=owner o.background=false
    o.actor,o.entry,o.world=actor,entry,Ledger.data()
    o.fontHeight,o.pad=h,math.ceil(h*0.6)
    o.backgroundColor,o.borderColor=Theme.window,Theme.border
    o.store=State.new({snapshot={workers={},running=false,intake=false,tidy=false},selection=false,notice=""})
    o.presentation=Presentation.new(actor) o.buttons={} o.nextCheck=0
    return o
end
function EmberRoutesLogisticsPage:initialise() ISPanel.initialise(self) end
function EmberRoutesLogisticsPage:createChildren()
    ISPanel.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local regions=assert(Layout.axis({x=0,y=0,width=self.width,height=self.height},
        {{basis=h*2},{basis=h+p},{basis=h+p},{basis=h+p/2},{grow=1},{basis=h+p},{basis=h*2}},
        {direction="column",padding=p,gap=p/2}))
    self.heading=regions[1]
    local function button(id,r,primary)
        local label=id=="close" and getText("UI_btn_close") or text("button_"..id)
        local control=ISButton:new(r.x,r.y,r.width,r.height,label,self,EmberRoutesLogisticsPage.clicked)
        control.internal=id control:initialise() Theme.button(control,primary)
        self.buttons[id]=control self:addChild(control)
    end
    local top=assert(Layout.axis(regions[2],{{grow=1},{grow=1}},{gap=p/2}))
    for i,id in ipairs({"toggle","refresh"}) do button(id,top[i],id=="toggle") end
    local modeSlots=assert(Layout.axis(regions[3],{{grow=1},{grow=1}},{gap=p}))
    self.modes={}
    for i,mode in ipairs({"intake","tidy"}) do
        local r=modeSlots[i]
        -- Native constructor uses height as boxSize, not as the group's height.
        local box=ISTickBox:new(r.x,r.y+(r.height-h)/2,r.width,h,"",self,EmberRoutesLogisticsPage.modeChanged,mode)
        box:initialise() box.autoWidth=false box:addOption(text(mode.."Short"))
        self.modes[i]=box self:addChild(box)
    end
    local columns=assert(Layout.axis(regions[5],{{grow=2},{grow=3}},{gap=p}))
    self.workerList=Cached.create(self,columns[1],EmberRoutesLogisticsPage.selectWorker,Cards.workers())
    Theme.list(self.workerList) self:addChild(self.workerList)
    self.details=Cards.details(self,columns[2]) self.focusedList=self.workerList
    self.columnTitles={{x=columns[1].x,y=regions[4].y,label=text("workersHeading")},
        {x=columns[2].x,y=regions[4].y,label=text("orderHeading")}}
    local actions=assert(Layout.axis(regions[6],{{grow=1},{grow=1},{grow=1},{grow=1}},{gap=p/2}))
    for i,id in ipairs({"addAll","add","retry","remove"}) do button(id,actions[i],false) end
    self.noticeBounds=regions[7]
end
function EmberRoutesLogisticsPage:activate()
    local started=Lifecycle.mount(self,function(callback) return Service.watch(self.entry.id,callback) end,
        function(snapshot)
            if snapshot.reason=="WORLD_RESET" then self:close() return end
            self.store:setState({snapshot=snapshot})
        end)
    if started and self.active then
        local changed=self.store:setState({snapshot=Service.status(self.entry.id)})
        self:project(self.store.value,{snapshot=not changed,notice=true})
    end
end
function EmberRoutesLogisticsPage:deactivate()
    Lifecycle.unmount(self)
    Tooltip.clear(self.workerList) Tooltip.clear(self.details.list)
end
function EmberRoutesLogisticsPage:dispose()
    if self.disposed then return end
    self.disposed=true self:deactivate()
end
function EmberRoutesLogisticsPage:close() self.owner:close() end
function EmberRoutesLogisticsPage:focusContent()
    if self.actor:getJoypadBind()~=-1 then setJoypadFocus(self.actor:getIndex(),self.focusedList or self.workerList) end
end
function EmberRoutesLogisticsPage:focusList(list) self.focusedList=list end
function EmberRoutesLogisticsPage:isListFocused(list) return self.active and self.focusedList==list end
function EmberRoutesLogisticsPage:selectWorker(row) self.store:setState({selection=row.id}) end
function EmberRoutesLogisticsPage:project(value,changes)
    if not self.active then return end
    local snapshot=value.snapshot
    if changes.notice then self.noticeLines=Text.wrapLimited(value.notice,self.noticeBounds.width,UIFont.Small,2) end
    if changes.snapshot then
        if value.notice=="" then
            self.noticeLines=Text.wrapLimited(#snapshot.workers==0 and text("pageHint") or "",self.noticeBounds.width,UIFont.Small,2)
        end
        self.syncing=true self.modes[1]:setSelected(1,snapshot.intake) self.modes[2]:setSelected(1,snapshot.tidy) self.syncing=false
        self.buttons.toggle:setTitle(text(snapshot.running and "button_stop" or "button_start"))
        local working=0 for _,worker in ipairs(snapshot.workers) do if worker.reason=="WORKING" then working=working+1 end end
        local width=(self.heading.width-self.pad*2)/3
        self.headerBadges={Visual.badge(text(snapshot.running and "active" or "inactive"),snapshot.running and "active" or "paused",width,self.fontHeight,self.pad/2),
            Visual.badge(text("workingCount").."  "..working,"active",width,self.fontHeight,self.pad/2),
            Visual.badge(text("waitingCount").."  "..(#snapshot.workers-working),"neutral",width,self.fontHeight,self.pad/2)}
        local rows=self.presentation:project(snapshot)
        local selected=Cached.reconcile(self.workerList,rows,function(row) return row.label end,function(row) return row.id end,true)
        for _,entry in ipairs(self.workerList.items) do
            local visual=entry.item.visual entry.tooltip=visual.tooltip or nil
        end
        local chosen
        for i,row in ipairs(rows) do if row.id==value.selection then chosen=row self.workerList.selected=i break end end
        if not chosen then chosen=selected or nil end
        if (chosen and chosen.id or false)~=value.selection then
            self.store:setState({selection=chosen and chosen.id or false}) return
        end
    end
    if changes.snapshot or changes.selection then
        local selected
        for _,entry in ipairs(self.workerList.items) do if entry.item.value.id==value.selection then selected=entry.item.value break end end
        self.details:set(selected)
        Theme.enable(self.buttons.remove,selected~=nil)
        Theme.enable(self.buttons.retry,selected~=nil and snapshot.running and selected.reason~="WORKING",true)
    end
end
function EmberRoutesLogisticsPage:modeChanged(index,selected,mode)
    if not self.syncing then self:command(mode) end
end
function EmberRoutesLogisticsPage:command(command)
    if not self.active or self.disposed then return end
    local entry,reason=Ledger.view(self.actor,self.entry.id)
    if not entry then self.actor:Say(text(reason)) self:close() return end
    local result
    if command=="retry" or command=="remove" then
        local id=self.store.value.selection
        if not id then return end
        result=Service.workerCommand(self.actor,self.entry.id,id,command)
    else result=Commands.command(self.actor,command,self.entry.id,true) end
    self.store:setState({notice=text(result),snapshot=Service.status(self.entry.id)})
end
function EmberRoutesLogisticsPage:clicked(button)
    local command=button.internal
    if command=="close" then self:close()
    elseif command=="warehouse" then
        self.owner:selectTab("warehouse")
    else
        if command=="toggle" then command=self.store.value.snapshot.running and "stop" or "start" end
        self:command(command)
    end
end
function EmberRoutesLogisticsPage:onListJoypad(button)
    if button==Joypad.XButton then self:command("refresh")
    elseif button==Joypad.YButton then self:command(self.store.value.snapshot.running and "stop" or "start") end
end
function EmberRoutesLogisticsPage:onListFocus(list,direction)
    if (list==self.workerList and direction==-1) or (list==self.details.list and direction==1) then
        self.owner:nextTab(direction) return
    end
    self.focusedList=list==self.workerList and self.details.list or self.workerList
    if self.actor:getJoypadBind()~=-1 then setJoypadFocus(self.actor:getIndex(),self.focusedList) end
end
function EmberRoutesLogisticsPage:prerender()
    ISPanel.prerender(self)
    if not self.active then return end
    for _,title in ipairs(self.columnTitles) do Theme.text(self,title.label,title.x,title.y,Theme.muted) end
    for i,badge in ipairs(self.headerBadges or {}) do
        Visual.drawBadge(self,self.heading.x+(i-1)*(badge.width+self.pad),self.heading.y,badge)
    end
    for i,line in ipairs(self.noticeLines or {}) do Theme.text(self,line,self.noticeBounds.x,self.noticeBounds.y+(i-1)*self.fontHeight,Theme.muted) end
end
return EmberRoutesLogisticsPage
