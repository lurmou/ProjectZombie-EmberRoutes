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
local Cached=require 'EmberRoutesProbe/UI/CachedList'
local Presentation=require 'EmberRoutesProbe/UI/ItemPresentation'
local Recipe=require 'EmberRoutesProbe/ProductionRecipe'
local Catalog=require 'EmberRoutesProbe/CraftingCatalog'

local function text(key,...) return getText('IGUI_EmberRoutesProbe_Public_'..key,...) end
local function craftText(key,...) return getText('IGUI_EmberRoutesProbe_Crafting_'..key,...) end

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
    o.requestId=Registry.id()
    o.page=1
    o.rows={}
    o.selectedRecipe=false
    o.activeTab='order' -- 'order' or 'stock'
    o.presentation=Presentation.new()
    o.resizable=false
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
        {{basis=h+p/2},{basis=h*4.5+p},{basis=h*2.5+p},{basis=h*6.5+p},{grow=1},{basis=h+p}},
        {direction='column',gap=p/3}))

    self.tabRegion=leftParts[1]
    self.recipeRegion=leftParts[2]
    self.surfaceRegion=leftParts[3]
    self.formRegion=leftParts[4]
    self.leftSpacer=leftParts[5]
    self.actionRegion=leftParts[6]

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
        self.page=1
        self:query()
    end
    self:addChild(self.search)

    self.recipeCombo=ISComboBox:new(recipeRows[2].x,recipeRows[2].y,recipeRows[2].width,recipeRows[2].height,self,function()
        local row=self.rows[self.recipeCombo.selected]
        self.selectedRecipe=row and row.id or false
        self.requestId=Registry.id()
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
        self.requestId=Registry.id()
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

    local btnW=math.floor(h*2.2)

    -- A. Quantity (Single Order: Row 1 Label, Row 2 Stepper Bar)
    local qRows=assert(Layout.axis({x=self.formRegion.x,y=self.formRegion.y,width=self.formRegion.width,height=h*2.5+p/2},
        {{basis=h},{basis=h+p/4}},{direction='column',gap=p/4}))
    self.quantityLabel=qRows[1]

    local qBar=assert(Layout.axis(qRows[2],
        {{basis=btnW},{basis=btnW},{grow=1},{basis=btnW},{basis=btnW}},{gap=p/4}))
    self.qStepDec5=makeStepper('-5',qBar[1],-5,nil,1)
    self.qStepDec1=makeStepper('-1',qBar[2],-1,nil,1)

    self.quantity=ISTextEntryBox:new('1',qBar[3].x,qBar[3].y,qBar[3].width,qBar[3].height)
    self.quantity:initialise()
    self.quantity.target=self
    self.quantity.onTextChangeFunction=function()
        self.requestId=Registry.id()
        self:describe()
    end
    self:addChild(self.quantity)
    self.qStepDec5.onclick=function() local cur=tonumber(self.quantity:getText()) or 0 self.quantity:setText(tostring(math.max(1,cur-5))) self.requestId=Registry.id() self:describe() end
    self.qStepDec1.onclick=function() local cur=tonumber(self.quantity:getText()) or 0 self.quantity:setText(tostring(math.max(1,cur-1))) self.requestId=Registry.id() self:describe() end

    self.qStepInc1=makeStepper('+1',qBar[4],1,self.quantity,1)
    self.qStepInc5=makeStepper('+5',qBar[5],5,self.quantity,1)

    -- B. Stock Thresholds (Maintain Stock)
    local stockRows=assert(Layout.axis({x=self.formRegion.x,y=self.formRegion.y,width=self.formRegion.width,height=self.formRegion.height},
        {{basis=h},{basis=h+p/4},{basis=h},{basis=h+p/4}},{direction='column',gap=p/4}))

    self.minimumLabel=stockRows[1]
    local minBar=assert(Layout.axis(stockRows[2],
        {{basis=btnW},{basis=btnW},{grow=1},{basis=btnW},{basis=btnW}},{gap=p/4}))
    self.minStepDec5=makeStepper('-5',minBar[1],-5,nil,0)
    self.minStepDec1=makeStepper('-1',minBar[2],-1,nil,0)
    self.minimum=ISTextEntryBox:new('0',minBar[3].x,minBar[3].y,minBar[3].width,minBar[3].height)
    self.minimum:initialise()
    self.minimum.target=self
    self.minimum.onTextChangeFunction=function() self:describe() end
    self:addChild(self.minimum)
    self.minStepDec5.onclick=function() local cur=tonumber(self.minimum:getText()) or 0 self.minimum:setText(tostring(math.max(0,cur-5))) self:describe() end
    self.minStepDec1.onclick=function() local cur=tonumber(self.minimum:getText()) or 0 self.minimum:setText(tostring(math.max(0,cur-1))) self:describe() end
    self.minStepInc1=makeStepper('+1',minBar[4],1,self.minimum,0)
    self.minStepInc5=makeStepper('+5',minBar[5],5,self.minimum,0)

    self.batchLabel=stockRows[3]
    local batchBar=assert(Layout.axis(stockRows[4],
        {{basis=btnW},{basis=btnW},{grow=1},{basis=btnW},{basis=btnW}},{gap=p/4}))
    self.bStepDec10=makeStepper('-10',batchBar[1],-10,nil,1)
    self.bStepDec5=makeStepper('-5',batchBar[2],-5,nil,1)
    self.batch=ISTextEntryBox:new('10',batchBar[3].x,batchBar[3].y,batchBar[3].width,batchBar[3].height)
    self.batch:initialise()
    self.batch.target=self
    self.batch.onTextChangeFunction=function() self:describe() end
    self:addChild(self.batch)
    self.bStepDec10.onclick=function() local cur=tonumber(self.batch:getText()) or 0 self.batch:setText(tostring(math.max(1,cur-10))) self:describe() end
    self.bStepDec5.onclick=function() local cur=tonumber(self.batch:getText()) or 0 self.batch:setText(tostring(math.max(1,cur-5))) self:describe() end
    self.bStepInc5=makeStepper('+5',batchBar[4],5,self.batch,1)
    self.bStepInc10=makeStepper('+10',batchBar[5],10,self.batch,1)

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

    -- ==================== RIGHT COLUMN: CRAFTING BLUEPRINT & CHAIN ====================
    local rightParts=assert(Layout.axis(rightCol,
        {{basis=h+p/2},{grow=1},{basis=h*2+p/2}},
        {direction='column',gap=p/3}))

    self.blueprintHeaderRegion=rightParts[1]
    self.blueprintListRegion=rightParts[2]
    self.blueprintStatusRegion=rightParts[3]

    local blueprintStyle={emptyColor=Theme.muted}

    function blueprintStyle.prepare(list,row)
        local icon=row.fullType and self.presentation:icon(row.fullType) or nil
        if row.kind=='heading' then
            return {height=math.floor(h*1.5),icon=nil}
        elseif row.kind=='output' then
            local slotSize=math.floor(h*2.2)
            local textW=math.max(1,list.width-slotSize-p*3)
            local titleLines=Text.wrapLimited(row.title or row.label,textW,UIFont.Small,1)
            local subLines=row.sub and Text.wrapLimited(row.sub,textW,UIFont.Small,1) or {}
            local headerH=math.floor(h*1.2)
            return {
                height=slotSize+p+headerH,
                icon=icon,
                slotSize=slotSize,
                title=titleLines[1] or '',
                sub=subLines[1] or '',
                headerH=headerH,
                sectionTitle=row.heading or text('outputHeading')
            }
        elseif row.kind=='input' then
            local slotSize=math.floor(h*2.0)
            local textW=math.max(1,list.width-slotSize-p*3)
            local titleLines=Text.wrapLimited(row.title or row.label,textW,UIFont.Small,1)
            local subLines=row.sub and Text.wrapLimited(row.sub,textW,UIFont.Small,1) or {}
            return {
                height=slotSize+p,
                icon=icon,
                slotSize=slotSize,
                title=titleLines[1] or '',
                sub=subLines[1] or ''
            }
        elseif row.kind=='chain_step' then
            local slotSize=math.floor(h*1.8)
            local cardH=slotSize+math.floor(p*0.6)
            local connectorH=row.isLast and 0 or math.floor(h*0.9)
            local gap=math.floor(p/2)
            local textX=p+4+slotSize+gap
            local right=list.width-p-4
            local hasSurface=row.surfaceBadge and row.surfaceBadge~=''
            local available=math.max(0,right-textX-gap*(hasSurface and 2 or 1))
            local manager=getTextManager()
            local badgeLimit=math.floor(available/3)
            local stepW=math.min(manager:MeasureStringX(UIFont.Small,row.stepBadge or '')+p,badgeLimit)
            local surfaceW=hasSurface and math.min(manager:MeasureStringX(UIFont.Small,row.surfaceBadge)+p,badgeLimit) or 0
            local surfaceX=right-surfaceW
            local nameX=textX+stepW+gap
            local nameW=math.max(0,(hasSurface and surfaceX-gap or right)-nameX)
            local function fit(label,width)
                if not label or width<=0 then return '' end
                local clipped=Text.wrapLimited(label,width,UIFont.Small,1)[1] or ''
                return manager:MeasureStringX(UIFont.Small,clipped)<=width and clipped or ''
            end
            return {
                width=list.width,
                height=cardH+connectorH,
                icon=icon,
                slotSize=slotSize,
                cardH=cardH,
                connectorH=connectorH,
                title=fit(row.title or row.label,nameW),
                sub=fit(row.sub,right-textX),
                stepBadge=fit(row.stepBadge,stepW-p),
                surfaceBadge=fit(row.surfaceBadge,surfaceW-p),
                textX=textX,nameX=nameX,stepW=stepW,surfaceX=surfaceX,surfaceW=surfaceW,
                isLast=row.isLast
            }
        else
            local lines=Text.wrapLimited(row.label or '',list.width-p*3,UIFont.Small,2)
            return {height=math.max(h+p,#lines*h+math.floor(p/2)),lines=lines,icon=nil}
        end
    end

    function blueprintStyle.draw(list,y,entry)
        local row,v=entry.item.value,entry.item.visual
        if row.kind=='chain_step' and v.width~=list.width then
            v=blueprintStyle.prepare(list,row) entry.item.visual=v
        end
        local scroll=list:getYScroll()
        local visible=y+scroll
        if visible+entry.height<=0 or visible>=list.height then return y+entry.height end

        local function safeText(txt,tx,ty,color)
            if not txt or txt=='' then return end
            local sy=ty+scroll
            if sy+h>0 and sy<list.height then Theme.text(list,txt,tx,ty,color) end
        end

        local function safeRect(rx,ry,rw,rh,color,border)
            if not color or rw<=0 or rh<=0 then return end
            local sy=ry+scroll
            if sy+rh<=0 or sy>=list.height then return end
            local clipTop=math.max(0,-sy)
            local clipBottom=math.max(0,(sy+rh)-list.height)
            local drawY=ry+clipTop
            local drawH=rh-clipTop-clipBottom
            if drawH>0 then Theme.rect(list,rx,drawY,rw,drawH,color,border) end
        end

        local function safeTexture(tex,tx,ty,tw,th)
            if not tex then return end
            local sy=ty+scroll
            if sy+th>0 and sy<list.height then list:drawTextureScaledAspect(tex,tx,ty,tw,th,1,1,1,1) end
        end

        if row.kind=='heading' then
            local barH=math.floor(h*1.2)
            local barY=y+math.floor((entry.height-barH)/2)
            safeRect(p,barY,list.width-p*2,barH,Theme.control,false)
            local accentColor=row.section=='tools' and {r=0.94,g=0.73,b=0.36,a=1} or Theme.accent
            safeRect(p,barY,3,barH,accentColor,false)
            safeText(row.label,p+8,barY+math.floor((barH-h)/2),Theme.textColor)
            return y+entry.height
        end

        if row.kind=='output' then
            local headerH=v.headerH or math.floor(h*1.2)
            local barH=math.floor(h*1.1)
            safeRect(p,y+2,list.width-p*2,barH,Theme.control,false)
            safeRect(p,y+2,3,barH,Theme.gold,false)
            safeText(v.sectionTitle or text('outputHeading'),p+8,y+2+math.floor((barH-h)/2),Theme.gold)

            local slotSize=v.slotSize or math.floor(h*2.2)
            local slotX=p
            local slotY=y+headerH+math.floor(p/2)

            safeRect(slotX,slotY,slotSize,slotSize,Theme.panel,false)
            safeRect(slotX,slotY,slotSize,slotSize,Theme.gold,true)

            if v.icon then safeTexture(v.icon,slotX+2,slotY+2,slotSize-4,slotSize-4) end

            local textX=slotX+slotSize+p
            local titleY=slotY+math.floor(p/4)
            local subY=titleY+h

            safeText(v.title or '',textX,titleY,Theme.textColor)
            if v.sub and v.sub~='' then safeText(v.sub,textX,subY,Theme.muted) end
            return y+entry.height
        end

        if row.kind=='input' then
            local slotSize=v.slotSize or math.floor(h*2.0)
            local slotX=p
            local slotY=y+math.floor((entry.height-slotSize)/2)

            safeRect(slotX,slotY,slotSize,slotSize,Theme.panel,false)

            local borderColor=Theme.border
            local countColor=Theme.textColor
            if row.precursor then
                borderColor=Theme.accent countColor=Theme.accent
            elseif row.isTool then
                borderColor={r=0.94,g=0.73,b=0.36,a=1}
                countColor=row.missing and {r=0.95,g=0.35,b=0.30,a=1} or {r=0.35,g=0.88,b=0.60,a=1}
            elseif row.missing then
                borderColor={r=0.95,g=0.35,b=0.30,a=1}
                countColor={r=0.95,g=0.35,b=0.30,a=1}
            elseif row.known then
                borderColor=Theme.border
                countColor={r=0.35,g=0.88,b=0.60,a=1}
            end
            safeRect(slotX,slotY,slotSize,slotSize,borderColor,true)

            if v.icon then safeTexture(v.icon,slotX+2,slotY+2,slotSize-4,slotSize-4) end

            local textX=slotX+slotSize+p
            local titleY=slotY+math.floor(p/4)
            local subY=titleY+h

            safeText(v.title or '',textX,titleY,Theme.textColor)
            safeText(v.sub or '',textX,subY,countColor)

            if row.isTool then
                local badgeText=craftText('toolBadge')
                local bw=getTextManager():MeasureStringX(UIFont.Small,badgeText)+p
                local bx=list.width-p-bw
                safeRect(bx,titleY,bw,h,Theme.control,false)
                safeRect(bx,titleY,bw,h,borderColor,true)
                safeText(badgeText,bx+math.floor(p/2),titleY,borderColor)
            elseif row.precursor then
                local chainText=text('chainSupplyTag')
                local bw=getTextManager():MeasureStringX(UIFont.Small,chainText)+p
                local bx=list.width-p-bw
                safeRect(bx,titleY,bw,h,Theme.control,false)
                safeRect(bx,titleY,bw,h,Theme.accent,true)
                safeText(chainText,bx+math.floor(p/2),titleY,Theme.accent)
            end

            return y+entry.height
        end

        if row.kind=='chain_step' then
            local cardW=list.width-p*2
            local cardH=v.cardH or math.floor(h*2.4)
            local cardY=y
            local isLast=row.isLast
            local nodeColor=isLast and Theme.gold or Theme.accent

            safeRect(p,cardY,cardW,cardH,Theme.panel,false)
            safeRect(p,cardY,cardW,cardH,isLast and nodeColor or Theme.border,true)

            local slotSize=v.slotSize or math.floor(h*1.8)
            local slotX=p+4
            local slotY=cardY+math.floor((cardH-slotSize)/2)
            safeRect(slotX,slotY,slotSize,slotSize,Theme.control,false)
            safeRect(slotX,slotY,slotSize,slotSize,isLast and nodeColor or Theme.border,true)
            if v.icon then safeTexture(v.icon,slotX+2,slotY+2,slotSize-4,slotSize-4) end

            local badgeH=math.floor(h*1.0)
            local badgeW=v.stepW
            local textX=v.textX
            local titleY=cardY+math.max(2,math.floor((cardH-h*2)/2))
            local subY=titleY+h

            safeRect(textX,titleY,badgeW,badgeH,Theme.control,false)
            safeRect(textX,titleY,badgeW,badgeH,nodeColor,true)
            safeText(v.stepBadge,textX+math.floor(p/2),titleY+math.floor((badgeH-h)/2),nodeColor)

            local nameX=v.nameX
            safeText(v.title or '',nameX,titleY,Theme.textColor)
            safeText(v.sub or '',textX,subY,nodeColor)

            if row.surfaceBadge then
                local sW=v.surfaceW
                local sX=v.surfaceX
                safeRect(sX,titleY,sW,badgeH,Theme.control,false)
                safeRect(sX,titleY,sW,badgeH,Theme.border,true)
                safeText(v.surfaceBadge,sX+math.floor(p/2),titleY+math.floor((badgeH-h)/2),Theme.muted)
            end

            if not isLast then
                local pipeX=math.floor(list.width/2)
                local pipeTop=cardY+cardH
                local connH=v.connectorH or math.floor(h*0.9)
                local pipeBottom=pipeTop+connH
                safeRect(pipeX-1,pipeTop,2,connH-5,Theme.accent,false)
                safeRect(pipeX-4,pipeBottom-6,8,1,Theme.accent,false)
                safeRect(pipeX-3,pipeBottom-5,6,1,Theme.accent,false)
                safeRect(pipeX-2,pipeBottom-4,4,1,Theme.accent,false)
                safeRect(pipeX-1,pipeBottom-3,2,2,Theme.accent,false)
            end

            return y+entry.height
        end

        local color=row.missing and {r=0.95,g=0.35,b=0.30,a=1} or Theme.textColor
        for i,line in ipairs(v.lines or {}) do
            safeText(line,p,y+math.floor(p/4)+(i-1)*h,color)
        end
        return y+entry.height
    end

    self.blueprintList=Cached.create(self,self.blueprintListRegion,nil,blueprintStyle)
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

    -- Read recipe spec for instant display
    local spec=Recipe.read(row.id)
    self.currentSpec=spec and Recipe.describe(spec) or row
    self:updateBlueprint()

    -- Async preview through Crafting service
    local status=Crafting.status(self.actor,self.entry.id)
    local repWorker=status and status.workers and status.workers[1] and status.workers[1].id or nil
    self.cancelPreview=Crafting.preview(self.actor,self.entry.id,repWorker,row.id,qty,surfaceId,function(result)
        if self.disposed then return end
        self.previewData=result
        self:updateBlueprint()
    end)
end

function EmberRoutesPublicOrderDialog:updateBlueprint()
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

    local yield=row.yield or (spec and spec.yield) or 1
    local units=math.max(1,math.ceil(targetQty/yield))
    local totalExpected=units*yield

    local rows={}
    local function add(r) rows[#rows+1]=r end

    -- 1. Hero Output Card
    add({
        kind='output',
        fullType=row.product or (spec and spec.product),
        title=(row.name or (spec and spec.name))..' x'..totalExpected,
        sub=text('batchCount',yield,units),
        heading=text('outputHeading'),
        label='output:'..tostring(row.id)..':'..totalExpected
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
                    label='input:'..tostring(input.slot)..':'..need..':'..tostring(avail)
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
                local first=choices[1]
                local toolName=first and first.name or (input.names and input.names[1]) or 'Tool'
                local count=preview and preview.counts and preview.counts[input.slot]
                local hasTool=count and count.available>=1
                local subStr=hasTool and craftText('readyBadge') or craftText('shortageBadge')
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
                    label='tool:'..tostring(input.slot)..':'..tostring(hasTool)
                })
            end
        end
    end

    -- 3. Multi-Step Production Chain Steps
    if preview and preview.chain and #preview.chain.nodes>1 then
        add({kind='heading',label=craftText('chainPlanHeading',#preview.chain.nodes)})
        for i,node in ipairs(preview.chain.nodes) do
            local isLast=(i==#preview.chain.nodes)
            local stepBadge=craftText(isLast and 'stepFinal' or 'stepPrecursor',i)
            local surfaceBadge=node.surface and craftText('badgeSurface') or craftText('badgeHand')
            add({
                kind='chain_step',
                fullType=node.product,
                stepIndex=i,
                isLast=isLast,
                stepBadge=stepBadge,
                surfaceBadge=surfaceBadge,
                title=node.recipeName,
                sub=craftText('planOutput',tostring(node.totalOutput or node.requested)),
                label='chain_step:'..i..':'..tostring(node.recipeId or node.product)
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
            label='single_step:1:'..tostring(row.id)
        })
    end

    Cached.reconcile(self.blueprintList,rows,function(r) return r.label end,function(r) return r.label end,true)

    -- Update Status Bar Message
    if preview then
        if preview.chain and #preview.chain.nodes>1 then
            self.statusNotice=text('statusChain')
            self.statusColor=Theme.accent
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
    else
        self.statusNotice=text('statusChecking')
        self.statusColor=Theme.muted
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

    -- Left Column Labels
    Theme.text(self,text('recipeSelect'),self.searchLabel.x,self.searchLabel.y+(self.searchLabel.height-h)/2,Theme.textColor)
    Theme.text(self,text('surfaceSelect'),self.surfaceLabel.x,self.surfaceLabel.y+(self.surfaceLabel.height-h)/2,Theme.textColor)

    local pageStr=(self.page or 1)..' / '..(self.totalPages or 1)
    local pageW=getTextManager():MeasureStringX(UIFont.Small,pageStr)
    Theme.text(self,pageStr,self.pageIndicatorRegion.x+(self.pageIndicatorRegion.width-pageW)/2,self.pageIndicatorRegion.y+(self.pageIndicatorRegion.height-h)/2,Theme.muted)

    if self.activeTab=='order' then
        Theme.text(self,text('targetQuantity'),self.quantityLabel.x,self.quantityLabel.y+(self.quantityLabel.height-h)/2,Theme.textColor)
    else
        Theme.text(self,text('stockThreshold'),self.minimumLabel.x,self.minimumLabel.y+(self.minimumLabel.height-h)/2,Theme.textColor)
        Theme.text(self,text('stockBatch'),self.batchLabel.x,self.batchLabel.y+(self.batchLabel.height-h)/2,Theme.textColor)
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
    if self.cancelPreview then self.cancelPreview() self.cancelPreview=nil end
    if self.presentation then self.presentation:clear() end
    self.recipeCombo:hidePopup()
    self.surfaceCombo:hidePopup()
    Tooltip.clear(self.recipeCombo)
    Tooltip.clear(self.surfaceCombo)
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if self.owner.publicDialog==self then self.owner.publicDialog=nil end
end

return EmberRoutesPublicOrderDialog
