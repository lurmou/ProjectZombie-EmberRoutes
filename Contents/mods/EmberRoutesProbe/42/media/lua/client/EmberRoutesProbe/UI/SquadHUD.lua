require 'ISUI/ISPanel'
require 'ISUI/ISButton'
require 'ISUI/ISToolTip'
local Service=require 'EmberRoutesProbe/Settlement/SquadService'
local Preferences=require 'EmberRoutesProbe/Settlement/SquadPreferences'
local Personnel=require 'EmberRoutesProbe/Settlement/PersonnelService'
local Signals=require 'EmberRoutesProbe/Work/LaborSignals'
local Lifecycle=require 'EmberRoutesProbe/UI/PageLifecycle'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Card=require 'EmberRoutesProbe/UI/CardPanel'
local Visual=require 'EmberRoutesProbe/UI/StatusVisual'
local Badge=require 'EmberRoutesProbe/UI/SemanticBadge'
local Text=require 'EmberRoutesProbe/UI/Text'
local Tooltip=require 'EmberRoutesProbe/UI/TooltipManager'
local Presentation=require 'EmberRoutesProbe/UI/SquadPresentation'
local Menus=require 'EmberRoutesProbe/UI/SquadHUDMenus'
local Viewport=require 'EmberRoutesProbe/UI/Viewport'
local Clock = require 'EmberRoutesProbe/Kernel/Clock'
local HUD=ISPanel:derive('EmberRoutesSquadHUD')
local function label(key) return getText('IGUI_EmberRoutesProbe_Squad_'..key) end
function HUD:new(actor,commands,hidden)
    local o=ISPanel.new(self,70,50,340,200)
    o.actor=actor o.onCommands=commands o.closeCommands=hidden o.cards={} o.selected={} o.scroll=0
    o.preferences=Preferences.new(actor) o.background=false
    o.bounds={x=0,y=0,width=340,height=200} o.bodyBounds={x=8,y=40,width=324,height=140}
    o.drawContent=function() o:drawCached() end
    o.drawBody=function() o:drawCards() end
    Lifecycle.createLifetimeScope(o)
    return o
end
function HUD:initialise()
    ISPanel.initialise(self)
    local function button(text,callback)
        local b=ISButton:new(0,0,60,24,text,self,callback)
        b:initialise() b:instantiate() self:addChild(b) return b
    end
    self.allButton=button(label('all'),function() self:selectAll() end)
    self.commandButton=button(label('commands'),function() self.onCommands(self,false) end)
    self.settingsButton=button(label('settings'),function() Menus.settings(self,getMouseX(),getMouseY()) end)
    self.closeButton=button('x',function() self:hide() end)
end
function HUD:show()
    if self.active or self.disposed then return end
    local scope=Lifecycle.createActivationScope(self)
    self.session=Service.new(self.actor,self)
    scope:defer(function() self.session:close() end)
    local dirty=scope:wrapCallback(function(id) self.session:invalidate(id) end)
    scope:defer(Signals.watch(dirty)) scope:defer(Personnel.watchPortrait(dirty))
    scope:defer(Theme.watch(scope:wrapCallback(function() self.session:invalidate() end)))
    Tooltip.register(self,{method='update',owner=self})
    scope:defer(function() Tooltip.unregister(self) end)
    scope:defer(function() Menus.close(self) self:cancelDrag() end)
    scope:defer(function() self.closeCommands(self) end)
    self:setVisible(true) self:addToUIManager()
    self:relayout() self:update()
end
function HUD:hide()
    Lifecycle.unmount(self) self:setVisible(false) self:removeFromUIManager()
    self.cards={} self.selected={} self.hovered=nil self.scroll=0
end
function HUD:close() self:hide() Lifecycle.dispose(self) end
function HUD:selectAll()
    self.selected={}
    for _,row in ipairs(self.session.rows) do self.selected[row.id]=true end
    self:project()
end
function HUD:relayout()
    self:cancelDrag() self:setHover(nil) Menus.close(self)
    local core=getCore() local tm=getTextManager()
    self.screenW=core:getScreenWidth() self.screenH=core:getScreenHeight()
    self.h=tm:getFontHeight(UIFont.Small)
    local scale=self.preferences.value.scale local buttonScale=self.preferences.value.buttonScale
    local h=self.h local pad=math.max(4,math.ceil(6*scale))
    local bh=math.max(h+6,math.floor((h+8)*buttonScale))
    local rowH=math.max(h,bh)
    local width=math.min(math.max(280,h*24)*scale,self.screenW-16)
    width=math.max(1,width)
    self:setWidth(width)
    self.layout={h=h,pad=pad,portrait=math.ceil(h*2.7*scale),header=rowH+bh+pad*3}
    self.headerHeight=self.layout.header
    self.titleText=Text.wrapLimited(label('title'),math.max(1,width-bh*2-100),UIFont.Small,1)[1]
    self.emptyLines=Text.wrapLimited(label('empty'),math.max(1,width-20),UIFont.Small,3)
    self.hintLines=Text.wrapLimited(label('selectionHint'),math.max(1,width-20),UIFont.Small,3)
    local function place(b,x,y,w)
        b:setX(x) b:setY(y) b:setWidth(w) b:setHeight(bh)
    end
    local closeW=bh
    local settingsW=math.min(width/2,math.ceil((tm:MeasureStringX(UIFont.Small,label('settings'))+pad*2)*buttonScale))
    place(self.closeButton,width-pad-closeW,pad,closeW)
    place(self.settingsButton,width-pad*2-closeW-settingsW,pad,settingsW)
    local half=math.max(1,(width-pad*3)/2)
    place(self.allButton,pad,rowH+pad*2,half)
    place(self.commandButton,pad*2+half,rowH+pad*2,half)
    self.bounds.width=width self.bodyBounds.width=math.max(0,width-16)
    self:project()
    local x,y=self.preferences:position(self.width,self.height,self.screenW,self.screenH)
    self:setX(x) self:setY(y)
end
function HUD:project()
    if not self.layout or not self.session then return end
    local rows=self.preferences:ordered(self.session.rows) local alive={}
    for _,row in ipairs(rows) do alive[row.id]=true end
    for id in pairs(self.selected) do if not alive[id] then self.selected[id]=nil end end
    if self.hovered and not alive[self.hovered] then self:setHover(nil) end
    if self.drag and self.drag.id and not alive[self.drag.id] then self:cancelDrag() end
    local cards,contentHeight=Presentation.cards(rows,self.selected,self.width,self.layout,Theme,
        self.preferences.value,self.hovered,self.scroll)
    local footer=self.h*#self.hintLines+12
    local maxBody=math.max(0,self.screenH-self.headerHeight-footer-16)
    local bodyHeight=math.min(#cards==0 and self.h*#self.emptyLines+16 or contentHeight,maxBody)
    local oldScroll=self.scroll
    self.scrollMax=math.max(0,contentHeight-bodyHeight)
    self.scroll=math.max(0,math.min(self.scroll,self.scrollMax))
    if oldScroll~=self.scroll then for _,card in ipairs(cards) do card.y=card.y+oldScroll-self.scroll end end
    self.cards=cards self.contentHeight=contentHeight
    self.bodyBounds.y=self.headerHeight self.bodyBounds.height=bodyHeight
    self:setHeight(self.headerHeight+bodyHeight+footer) self.bounds.height=self.height
    Theme.button(self.allButton,false) Theme.button(self.commandButton,true)
    Theme.button(self.settingsButton,false) Theme.button(self.closeButton,false)
    self.commandButton:setEnable(#cards>0) self.allButton:setEnable(#cards>0)
    self:setX(math.max(0,math.min(self.x,self.screenW-self.width)))
    self:setY(math.max(0,math.min(self.y,self.screenH-self.height)))
    self:updateTooltip()
end
function HUD:update()
    if not self.active then return end
    if not self.session:valid() then self:close() return end
    local now=Clock.nowMs()
    if now>=(self.nextLayoutAt or 0) then
        self.nextLayoutAt=now+500
        local core=getCore()
        if core:getScreenWidth()~=self.screenW or core:getScreenHeight()~=self.screenH
            or getTextManager():getFontHeight(UIFont.Small)~=self.h then self:relayout() end
    end
    if self.session:refresh(now) then self:project() end
    self:updateTooltip()
end
function HUD:cardAt(x,y)
    if x<8 or x>self.width-8 or y<self.bodyBounds.y or y>=self.bodyBounds.y+self.bodyBounds.height then return end
    for _,card in ipairs(self.cards) do if y>=card.y and y<card.y+card.height then return card end end
end
function HUD:setHover(id)
    if self.hovered==id then return end
    self.hovered=id
    for _,card in ipairs(self.cards) do card.opts.hover=card.id==id end
    self:updateTooltip()
end
function HUD:updateTooltip()
    if not self.active then return end
    local description
    for _,card in ipairs(self.cards) do if card.id==self.hovered then description=card.tooltip break end end
    if not description or self.drag then Tooltip.clear(self) return end
    if not self.tooltipUI then
        self.tooltipUI=ISToolTip:new() self.tooltipUI:initialise() self.tooltipUI:instantiate()
        self.tooltipUI:setOwner(self) self.tooltipUI:setAlwaysOnTop(true) self.tooltipUI.maxLineWidth=360
    end
    if self.tooltipDescription~=description then
        self.tooltipDescription=description self.tooltipUI:setDescription(description)
    end
    if not self.tooltipUI:getIsVisible() then self.tooltipUI:addToUIManager() self.tooltipUI:setVisible(true) end
    Tooltip.position(self)
end
function HUD:cancelDrag()
    self.drag=nil self.dropIndex=nil self.dropY=nil self.dropHeight=nil self:setCapture(false)
end
function HUD:onMouseDown(x,y)
    if not self.active then return false end
    if y>=0 and y<self.layout.header then
        -- Header buttons consume their own events. Remaining title space is the dock handle.
        self.drag={kind='dock',x=self.x,y=self.y,dx=0,dy=0} self:setCapture(true) self:setHover(nil) return true
    end
    local card=self:cardAt(x,y)
    if card then
        self.drag={kind='card',id=card.id,dx=0,dy=0,shift=isShiftKeyDown()}
        self:setCapture(true) self:setHover(nil) return true
    end
    return true
end
function HUD:movePointer(dx,dy)
    local d=self.drag
    if d then
        d.dx=d.dx+dx d.dy=d.dy+dy
        if d.kind=='dock' then
            self:setX(math.max(0,math.min(d.x+d.dx,self.screenW-self.width)))
            self:setY(math.max(0,math.min(d.y+d.dy,self.screenH-self.height)))
        elseif math.abs(d.dx)+math.abs(d.dy)>=6 then
            d.moved=true
            local target=self:cardAt(self:getMouseX(),self:getMouseY())
            self.dropIndex=nil self.dropY=nil self.dropHeight=nil
            if target then
                for i,card in ipairs(self.cards) do if card.id==target.id then self.dropIndex=i break end end
                self.dropY=target.y self.dropHeight=target.height
            end
        end
        return true
    end
    local card=self:cardAt(self:getMouseX(),self:getMouseY()) self:setHover(card and card.id)
    return true
end
function HUD:onMouseMove(dx,dy) return self:movePointer(dx,dy) end
function HUD:onMouseMoveOutside(dx,dy)
    if self.drag then return self:movePointer(dx,dy) end
    self:setHover(nil) return true
end
function HUD:finishDrag(x,y)
    local d=self.drag if not d then return false end
    local index=self.dropIndex self:cancelDrag()
    if d.kind=='dock' then self.preferences:setPosition(self.x,self.y,self.screenW,self.screenH)
    elseif d.moved then
        if self:cardAt(x,y) and index then self.preferences:reorder(self.session.rows,d.id,index) self:project() end
    else
        local card=self:cardAt(x,y)
        if card and card.id==d.id then
            if not d.shift then self.selected={} end
            self.selected[d.id]=not self.selected[d.id] or nil self:project()
        end
    end
    return true
end
function HUD:onMouseUp(x,y) return self:finishDrag(x,y) end
function HUD:onMouseUpOutside(x,y) return self:finishDrag(x,y) end
function HUD:onMouseWheel(delta)
    self:cancelDrag() self:setHover(nil)
    self.scroll=math.max(0,math.min(self.scrollMax,self.scroll-delta*self.h*3)) self:project() return true
end
function HUD:onRightMouseUp(x,y)
    local card=self:cardAt(x,y)
    if card then self:cancelDrag() Menus.member(self,card.id,self:getAbsoluteX()+x,self:getAbsoluteY()+y) return true end
    return false
end
function HUD:drawCards()
    local h,pad,portrait=self.h,self.layout.pad,self.layout.portrait
    if #self.cards==0 then
        for i,line in ipairs(self.emptyLines) do Theme.text(self,line,10,self.headerHeight+(i-1)*h+6,Theme.muted) end
    end
    for _,card in ipairs(self.cards) do
        if card.y+card.height>self.bodyBounds.y and card.y<self.bodyBounds.y+self.bodyBounds.height then
            local x,y=8,card.y
            Card.draw(self,x,y,self.width-16,card.height,card.opts)
            if card.portrait then self:drawTextureScaledAspect(card.portrait,x+pad,y+4,portrait,portrait,1,1,1,1) end
            Theme.text(self,card.name,x+portrait+pad*2,y+2,Theme.textColor)
            Theme.text(self,card.healthText,x+portrait+pad*2,y+h+2,Theme.muted)
            Visual.meter(self,x+portrait+pad*2,y+h*2+4,self.width-24-portrait-pad*3,3,
                card.health and card.health/100,card.healthColor)
            Theme.text(self,card.command,x+pad,y+card.top,Theme.textColor)
            Theme.text(self,card.actual,x+pad,y+card.top+h,Theme.muted)
            Theme.text(self,card.feedback,x+pad,y+card.top+h*2,card.feedbackColor)
            for _,badge in ipairs(card.badges) do
                Badge.draw(self,x+pad+badge.x,y+card.top+h*3,badge.width,h+4,badge.descriptor)
            end
        end
    end
    if self.dropY then Theme.rect(self,8,self.dropY,self.width-16,self.dropHeight,Theme.accent,true) end
end
function HUD:drawCached()
    Theme.rect(self,0,0,self.width,self.height,Theme.window)
    Theme.text(self,self.titleText,10,self.layout.pad,Theme.gold)
    Viewport.draw(self,self.bodyBounds,self.drawBody)
    for i,line in ipairs(self.hintLines) do
        Theme.text(self,line,10,self.height-self.h*(#self.hintLines-i+1)-4,Theme.muted)
    end
end
function HUD:prerender() Viewport.draw(self,self.bounds,self.drawContent) end
function HUD:render() end
return HUD
