require 'ISUI/ISCollapsableWindow'
require 'ISUI/ISButton'
require 'ISUI/ISTextEntryBox'
require 'ISUI/ISComboBox'
local Crafting=require 'EmberRoutesProbe/CraftingService'
local Public=require 'EmberRoutesProbe/PublicWork'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Layout=require 'EmberRoutesProbe/UI/Layout'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Text=require 'EmberRoutesProbe/UI/Text'
local Tooltip=require 'EmberRoutesProbe/UI/TooltipAnchor'
local function text(key,...) return getText('IGUI_EmberRoutesProbe_Public_'..key,...) end
EmberRoutesPublicOrderDialog=ISCollapsableWindow:derive('EmberRoutesPublicOrderDialog')
function EmberRoutesPublicOrderDialog.open(owner,context)
    local h,p=owner.fontHeight,owner.pad
    local w=math.min(getCore():getScreenWidth()*0.9,h*30)
    local height=math.min(getCore():getScreenHeight()*0.94,h*25)
    local o=ISCollapsableWindow.new(EmberRoutesPublicOrderDialog,(getCore():getScreenWidth()-w)/2,(getCore():getScreenHeight()-height)/2,w,height)
    o.owner,o.actor,o.entry=owner,owner.actor,owner.entry o.fontHeight,o.pad=h,p
    o.context=context or {} o.title=text('createOrder') o.requestId=Registry.id() o.page=1 o.rows={} o.selectedRecipe=false
    o.resizable=false o.backgroundColor=Theme.window o.borderColor=Theme.border
    o:initialise() o:addToUIManager() o:query() return o
end
function EmberRoutesPublicOrderDialog:initialise() ISCollapsableWindow.initialise(self) end
function EmberRoutesPublicOrderDialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local tracks={}
    for _=1,9 do tracks[#tracks+1]={basis=h+math.max(2,math.floor(p/3))} end
    tracks[#tracks+1]={grow=1}
    self.regions=assert(Layout.axis({x=0,y=self:titleBarHeight(),width=self.width,height=self.height-self:titleBarHeight()},tracks,
        {direction='column',padding=p,gap=p/3}))
    local function input(index,value,changed)
        local r=self.regions[index] local box=ISTextEntryBox:new(value,r.x+r.width/2,r.y,r.width/2,r.height)
        box:initialise() box.target=self box.onTextChangeFunction=changed self:addChild(box) return box
    end
    self.search=input(1,self.context.recipeName or (self.context.productType and getItemNameFromFullType(self.context.productType)) or '',function()
        self.page=1 self:query()
    end)
    local r=self.regions[2]
    self.recipeCombo=ISComboBox:new(r.x,r.y,r.width,r.height,self,function()
        local row=self.rows[self.recipeCombo.selected]
        self.selectedRecipe=row and row.id or false self.requestId=Registry.id() self:loadRule() self:describe()
    end)
    self.recipeCombo:initialise() self:addChild(self.recipeCombo)
    local nav=assert(Layout.axis(self.regions[3],{{grow=1},{grow=1}},{gap=p}))
    local function button(label,r,fn)
        local b=ISButton:new(r.x,r.y,r.width,r.height,label,self,fn)
        b:initialise() Theme.button(b) self:addChild(b) return b
    end
    self.previous=button(text('previous'),nav[1],function() self.page=math.max(1,self.page-1) self:query() end)
    self.next=button(text('next'),nav[2],function() self.page=self.page+1 self:query() end)
    self.quantity=input(4,'1',function() self.requestId=Registry.id() self:describe() end)
    r=self.regions[5]
    self.surfaceCombo=ISComboBox:new(r.x+r.width/2,r.y,r.width/2,r.height,self,function() self.requestId=Registry.id() end)
    self.surfaceCombo:initialise() self:addChild(self.surfaceCombo) self.surfaces={false}
    self.surfaceCombo:addOption(text('noSurface'))
    for _,surface in ipairs(require('EmberRoutesProbe/CraftSurfaces').list(self.entry)) do
        self.surfaces[#self.surfaces+1]=surface.id self.surfaceCombo:addOption(text('surfaceAt',surface.x,surface.y,surface.z))
        if surface.id==self.context.surfaceId then self.surfaceCombo.selected=#self.surfaces end
    end
    self.minimum=input(6,'0',function() end)
    self.batch=input(7,'10',function() end)
    self.submit=button(text('submit'),self.regions[8],function() self:submitOrder() end)
    self.saveRule=button(text('saveRule'),self.regions[9],function() self:submitRule() end)
end
function EmberRoutesPublicOrderDialog:query()
    if self.releaseCatalog then self.releaseCatalog() self.releaseCatalog=nil end
    if self.disposed then return end
    local token={} self.catalogToken=token
    local release=Crafting.watchCatalog(self.actor,self.entry.id,{search=self.search:getText(),category=false,unsupported=false,page=self.page,size=12},function(snapshot)
        if self.disposed or self.catalogToken~=token then return end
        if not self.owner:valid() then self:close() return end
        self.rows=snapshot.rows or {} self.recipeCombo:clear()
        local selected=1
        for i,row in ipairs(self.rows) do
            self.recipeCombo:addOption(row.name)
            if row.id==(self.context.recipeId or self.selectedRecipe) then selected=i end
        end
        self.recipeCombo.selected=selected
        local chosen=self.rows[selected] and self.rows[selected].id or false
        if chosen~=self.selectedRecipe then self.requestId=Registry.id() end
        self.selectedRecipe=chosen self.context.recipeId=nil self:loadRule()
        self.page=snapshot.page or 1 Theme.enable(self.previous,self.page>1)
        Theme.enable(self.next,self.page<(snapshot.pages or 1)) self:describe()
    end)
    if self.disposed or self.catalogToken~=token then if release then release() end else self.releaseCatalog=release end
end
function EmberRoutesPublicOrderDialog:loadRule()
    local row=self.rows[self.recipeCombo.selected]
    if not row or self.ruleProduct==row.product then return end
    self.ruleProduct=row.product
    local rule=Public.rule(self.entry.id,row.product)
    self.minimum:setText(tostring(rule and rule.minimum or 0))
    self.batch:setText(tostring(rule and rule.batch or 10))
end
function EmberRoutesPublicOrderDialog:describe()
    local row=self.rows[self.recipeCombo.selected]
    local n=tonumber(self.quantity:getText())
    self.preview=row and row.yield and row.yield>0 and n and n>=1 and n==math.floor(n) and text('expected',n,math.ceil(n/row.yield),math.ceil(n/row.yield)*row.yield) or text('chooseRecipe')
    Theme.enable(self.submit,row~=nil and n~=nil and n>=1 and n<=9999 and n==math.floor(n),true)
    Theme.enable(self.saveRule,row~=nil)
end
function EmberRoutesPublicOrderDialog:submitOrder()
    if not self.owner:valid() then self:close() return end
    local result=Public.create(self.actor,self.entry.id,self.selectedRecipe,tonumber(self.quantity:getText()),
        self.surfaces[self.surfaceCombo.selected],self.requestId)
    self.notice=require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)
    if result=='ORDER_CREATED' then self.owner:selectTab('orders') self:close() end
end
function EmberRoutesPublicOrderDialog:submitRule()
    if not self.owner:valid() then self:close() return end
    local result=Public.saveRule(self.actor,self.entry.id,self.selectedRecipe,tonumber(self.minimum:getText()),
        tonumber(self.batch:getText()),self.surfaces[self.surfaceCombo.selected])
    self.notice=require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)
end
function EmberRoutesPublicOrderDialog:prerender()
    ISCollapsableWindow.prerender(self)
    local labels={[1]='search',[4]='quantity',[5]='surface',[6]='minimum',[7]='batch'}
    for i,key in pairs(labels) do local r=self.regions[i] Theme.text(self,(Text.wrapLimited(text(key),r.width/2-self.pad,UIFont.Small,1)[1] or ''),r.x,r.y+(r.height-self.fontHeight)/2,Theme.textColor) end
    local r=self.regions[10] local y=r.y
    for _,line in ipairs(Text.wrapLimited(self.notice or self.preview or text('chooseRecipe'),r.width,UIFont.Small,3)) do
        Theme.text(self,line,r.x,y,Theme.accent) y=y+self.fontHeight
    end
end
function EmberRoutesPublicOrderDialog:close()
    if self.disposed then return end self.disposed=true self.catalogToken=nil
    if self.releaseCatalog then self.releaseCatalog() self.releaseCatalog=nil end
    self.recipeCombo:hidePopup() self.surfaceCombo:hidePopup()
    Tooltip.clear(self.recipeCombo) Tooltip.clear(self.surfaceCombo)
    ISCollapsableWindow.close(self) self:removeFromUIManager()
    if self.owner.publicDialog==self then self.owner.publicDialog=nil end
end
return EmberRoutesPublicOrderDialog
