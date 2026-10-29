require 'ISUI/ISCollapsableWindow'
require 'ISUI/ISComboBox'
require 'ISUI/ISButton'
local Zones=require 'EmberRoutesProbe/SettlementZones'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Layout=require 'EmberRoutesProbe/UI/Layout'
local Text=require 'EmberRoutesProbe/UI/Text'
local Dialog=ISCollapsableWindow:derive('EmberRoutesLifeZoneRules')
local active
local function text(key) return getText('IGUI_EmberRoutesProbe_LifeZone_'..key) end
function Dialog.open(actor,zone)
    if not Ledger.view(actor,zone.settlementId) then return end
    if active then active:close() end
    local h=getTextManager():getFontHeight(UIFont.Small) local p=math.ceil(h*.6)
    local ids=Zones.activities()
    local width=math.min(getCore():getScreenWidth()*.9,h*31)
    local height=math.min(getCore():getScreenHeight()*.94,(h+p)*(#ids+3)+h*5)
    local o=ISCollapsableWindow.new(Dialog,(getCore():getScreenWidth()-width)/2,(getCore():getScreenHeight()-height)/2,width,height)
    o.actor,o.zone,o.world,o.ids=actor,zone,Ledger.data(),ids
    o.fontHeight,o.pad=h,p o.title=text('rules')..' - '..zone.name o.resizable=false
    o.backgroundColor,o.borderColor=Theme.window,Theme.border
    o:initialise() o:addToUIManager() active=o return o
end
function Dialog:initialise() ISCollapsableWindow.initialise(self) end
function Dialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local tracks={}
    for _ in ipairs(self.ids) do tracks[#tracks+1]={grow=1} end
    tracks[#tracks+1]={basis=h*3} tracks[#tracks+1]={basis=h+p}
    local rows=assert(Layout.axis({x=0,y=self:titleBarHeight(),width=self.width,height=self.height-self:titleBarHeight()},
        tracks,{direction='column',padding=p,gap=p/2}))
    self.fields,self.labels={},{}
    for i,id in ipairs(self.ids) do
        local row=rows[i]
        local columns=assert(Layout.axis(row,{{grow=1},{grow=1}},{gap=p}))
        self.labels[#self.labels+1]={text=text(id),x=columns[1].x,y=columns[1].y}
        local r=columns[2]
        local combo=ISComboBox:new(r.x,r.y,r.width,math.min(r.height,h+p),self,nil)
        combo:initialise() self:addChild(combo)
        for n=0,2 do combo:addOption(text('rule'..n)) end
        combo.selected=(self.zone.rules[id] or 1)+1 self.fields[id]=combo
    end
    self.noticeBounds=rows[#rows-1]
    local r=rows[#rows]
    local button=ISButton:new(r.x,r.y,r.width,r.height,getText('UI_btn_apply'),self,Dialog.apply)
    button:initialise() Theme.button(button,true) self:addChild(button)
end
function Dialog:apply()
    local rules={} for id,combo in pairs(self.fields) do rules[id]=combo.selected-1 end
    local zone,why=Zones.save(self.actor,self.zone.settlementId,self.zone.id,self.zone.revision,
        {name=self.zone.name,area=self.zone.area,enabled=self.zone.enabled,rules=rules})
    if zone then self.zone=zone self.notice=text('saved') else self.notice=text(why) end
end
function Dialog:prerender()
    ISCollapsableWindow.prerender(self)
    for _,label in ipairs(self.labels or {}) do
        Theme.text(self,label.text,label.x,label.y+self.pad/2,Theme.textColor)
    end
    if self.noticeBounds then
        local r=self.noticeBounds
        local lines=Text.wrapLimited(self.notice or text('ruleHint'),r.width,UIFont.Small,3)
        for i,line in ipairs(lines) do Theme.text(self,line,r.x,r.y+(i-1)*self.fontHeight,Theme.muted) end
    end
end
function Dialog:update()
    if ISCollapsableWindow.update then ISCollapsableWindow.update(self) end
    if Ledger.data()~=self.world or not Ledger.view(self.actor,self.zone.settlementId) then self:close() end
end
function Dialog:close()
    if self.disposed then return end self.disposed=true
    for _,combo in pairs(self.fields or {}) do combo:hidePopup() end
    ISCollapsableWindow.close(self) self:removeFromUIManager()
    if active==self then active=nil end
end
return Dialog
