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

---@class EmberRoutesPublicOrderDialog:ISCollapsableWindow
---@field owner EmberRoutesSettlementDashboard
---@field actor IsoPlayer
---@field entry table
---@field fontHeight number
---@field pad number
---@field activeTab string
EmberRoutesPublicOrderDialog=ISCollapsableWindow:derive('EmberRoutesPublicOrderDialog')

function EmberRoutesPublicOrderDialog.open(owner,context)
    local h,p=owner.fontHeight,owner.pad
    local w=math.min(getCore():getScreenWidth()*0.9,h*36)
    local height=math.min(getCore():getScreenHeight()*0.94,h*29)
    local o=ISCollapsableWindow.new(EmberRoutesPublicOrderDialog,(getCore():getScreenWidth()-w)/2,(getCore():getScreenHeight()-height)/2,w,height)
    o.owner,o.actor,o.entry=owner,owner.actor,owner.entry
    o.fontHeight,o.pad=h,p
    o.context=context or {}
    o.title=text('createOrder')
    o.requestId=Registry.id()
    o.page=1
    o.rows={}
    o.selectedRecipe=false
    o.activeTab='order' -- 'order' or 'stock'
    o.resizable=false
    o.backgroundColor=Theme.window
    o.borderColor=Theme.border
    o:setWantKeyEvents(true)
    o:initialise()
    o:addToUIManager()
    o:query()
    return o
end

function EmberRoutesPublicOrderDialog:initialise() ISCollapsableWindow.initialise(self) end

function EmberRoutesPublicOrderDialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    local h,p=self.fontHeight,self.pad

    -- Vertical 6-part layout
    -- 1. Mode Tabs (Single Order vs Maintain Stock)
    -- 2. Recipe Search & Selection
    -- 3. Surface Selection
    -- 4. Dynamic Parameter Form (Quantity + Stepper OR Stock Thresholds + Stepper)
    -- 5. Preview & Status Area
    -- 6. Action Button
    local regions=assert(Layout.axis({x=0,y=self:titleBarHeight(),width=self.width,height=self.height-self:titleBarHeight()},
        {{basis=h+p/2},{basis=h*4+p},{basis=h+p/2},{basis=h*5+p},{grow=1},{basis=h+p}},
        {direction='column',padding=p,gap=p/3}))

    self.tabRegion=regions[1]
    self.recipeRegion=regions[2]
    self.surfaceRegion=regions[3]
    self.formRegion=regions[4]
    self.previewRegion=regions[5]
    self.actionRegion=regions[6]

    -- 1. Top Tabs
    local tabCols=assert(Layout.axis(self.tabRegion,{{grow=1},{grow=1}},{gap=p/2}))
    self.orderTabBtn=ISButton:new(tabCols[1].x,tabCols[1].y,tabCols[1].width,tabCols[1].height,text('tab_order'),self,function()
        self:selectTab('order')
    end)
    self.orderTabBtn:initialise()
    self:addChild(self.orderTabBtn)

    self.stockTabBtn=ISButton:new(tabCols[2].x,tabCols[2].y,tabCols[2].width,tabCols[2].height,text('tab_stock'),self,function()
        self:selectTab('stock')
    end)
    self.stockTabBtn:initialise()
    self:addChild(self.stockTabBtn)

    -- 2. Recipe Search & Selection Rows
    local recipeRows=assert(Layout.axis(self.recipeRegion,
        {{basis=h+math.floor(p/4)},{basis=h+math.floor(p/4)},{basis=h+math.floor(p/4)}},
        {direction='column',gap=p/4}))

    -- Search input row (Label left, input right)
    local r1=assert(Layout.axis(recipeRows[1],{{basis=h*8},{grow=1}},{gap=p/2}))
    self.searchLabel=r1[1]
    local defaultSearch=self.context.recipeName or (self.context.productType and getItemNameFromFullType(self.context.productType)) or ''
    self.search=ISTextEntryBox:new(defaultSearch,r1[2].x,r1[2].y,r1[2].width,r1[2].height)
    self.search:initialise()
    self.search.target=self
    self.search.onTextChangeFunction=function()
        self.page=1
        self:query()
    end
    self:addChild(self.search)

    -- Recipe Combo row
    self.recipeCombo=ISComboBox:new(recipeRows[2].x,recipeRows[2].y,recipeRows[2].width,recipeRows[2].height,self,function()
        local row=self.rows[self.recipeCombo.selected]
        self.selectedRecipe=row and row.id or false
        self.requestId=Registry.id()
        self:loadRule()
        self:describe()
    end)
    self.recipeCombo:initialise()
    self:addChild(self.recipeCombo)

    -- Recipe Pager row
    local nav=assert(Layout.axis(recipeRows[3],{{grow=1},{basis=h*6},{grow=1}},{gap=p/2}))
    self.previous=ISButton:new(nav[1].x,nav[1].y,nav[1].width,nav[1].height,text('previous'),self,function()
        self.page=math.max(1,self.page-1)
        self:query()
    end)
    self.previous:initialise()
    Theme.button(self.previous)
    self:addChild(self.previous)

    self.pageIndicatorRegion=nav[2]

    self.next=ISButton:new(nav[3].x,nav[3].y,nav[3].width,nav[3].height,text('next'),self,function()
        self.page=self.page+1
        self:query()
    end)
    self.next:initialise()
    Theme.button(self.next)
    self:addChild(self.next)

    -- 3. Surface Selection
    local surfCols=assert(Layout.axis(self.surfaceRegion,{{basis=h*8},{grow=1}},{gap=p/2}))
    self.surfaceLabel=surfCols[1]
    self.surfaceCombo=ISComboBox:new(surfCols[2].x,surfCols[2].y,surfCols[2].width,surfCols[2].height,self,function()
        self.requestId=Registry.id()
    end)
    self.surfaceCombo:initialise()
    self:addChild(self.surfaceCombo)
    self.surfaces={false}
    self.surfaceCombo:addOption(text('noSurface'))
    for _,surface in ipairs(require('EmberRoutesProbe/CraftSurfaces').list(self.entry)) do
        self.surfaces[#self.surfaces+1]=surface.id
        self.surfaceCombo:addOption(text('surfaceAt',surface.x,surface.y,surface.z))
        if surface.id==self.context.surfaceId then self.surfaceCombo.selected=#self.surfaces end
    end

    -- 4. Dynamic Parameter Form Controls
    -- A. Quantity (Single Order)
    local qCols=assert(Layout.axis({x=self.formRegion.x,y=self.formRegion.y+p/4,width=self.formRegion.width,height=h+p/2},
        {{basis=h*8},{basis=h*5},{basis=h*3},{basis=h*3},{basis=h*3},{basis=h*3}},{gap=p/3}))
    self.quantityLabel=qCols[1]
    self.quantity=ISTextEntryBox:new('1',qCols[2].x,qCols[2].y,qCols[2].width,qCols[2].height)
    self.quantity:initialise()
    self.quantity.target=self
    self.quantity.onTextChangeFunction=function()
        self.requestId=Registry.id()
        self:describe()
    end
    self:addChild(self.quantity)

    local function makeStepper(label,r,delta,targetBox,minVal)
        minVal=minVal or 1
        local btn=ISButton:new(r.x,r.y,r.width,r.height,label,self,function()
            local cur=tonumber(targetBox:getText()) or 0
            local n=math.max(minVal,math.min(9999,cur+delta))
            targetBox:setText(tostring(n))
            self.requestId=Registry.id()
            self:describe()
        end)
        btn:initialise()
        Theme.button(btn)
        self:addChild(btn)
        return btn
    end

    self.qStepDec5=makeStepper('-5',qCols[3],-5,self.quantity,1)
    self.qStepDec1=makeStepper('-1',qCols[4],-1,self.quantity,1)
    self.qStepInc1=makeStepper('+1',qCols[5],1,self.quantity,1)
    self.qStepInc5=makeStepper('+5',qCols[6],5,self.quantity,1)

    -- B. Stock Thresholds (Maintain Stock)
    local minCols=assert(Layout.axis({x=self.formRegion.x,y=self.formRegion.y+p/4,width=self.formRegion.width,height=h+p/2},
        {{basis=h*8},{basis=h*5},{basis=h*3},{basis=h*3},{basis=h*3},{basis=h*3}},{gap=p/3}))
    self.minimumLabel=minCols[1]
    self.minimum=ISTextEntryBox:new('0',minCols[2].x,minCols[2].y,minCols[2].width,minCols[2].height)
    self.minimum:initialise()
    self.minimum.target=self
    self.minimum.onTextChangeFunction=function() self:describe() end
    self:addChild(self.minimum)
    self.minStepDec5=makeStepper('-5',minCols[3],-5,self.minimum,0)
    self.minStepDec1=makeStepper('-1',minCols[4],-1,self.minimum,0)
    self.minStepInc1=makeStepper('+1',minCols[5],1,self.minimum,0)
    self.minStepInc5=makeStepper('+5',minCols[6],5,self.minimum,0)

    local batchCols=assert(Layout.axis({x=self.formRegion.x,y=self.formRegion.y+h+p,width=self.formRegion.width,height=h+p/2},
        {{basis=h*8},{basis=h*5},{basis=h*3},{basis=h*3},{basis=h*3},{basis=h*3}},{gap=p/3}))
    self.batchLabel=batchCols[1]
    self.batch=ISTextEntryBox:new('10',batchCols[2].x,batchCols[2].y,batchCols[2].width,batchCols[2].height)
    self.batch:initialise()
    self.batch.target=self
    self.batch.onTextChangeFunction=function() self:describe() end
    self:addChild(self.batch)
    self.bStepDec10=makeStepper('-10',batchCols[3],-10,self.batch,1)
    self.bStepDec5=makeStepper('-5',batchCols[4],-5,self.batch,1)
    self.bStepInc5=makeStepper('+5',batchCols[5],5,self.batch,1)
    self.bStepInc10=makeStepper('+10',batchCols[6],10,self.batch,1)

    -- 6. Main Action Button
    self.actionButton=ISButton:new(self.actionRegion.x,self.actionRegion.y,self.actionRegion.width,self.actionRegion.height,text('submit'),self,function()
        if self.activeTab=='order' then
            self:submitOrder()
        else
            self:submitRule()
        end
    end)
    self.actionButton:initialise()
    Theme.button(self.actionButton,true)
    self:addChild(self.actionButton)

    self:selectTab('order')
end

function EmberRoutesPublicOrderDialog:selectTab(tab)
    self.activeTab=tab
    local isOrder=tab=='order'
    Theme.styleButton(self.orderTabBtn,isOrder,isOrder)
    Theme.styleButton(self.stockTabBtn,not isOrder,not isOrder)

    -- Toggle visibility of controls
    self.quantity:setVisible(isOrder)
    self.qStepDec5:setVisible(isOrder)
    self.qStepDec1:setVisible(isOrder)
    self.qStepInc1:setVisible(isOrder)
    self.qStepInc5:setVisible(isOrder)

    self.minimum:setVisible(not isOrder)
    self.minStepDec5:setVisible(not isOrder)
    self.minStepDec1:setVisible(not isOrder)
    self.minStepInc1:setVisible(not isOrder)
    self.minStepInc5:setVisible(not isOrder)

    self.batch:setVisible(not isOrder)
    self.bStepDec10:setVisible(not isOrder)
    self.bStepDec5:setVisible(not isOrder)
    self.bStepInc5:setVisible(not isOrder)
    self.bStepInc10:setVisible(not isOrder)

    self.actionButton:setTitle(text(isOrder and 'submit' or 'saveRule'))
    self:describe()
end

function EmberRoutesPublicOrderDialog:query()
    if self.releaseCatalog then self.releaseCatalog() self.releaseCatalog=nil end
    if self.disposed then return end
    local token={}
    self.catalogToken=token
    local release=Crafting.watchCatalog(self.actor,self.entry.id,{search=self.search:getText(),category=false,unsupported=false,page=self.page,size=12},function(snapshot)
        if self.disposed or self.catalogToken~=token then return end
        if not self.owner:valid() then self:close() return end
        self.rows=snapshot.rows or {}
        self.recipeCombo:clear()
        local selected=1
        for i,row in ipairs(self.rows) do
            self.recipeCombo:addOption(row.name)
            if row.id==(self.context.recipeId or self.selectedRecipe) then selected=i end
        end
        self.recipeCombo.selected=selected
        local chosen=self.rows[selected] and self.rows[selected].id or false
        if chosen~=self.selectedRecipe then self.requestId=Registry.id() end
        self.selectedRecipe=chosen
        self.context.recipeId=nil
        self:loadRule()
        self.page=snapshot.page or 1
        self.totalPages=snapshot.pages or 1
        Theme.enable(self.previous,self.page>1)
        Theme.enable(self.next,self.page<self.totalPages)
        self:describe()
    end)
    if self.disposed or self.catalogToken~=token then
        if release then release() end
    else
        self.releaseCatalog=release
    end
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
    if self.activeTab=='order' then
        self.preview=row and row.yield and row.yield>0 and n and n>=1 and n==math.floor(n)
            and text('expected',n,math.ceil(n/row.yield),math.ceil(n/row.yield)*row.yield) or text('chooseRecipe')
        Theme.enable(self.actionButton,row~=nil and n~=nil and n>=1 and n<=9999 and n==math.floor(n),true)
    else
        local minVal=tonumber(self.minimum:getText())
        local batchVal=tonumber(self.batch:getText())
        local validStock=minVal and minVal>=0 and minVal<=9999 and minVal==math.floor(minVal)
            and batchVal and batchVal>=1 and batchVal<=9999 and batchVal==math.floor(batchVal)
        self.preview=row and text('maintainPreview',row.name) or text('chooseRecipe')
        Theme.enable(self.actionButton,row~=nil and validStock,true)
    end
end

function EmberRoutesPublicOrderDialog:submitOrder()
    if not self.owner:valid() then self:close() return end
    local result=Public.create(self.actor,self.entry.id,self.selectedRecipe,tonumber(self.quantity:getText()),
        self.surfaces[self.surfaceCombo.selected],self.requestId)
    self.notice=require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)
    if result=='ORDER_CREATED' then
        self.owner:selectTab('orders')
        self:close()
    end
end

function EmberRoutesPublicOrderDialog:submitRule()
    if not self.owner:valid() then self:close() return end
    local result=Public.saveRule(self.actor,self.entry.id,self.selectedRecipe,tonumber(self.minimum:getText()),
        tonumber(self.batch:getText()),self.surfaces[self.surfaceCombo.selected])
    self.notice=require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)
end

function EmberRoutesPublicOrderDialog:prerender()
    ISCollapsableWindow.prerender(self)
    local h=self.fontHeight

    -- Labels
    Theme.text(self,text('recipeSelect'),self.searchLabel.x,self.searchLabel.y+(self.searchLabel.height-h)/2,Theme.textColor)
    Theme.text(self,text('surfaceSelect'),self.surfaceLabel.x,self.surfaceLabel.y+(self.surfaceLabel.height-h)/2,Theme.textColor)

    -- Page indicator
    local pageStr=(self.page or 1)..' / '..(self.totalPages or 1)
    local pageW=getTextManager():MeasureStringX(UIFont.Small,pageStr)
    Theme.text(self,pageStr,self.pageIndicatorRegion.x+(self.pageIndicatorRegion.width-pageW)/2,self.pageIndicatorRegion.y+(self.pageIndicatorRegion.height-h)/2,Theme.muted)

    if self.activeTab=='order' then
        Theme.text(self,text('targetQuantity'),self.quantityLabel.x,self.quantityLabel.y+(self.quantityLabel.height-h)/2,Theme.textColor)
    else
        Theme.text(self,text('stockThreshold'),self.minimumLabel.x,self.minimumLabel.y+(self.minimumLabel.height-h)/2,Theme.textColor)
        Theme.text(self,text('stockBatch'),self.batchLabel.x,self.batchLabel.y+(self.batchLabel.height-h)/2,Theme.textColor)
    end

    -- Preview Card
    local pr=self.previewRegion
    Theme.rect(self,pr.x,pr.y,pr.width,pr.height,Theme.panel)
    Theme.rect(self,pr.x,pr.y,pr.width,pr.height,Theme.border,true)

    local msg=self.notice or self.preview or text('chooseRecipe')
    local lines=Text.wrapLimited(msg,pr.width-self.pad*2,UIFont.Small,3)
    local curY=pr.y+self.pad/2
    for _,line in ipairs(lines) do
        Theme.text(self,line,pr.x+self.pad,curY,self.notice and Theme.gold or Theme.accent)
        curY=curY+h
    end
end

function EmberRoutesPublicOrderDialog:isKeyConsumed(key)
    return not self.disposed and key==Keyboard.KEY_ESCAPE
end

function EmberRoutesPublicOrderDialog:onKeyPress(key)
    if self:isKeyConsumed(key) then self:close() end
end

function EmberRoutesPublicOrderDialog:close()
    if self.disposed then return end
    self.disposed=true
    self.catalogToken=nil
    if self.releaseCatalog then self.releaseCatalog() self.releaseCatalog=nil end
    self.recipeCombo:hidePopup()
    self.surfaceCombo:hidePopup()
    Tooltip.clear(self.recipeCombo)
    Tooltip.clear(self.surfaceCombo)
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if self.owner.publicDialog==self then self.owner.publicDialog=nil end
end

return EmberRoutesPublicOrderDialog
