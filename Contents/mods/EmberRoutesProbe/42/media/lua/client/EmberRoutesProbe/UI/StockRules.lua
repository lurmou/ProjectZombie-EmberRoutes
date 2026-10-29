require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
local Probe=require "EmberRoutesProbe/Probe"
local StockService=require "EmberRoutesProbe/StockService"
local StockStore=require "EmberRoutesProbe/StockStore"
local CraftingService=require "EmberRoutesProbe/CraftingService"
local Layout=require "EmberRoutesProbe/UI/Layout"
local State=require "EmberRoutesProbe/UI/State"
local Cached=require "EmberRoutesProbe/UI/CachedList"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Lifecycle=require "EmberRoutesProbe/UI/PageLifecycle"
local Tooltip=require "EmberRoutesProbe/UI/TooltipAnchor"
local Visual=require "EmberRoutesProbe/UI/StatusVisual"
local Text=require "EmberRoutesProbe/UI/Text"
local Recipes=require "EmberRoutesProbe/ProductionRecipe"
local Surfaces=require "EmberRoutesProbe/CraftSurfaces"
local Driver=require "EmberRoutesProbe/Driver"
local Words=require "EmberRoutesProbe/CraftingText"

local function text(key)
    return getTextOrNull("IGUI_EmberRoutesProbe_Stock_"..key) or Words.get(key)
end

local function stateBadge(ruleState)
    local labels={
        SATISFIED={"done",text("status_satisfied")},
        RESTOCKING={"active",text("status_restocking")},
        WAIT_INVENTORY={"paused",text("status_wait_inventory")},
        WAIT_WORKER={"paused",text("status_wait_worker")},
        WAIT_EXISTING_ORDER={"paused",text("status_wait_order")},
        WAIT_SURFACE={"paused",text("status_wait_surface")},
        SCOPE_OVERLAP={"blocked",text("status_overlap")},
        DISABLED={"neutral",text("status_disabled")},
        DELETING={"blocked",text("status_deleting")},
        RECONCILE_REQUIRED={"blocked",text("status_reconcile")}
    }
    return labels[ruleState] or {"neutral",ruleState or text("status_unknown")}
end

---@class EmberRoutesStockRules:ISPanel
EmberRoutesStockRules=ISPanel:derive("EmberRoutesStockRules")

function EmberRoutesStockRules:new(shell,bounds)
    local o=ISPanel.new(self,bounds.x,bounds.y,bounds.width,bounds.height)
    o.owner=shell.owner
    o.actor=shell.actor
    o.entry=shell.entry
    o.fontHeight=shell.fontHeight
    o.pad=shell.pad
    o.background=false
    o.store=State.new({rules={},selection=false,mode="detail",targetDraft=20,newRule={minimum=20,fullType=""}})
    o.buttons={}
    return o
end

function EmberRoutesStockRules:initialise() ISPanel.initialise(self) end

function EmberRoutesStockRules:createChildren()
    ISPanel.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local regions=assert(Layout.axis({x=0,y=0,width=self.width,height=self.height},{{grow=2},{grow=3}},{gap=p}))
    local leftBounds,rightBounds=regions[1],regions[2]

    -- Left Column: Header (Title + New Rule button) + Rules List
    local leftParts=assert(Layout.axis(leftBounds,{{basis=h+p/2},{grow=1}},{direction="column",gap=p/2}))
    local topRow=assert(Layout.axis(leftParts[1],{{grow=1},{basis=h*5}},{gap=p/2}))

    self.titleLabel=text("title")
    self.newBtn=ISButton:new(topRow[2].x,topRow[2].y,topRow[2].width,topRow[2].height,text("btn_new_rule"),self,function()
        self:selectNewRuleMode()
    end)
    self.newBtn:initialise() Theme.button(self.newBtn) self:addChild(self.newBtn)

    local listStyle={
        emptyColor=Theme.muted,
        prepare=function(list,r)
            local badgeInfo=stateBadge(r.state)
            local badge=Visual.badge(badgeInfo[2],badgeInfo[1],list.width-p*2,h,p/2)
            local itemName=r.fullType
            local itemType=ScriptManager.instance:getItem(r.fullType)
            if itemType then itemName=itemType:getDisplayName() end
            local countsStr=getText("IGUI_EmberRoutesProbe_Stock_countsFormat",r.knownCount or 0,r.minimum or 0)
            return {
                height=h*3.5+p,
                name=Text.wrapLimited(itemName,list.width-p*2,UIFont.Small,1)[1],
                counts=countsStr,
                fraction=r.minimum>0 and math.min(1,(r.knownCount or 0)/r.minimum) or 0,
                badge=badge
            }
        end,
        draw=function(list,y,entry)
            local v=entry.item.visual
            local visible=y+list:getYScroll()
            if visible+v.height<0 or visible>=list.height then return y+v.height end
            if list.selected==entry.index then
                Theme.rect(list,0,y,list.width,v.height,Theme.selected)
                Theme.rect(list,0,y,math.max(2,p/4),v.height,Theme.accent)
            elseif list.mouseoverselected==entry.index then
                Theme.rect(list,0,y,list.width,v.height,Theme.hover)
            end
            Theme.text(list,v.name,p,y+p/4,Theme.textColor)
            Theme.text(list,v.counts,p,y+h+p/4,Theme.muted)
            Visual.meter(list,list.width-h*5-p,y+h+p/4,h*5,h*0.8,v.fraction)
            Visual.drawBadge(list,p,y+h*2+p/2,v.badge)
            return y+v.height
        end
    }
    self.rulesList=Cached.create(self,leftParts[2],function(_,row)
        self:selectRule(row.id)
    end,listStyle)
    Theme.list(self.rulesList)
    self:addChild(self.rulesList)

    -- Right Column: Panel container for Detail or New Form
    self.rightPanel=ISPanel:new(rightBounds.x,rightBounds.y,rightBounds.width,rightBounds.height)
    self.rightPanel:initialise()
    self.rightPanel.background=false
    self:addChild(self.rightPanel)

    self:buildDetailView(rightBounds)
    self:buildNewFormView(rightBounds)
end

function EmberRoutesStockRules:buildDetailView(bounds)
    local h,p=self.fontHeight,self.pad
    self.detailContainer=ISPanel:new(0,0,bounds.width,bounds.height)
    self.detailContainer:initialise()
    self.detailContainer.background=false
    self.rightPanel:addChild(self.detailContainer)

    -- Stepper buttons for target
    local rowY=h*3+p
    local stepW=math.floor(h*2.5)
    local steppers={{-5,"-5"},{-1,"-1"},{1,"+1"},{5,"+5"}}
    self.stepButtons={}
    for i,s in ipairs(steppers) do
        local btn=ISButton:new(p*2+(i-1)*(stepW+p/2),rowY,stepW,h+p/4,s[2],self,function()
            self:stepDraftTarget(s[1])
        end)
        btn:initialise() Theme.button(btn)
        self.detailContainer:addChild(btn)
        self.stepButtons[#self.stepButtons+1]=btn
    end

    self.saveTargetBtn=ISButton:new(p*2+4*(stepW+p/2)+p,rowY,h*4.5,h+p/4,text("btn_save"),self,function()
        self:commitTargetUpdate()
    end)
    self.saveTargetBtn:initialise() Theme.button(self.saveTargetBtn)
    self.detailContainer:addChild(self.saveTargetBtn)

    -- Bottom action buttons: Toggle Enable, Delete, Retry
    local botY=bounds.height-h-p*1.5
    local botW=math.floor((bounds.width-p*4)/3)

    self.toggleBtn=ISButton:new(p,botY,botW,h+p/2,text("btn_toggle"),self,function()
        self:commitToggle()
    end)
    self.toggleBtn:initialise() Theme.button(self.toggleBtn)
    self.detailContainer:addChild(self.toggleBtn)

    self.retryBtn=ISButton:new(p*2+botW,botY,botW,h+p/2,text("btn_retry"),self,function()
        self:commitRetry()
    end)
    self.retryBtn:initialise() Theme.button(self.retryBtn)
    self.detailContainer:addChild(self.retryBtn)

    self.deleteBtn=ISButton:new(p*3+botW*2,botY,botW,h+p/2,text("btn_delete"),self,function()
        self:commitDelete()
    end)
    self.deleteBtn:initialise() Theme.button(self.deleteBtn)
    self.detailContainer:addChild(self.deleteBtn)
end

function EmberRoutesStockRules:buildNewFormView(bounds)
    local h,p=self.fontHeight,self.pad
    self.newFormContainer=ISPanel:new(0,0,bounds.width,bounds.height)
    self.newFormContainer:initialise()
    self.newFormContainer.background=false
    self.newFormContainer:setVisible(false)
    self.rightPanel:addChild(self.newFormContainer)

    local inputH=h+math.floor(p/2)
    local gapLabel=math.floor(p/4)
    local gapField=math.floor(p/2)
    local y=p

    self.formY={}

    -- 1. Item input
    self.formY.itemLabel=y
    y=y+h+gapLabel
    self.itemInput=ISTextEntryBox:new("",p,y,bounds.width-p*2,inputH)
    self.itemInput:initialise()
    self.itemInput:setPlaceholderText(text("placeholderItem"))
    self.itemInput.backgroundColor=Theme.panel
    self.itemInput.borderColor=Theme.border
    self.itemInput.onTextChangeFunction=function() self:onItemInputChanged() end
    self.newFormContainer:addChild(self.itemInput)
    y=y+inputH+gapLabel

    -- Item name display / hint
    self.formY.itemHint=y
    y=y+h+gapField

    -- 2. Recipe select
    self.formY.recipeLabel=y
    y=y+h+gapLabel
    self.recipeCombo=ISComboBox:new(p,y,bounds.width-p*2,inputH,self,EmberRoutesStockRules.onRecipeSelected)
    self.recipeCombo:initialise()
    self.recipeCombo.backgroundColor=Theme.panel
    self.recipeCombo.borderColor=Theme.border
    self.newFormContainer:addChild(self.recipeCombo)
    y=y+inputH+gapField

    -- 3. Worker select
    self.formY.workerLabel=y
    y=y+h+gapLabel
    self.workerCombo=ISComboBox:new(p,y,bounds.width-p*2,inputH)
    self.workerCombo:initialise()
    self.workerCombo.backgroundColor=Theme.panel
    self.workerCombo.borderColor=Theme.border
    self.newFormContainer:addChild(self.workerCombo)
    y=y+inputH+gapField

    -- 4. Surface select
    self.formY.surfaceLabel=y
    y=y+h+gapLabel
    self.surfaceCombo=ISComboBox:new(p,y,bounds.width-p*2,inputH)
    self.surfaceCombo:initialise()
    self.surfaceCombo.backgroundColor=Theme.panel
    self.surfaceCombo.borderColor=Theme.border
    self.newFormContainer:addChild(self.surfaceCombo)
    y=y+inputH+gapField

    -- 5. Target stock stepper
    self.formY.targetLabel=y
    y=y+h+gapLabel
    local stepW=math.floor(h*2.5)
    local steppers={{-5,"-5"},{-1,"-1"},{1,"+1"},{5,"+5"}}
    for i,s in ipairs(steppers) do
        local btn=ISButton:new(p+(i-1)*(stepW+gapField),y,stepW,inputH,s[2],self,function()
            local cur=(self.store.value.newRule and self.store.value.newRule.minimum) or 20
            local v=math.max(1,math.min(9999,cur+s[1]))
            if not self.store.value.newRule then self.store.value.newRule={minimum=20} end
            self.store.value.newRule.minimum=v
            self:updateNewForm()
        end)
        btn:initialise() Theme.button(btn)
        self.newFormContainer:addChild(btn)
    end

    -- Create submit button
    local botY=bounds.height-inputH-p
    self.createSubmitBtn=ISButton:new(p,botY,bounds.width-p*2,inputH,text("btn_create_confirm"),self,function()
        self:commitCreateRule()
    end)
    self.createSubmitBtn:initialise() Theme.button(self.createSubmitBtn)
    self.newFormContainer:addChild(self.createSubmitBtn)
end

function EmberRoutesStockRules:onItemInputChanged()
    local val=self.itemInput and self.itemInput:getText() or ""
    if self.store.value.newRule then
        self.store.value.newRule.fullType=val
    end
    self:populateCombos(val)
    self.formNotice=nil
end

function EmberRoutesStockRules:onRecipeSelected()
    local recipeId=self.recipeCombo and self.recipeCombo:getOptionData(self.recipeCombo.selected)
    if recipeId then
        local currentText=self.itemInput and self.itemInput:getText() or ""
        if not currentText or currentText=="" then
            local spec=Recipes.read(recipeId)
            if spec and spec.product then
                self.itemInput:setText(spec.product)
                if self.store.value.newRule then
                    self.store.value.newRule.fullType=spec.product
                end
            end
        end
    end
    self.formNotice=nil
end

function EmberRoutesStockRules:activate()
    local mounted=Lifecycle.mount(self,function(callback)
        return StockService.watch(self.actor,self.entry.id,callback)
    end,function(snapshot)
        if snapshot.reason=="WORLD_RESET" then self.owner:close() return end
        self.store:setState({rules=snapshot.rules})
    end)
    if mounted and self.active then
        self.store:setState({rules=StockService.status(self.actor,self.entry.id).rules})
        self:project(self.store.value,{rules=true})
    end
end

function EmberRoutesStockRules:deactivate()
    Lifecycle.unmount(self)
end

function EmberRoutesStockRules:dispose()
    self.disposed=true
    self:deactivate()
end

function EmberRoutesStockRules:focusContent() end

function EmberRoutesStockRules:applyArgs(args)
    if not args then return end
    local fullType=args.fullType or args.prefillFullType
    if fullType then
        self:selectNewRuleMode(fullType)
    end
end

function EmberRoutesStockRules:selectRule(ruleId)
    local rule
    for _,r in ipairs(self.store.value.rules or {}) do
        if r.id==ruleId then rule=r break end
    end
    if rule then
        self.store:setState({selection=ruleId,mode="detail",targetDraft=rule.minimum})
    end
end

function EmberRoutesStockRules:selectNewRuleMode(prefillFullType)
    local newR={minimum=20,fullType=prefillFullType or ""}
    if self.itemInput then
        self.itemInput:setText(prefillFullType or "")
    end
    self.formNotice=nil
    self:populateCombos(prefillFullType or "")
    self.store:setState({mode="new",selection=false,newRule=newR})
end

function EmberRoutesStockRules:stepDraftTarget(delta)
    local cur=self.store.value.targetDraft or 20
    cur=math.max(1,math.min(9999,cur+delta))
    self.store:setState({targetDraft=cur})
end

function EmberRoutesStockRules:populateCombos(filterFullType)
    self.recipeCombo:clear()
    local added={}
    local targetType=filterFullType or (self.itemInput and self.itemInput:getText()) or ""

    if targetType~="" then
        local Catalog=require "EmberRoutesProbe/CraftingCatalog"
        local _,productionByType=Catalog.productionIndex()
        local matches=productionByType and productionByType[targetType]
        if matches then
            for _,spec in ipairs(matches) do
                self.recipeCombo:addOptionWithData(spec.name,spec.id)
                added[spec.id]=true
            end
        end
        for _,ex in ipairs(Recipes.examples()) do
            if ex.product==targetType and not added[ex.id] then
                self.recipeCombo:addOptionWithData(ex.name,ex.id)
                added[ex.id]=true
            end
        end
    end

    if #self.recipeCombo.options==0 then
        if targetType=="" then
            for _,ex in ipairs(Recipes.examples()) do
                if not added[ex.id] then
                    self.recipeCombo:addOptionWithData(ex.name,ex.id)
                    added[ex.id]=true
                end
            end
        else
            self.recipeCombo:addOptionWithData(text("noRecipeFound"),nil)
        end
    end

    self.workerCombo:clear()
    local workerFound=false
    local cStatus=CraftingService.status(self.actor,self.entry.id)
    if cStatus and cStatus.workers and #cStatus.workers>0 then
        for _,w in ipairs(cStatus.workers) do
            self.workerCombo:addOptionWithData(w.name,w.id)
            workerFound=true
        end
    end
    if not workerFound and Probe.hasJava() then
        for i=0,EmberRoutesProbeJava.workerCount()-1 do
            local npcId=EmberRoutesProbeJava.workerIdAt(i)
            local binding=Driver.bindId(self.actor,npcId)
            local name=binding and binding.handle:getFullName() or string.sub(npcId,1,8)
            self.workerCombo:addOptionWithData(name,npcId)
            workerFound=true
        end
    end
    if not workerFound then
        self.workerCombo:addOptionWithData(text("noWorkersAvailable"),nil)
    end

    self.surfaceCombo:clear()
    self.surfaceCombo:addOptionWithData(text("inHandNoSurface"),nil)
    local surfaces=Surfaces.list(self.entry)
    for _,s in ipairs(surfaces or {}) do
        local label=getText("IGUI_EmberRoutesProbe_Stock_benchLocation",s.x,s.y)
        self.surfaceCombo:addOptionWithData(label,s.id)
    end
end

function EmberRoutesStockRules:commitTargetUpdate()
    local sel=self:getSelectedRule()
    if not sel then return end
    local draft=self.store.value.targetDraft
    StockStore.command(self.actor,self.entry.id,"update",{
        ruleId=sel.id,
        expectedRevision=sel.revision,
        minimum=draft
    })
    StockService.markDirty(sel.id)
end

function EmberRoutesStockRules:commitToggle()
    local sel=self:getSelectedRule()
    if not sel then return end
    local cmd=sel.enabled and "disable" or "enable"
    StockStore.command(self.actor,self.entry.id,cmd,{
        ruleId=sel.id,
        expectedRevision=sel.revision
    })
    StockService.markDirty(sel.id)
end

function EmberRoutesStockRules:commitDelete()
    local sel=self:getSelectedRule()
    if not sel then return end
    StockStore.command(self.actor,self.entry.id,"delete",{
        ruleId=sel.id,
        expectedRevision=sel.revision
    })
    StockService.markDirty(sel.id)
    self.store:setState({selection=false,mode="new"})
end

function EmberRoutesStockRules:commitRetry()
    local sel=self:getSelectedRule()
    if not sel then return end
    StockStore.command(self.actor,self.entry.id,"retry",{ruleId=sel.id})
    StockService.markDirty(sel.id)
end

function EmberRoutesStockRules:commitCreateRule()
    local fullType=self.itemInput and self.itemInput:getText() or ""
    if string.trim then fullType=string.trim(fullType) end
    local recipeId=self.recipeCombo and self.recipeCombo:getOptionData(self.recipeCombo.selected)
    local npcId=self.workerCombo and self.workerCombo:getOptionData(self.workerCombo.selected)
    local surfaceId=self.surfaceCombo and self.surfaceCombo:getOptionData(self.surfaceCombo.selected)
    local min=(self.store.value.newRule and self.store.value.newRule.minimum) or 20

    if not fullType or fullType=="" then
        self.formNotice=text("error_no_item")
        return
    end
    if not recipeId then
        self.formNotice=text("error_no_recipe")
        return
    end
    if not npcId then
        self.formNotice=text("error_no_worker")
        return
    end

    local spec=Recipes.read(recipeId)
    local sig=spec and spec.signature or recipeId

    local id,err=StockStore.command(self.actor,self.entry.id,"create",{
        fullType=fullType,
        recipeId=recipeId,
        recipeSignature=sig,
        npcId=npcId,
        surfaceId=surfaceId,
        minimum=min,
        enabled=true
    })
    if id then
        self.formNotice=nil
        StockService.markDirty(id)
        self:selectRule(id)
    else
        self.formNotice=tostring(err or text("error_create_failed"))
    end
end

function EmberRoutesStockRules:getSelectedRule()
    local selId=self.store.value.selection
    if not selId then return nil end
    for _,r in ipairs(self.store.value.rules or {}) do
        if r.id==selId then return r end
    end
    return nil
end

function EmberRoutesStockRules:project(value,_changes)
    if not self.active then return end
    local rules=value.rules or {}
    Cached.reconcile(self.rulesList,rules,function(r)
        return r.id..":"..tostring(r.revision)..":"..tostring(r.state)..":"..(r.knownCount or 0)..":"..(r.minimum or 0)..":"..tostring(r.enabled)
    end,function(r) return r.id end,true)

    local isNew=value.mode=="new" or not value.selection
    self.detailContainer:setVisible(not isNew)
    self.newFormContainer:setVisible(isNew)

    if not isNew then
        local sel=self:getSelectedRule()
        if sel then
            self.toggleBtn:setTitle(sel.enabled and (text("btn_disable")) or (text("btn_enable")))
            Theme.enable(self.retryBtn,sel.state=="RECONCILE_REQUIRED")
        end
    else
        self:updateNewForm()
    end
end

function EmberRoutesStockRules:updateNewForm()
    local min=self.store.value.newRule and self.store.value.newRule.minimum or 20
    self.createSubmitBtn:setTitle(string.format(text("btn_create_confirm_with_target"),min))
end

function EmberRoutesStockRules:prerender()
    ISPanel.prerender(self)
    local h,p=self.fontHeight,self.pad
    Theme.text(self,self.titleLabel or text("title"),p,p/4,Theme.textColor)

    if self.detailContainer:isVisible() then
        local sel=self:getSelectedRule()
        if sel then
            local x=self.rightPanel.x+p
            local y=self.rightPanel.y+p
            local nameKey=sel.id..':'..sel.revision
            if self._nameKey~=nameKey then
                self._nameKey=nameKey
                local itemType=ScriptManager.instance:getItem(sel.fullType)
                self._nameText=itemType and itemType:getDisplayName() or sel.fullType
            end
            local name=self._nameText
            Theme.text(self,name.." ("..sel.fullType..")",x,y,Theme.textColor)
            Theme.text(self,getText("IGUI_EmberRoutesProbe_Stock_targetStockFormat",self.store.value.targetDraft or sel.minimum),x,y+h+p/4,Theme.accent)

            local badgeInfo=stateBadge(sel.state)
            local badge=Visual.badge(badgeInfo[2],badgeInfo[1],math.floor(h*7),h,p/2)
            Visual.drawBadge(self,x,y+h*2+p/2,badge)

            local infoY=y+h*4.5+p
            Theme.text(self,getText("IGUI_EmberRoutesProbe_Stock_physicalCountFormat",sel.knownCount or 0),x,infoY,Theme.textColor)
            Theme.text(self,getText("IGUI_EmberRoutesProbe_Stock_deficitFormat",sel.deficit or 0),x,infoY+h,Theme.muted)
            Theme.text(self,getText("IGUI_EmberRoutesProbe_Stock_workerFormat",sel.npcId),x,infoY+h*2,Theme.muted)
            Theme.text(self,getText("IGUI_EmberRoutesProbe_Stock_recipeFormat",sel.recipeId),x,infoY+h*3,Theme.muted)

            if sel.activeCycle then
                Theme.text(self,getText("IGUI_EmberRoutesProbe_Stock_cycleFormat",sel.activeCycle.taskId,sel.activeCycle.phase),x,infoY+h*4.5,Theme.accent)
            end

            local noteY=infoY+h*6
            Theme.text(self,text("notePhysical"),x,noteY,Theme.muted)
            Theme.text(self,text("noteReserved"),x,noteY+h,Theme.muted)
        end
    elseif self.newFormContainer:isVisible() then
        local x=self.rightPanel.x+p
        local baseY=self.rightPanel.y
        local fy=self.formY
        if fy then
            Theme.text(self,text("lbl_item_type"),x,baseY+fy.itemLabel,Theme.textColor)

            local fullType=self.itemInput and self.itemInput:getText() or ""
            local itemObj=fullType~="" and ScriptManager.instance:getItem(fullType)
            if itemObj then
                Theme.text(self,getText("IGUI_EmberRoutesProbe_Stock_selectedItemDisplay",itemObj:getDisplayName()),x,baseY+fy.itemHint,Theme.accent)
            else
                Theme.text(self,text("hint_select_from_storage"),x,baseY+fy.itemHint,Theme.muted)
            end

            Theme.text(self,text("lbl_recipe"),x,baseY+fy.recipeLabel,Theme.textColor)
            Theme.text(self,text("lbl_worker"),x,baseY+fy.workerLabel,Theme.textColor)
            Theme.text(self,text("lbl_surface"),x,baseY+fy.surfaceLabel,Theme.textColor)

            local minVal=self.store.value.newRule and self.store.value.newRule.minimum or 20
            local targetLabel=getText("IGUI_EmberRoutesProbe_Stock_targetStockFormatLabel",minVal)
            Theme.text(self,targetLabel,x,baseY+fy.targetLabel,Theme.textColor)

            if self.formNotice then
                Theme.text(self,self.formNotice,x,baseY+self.createSubmitBtn.y-h-math.floor(p/4),Theme.accent)
            end
        end
    end
end

return EmberRoutesStockRules
