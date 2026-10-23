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
    o.store=State.new({alertLevel=0,heat=18,maxHeat=100,posts={}})
    o.store:subscribe(function(value)
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

    -- Alert level buttons (Defcon 0, 1, 2)
    local alertTrack=assert(Layout.axis(self.alertBounds,{{grow=1},{grow=1},{grow=1}},{gap=p/2}))
    for i=0,2 do
        local r=alertTrack[i+1]
        local btn=ISButton:new(r.x,r.y,r.width,r.height,text('alert_'..i),self,function()
            self:setAlertLevel(i)
        end)
        btn:initialise()
        Theme.styleButton(btn,false,i==self.store.value.alertLevel)
        btn.tooltip=text('alertHint')
        Tooltip.attach(btn,'prerender')
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
    self:deactivate()
end

function EmberRoutesDefensePage:project(value)
    if not self.active or self.disposed then return end
    -- Keep buttons synced with state
    for i=0,2 do
        local btn=self.alertButtons[i]
        if btn then Theme.styleButton(btn,i==value.alertLevel,i==value.alertLevel) end
    end
end

function EmberRoutesDefensePage:prerender()
    ISPanel.prerender(self)
    local h,p=self.fontHeight,self.pad

    -- Title
    Theme.text(self,text('title'),self.titleBounds.x,self.titleBounds.y,Theme.gold)
    Theme.text(self,text('alertHint'),self.titleBounds.x,self.titleBounds.y+h,Theme.muted)

    -- Heat Meter Card
    local hr=self.heatBounds
    Theme.rect(self,hr.x,hr.y,hr.width,hr.height,Theme.panel)
    Theme.rect(self,hr.x,hr.y,hr.width,hr.height,Theme.border,true)

    local heat=self.store.value.heat or 0
    local maxH=self.store.value.maxHeat or 100
    local heatRatio=math.max(0,math.min(1,heat/maxH))

    local heatLabel=text('heatValue',heat,heatRatio>0.6 and text('heatWarning') or text('heatSafe'))
    Theme.text(self,text('heatMeter'),hr.x+p,hr.y+p/2,Theme.accent)
    Theme.text(self,heatLabel,hr.x+p+getTextManager():MeasureStringX(UIFont.Small,text('heatMeter'))+p,hr.y+p/2,Theme.textColor)

    -- Heat Progress Bar
    local barY=hr.y+h+p/2
    local barW=hr.width-p*2
    local barH=h
    Theme.rect(self,hr.x+p,barY,barW,barH,Theme.control)
    Theme.rect(self,hr.x+p,barY,barW,barH,Theme.border,true)

    local fillW=math.floor(barW*heatRatio)
    local barColor=heatRatio>0.7 and {r=0.95,g=0.35,b=0.30,a=0.9} or (heatRatio>0.4 and {r=1.0,g=0.75,b=0.25,a=0.9} or {r=0.25,g=0.75,b=1.0,a=0.9})
    if fillW>0 then
        Theme.rect(self,hr.x+p+1,barY+1,fillW-2,barH-2,barColor)
    end

    -- Posts Card
    local pr=self.postsBounds
    Theme.rect(self,pr.x,pr.y,pr.width,pr.height,Theme.panel)
    Theme.rect(self,pr.x,pr.y,pr.width,pr.height,Theme.border,true)

    Theme.text(self,text('posts'),pr.x+p,pr.y+p,Theme.gold)
    Theme.rect(self,pr.x+p,pr.y+p+h+p/4,pr.width-p*2,1,Theme.border)

    local lines=Text.wrap(text('noPosts'),pr.width-p*3,UIFont.Small)
    for i,line in ipairs(lines) do
        Theme.text(self,line,pr.x+p,pr.y+p+h+p+(i-1)*h,Theme.muted)
    end
end

function EmberRoutesDefensePage:focusContent() end

return EmberRoutesDefensePage
