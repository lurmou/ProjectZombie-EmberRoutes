require 'ISUI/ISPanel'
require 'ISUI/ISButton'
local Layout=require 'EmberRoutesProbe/UI/Layout'
local State=require 'EmberRoutesProbe/UI/State'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Text=require 'EmberRoutesProbe/UI/Text'
local Tooltip=require 'EmberRoutesProbe/UI/TooltipAnchor'

local function text(key,...) return getText('IGUI_EmberRoutesProbe_Defense_'..key,...) end

---@class EmberRoutesDefensePage:ISPanel
---@field owner EmberRoutesSettlementDashboard
---@field actor IsoPlayer
---@field entry table
---@field fontHeight number
---@field pad number
---@field store table
---@field alertButtons table
---@field active boolean?
---@field disposed boolean?
EmberRoutesDefensePage=ISPanel:derive('EmberRoutesDefensePage')

---@param owner EmberRoutesSettlementDashboard
---@param bounds table
---@return EmberRoutesDefensePage
function EmberRoutesDefensePage:new(owner,bounds)
    local o=ISPanel.new(self,bounds.x,bounds.y,bounds.width,bounds.height)
    o.owner=owner
    o.actor,o.entry=owner.actor,owner.entry
    o.fontHeight,o.pad=owner.fontHeight,owner.pad
    o.background=false
    o.alertButtons={}
    o.store=State.new({alertLevel=0,posts={}})
    o.unsubscribe=o.store:subscribe(function(value)
        if o.active and not o.disposed then o:project(value) end
    end)
    return o
end

function EmberRoutesDefensePage:initialise() ISPanel.initialise(self) end

function EmberRoutesDefensePage:createChildren()
    ISPanel.createChildren(self)
    local h,p=self.fontHeight,self.pad

    local regions=assert(Layout.axis({x=0,y=0,width=self.width,height=self.height},
        {{basis=h*2+p},{basis=h*3+p},{basis=h*3+p},{grow=1}},
        {direction='column',padding=p,gap=p/2}))

    self.titleBounds=regions[1]
    self.alertBounds=regions[2]
    self.heatBounds=regions[3]
    self.postsBounds=regions[4]

    -- Cached static text for zero-GC prerender
    self.titleText=text('title')
    self.badgeText=text('previewBadge')
    self.alertHintText=text('alertLocked')
    self.heatTitle=text('heatMeter')
    self.heatSafeLabel=text('heatSafe')..' (0 / 100)'
    self.heatUnavailable=text('unavailable')
    self.postsTitle=text('posts')
    self.checklists={
        text('req_tower'),
        text('req_patrol'),
        text('req_guard')
    }
    self.noPostsLines=Text.wrap(text('noPosts'),self.postsBounds.width-p*3,UIFont.Small)

    -- Alert level buttons (Defcon 0, 1, 2)
    local alertTrack=assert(Layout.axis(self.alertBounds,{{grow=1},{grow=1},{grow=1}},{gap=p/2}))
    local fullHint=text('alertLocked')..'\n'..text('alertHint')
    for i=0,2 do
        local r=alertTrack[i+1]
        local btn=ISButton:new(r.x,r.y,r.width,r.height,text('alert_'..i),self,function()
            self:setAlertLevel(i)
        end)
        btn:initialise()
        btn:setEnable(false)
        Theme.styleButton(btn,false,i==self.store.value.alertLevel)
        btn.tooltip=fullHint
        Tooltip.attach(btn,'prerender',self)
        self:addChild(btn)
        self.alertButtons[i]=btn
    end
end

function EmberRoutesDefensePage:setAlertLevel(level)
    self.store:setState({alertLevel=level})
    for i=0,2 do
        local btn=self.alertButtons[i]
        if btn then
            Theme.styleButton(btn,i==level,i==level)
            btn:setEnable(false)
        end
    end
end

function EmberRoutesDefensePage:activate()
    self.active=true
    self:setAlertLevel(self.store.value.alertLevel)
end

function EmberRoutesDefensePage:deactivate()
    self.active=false
    for _,btn in pairs(self.alertButtons) do
        Tooltip.clear(btn)
    end
end

function EmberRoutesDefensePage:dispose()
    self.disposed=true
    if self.unsubscribe then
        self.unsubscribe()
        self.unsubscribe=nil
    end
    self:deactivate()
end

function EmberRoutesDefensePage:project(value)
    if not self.active or self.disposed then return end
    -- Keep buttons synced with state
    for i=0,2 do
        local btn=self.alertButtons[i]
        if btn then
            Theme.styleButton(btn,i==value.alertLevel,i==value.alertLevel)
            btn:setEnable(false)
        end
    end
end

function EmberRoutesDefensePage:prerender()
    ISPanel.prerender(self)
    local h,p=self.fontHeight,self.pad

    -- Title with Preview Badge
    local title=self.titleText or text('title')
    Theme.text(self,title,self.titleBounds.x,self.titleBounds.y,Theme.gold)
    local titleW=getTextManager():MeasureStringX(UIFont.Small,title)
    Theme.text(self,self.badgeText or '',self.titleBounds.x+titleW+p,self.titleBounds.y,Theme.accent)
    Theme.text(self,self.alertHintText or text('alertLocked'),self.titleBounds.x,self.titleBounds.y+h,Theme.muted)

    -- Heat Meter Card
    local hr=self.heatBounds
    local CardPanel=require 'EmberRoutesProbe/UI/CardPanel'
    local heatTitle=self.heatTitle or text('heatMeter')
    local heatSafeLabel=self.heatSafeLabel or (text('heatSafe')..' (0 / 100)')
    CardPanel.draw(self,hr.x,hr.y,hr.width,hr.height,{
        title=heatTitle,
        badge=heatSafeLabel,
        badgeColor=Theme.status.READY
    })
    Theme.text(self,self.heatUnavailable or text('unavailable'),hr.x+p,hr.y+p+h+p/4,Theme.muted)

    -- Heat progress bar preview (0/100, safe threshold at 70%)
    local StatMeter=require 'EmberRoutesProbe/UI/StatMeter'
    local meterY=hr.y+hr.height-p*1.5
    local meterW=hr.width-p*2
    local meterH=math.max(6,math.floor(p*0.8))
    StatMeter.draw(self,hr.x+p,meterY,meterW,meterH,0.0,{
        mode="danger",
        threshold=0.7
    })

    -- Posts Card
    local pr=self.postsBounds
    CardPanel.draw(self,pr.x,pr.y,pr.width,pr.height,{
        title=self.postsTitle or text('posts')
    })

    local curY=pr.y+p+h+p
    if self.checklists then
        for _,req in ipairs(self.checklists) do
            Theme.text(self,req,pr.x+p,curY,Theme.muted)
            curY=curY+h
        end
        curY=curY+p/2
    end

    if self.noPostsLines then
        for _,line in ipairs(self.noPostsLines) do
            Theme.text(self,line,pr.x+p,curY,Theme.muted)
            curY=curY+h
        end
    end
end

function EmberRoutesDefensePage:focusContent() end

return EmberRoutesDefensePage
