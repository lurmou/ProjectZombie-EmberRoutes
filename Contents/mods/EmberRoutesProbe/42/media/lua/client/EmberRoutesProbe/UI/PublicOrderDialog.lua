require 'ISUI/ISCollapsableWindow'
require 'ISUI/ISButton'
require 'ISUI/ISTextEntryBox'
require 'ISUI/ISComboBox'
local Crafting=require 'EmberRoutesProbe/CraftingService'
local Public=require 'EmberRoutesProbe/PublicWork'
local Layout=require 'EmberRoutesProbe/UI/Layout'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Text=require 'EmberRoutesProbe/UI/Text'
local Tooltip=require 'EmberRoutesProbe/UI/TooltipAnchor'
local Cached=require 'EmberRoutesProbe/UI/CachedList'
local Presentation=require 'EmberRoutesProbe/UI/ItemPresentation'
local Recipe=require 'EmberRoutesProbe/ProductionRecipe'
local Catalog=require 'EmberRoutesProbe/CraftingCatalog'
local StepperInput=require 'EmberRoutesProbe/UI/StepperInput'

local function text(key,...) return getText('IGUI_EmberRoutesProbe_Public_'..key,...) end
local function craftText(key,...) return getText('IGUI_EmberRoutesProbe_Crafting_'..key,...) end

local function isEnglish()
    return getText('IGUI_EmberRoutesProbe_Public_targetQuantity') == 'Target Product Quantity'
end

local function submittingText()
    return getTextOrNull('IGUI_EmberRoutesProbe_Public_submitting') or 'IGUI_EmberRoutesProbe_Public_submitting'
end

---@class EmberRoutesPublicOrderDialog:ISCollapsableWindow
---@field owner EmberRoutesSettlementDashboard
---@field actor IsoPlayer
---@field entry table
---@field fontHeight number
---@field pad number
---@field activeTab string
---@field presentation table
---@field blueprintList EmberRoutesCachedList
---@field previewData table?
---@field cancelPreview function?
EmberRoutesPublicOrderDialog=ISCollapsableWindow:derive('EmberRoutesPublicOrderDialog')

function EmberRoutesPublicOrderDialog.open(owner,context)
    if owner.publicDialog and not owner.publicDialog.disposed then
        owner.publicDialog:bringToTop()
        return owner.publicDialog
    end
    local h,p=owner.fontHeight,owner.pad
    local w=math.min(getCore():getScreenWidth()*0.94,h*46)
    local height=math.min(getCore():getScreenHeight()*0.94,h*32)
    local o=ISCollapsableWindow.new(EmberRoutesPublicOrderDialog,(getCore():getScreenWidth()-w)/2,(getCore():getScreenHeight()-height)/2,w,height)
    o.owner,o.actor,o.entry=owner,owner.actor,owner.entry
    o.fontHeight,o.pad=h,p
    o.context=context or {}
    o.title=text('createOrder')
    o.requestId=Public.requestId()
    o.page=1
    o.rows={}
    o.selectedRecipe=false
    o.preferences={}
    o.activeTab='order' -- 'order' or 'stock'
    o.presentation=Presentation.new()
    o.resizable=false
    o.submitting=false
    o.backgroundColor=Theme.window
    o.borderColor=Theme.border
    o:setWantKeyEvents(true)
    o:initialise()
    o:addToUIManager()
    owner.publicDialog=o
    o:query()
    return o
end

function EmberRoutesPublicOrderDialog:initialise() ISCollapsableWindow.initialise(self) end

function EmberRoutesPublicOrderDialog:createChildren()
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
    self.search=ISTextEntryBox:new(defaultSearch,r1[2].x,r1[2].y,r1[2].width,r1[2].height)
    self.search:initialise()
    self.search.target=self
    self.search.onTextChangeFunction=function()
        self.notice=nil
        self.page=1
        self:query()
    end
    self:addChild(self.search)

    self.recipeCombo=ISComboBox:new(recipeRows[2].x,recipeRows[2].y,recipeRows[2].width,recipeRows[2].height,self,function()
        self.notice=nil
        local row=self.rows[self.recipeCombo.selected]
        self.selectedRecipe=row and row.id or false
        self.requestId=Public.requestId()
        self.preferences={}
        self:loadRule()
        self:describe()
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
    self.surfaceCombo=ISComboBox:new(surfRows[2].x,surfRows[2].y,surfRows[2].width,surfRows[2].height,self,function()
        self.notice=nil
        self.requestId=Public.requestId()
        self:describe()
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
    -- A. Quantity (Single Order: Row 1 Label, Row 2 Stepper Bar)
    local qRows=assert(Layout.axis({x=self.formRegion.x,y=self.formRegion.y,width=self.formRegion.width,height=h*2.5+p/2},
        {{basis=h},{basis=h+p/4}},{direction='column',gap=p/4}))
    self.quantityLabel=qRows[1]

    local qBar=qRows[2]
    self.quantityStepper=StepperInput:new(qBar.x,qBar.y,qBar.width,qBar.height,1,1,9999,{-5,-1,1,5},function()
        self.notice=nil
        self.requestId=Public.requestId()
        self:describe()
    end)
    self.quantity=self.quantityStepper.entry
    self.quantity.tooltip=craftText('quantityHint')
    Tooltip.attach(self.quantity,'prerender')
    self:addChild(self.quantityStepper)

    -- B. Stock Thresholds (Maintain Stock)
    local stockRows=assert(Layout.axis({x=self.formRegion.x,y=self.formRegion.y,width=self.formRegion.width,height=self.formRegion.height},
        {{basis=h},{basis=h+p/4},{basis=h},{basis=h+p/4}},{direction='column',gap=p/4}))

    self.minimumLabel=stockRows[1]
    local minBar=stockRows[2]
    self.minimumStepper=StepperInput:new(minBar.x,minBar.y,minBar.width,minBar.height,0,0,9999,{-5,-1,1,5},function()
        self.notice=nil
        self:describe()
    end)
    self.minimum=self.minimumStepper.entry
    self:addChild(self.minimumStepper)

    self.batchLabel=stockRows[3]
    local batchBar=stockRows[4]
    self.batchStepper=StepperInput:new(batchBar.x,batchBar.y,batchBar.width,batchBar.height,10,1,9999,{-10,-5,5,10},function()
        self.notice=nil
        self:describe()
    end)
    self.batch=self.batchStepper.entry
    self.batch.tooltip=craftText('quantityHint')
    Tooltip.attach(self.batch,'prerender')
    self:addChild(self.batchStepper)

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

function EmberRoutesPublicOrderDialog:selectTab(tab)
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

function EmberRoutesPublicOrderDialog:query()
    if self.releaseCatalog then self.releaseCatalog() self.releaseCatalog=nil end
    if self.disposed then return end

    -- Fast-path for direct recipe injection (from vanilla crafting menu or direct context)
    if self.context.recipeId then
        local targetId=self.context.recipeId
        local cooking=require('EmberRoutesProbe/CookingOrders').describe(targetId)
        local spec=cooking or Recipe.read(targetId)
        if spec then
            local desc=cooking or Recipe.describe(spec)
            self.rows={desc}
            self.recipeCombo:clear()
            self.recipeCombo:addOption(desc.name or spec.name)
            self.recipeCombo.selected=1
            self.selectedRecipe=targetId
            self.context.recipeId=nil
            self.page=1
            self.totalPages=1
            if self.previous then self.previous:setVisible(false) end
            if self.next then self.next:setVisible(false) end
            self:loadRule()
            self:describe()
            return
        end
    end

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
            if row.id==(self.context.recipeId or self.selectedRecipe) then
                selected=i
            elseif self.context.productType and row.product==self.context.productType and selected==1 then
                selected=i
            end
        end
        self.recipeCombo.selected=selected
        local chosen=self.rows[selected] and self.rows[selected].id or false
        if chosen~=self.selectedRecipe then
            self.requestId=Public.requestId()
            self.preferences={}
        end
        self.selectedRecipe=chosen
        self.context.recipeId=nil
        self:loadRule()
        self.page=snapshot.page or 1
        self.totalPages=snapshot.pages or 1
        local hasMultiplePages = self.totalPages > 1
        if self.previous then
            self.previous:setVisible(hasMultiplePages)
            Theme.enable(self.previous,self.page>1)
        end
        if self.next then
            self.next:setVisible(hasMultiplePages)
            Theme.enable(self.next,self.page<self.totalPages)
        end
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
    local minVal=rule and rule.minimum or 0
    local batchVal=rule and rule.batch or 10
    if self.minimumStepper then self.minimumStepper:setValue(minVal) else self.minimum:setText(tostring(minVal)) end
    if self.batchStepper then self.batchStepper:setValue(batchVal) else self.batch:setText(tostring(batchVal)) end
end

function EmberRoutesPublicOrderDialog:updateConversion()
    local row=self.rows and self.rows[self.recipeCombo.selected]
    if not row or not row.id then
        self.conversion=nil
        self.conversionFull=nil
        self.conversionLine1=nil
        self.conversionLine2=nil
        return
    end

    local spec=self.currentSpec or (row.id and Recipe.read(row.id) and Recipe.describe(Recipe.read(row.id))) or row
    local resultCount=(row and (row.resultCount or row.yield)) or (spec and (spec.resultCount or spec.yield)) or 1
    if not resultCount or resultCount<1 then resultCount=1 end
    self.resultCount=resultCount

    local targetQty
    if self.activeTab=='order' then
        targetQty=tonumber(self.quantity:getText()) or 1
    else
        targetQty=tonumber(self.batch:getText()) or 10
    end
    targetQty=math.max(1,math.floor(targetQty))
    self.targetQty=targetQty

    local executions=math.max(1,math.ceil(targetQty/resultCount))
    local expectedOutput=executions*resultCount
    local surplus=math.max(0,expectedOutput-targetQty)

    self.conversion={
        resultCount=resultCount,
        targetQty=targetQty,
        executions=executions,
        expectedOutput=expectedOutput,
        surplus=surplus
    }

    local isEN=isEnglish()
    local targetLabel
    if isEN then
        targetLabel=(self.activeTab=='order') and 'Target Need' or 'Batch Size'
        self.conversionFull=string.format('Per Batch Output: %d | %s: %d => Craft Runs: %d | Expected: %d (%d surplus)',
            resultCount,targetLabel,targetQty,executions,expectedOutput,surplus)
        self.conversionLine1=string.format('Per Batch Output: %d  |  %s: %d',resultCount,targetLabel,targetQty)
        self.conversionLine2=string.format('=> Craft Runs: %d  |  Expected: %d (%d surplus)',executions,expectedOutput,surplus)
    else
        local labelKey=(self.activeTab=='order') and 'IGUI_EmberRoutesProbe_Public_targetDemand' or 'IGUI_EmberRoutesProbe_Public_restockBatch'
        targetLabel=getTextOrNull(labelKey) or labelKey
        self.conversionFull=string.format(getTextOrNull('IGUI_EmberRoutesProbe_Public_conversionFull') or 'IGUI_EmberRoutesProbe_Public_conversionFull',
            resultCount,targetLabel,targetQty,executions,expectedOutput,surplus)
        self.conversionLine1=string.format(getTextOrNull('IGUI_EmberRoutesProbe_Public_conversionLine1') or 'IGUI_EmberRoutesProbe_Public_conversionLine1',
            resultCount,targetLabel,targetQty)
        self.conversionLine2=string.format(getTextOrNull('IGUI_EmberRoutesProbe_Public_conversionLine2') or 'IGUI_EmberRoutesProbe_Public_conversionLine2',
            executions,expectedOutput,surplus)
    end
end

function EmberRoutesPublicOrderDialog:describe()
    self:updateConversion()
    if self.submitting then
        Theme.enable(self.actionButton,false)
        self:requestPreview()
        return
    end

    local row=self.rows[self.recipeCombo.selected]
    local n=tonumber(self.quantity:getText())
    if self.activeTab=='order' then
        local valid=row~=nil and n~=nil and n>=1 and n<=9999 and n==math.floor(n)
        Theme.enable(self.actionButton,valid,true)
    else
        local minVal=tonumber(self.minimum:getText())
        local batchVal=tonumber(self.batch:getText())
        local validStock=minVal and minVal>=0 and minVal<=9999 and minVal==math.floor(minVal)
            and batchVal and batchVal>=1 and batchVal<=9999 and batchVal==math.floor(batchVal)
        Theme.enable(self.actionButton,row~=nil and validStock,true)
    end
    self:requestPreview()
end

function EmberRoutesPublicOrderDialog:switchPrecursor(product,nextRecipeId)
    self.preferences=self.preferences or {}
    self.preferences[product]=nextRecipeId
    self.requestId=Public.requestId()
    self:requestPreview()
end

function EmberRoutesPublicOrderDialog:requestPreview()
    if self.cancelPreview then self.cancelPreview() self.cancelPreview=nil end
    local row=self.rows[self.recipeCombo.selected]
    if not row or not row.id then
        self.previewData=nil
        self:updateBlueprint()
        return
    end

    local qty=tonumber(self.quantity:getText()) or 1
    if self.activeTab=='stock' then
        qty=tonumber(self.batch:getText()) or 10
    end
    local surfaceId=self.surfaces[self.surfaceCombo.selected]

    self.previewData=nil
    local spec=Recipe.read(row.id)
    self.currentSpec=row.cooking and Catalog.describe(row.id) or spec and Recipe.describe(spec) or row
    self:updateBlueprint()

    self.cancelPreview=require('EmberRoutesProbe/PublicPreview').watch(self.actor,self.entry.id,row.id,qty,surfaceId,function(result)
        if self.disposed then return end
        self.previewData=result
        if result.cooking and result.recipe then self.currentSpec=result.recipe end
        self:updateBlueprint()
    end,self.preferences)
end

function EmberRoutesPublicOrderDialog:updateBlueprint()
    self:updateConversion()
    local row=self.rows[self.recipeCombo.selected]
    if not row or not row.id then
        Cached.reconcile(self.blueprintList,{},function() return '' end,function() return '' end,true)
        self.statusNotice=text('chooseRecipe')
        return
    end

    local spec=self.currentSpec or (Recipe.read(row.id) and Recipe.describe(Recipe.read(row.id))) or row
    local preview=self.previewData
    local targetQty=tonumber(self.quantity:getText()) or 1
    if self.activeTab=='stock' then
        targetQty=tonumber(self.batch:getText()) or 10
    end

    local yield=(row and (row.resultCount or row.yield)) or (spec and (spec.resultCount or spec.yield)) or 1
    if not yield or yield<1 then yield=1 end
    local units=math.max(1,math.ceil(targetQty/yield))
    local totalExpected=units*yield

    local rows={}
    local function add(r) rows[#rows+1]=r end

    -- 1. Hero Output Card
    local prodType=row.product or (spec and spec.product)
    local prodName=(spec and spec.outputs and type(spec.outputs[1])=='table' and spec.outputs[1].name)
        or (row and row.outputs and row.outputs[1] and row.outputs[1].name)
        or (getItemNameFromFullType and prodType and getItemNameFromFullType(prodType))
        or (prodType and tostring(prodType):match("[^.]+$"))
        or row.name or (spec and spec.name) or 'Product'
    local recipeTitle=row.name or (spec and spec.name)
    local subStr=text('batchCount',yield,units)
    if recipeTitle and recipeTitle~=prodName then
        subStr=subStr..' · '..recipeTitle
    end
    add({
        kind='output',
        fullType=prodType,
        title=prodName..' x'..totalExpected,
        sub=subStr,
        heading=text('outputHeading'),
        label='output:'..tostring(row.id)..':'..tostring(prodType)..':'..totalExpected
    })

    -- 2. Inputs & Tools Breakdown
    local hasInputs=spec and spec.inputs and #spec.inputs>0
    if hasInputs then
        -- Materials (keep == false)
        local matHeaded=false
        for _,input in ipairs(spec.inputs) do
            if not input.keep then
                if not matHeaded then
                    add({kind='heading',section='materials',label=text('materialsHeading')})
                    matHeaded=true
                end
                local need=input.count*units
                local count=preview and preview.counts and preview.counts[input.slot]
                local avail=count and count.available or 0
                local isMissing=(count and count.available<need) or (count==nil)
                local precursor=isMissing and preview and preview.chain and #preview.chain.nodes>1
                local choices=input.choices or {}
                local first=choices[1]
                if count and count.fullType then
                    for _,choice in ipairs(choices) do
                        if choice.fullType==count.fullType then first=choice break end
                    end
                end
                local itemName=first and first.name or (input.names and input.names[1]) or 'Material'
                local subStr=tostring(avail)..' / '..need
                if precursor then subStr=subStr..'  '..text('chainSupplyTag') end
                add({
                    kind='input',
                    slot=input.slot,
                    fullType=first and first.fullType,
                    title=itemName,
                    sub=subStr,
                    known=count~=nil,
                    missing=isMissing and not precursor,
                    precursor=precursor,
                    isTool=false,
                    choices=choices,
                    label='input:'..tostring(row.id)..':'..tostring(input.slot)..':'..tostring(first and first.fullType)..':'..need..':'..tostring(avail)
                })
            end
        end

        -- Tools (keep == true)
        local toolHeaded=false
        for _,input in ipairs(spec.inputs) do
            if input.keep then
                if not toolHeaded then
                    add({kind='heading',section='tools',label=text('toolsHeading')})
                    toolHeaded=true
                end
                local choices=input.choices or {}
                local count=preview and preview.counts and preview.counts[input.slot]
                local hasTool=count and count.available>=1
                local first=choices[1]
                if count and count.fullType then
                    for _,choice in ipairs(choices) do
                        if choice.fullType==count.fullType then first=choice break end
                    end
                end
                local toolName=first and first.name or (input.names and input.names[1]) or 'Tool'
                local subStr=hasTool and craftText('readyBadge') or craftText('shortageBadge')
                if #choices>1 then
                    local altNames={}
                    for _,c in ipairs(choices) do
                        if c.name~=toolName and not altNames[c.name] then
                            altNames[#altNames+1]=c.name
                            altNames[c.name]=true
                        end
                    end
                    if #altNames>0 then
                        subStr=subStr..' · '..text('toolAlternatives',table.concat(altNames,' / '))
                    end
                end
                add({
                    kind='input',
                    slot=input.slot,
                    fullType=first and first.fullType,
                    title=toolName,
                    sub=subStr,
                    known=count~=nil,
                    missing=not hasTool,
                    precursor=false,
                    isTool=true,
                    choices=choices,
                    label='tool:'..tostring(row.id)..':'..tostring(input.slot)..':'..tostring(first and first.fullType)..':'..tostring(hasTool)..':'..tostring(#choices)
                })
            end
        end
    end

    -- 3. Multi-Step Production Chain Steps
    if preview and preview.chain and #preview.chain.nodes>1 then
        add({kind='heading',label=craftText('chainPlanHeading',#preview.chain.nodes)})
        local byId,byType=Catalog.productionIndex()
        for i,node in ipairs(preview.chain.nodes) do
            local isLast=(i==#preview.chain.nodes)
            local stepBadge=craftText(isLast and 'stepFinal' or 'stepPrecursor',i)
            local surfaceBadge=node.surface and craftText('badgeSurface') or craftText('badgeHand')
            local canSwitch=false
            local nextRecipeId,nextRecipeName
            if not isLast and byType and node.product then
                local producers=byType[node.product] or {}
                if #producers>1 then
                    for idx,cand in ipairs(producers) do
                        if cand.id==node.recipeId then
                            local nextIdx=(idx%#producers)+1
                            nextRecipeId=producers[nextIdx].id
                            nextRecipeName=producers[nextIdx].name
                            canSwitch=true
                            break
                        end
                    end
                    if not canSwitch and #producers>0 then
                        nextRecipeId=producers[1].id
                        nextRecipeName=producers[1].name
                        canSwitch=true
                    end
                end
            end
            local switchText=canSwitch and text('switchRecipe',nextRecipeName) or nil
            add({
                kind='chain_step',
                fullType=node.product,
                stepIndex=i,
                isLast=isLast,
                stepBadge=stepBadge,
                surfaceBadge=surfaceBadge,
                title=node.recipeName,
                sub=craftText('planOutput',tostring(node.totalOutput or node.requested)),
                canSwitch=canSwitch,
                nextRecipeId=nextRecipeId,
                nextRecipeName=nextRecipeName,
                switchText=switchText,
                label='chain_step:'..i..':'..tostring(node.recipeId or node.product)..':'..tostring(nextRecipeId or '')
            })
        end
    else
        -- Single-step summary chain card
        local isSurface=row.surface or (spec and spec.surface)
        local surfaceBadge=isSurface and craftText('badgeSurface') or craftText('badgeHand')
        add({
            kind='chain_step',
            fullType=row.product or (spec and spec.product),
            stepIndex=1,
            isLast=true,
            stepBadge=craftText('stepFinal',1),
            surfaceBadge=surfaceBadge,
            title=row.name or (spec and spec.name),
            sub=craftText('planOutput',tostring(totalExpected)),
            label='single_step:1:'..tostring(row.id)..':'..totalExpected
        })
    end

    Cached.reconcile(self.blueprintList,rows,function(r) return r.label end,function(r) return r.label end,true)

    -- Update Status Bar Message
    if preview then
        if preview.chain and #preview.chain.nodes>1 then
            self.statusNotice=text('statusChain')
            self.statusColor=Theme.accent
        elseif preview.state=='WAITING' then
            self.statusNotice=getText('IGUI_EmberRoutesProbe_Public_WAITING_CLAIM') self.statusColor=Theme.muted
        elseif preview.state=='READY' then
            self.statusNotice=text('statusReady')
            self.statusColor={r=0.35,g=0.88,b=0.60,a=1.0}
        elseif preview.conditions and #preview.conditions>0 then
            self.statusNotice=text('statusShortage')
            self.statusColor={r=0.95,g=0.45,b=0.35,a=1.0}
        else
            self.statusNotice=text('statusReady')
            self.statusColor={r=0.35,g=0.88,b=0.60,a=1.0}
        end

        if preview.eligibleWorkerCount~=nil then
            local workerMsg = (preview.eligibleWorkerCount>0)
                and getText('IGUI_EmberRoutesProbe_Public_workersReady',preview.eligibleWorkerCount)
                or getText('IGUI_EmberRoutesProbe_Public_noWorkersReady')
            self.statusNotice = self.statusNotice .. ' · ' .. workerMsg
        end
    else
        self.statusNotice=text('statusChecking')
        self.statusColor=Theme.muted
    end
end

function EmberRoutesPublicOrderDialog:submitOrder()
    if self.disposed or self.submitting or not self.owner:valid() then
        if not self.owner:valid() then self:close() end
        return
    end
    if not self.actionButton or self.actionButton.enable == false then return end
    if not self.selectedRecipe then return end

    local qty=tonumber(self.quantity:getText())
    if not qty or qty<1 or qty>9999 or qty~=math.floor(qty) then return end

    self.submitting=true
    local oldTitle=text('submit')
    self.actionButton:setTitle(submittingText())
    Theme.enable(self.actionButton,false)

    local ok,result=pcall(function()
        return Public.create(self.actor,self.entry.id,self.selectedRecipe,math.floor(qty),
            self.surfaces[self.surfaceCombo.selected],self.requestId,self.preferences)
    end)

    if not ok then
        self.submitting=false
        self.notice=tostring(result)
        self.actionButton:setTitle(oldTitle)
        self:describe()
        return
    end

    self.notice=require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)
    if result=='ORDER_CREATED' then
        self.submitting=false
        self.owner:selectTab('orders')
        self:close()
    else
        self.submitting=false
        self.actionButton:setTitle(oldTitle)
        self:describe()
    end
end

function EmberRoutesPublicOrderDialog:submitRule()
    if self.disposed or self.submitting or not self.owner:valid() then
        if not self.owner:valid() then self:close() end
        return
    end
    if not self.actionButton or self.actionButton.enable == false then return end
    if not self.selectedRecipe then return end

    local minVal=tonumber(self.minimum:getText())
    local batchVal=tonumber(self.batch:getText())
    if not minVal or minVal<0 or minVal>9999 or minVal~=math.floor(minVal) then return end
    if not batchVal or batchVal<1 or batchVal>9999 or batchVal~=math.floor(batchVal) then return end

    self.submitting=true
    local oldTitle=text('saveRule')
    self.actionButton:setTitle(submittingText())
    Theme.enable(self.actionButton,false)

    local ok,result=pcall(function()
        return Public.saveRule(self.actor,self.entry.id,self.selectedRecipe,math.floor(minVal),
            math.floor(batchVal),self.surfaces[self.surfaceCombo.selected],self.preferences)
    end)

    if not ok then
        self.submitting=false
        self.notice=tostring(result)
        self.actionButton:setTitle(oldTitle)
        self:describe()
        return
    end

    self.submitting=false
    self.notice=require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)
    self.actionButton:setTitle(oldTitle)
    self:describe()
end
EmberRoutesPublicOrderDialog.saveRule=EmberRoutesPublicOrderDialog.submitRule

function EmberRoutesPublicOrderDialog:prerender()
    ISCollapsableWindow.prerender(self)
    local h=self.fontHeight

    -- Left Column Labels
    Theme.text(self,text('recipeSelect'),self.searchLabel.x,self.searchLabel.y+(self.searchLabel.height-h)/2,Theme.textColor)
    Theme.text(self,text('surfaceSelect'),self.surfaceLabel.x,self.surfaceLabel.y+(self.surfaceLabel.height-h)/2,Theme.textColor)

    local pageStr=(self.page or 1)..' / '..(self.totalPages or 1)
    if self._pageKey~=pageStr then self._pageKey=pageStr
        self._pageW=getTextManager():MeasureStringX(UIFont.Small,pageStr) end
    local pageW=self._pageW
    Theme.text(self,pageStr,self.pageIndicatorRegion.x+(self.pageIndicatorRegion.width-pageW)/2,self.pageIndicatorRegion.y+(self.pageIndicatorRegion.height-h)/2,Theme.muted)

    if self.activeTab=='order' then
        Theme.text(self,text('targetQuantity'),self.quantityLabel.x,self.quantityLabel.y+(self.quantityLabel.height-h)/2,Theme.textColor)
    else
        Theme.text(self,text('stockThreshold'),self.minimumLabel.x,self.minimumLabel.y+(self.minimumLabel.height-h)/2,Theme.textColor)
        Theme.text(self,text('stockBatch'),self.batchLabel.x,self.batchLabel.y+(self.batchLabel.height-h)/2,Theme.textColor)
    end

    -- Conversion Dashboard Card
    if self.calcDashboardRegion then
        local cr=self.calcDashboardRegion
        Theme.rect(self,cr.x,cr.y,cr.width,cr.height,Theme.panel)
        Theme.rect(self,cr.x,cr.y,cr.width,cr.height,Theme.border,true)

        local row=self.rows and self.rows[self.recipeCombo.selected]
        if not row or not self.conversion then
            local emptyText=text('chooseRecipe')
            if self._mKey~=emptyText then self._mKey=emptyText
                self._mW=getTextManager():MeasureStringX(UIFont.Small,emptyText) end
            local tw=self._mW
            Theme.text(self,emptyText,cr.x+math.max(self.pad,math.floor((cr.width-tw)/2)),cr.y+math.floor((cr.height-h)/2),Theme.muted)
        else
            local conv=self.conversionFull or ''
            if self._cKey~=conv then self._cKey=conv
                self._cW=getTextManager():MeasureStringX(UIFont.Small,conv) end
            local tw=self._cW
            if tw<=cr.width-self.pad*2 then
                Theme.text(self,self.conversionFull,cr.x+math.max(self.pad,math.floor((cr.width-tw)/2)),cr.y+math.floor((cr.height-h)/2),Theme.gold)
            else
                local l1=self.conversionLine1 or '' local l2=self.conversionLine2 or ''
                if self._l1Key~=l1 then self._l1Key=l1
                    self._l1W=getTextManager():MeasureStringX(UIFont.Small,l1) end
                if self._l2Key~=l2 then self._l2Key=l2
                    self._l2W=getTextManager():MeasureStringX(UIFont.Small,l2) end
                local l1w=self._l1W local l2w=self._l2W
                local startY=cr.y+math.max(2,math.floor((cr.height-h*2-2)/2))
                Theme.text(self,self.conversionLine1 or '',cr.x+math.max(self.pad,math.floor((cr.width-l1w)/2)),startY,Theme.textColor)
                Theme.text(self,self.conversionLine2 or '',cr.x+math.max(self.pad,math.floor((cr.width-l2w)/2)),startY+h+2,Theme.gold)
            end
        end
    end

    -- Right Column Header
    Theme.text(self,text('blueprintTitle'),self.blueprintHeaderRegion.x,self.blueprintHeaderRegion.y+(self.blueprintHeaderRegion.height-h)/2,Theme.gold)

    -- Right Column Status Card
    local sr=self.blueprintStatusRegion
    Theme.rect(self,sr.x,sr.y,sr.width,sr.height,Theme.panel)
    Theme.rect(self,sr.x,sr.y,sr.width,sr.height,Theme.border,true)

    local msg=self.notice or self.statusNotice or text('statusChecking')
    local lines=Text.wrapLimited(msg,sr.width-self.pad*2,UIFont.Small,2)
    local curY=sr.y+math.max(2,math.floor((sr.height-#lines*h)/2))
    for _,line in ipairs(lines) do
        Theme.text(self,line,sr.x+self.pad,curY,self.notice and Theme.gold or (self.statusColor or Theme.textColor))
        curY=curY+h
    end
end

function EmberRoutesPublicOrderDialog:isKeyConsumed(key)
    if self.disposed then return false end
    return key==Keyboard.KEY_ESCAPE or key==Keyboard.KEY_RETURN
end

function EmberRoutesPublicOrderDialog:onKeyPress(key)
    if self.disposed then return end
    if key==Keyboard.KEY_ESCAPE then
        self:close()
    elseif key==Keyboard.KEY_RETURN then
        if not self.submitting and self.actionButton and self.actionButton.enable ~= false then
            if self.search and self.search:isFocused() then
                self.search:unfocus()
                return
            end
            if self.activeTab=='order' then
                self:submitOrder()
            else
                self:submitRule()
            end
        end
    end
end

function EmberRoutesPublicOrderDialog:close()
    if self.disposed then return end
    self.disposed=true
    self.submitting=false
    self.catalogToken=nil
    if self.releaseCatalog then self.releaseCatalog() self.releaseCatalog=nil end
    if self.cancelPreview then self.cancelPreview() self.cancelPreview=nil end
    if self.presentation then self.presentation:clear() end
    self.recipeCombo:hidePopup()
    self.surfaceCombo:hidePopup()
    Tooltip.clear(self.recipeCombo)
    Tooltip.clear(self.surfaceCombo)
    Tooltip.clear(self.quantity)
    Tooltip.clear(self.batch)
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if self.owner.publicDialog==self then self.owner.publicDialog=nil end
end

return EmberRoutesPublicOrderDialog
