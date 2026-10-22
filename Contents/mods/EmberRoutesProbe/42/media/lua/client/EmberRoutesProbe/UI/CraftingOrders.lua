require "ISUI/ISPanel"
require "ISUI/ISButton"
local Service=require "EmberRoutesProbe/CraftingService"
local Layout=require "EmberRoutesProbe/UI/Layout"
local State=require "EmberRoutesProbe/UI/State"
local Cached=require "EmberRoutesProbe/UI/CachedList"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Lifecycle=require "EmberRoutesProbe/UI/PageLifecycle"
local Tooltip=require "EmberRoutesProbe/UI/TooltipAnchor"
local Cards=require "EmberRoutesProbe/UI/CraftingCards"
local Words=require "EmberRoutesProbe/CraftingText"
local text=Words.get
---@class EmberRoutesCraftingOrders:ISPanel
---@field owner EmberRoutesSettlementDashboard
---@field actor IsoPlayer
---@field entry table
---@field fontHeight number
---@field pad number
---@field store table
---@field buttons table
---@field workerList EmberRoutesCachedList
---@field details EmberRoutesCachedList
---@field detailCard table
---@field notice string?
---@field active boolean?
---@field disposed boolean?
EmberRoutesCraftingOrders=ISPanel:derive("EmberRoutesCraftingOrders")
---@param shell EmberRoutesCraftingPage
---@param bounds {x:number,y:number,width:number,height:number}
---@return EmberRoutesCraftingOrders
function EmberRoutesCraftingOrders:new(shell,bounds)
    ---@type EmberRoutesCraftingOrders
    local o=ISPanel.new(self,bounds.x,bounds.y,bounds.width,bounds.height)
    o.owner=shell.owner o.actor=shell.actor o.entry=shell.entry o.fontHeight=shell.fontHeight o.pad=shell.pad o.background=false
    o.store=State.new({snapshot={workers={},surfaces={}},selection=false}) o.buttons={}
    return o
end
function EmberRoutesCraftingOrders:initialise() ISPanel.initialise(self) end
function EmberRoutesCraftingOrders:createChildren()
    ISPanel.createChildren(self) local h,p=self.fontHeight,self.pad
    local regions=assert(Layout.axis({x=0,y=0,width=self.width,height=self.height},{{grow=1},{basis=h+p},{basis=h}},
        {direction="column",padding=p,gap=p/2}))
    local columns=assert(Layout.axis(regions[1],{{grow=2},{grow=3}},{gap=p}))
    self.workerList=Cached.create(self,columns[1],function(_,row) self.store:setState({selection=row.id}) end,Cards.workers())
    Theme.list(self.workerList) self:addChild(self.workerList)
    self.detailCard=Cards.details(self,columns[2]) self.details=self.detailCard.list
    local actions=assert(Layout.axis(regions[2],{{grow=1},{grow=1},{grow=1}},{gap=p/2}))
    for _,id in ipairs({"resume","stop","return","refresh"}) do
        local r=actions[(id=="stop" or id=="resume") and 1 or id=="return" and 2 or 3]
        local button=ISButton:new(r.x,r.y,r.width,r.height,text("button_"..id),self,function(_,clicked) self:command(clicked.internal) end)
        button.internal=id button:initialise() Theme.button(button) Tooltip.attach(button,"prerender") self:addChild(button) self.buttons[id]=button
    end
end
function EmberRoutesCraftingOrders:activate()
    local mounted=Lifecycle.mount(self,function(callback) return Service.watch(self.actor,self.entry.id,callback) end,function(snapshot)
        if snapshot.reason=="WORLD_RESET" then self.owner:close() return end
        self.store:setState({snapshot=snapshot})
    end)
    if mounted and self.active then self.store:setState({snapshot=Service.status(self.actor,self.entry.id)}) self:project(self.store.value,{snapshot=true}) end
end
function EmberRoutesCraftingOrders:project(value,_changes)
    if not self.active then return end
    local chosen=Cached.reconcile(self.workerList,value.snapshot.workers,function(row)
        local order=row.order
        return row.name..":"..tostring(row.busy)..":"..(order and (tostring(order.id)..":"..tostring(order.state)..":"..tostring(order.phase)..":"..tostring(order.reason)) or "")
    end,function(row) return row.id end,true)
    local selected
    for i,row in ipairs(value.snapshot.workers) do if row.id==value.selection then selected=row self.workerList.selected=i break end end
    selected=selected or chosen
    if (selected and selected.id or false)~=value.selection then self.store:setState({selection=selected and selected.id or false}) return end
    ---@type table?
    local order=selected and selected.order
    local retained=order and not order.released
    self.buttons.stop:setVisible(selected and selected.busy and retained or false)
    self.buttons.resume:setVisible(not (selected and selected.busy and retained))
    Theme.enable(self.buttons.stop,selected and selected.busy and retained or false,true)
    Theme.enable(self.buttons.resume,selected and not selected.busy and order and not order.released and order.resumable or false,true)
    Theme.enable(self.buttons["return"],selected and not selected.busy and retained or false)
    self.detailCard:set(selected,value.snapshot.surfaces,nil,nil,1)
end
function EmberRoutesCraftingOrders:command(command)
    local v=self.store.value
    local result=command=="refresh" and "REFRESHED" or Service.command(self.actor,self.entry.id,v.selection,command,v.snapshot.surfaceId)
    self.notice=Words.reason(result) self.store:setState({snapshot=Service.status(self.actor,self.entry.id)})
end
function EmberRoutesCraftingOrders:deactivate()
    Lifecycle.unmount(self) Tooltip.clear(self.workerList) Tooltip.clear(self.details)
    for _,button in pairs(self.buttons) do Tooltip.clear(button) end
end
function EmberRoutesCraftingOrders:dispose() self.disposed=true self:deactivate() end
function EmberRoutesCraftingOrders:close() self.owner:close() end
function EmberRoutesCraftingOrders:focusList() end
function EmberRoutesCraftingOrders:focusContent()
    if self.actor:getJoypadBind()~=-1 then setJoypadFocus(self.actor:getIndex(),self.workerList) end
end
function EmberRoutesCraftingOrders:prerender()
    ISPanel.prerender(self) if not self.active then return end
    if self.notice then Theme.text(self,self.notice,self.pad,self.height-self.fontHeight,Theme.muted) end
end
return EmberRoutesCraftingOrders
