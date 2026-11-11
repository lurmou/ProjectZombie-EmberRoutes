-- PublicOrderDialogLayout.lua - EmberRoutes UI
-- Dialog layout: two-column control/blueprint assembly, tabs, recipe and
-- surface selectors, quantity/stock steppers and the action button.
-- Moved verbatim from PublicOrderDialog.lua (P1 split); behaviour unchanged.
-- Attached to EmberRoutesPublicOrderDialog by PublicOrderDialog.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the dialog module).

require 'ISUI/ISButton'
local SearchInput = require 'EmberRoutesProbe/UI/SearchInput'
local Dropdown = require 'EmberRoutesProbe/UI/Dropdown'
local StepperInput = require 'EmberRoutesProbe/UI/StepperInput'
local Layout = require 'EmberRoutesProbe/UI/Layout'
local Theme = require 'EmberRoutesProbe/UI/Theme'
local Text = require 'EmberRoutesProbe/UI/Text'
local Tooltip = require 'EmberRoutesProbe/UI/TooltipManager'
local Cached = require 'EmberRoutesProbe/UI/CachedList'

local function text(key,...) return getText('IGUI_EmberRoutesProbe_Public_'..key,...) end
local function craftText(key,...) return getText('IGUI_EmberRoutesProbe_Crafting_'..key,...) end

local function attach(Page)
function Page:createChildren()
    ISCollapsableWindow.createChildren(self)
    local h,p=self.fontHeight,self.pad

    -- Top-level 2-column layout (Left: Controls ~42%, Right: Blueprint & Chain ~58%)
    local mainCols=assert(Layout.axis({x=0,y=self:titleBarHeight(),width=self.width,height=self.height-self:titleBarHeight()},
        {{basis=math.floor(self.width*0.42)},{grow=1}},
        {direction='row',padding=p,gap=p}))

    local leftCol=mainCols[1]
    local rightCol=mainCols[2]

    -- ==================== LEFT COLUMN: CONTROLS ====================
    local leftParts=assert(Layout.axis(leftCol,
        {{basis=h+p/2},{basis=h*3+p*1.5},{basis=h*2+p/2},{basis=h*4+p*1.5},{basis=h*2+p/2},{grow=1},{basis=h+p/2}},
        {direction='column',gap=p/4}))

    self.tabRegion=leftParts[1]
    self.recipeRegion=leftParts[2]
    self.surfaceRegion=leftParts[3]
    self.formRegion=leftParts[4]
    self.calcDashboardRegion=leftParts[5]
    self.leftSpacer=leftParts[6]
    self.actionRegion=leftParts[7]

    -- 1. Mode Tabs
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

    -- 2. Recipe Search, Selection & Pager
    local recipeRows=assert(Layout.axis(self.recipeRegion,
        {{basis=h+math.floor(p/4)},{basis=h+math.floor(p/4)},{basis=h+math.floor(p/4)}},
        {direction='column',gap=p/4}))

    local r1=assert(Layout.axis(recipeRows[1],{{basis=h*5},{grow=1}},{gap=p/4}))
    self.searchLabel=r1[1]
    local defaultSearch=self.context.recipeName or (self.context.productType and getItemNameFromFullType(self.context.productType)) or ''
    self.search=SearchInput:new(r1[2].x,r1[2].y,r1[2].width,r1[2].height,"",self,function()
        self.notice=nil
        self.page=1
        self:query()
    end)
    if defaultSearch~="" then self.search:setText(defaultSearch) end
    self:addChild(self.search)

    self.recipeCombo=Dropdown:new(recipeRows[2].x,recipeRows[2].y,recipeRows[2].width,recipeRows[2].height,self,function(target,selectedRecipeId)
        target.notice=nil
        target.selectedRecipe=selectedRecipeId or false
        target.preferences={}
        target:loadRule()
        target:describe()
    end)
    self.recipeCombo:initialise()
    self:addChild(self.recipeCombo)

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

    -- 3. Surface Selection (Row 1: Label, Row 2: Combo)
    local surfRows=assert(Layout.axis(self.surfaceRegion,{{basis=h},{basis=h+p/4}},{direction='column',gap=p/4}))
    self.surfaceLabel=surfRows[1]
    self.surfaceCombo=Dropdown:new(surfRows[2].x,surfRows[2].y,surfRows[2].width,surfRows[2].height,self,function(target,selectedSurfaceId)
        target.notice=nil
        target:describe()
    end)
    self.surfaceCombo:initialise()
    self:addChild(self.surfaceCombo)
    local surfOptions={{id=false,label=text('noSurface')}}
    for _,surface in ipairs(require('EmberRoutesProbe/Crafting/CraftSurfaces').list(self.entry)) do
        table.insert(surfOptions,{id=surface.id,label=text('surfaceAt',surface.x,surface.y,surface.z)})
    end
    self.surfaceCombo:setOptions(surfOptions,self.context.surfaceId or false)

    -- 4. Dynamic Parameter Form Controls
    -- A. Quantity (Single Order: Row 1 Label, Row 2 Stepper Bar)
    local qRows=assert(Layout.axis({x=self.formRegion.x,y=self.formRegion.y,width=self.formRegion.width,height=h*2.5+p/2},
        {{basis=h},{basis=h+p/4}},{direction='column',gap=p/4}))
    self.quantityLabel=qRows[1]

    local qBar=qRows[2]
    self.quantityStepper=StepperInput:new(qBar.x,qBar.y,qBar.width,qBar.height,self.restoredDraft and self.restoredDraft.quantity or 1,1,9999,{-5,-1,1,5},function()
        self.notice=nil
        self:describe()
    end)
    self:addChild(self.quantityStepper)
    self.quantity=self.quantityStepper.entry
    self.quantity.tooltip=craftText('quantityHint')
    Tooltip.register(self.quantity,{method='prerender',owner=self})

    -- B. Stock Thresholds (Maintain Stock)
    local stockRows=assert(Layout.axis({x=self.formRegion.x,y=self.formRegion.y,width=self.formRegion.width,height=self.formRegion.height},
        {{basis=h},{basis=h+p/4},{basis=h},{basis=h+p/4}},{direction='column',gap=p/4}))

    self.minimumLabel=stockRows[1]
    local minBar=stockRows[2]
    self.minimumStepper=StepperInput:new(minBar.x,minBar.y,minBar.width,minBar.height,0,0,9999,{-5,-1,1,5},function()
        self.notice=nil
        self:describe()
    end)
    self:addChild(self.minimumStepper)
    self.minimum=self.minimumStepper.entry

    self.batchLabel=stockRows[3]
    local batchBar=stockRows[4]
    self.batchStepper=StepperInput:new(batchBar.x,batchBar.y,batchBar.width,batchBar.height,10,1,9999,{-10,-5,5,10},function()
        self.notice=nil
        self:describe()
    end)
    self:addChild(self.batchStepper)
    self.batch=self.batchStepper.entry
    self.batch.tooltip=craftText('quantityHint')
    Tooltip.register(self.batch,{method='prerender',owner=self})

    -- 6. Main Action Button
    self.actionButton=ISButton:new(self.actionRegion.x,self.actionRegion.y,self.actionRegion.width,self.actionRegion.height,text('submit'),self,function()
        if self.submitting then return end
        if self.activeTab=='order' then
            self:submitOrder()
        else
            self:submitRule()
        end
    end)
    self.actionButton:initialise()
    Theme.button(self.actionButton,true)
    self:addChild(self.actionButton)

    -- ==================== RIGHT COLUMN: CRAFTING BLUEPRINT & CHAIN ====================
    local rightParts=assert(Layout.axis(rightCol,
        {{basis=h+p/2},{grow=1},{basis=h*2+p/2}},
        {direction='column',gap=p/3}))

    self.blueprintHeaderRegion=rightParts[1]
    self.blueprintListRegion=rightParts[2]
    self.blueprintStatusRegion=rightParts[3]

    local blueprintStyle=require('EmberRoutesProbe/UI/BlueprintRows').style(self)

    self.blueprintList=Cached.create(self,self.blueprintListRegion,function(target,row)
        if row and row.kind=='chain_step' and row.canSwitch and row.nextRecipeId then
            target:switchPrecursor(row.fullType,row.nextRecipeId)
        end
    end,blueprintStyle)
    Theme.list(self.blueprintList)
    self.blueprintList.emberEmptyLines=Text.wrap(text('chooseRecipe'),self.blueprintListRegion.width-p*2,UIFont.Small)
    self:addChild(self.blueprintList)

    self:selectTab('order')
end

function Page:selectTab(tab)
    self.activeTab=tab
    local isOrder=tab=='order'
    Theme.styleButton(self.orderTabBtn,isOrder,isOrder)
    Theme.styleButton(self.stockTabBtn,not isOrder,not isOrder)

    if self.quantityStepper then self.quantityStepper:setVisible(isOrder) end
    if self.minimumStepper then self.minimumStepper:setVisible(not isOrder) end
    if self.batchStepper then self.batchStepper:setVisible(not isOrder) end

    if not self.submitting then
        self.actionButton:setTitle(text(isOrder and 'submit' or 'saveRule'))
    end
    self:describe()
end
end

return attach
