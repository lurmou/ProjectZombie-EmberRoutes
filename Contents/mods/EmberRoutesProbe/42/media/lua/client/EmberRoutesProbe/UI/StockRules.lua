require "ISUI/ISPanel"
require "ISUI/ISButton"
local SearchInput=require "EmberRoutesProbe/UI/SearchInput"
local Dropdown=require "EmberRoutesProbe/UI/Dropdown"
local Probe=require "EmberRoutesProbe/Kernel/Boot"
local StockService=require "EmberRoutesProbe/Warehouse/StockService"
local StockStore=require "EmberRoutesProbe/Warehouse/StockStore"
local CraftingService=require "EmberRoutesProbe/Crafting/CraftingService"
local LayoutHost=require "EmberRoutesProbe/UI/LayoutHost"
local UI=require "EmberRoutesProbe/UI/UI"
local State=require "EmberRoutesProbe/UI/State"
local Cached=require "EmberRoutesProbe/UI/CachedList"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Lifecycle=require "EmberRoutesProbe/UI/PageLifecycle"
local Visual=require "EmberRoutesProbe/UI/StatusVisual"
local Text=require "EmberRoutesProbe/UI/Text"
local StepperInput=require "EmberRoutesProbe/UI/StepperInput"
local Recipes=require "EmberRoutesProbe/Crafting/ProductionRecipe"
local Surfaces=require "EmberRoutesProbe/Crafting/CraftSurfaces"
local Driver=require "EmberRoutesProbe/Runtime/Driver"
local Words=require "EmberRoutesProbe/Crafting/CraftingText"

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

local CREATE_RULE_SCHEMA={
    fullType={required=true,type="string",message="error_no_item"},
    recipeId={required=true,message="error_no_recipe"},
    npcId={required=true,message="error_no_worker"},
    minimum={required=true,type="number",integer=true,min=1}
}

local function isDetailMode(ctx)
    return ctx and ctx.mode=="detail"
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
    o.store=State.new({rules={},selection=false,mode="new",targetDraft=20,newRule={minimum=20,fullType=""}})
    o.buttons={}

    -- Preallocated bounds for Zero-GC presentation rendering
    o.leftBounds={x=0,y=0,width=0,height=0,visible=false}
    o.rightBounds={x=0,y=0,width=0,height=0,visible=false}
    o.titleBounds={x=0,y=0,width=0,height=0,visible=false}
    o.rulesListBounds={x=0,y=0,width=0,height=0,visible=false}
    o.detailBounds={x=0,y=0,width=0,height=0,visible=false}
    o.detailHeaderBounds={x=0,y=0,width=0,height=0,visible=false}
    o.detailStepperBounds={x=0,y=0,width=0,height=0,visible=false}
    o.detailInfoBounds={x=0,y=0,width=0,height=0,visible=false}
    o.detailActionBounds={x=0,y=0,width=0,height=0,visible=false}
    o.newFormBounds={x=0,y=0,width=0,height=0,visible=false}
    o.itemHintBounds={x=0,y=0,width=0,height=0,visible=false}
    o.formNoticeBounds={x=0,y=0,width=0,height=0,visible=false}
    o.formActionBounds={x=0,y=0,width=0,height=0,visible=false}
    return o
end

function EmberRoutesStockRules:initialise() ISPanel.initialise(self) end

function EmberRoutesStockRules:createChildren()
    ISPanel.createChildren(self)
    local h,p=self.fontHeight,self.pad

    self.host=LayoutHost:new(0,0,self.width,self.height)
    self.host:initialise()
    self:addChild(self.host)

    self.titleLabel=text("title")
    self.newBtn=ISButton:new(0,0,math.floor(h*5),h+math.floor(p/2),text("btn_new_rule"),self,function()
        self:selectNewRuleMode()
    end)
    self.newBtn:initialise() Theme.button(self.newBtn)

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
                Theme.rect(list,0,y,list.width,v.height,Theme.selectedBorder or Theme.border,true)
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
    self.rulesList=Cached.create(self,self.rulesListBounds,function(_,row)
        self:selectRule(row.id)
    end,listStyle)
    Theme.list(self.rulesList)

    local detailSpec=self:buildDetailView()
    local newFormSpec=self:buildNewFormView()

    local views=UI.Show(isDetailMode,
        UI.Item(detailSpec,{key="detailView",grow=1,bind=self.detailBounds}),
        UI.Item(newFormSpec,{key="newFormView",grow=1,bind=self.newFormBounds})
    )

    local leftSpec=UI.Column({gap=math.floor(p/2),align="stretch"},{
        UI.Item(UI.Row({gap=math.floor(p/2),align="center"},{
            UI.Item(self.titleBounds,{key="titleLabel",grow=1,bind=self.titleBounds}),
            UI.Item(self.newBtn,{key="newBtn",basis=math.floor(h*5),grow=0})
        }),{key="leftHeader",basis=h+math.floor(p/2),grow=0}),
        UI.Item(self.rulesList,{key="rulesList",grow=1,bind=self.rulesListBounds})
    })

    local rightSpec=UI.Column({gap=p,align="stretch"},{views[1],views[2]})

    local rootSpec=UI.Row({padding=p,gap=p,align="stretch"},{
        UI.Item(leftSpec,{key="leftPane",grow=2,bind=self.leftBounds}),
        UI.Item(rightSpec,{key="rightPane",grow=3,bind=self.rightBounds})
    })

    local handles,err=self.host:build(rootSpec,self.store.value)
    assert(handles,err)
    self.layoutHandles=handles
end

function EmberRoutesStockRules:buildDetailView(_bounds)
    local h,p=self.fontHeight,self.pad
    local rowH=h+math.floor(p/4)
    local saveW=math.floor(h*4.5)
    local initialTarget=(self.store.value and self.store.value.targetDraft) or 20

    self.targetStepper=StepperInput:new(0,0,200,rowH,initialTarget,1,9999,{-5,-1,1,5},function(v)
        if v then self.store:setState({targetDraft=v}) end
    end)

    self.saveTargetBtn=ISButton:new(0,0,saveW,rowH,text("btn_save"),self,function() self:commitTargetUpdate() end)
    self.saveTargetBtn:initialise() Theme.button(self.saveTargetBtn, true)

    self.toggleBtn=ISButton:new(0,0,0,h+math.floor(p/2),text("btn_toggle"),self,function() self:commitToggle() end)
    self.toggleBtn:initialise() Theme.button(self.toggleBtn)

    self.retryBtn=ISButton:new(0,0,0,h+math.floor(p/2),text("btn_retry"),self,function() self:commitRetry() end)
    self.retryBtn:initialise() Theme.button(self.retryBtn)

    self.deleteBtn=ISButton:new(0,0,0,h+math.floor(p/2),text("btn_delete"),self,function() self:commitDelete() end)
    self.deleteBtn:initialise() Theme.button(self.deleteBtn)

    return UI.Column({padding=p,gap=p,align="stretch"},{
        UI.Item(self.detailHeaderBounds,{key="detailHeader",basis=h*3+math.floor(p/2),grow=0,bind=self.detailHeaderBounds}),
        UI.Item(UI.Row({gap=p,align="center"},{
            UI.Item(self.targetStepper,{key="targetStepper",grow=1}),
            UI.Item(self.saveTargetBtn,{key="saveTargetBtn",basis=saveW,grow=0})
        }),{key="detailStepperRow",basis=rowH,grow=0,bind=self.detailStepperBounds}),
        UI.Item(self.detailInfoBounds,{key="detailInfo",basis=h*7+p,grow=0,bind=self.detailInfoBounds}),
        UI.Spacer(1),
        UI.Item(UI.Row({gap=p,align="stretch"},{
            UI.Item(self.toggleBtn,{key="toggleBtn",grow=1}),
            UI.Item(self.retryBtn,{key="retryBtn",grow=1}),
            UI.Item(self.deleteBtn,{key="deleteBtn",grow=1})
        }),{key="detailActions",basis=h+math.floor(p/2),grow=0,bind=self.detailActionBounds})
    })
end

function EmberRoutesStockRules:buildNewFormView(_bounds)
    local h,p=self.fontHeight,self.pad
    local inputH=h+math.floor(p/2)
    local labelW=math.max(120,math.floor(h*6))
    local gap=math.floor(p/2)

    self.formLabels={
        item={text=text("lbl_item_type"),x=0,y=0,width=labelW,height=inputH,visible=true},
        recipe={text=text("lbl_recipe"),x=0,y=0,width=labelW,height=inputH,visible=true},
        worker={text=text("lbl_worker"),x=0,y=0,width=labelW,height=inputH,visible=true},
        surface={text=text("lbl_surface"),x=0,y=0,width=labelW,height=inputH,visible=true},
        target={text=text("lbl_target_stock"),x=0,y=0,width=labelW,height=inputH,visible=true}
    }

    self.itemInput=SearchInput:new(0,0,0,inputH,text("placeholderItem"),self,function()
        self:onItemInputChanged()
    end)

    self.recipeCombo=Dropdown:new(0,0,0,inputH,self,EmberRoutesStockRules.onRecipeSelected)
    self.recipeCombo:initialise()

    self.workerCombo=Dropdown:new(0,0,0,inputH)
    self.workerCombo:initialise()

    self.surfaceCombo=Dropdown:new(0,0,0,inputH)
    self.surfaceCombo:initialise()

    self.newRuleStepper=StepperInput:new(0,0,200,inputH,20,1,9999,{-5,-1,1,5},function(v)
        if not v then return end
        if not self.store.value.newRule then self.store.value.newRule={minimum=v,fullType=""} end
        self.store.value.newRule.minimum=v
        self:updateNewForm()
    end)

    self.createSubmitBtn=ISButton:new(0,0,0,inputH,text("btn_create_confirm"),self,function() self:commitCreateRule() end)
    self.createSubmitBtn:initialise() Theme.button(self.createSubmitBtn, true)

    return UI.Column({padding=p,gap=gap,align="stretch"},{
        UI.FormRow(self.formLabels.item,self.itemInput,nil,{key="itemRow",height=inputH,labelWidth=labelW,gap=gap}),
        UI.Item(self.itemHintBounds,{key="itemHint",basis=h,grow=0,margin={left=labelW+gap},bind=self.itemHintBounds}),
        UI.FormRow(self.formLabels.recipe,self.recipeCombo,nil,{key="recipeRow",height=inputH,labelWidth=labelW,gap=gap}),
        UI.FormRow(self.formLabels.worker,self.workerCombo,nil,{key="workerRow",height=inputH,labelWidth=labelW,gap=gap}),
        UI.FormRow(self.formLabels.surface,self.surfaceCombo,nil,{key="surfaceRow",height=inputH,labelWidth=labelW,gap=gap}),
        UI.FormRow(self.formLabels.target,self.newRuleStepper,nil,{key="targetRow",height=inputH,labelWidth=labelW,gap=gap}),
        UI.Spacer(1),
        UI.Item(self.formNoticeBounds,{key="formNotice",basis=h,grow=0,bind=self.formNoticeBounds}),
        UI.Item(self.createSubmitBtn,{key="submitBtn",basis=inputH,grow=0,bind=self.formActionBounds})
    })
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
    local recipeId=self.recipeCombo and self.recipeCombo:getSelectedData()
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
        if self.host and self.activationScope and self.activationScope:isCurrent() then
            self.host:setActivation(self.activationScope)
        end
        self.store:setState({rules=StockService.status(self.actor,self.entry.id).rules})
    end
end

function EmberRoutesStockRules:deactivate()
    for _,c in ipairs({self.recipeCombo,self.workerCombo,self.surfaceCombo}) do
        if c and c.closePopup then c:closePopup() end
    end
    if self.host then self.host:deactivate() end
    Lifecycle.unmount(self)
end

function EmberRoutesStockRules:dispose()
    self.disposed=true
    self:deactivate()
    if self.host then self.host:dispose() end
end

function EmberRoutesStockRules:onResize()
    ISPanel.onResize(self)
    if self.host then
        self.host:setWidth(self.width)
        self.host:setHeight(self.height)
        if self.host.onResize then self.host:onResize() end
        if self.host.resolveLayout then self.host:resolveLayout() end
    end
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
        if self.targetStepper then self.targetStepper:setValue(rule.minimum) end
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
    if self.newRuleStepper then self.newRuleStepper:setValue(20) end
end

function EmberRoutesStockRules:populateCombos(filterFullType)
    self.recipeCombo:clear()
    local added={}
    local targetType=filterFullType or (self.itemInput and self.itemInput:getText()) or ""

    if targetType~="" then
        local Catalog=require "EmberRoutesProbe/Crafting/CraftingCatalog"
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
    local recipeId=self.recipeCombo and self.recipeCombo:getSelectedData()
    local npcId=self.workerCombo and self.workerCombo:getSelectedData()
    local surfaceId=self.surfaceCombo and self.surfaceCombo:getSelectedData()
    local min=(self.newRuleStepper and self.newRuleStepper.value) or (self.store.value.newRule and self.store.value.newRule.minimum) or 20

    local formData={
        fullType=fullType,
        recipeId=recipeId,
        npcId=npcId,
        surfaceId=surfaceId,
        minimum=min
    }

    local ok,err=UI.validate(formData,CREATE_RULE_SCHEMA)
    if not ok then
        self.formNotice=text(err) or err
        return
    end

    local spec=Recipes.read(recipeId)
    local sig=spec and spec.signature or recipeId

    local id,createErr=StockStore.command(self.actor,self.entry.id,"create",{
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
        self.formNotice=tostring(createErr or text("error_create_failed"))
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

    if self.host then
        self.host:syncVisibility(value)
        self.host:resolveLayout()
    end

    local isDetail=(value.mode=="detail")
    if isDetail then
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
    if self.newRuleStepper and self.newRuleStepper.entry then
        local shown=tonumber(self.newRuleStepper.entry:getText())
        if shown~=min then self.newRuleStepper:setValue(min) end
    end
end

function EmberRoutesStockRules:prerender()
    ISPanel.prerender(self)
    local h,p=self.fontHeight,self.pad
    if self.titleBounds and self.titleBounds.visible then
        Theme.text(self,self.titleLabel or text("title"),self.titleBounds.x,self.titleBounds.y+math.floor((self.titleBounds.height-h)/2),Theme.textColor)
    end

    if self.detailBounds and self.detailBounds.visible then
        Theme.drawCard(self, self.detailBounds)
        local sel=self:getSelectedRule()
        if sel then
            local x=self.detailHeaderBounds.x
            local y=self.detailHeaderBounds.y
            local nameKey=sel.id..':'..sel.revision
            if self._nameKey~=nameKey then
                self._nameKey=nameKey
                local itemType=ScriptManager.instance:getItem(sel.fullType)
                self._nameText=itemType and itemType:getDisplayName() or sel.fullType
            end
            local name=self._nameText
            local draft=self.store.value.targetDraft or sel.minimum
            local cycle=sel.activeCycle
            local phase=cycle and cycle.phase

            if self._detailSel~=sel or self._detailRevision~=sel.revision
                or self._detailDraft~=draft or self._detailCount~=sel.knownCount
                or self._detailDeficit~=sel.deficit or self._detailNpc~=sel.npcId
                or self._detailRecipe~=sel.recipeId or self._detailCycle~=cycle
                or self._detailPhase~=phase or self._detailState~=sel.state
                or self._detailName~=name or self._detailH~=h then
                self._detailSel=sel self._detailRevision=sel.revision
                self._detailDraft=draft self._detailCount=sel.knownCount
                self._detailDeficit=sel.deficit self._detailNpc=sel.npcId
                self._detailRecipe=sel.recipeId self._detailCycle=cycle
                self._detailPhase=phase self._detailState=sel.state
                self._detailName=name self._detailH=h
                local badgeInfo=stateBadge(sel.state)
                self._detail={
                    nameText=name.." ("..sel.fullType..")",
                    targetText=getText("IGUI_EmberRoutesProbe_Stock_targetStockFormat",draft),
                    physicalText=getText("IGUI_EmberRoutesProbe_Stock_physicalCountFormat",sel.knownCount or 0),
                    deficitText=getText("IGUI_EmberRoutesProbe_Stock_deficitFormat",sel.deficit or 0),
                    workerText=getText("IGUI_EmberRoutesProbe_Stock_workerFormat",sel.npcId),
                    recipeText=getText("IGUI_EmberRoutesProbe_Stock_recipeFormat",sel.recipeId),
                    cycleText=cycle and getText("IGUI_EmberRoutesProbe_Stock_cycleFormat",cycle.taskId,cycle.phase) or nil,
                    badge=Visual.badge(badgeInfo[2],badgeInfo[1],math.floor(h*7),h,p/2)
                }
            end
            local d=self._detail
            Theme.text(self,d.nameText,x,y,Theme.textColor)
            Theme.text(self,d.targetText,x,y+h+math.floor(p/4),Theme.accent)

            Visual.drawBadge(self,x,y+h*2+math.floor(p/2),d.badge)

            local infoX=self.detailInfoBounds.x
            local infoY=self.detailInfoBounds.y
            Theme.text(self,d.physicalText,infoX,infoY,Theme.textColor)
            Theme.text(self,d.deficitText,infoX,infoY+h,Theme.muted)
            Theme.text(self,d.workerText,infoX,infoY+h*2,Theme.muted)
            Theme.text(self,d.recipeText,infoX,infoY+h*3,Theme.muted)

            if d.cycleText then
                Theme.text(self,d.cycleText,infoX,infoY+math.floor(h*4.5),Theme.accent)
            end

            local noteY=infoY+h*6
            Theme.text(self,text("notePhysical"),infoX,noteY,Theme.muted)
            Theme.text(self,text("noteReserved"),infoX,noteY+h,Theme.muted)
        end
    elseif self.newFormBounds and self.newFormBounds.visible then
        Theme.drawCard(self, self.newFormBounds)
        for k,lbl in pairs(self.formLabels or {}) do
            if k~="target" and lbl.visible then
                Theme.text(self,lbl.text,lbl.x,lbl.y+math.floor((lbl.height-h)/2),Theme.textColor)
            end
        end

        local fullType=self.itemInput and self.itemInput:getText() or ""
        if self._inputType~=fullType then
            self._inputType=fullType
            local itemObj=fullType~="" and ScriptManager.instance:getItem(fullType)
            self._inputText=itemObj and getText("IGUI_EmberRoutesProbe_Stock_selectedItemDisplay",itemObj:getDisplayName()) or nil
        end
        if self.itemHintBounds and self.itemHintBounds.visible then
            if self._inputText then
                Theme.text(self,self._inputText,self.itemHintBounds.x,self.itemHintBounds.y,Theme.accent)
            else
                Theme.text(self,text("hint_select_from_storage"),self.itemHintBounds.x,self.itemHintBounds.y,Theme.muted)
            end
        end

        if self.formLabels and self.formLabels.target and self.formLabels.target.visible then
            local minVal=self.store.value.newRule and self.store.value.newRule.minimum or 20
            if self._targetLabelFor~=minVal then
                self._targetLabelFor=minVal
                self._targetLabel=getText("IGUI_EmberRoutesProbe_Stock_targetStockFormatLabel",minVal)
            end
            Theme.text(self,self._targetLabel,self.formLabels.target.x,self.formLabels.target.y+math.floor((self.formLabels.target.height-h)/2),Theme.textColor)
        end

        if self.formNotice and self.formNoticeBounds and self.formNoticeBounds.visible then
            Theme.text(self,self.formNotice,self.formNoticeBounds.x,self.formNoticeBounds.y,Theme.accent)
        end
    end
end

return EmberRoutesStockRules
