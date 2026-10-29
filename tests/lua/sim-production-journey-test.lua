-- tests/lua/sim-production-journey-test.lua
-- Track B: 公共委托与生产监控全旅程 (Public Order & Production Journey)
-- 包含玩家操作全链路深度模拟与高保真验证测试

package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path

local checks=0
local function check(value,message)
    checks=checks+1
    assert(value,message)
end

-- =========================================================================
-- 1. ISUI & Host Environment Mock Harness
-- =========================================================================
package.loaded['ISUI/ISContextMenu']=true
ISContextMenu={get=function() return {addOption=function() end} end}

_G.Events=_G.Events or {}
for _,name in ipairs({'OnGameStart','OnServerStarted','OnTick','OnTickEvenPaused','OnPreMapLoad','OnSave'}) do
    _G.Events[name]={Add=function() end,Remove=function() end}
end

local Base={}
function Base:derive(name)
    local cls={Type=name}
    cls.__index=cls
    return setmetatable(cls,{__index=self})
end
function Base.new(self,x,y,w,h,title,target,callback)
    if type(self)~='table' then
        callback=target target=title title=h h=w w=y y=x x=self self=Base
    end
    local cls=self
    if type(x)=='table' and x.Type then
        cls=x
        x,y,w,h=y,w,h,title
        title,target,callback=target,callback,nil
    end
    return setmetatable({
        x=x or 0,y=y or 0,width=w or 0,height=h or 0,
        title=title or '',target=target,onclick=callback,
        children={},items={},selected=0,visible=true,enable=true
    },{__index=cls})
end
function Base:initialise()
    self.children={}
    self.initialised=true
end
function Base:instantiate()
    if self.native then return end
    self.native=true
    self:createChildren()
end
function Base:createChildren() end
function Base:addChild(child)
    check(child.initialised,'child initialized before mount')
    child.parent=self
    child:instantiate()
    self.children[#self.children+1]=child
end
function Base:addToUIManager() self:instantiate() self.added=true end
function Base:removeFromUIManager() self.added=false end
function Base:setVisible(v) self:instantiate() self.visible=v end
function Base:isVisible() return self.visible~=false end
function Base:close() self:setVisible(false) end
function Base:bringToTop() self.raised=true end
function Base:clear() self.items={} self.selected=0 end
function Base:titleBarHeight() return 24 end
function Base:setWantKeyEvents() end
function Base:update() end
function Base:prerender() end
function Base:getMouseX() return -1 end
function Base:getMouseY() return -1 end
function Base:setX(x) self.x=x end
function Base:setY(y) self.y=y end
function Base:setWidth(w) self.width=w end
function Base:setHeight(h) self.height=h end
function Base:getWidth() return self.width end
function Base:getHeight() return self.height end
function Base:getAbsoluteX() return self.x+(self.parent and self.parent:getAbsoluteX() or 0) end
function Base:getAbsoluteY() return self.y+(self.parent and self.parent:getAbsoluteY() or 0) end
function Base:setTitle(value) self.title=value end
function Base:setEnable(value) self.enable=value end
function Base:setOnMouseDownFunction(target,fn) self.target=target self.onclick=fn end
function Base:setOverrideAButtonFunction() end
function Base:setYScroll(value) self.scroll=value end
function Base:getYScroll() return self.scroll or 0 end
function Base:setScrollHeight(value) self.scrollHeight=value end
function Base:ensureVisible() end
function Base:drawText() end
function Base:drawRect() end
function Base:drawRectBorder() end
function Base:drawTextureScaledAspect() end
function Base:addItem(label,item,tooltip)
    local entry={text=label,item=item,tooltip=tooltip,height=self.itemheight or 20,index=#self.items+1}
    self.items[#self.items+1]=entry
    return entry
end

ISPanel=Base:derive('ISPanel')
ISCollapsableWindow=Base:derive('ISCollapsableWindow')
ISButton=Base:derive('ISButton')
ISScrollingListBox=Base:derive('ISScrollingListBox')

ISTextEntryBox=Base:derive('ISTextEntryBox')
function ISTextEntryBox:new(value,x,y,w,h)
    local o=Base.new(self,x,y,w,h)
    o.value=value or ''
    return o
end
function ISTextEntryBox:setPlaceholderText(value) self.placeholderText=value end
function ISTextEntryBox:setText(value)
    self.value=value
    if self.onTextChangeFunction then self.onTextChangeFunction(self.target) end
end
function ISTextEntryBox:getText() return self.value end
function ISTextEntryBox:isFocused() return self.focused==true end
function ISTextEntryBox:unfocus() self.focused=false end

ISComboBox=Base:derive('ISComboBox')
function ISComboBox:new(...)
    local o=Base.new(self,...)
    o.options={}
    o.selected=1
    return o
end
function ISComboBox:addOption(value) self.options[#self.options+1]=value end
function ISComboBox:clear() self.options={} self.selected=1 end
function ISComboBox:hidePopup() self.popupHidden=true end

ISModalDialog=Base:derive('ISModalDialog')
function ISModalDialog:new(x,y,w,h,text,yesno,target,onclick,player,param1,param2)
    local o=Base.new(self,x,y,w,h)
    o.text=text
    o.yesno=yesno
    o.target=target
    o.onclick=onclick
    o.player=player
    o.param1=param1
    o.param2=param2
    o.visible=true
    if yesno then
        local yes=ISButton:new(0,0,80,24,'Yes',o,ISModalDialog.onClick)
        yes.internal='YES'
        o.yes=yes
        local no=ISButton:new(0,0,80,24,'No',o,ISModalDialog.onClick)
        no.internal='NO'
        o.no=no
    else
        local ok=ISButton:new(0,0,80,24,'Ok',o,ISModalDialog.onClick)
        ok.internal='OK'
        o.ok=ok
    end
    return o
end
function ISModalDialog:destroy()
    self.visible=false
    self:removeFromUIManager()
end
function ISModalDialog:onClick(button)
    self:destroy()
    if self.onclick then
        self.onclick(self.target,button,self.param1,self.param2)
    end
end

for _,name in ipairs({'ISPanel','ISCollapsableWindow','ISButton','ISScrollingListBox','ISTextEntryBox','ISComboBox','ISModalDialog'}) do
    package.loaded['ISUI/'..name]=true
end

UIFont={Small=1}
Keyboard={KEY_UP=1,KEY_DOWN=2,KEY_ESCAPE=3,KEY_LEFT=4,KEY_RIGHT=5,KEY_TAB=6,KEY_RETURN=7}
Joypad={AButton=1,BButton=2,XButton=3,YButton=4}

local sw,sh,fh=1920,1080,20
function getCore() return {getScreenWidth=function() return sw end,getScreenHeight=function() return sh end} end
function getTextManager()
    return {
        getFontHeight=function() return fh end,
        MeasureStringX=function(_,_,s)
            s=tostring(s or '')
            local w=0
            local i=1
            local n=#s
            while i<=n do
                local b=s:byte(i)
                if b<128 then
                    w=w+fh*0.35
                    i=i+1
                elseif b<224 then
                    w=w+fh*0.60
                    i=i+2
                elseif b<240 then
                    w=w+fh*0.65
                    i=i+3
                else
                    w=w+fh*0.70
                    i=i+4
                end
            end
            return w
        end
    }
end

local fallbackTranslations={
    IGUI_EmberRoutesProbe_Public_createOrder='创建工单',
    IGUI_EmberRoutesProbe_Public_tab_order='单次委托',
    IGUI_EmberRoutesProbe_Public_tab_stock='维持存量',
    IGUI_EmberRoutesProbe_Public_submit='创建工单',
    IGUI_EmberRoutesProbe_Public_submitting='提交中...',
    IGUI_EmberRoutesProbe_Public_saveRule='保存补货规则',
    IGUI_EmberRoutesProbe_Public_targetQuantity='目标成品数',
    IGUI_EmberRoutesProbe_Public_stockThreshold='存量阈值',
    IGUI_EmberRoutesProbe_Public_stockBatch='补货批量',
    IGUI_EmberRoutesProbe_Public_recipeSelect='制作配方',
    IGUI_EmberRoutesProbe_Public_surfaceSelect='制作设施',
    IGUI_EmberRoutesProbe_Public_noSurface='徒手制作',
    IGUI_EmberRoutesProbe_Public_surfaceAt='工作台 (%1, %2, %3)',
    IGUI_EmberRoutesProbe_Public_previous='上一页',
    IGUI_EmberRoutesProbe_Public_next='下一页',
    IGUI_EmberRoutesProbe_Public_chooseRecipe='请选择一个配方开始生产',
    IGUI_EmberRoutesProbe_Public_blueprintTitle='工单生产蓝图',
    IGUI_EmberRoutesProbe_Public_outputHeading='最终产出',
    IGUI_EmberRoutesProbe_Public_materialsHeading='消耗原料',
    IGUI_EmberRoutesProbe_Public_toolsHeading='生产工具',
    IGUI_EmberRoutesProbe_Public_statusChecking='正在核对物料与设施...',
    IGUI_EmberRoutesProbe_Public_statusReady='原料就绪',
    IGUI_EmberRoutesProbe_Public_statusShortage='物料短缺',
    IGUI_EmberRoutesProbe_Public_statusChain='多步生产链已就绪',
    IGUI_EmberRoutesProbe_Public_batchCount='单批产出 %1 件 · 需执行 %2 批次',
    IGUI_EmberRoutesProbe_Public_chainSupplyTag='内部链供应',
    IGUI_EmberRoutesProbe_Public_ORDER_CREATED='工单已下发至公共委托池',
    IGUI_EmberRoutesProbe_Public_RULE_SAVED='补货规则已保存',
    IGUI_EmberRoutesProbe_Public_NO_CAPACITY='委托池已满，暂无法接收新工单',
    IGUI_EmberRoutesProbe_Monitor_crafting='制作任务',
    IGUI_EmberRoutesProbe_Monitor_hauling='搬运任务',
    IGUI_EmberRoutesProbe_Monitor_button_stop='暂停',
    IGUI_EmberRoutesProbe_Monitor_button_resume='继续',
    IGUI_EmberRoutesProbe_Monitor_button_return='取消',
    IGUI_EmberRoutesProbe_Monitor_filter_open='进行中',
    IGUI_EmberRoutesProbe_Monitor_details='详情',
    IGUI_EmberRoutesProbe_Monitor_refresh='刷新',
    IGUI_EmberRoutesProbe_Monitor_selectOrder='请选择一个工单查看监控详情',
    IGUI_EmberRoutesProbe_Monitor_empty='当前无工单记录',
    IGUI_EmberRoutesProbe_Monitor_haulRecovery='取消后将执行物料原路回退',
    IGUI_EmberRoutesProbe_Crafting_readyBadge='[已备齐]',
    IGUI_EmberRoutesProbe_Crafting_shortageBadge='[短缺]',
    IGUI_EmberRoutesProbe_Crafting_toolBadge='[工具]',
    IGUI_EmberRoutesProbe_Crafting_quantityHint='输入期望产出成品数，自动换算批次',
    IGUI_EmberRoutesProbe_Crafting_stepFinal='第 %1 步（最终产出）',
    IGUI_EmberRoutesProbe_Crafting_stepPrecursor='第 %1 步（中间体）',
    IGUI_EmberRoutesProbe_Crafting_badgeSurface='工作台',
    IGUI_EmberRoutesProbe_Crafting_badgeHand='手工徒手',
    IGUI_EmberRoutesProbe_Crafting_planOutput='预计产出: %1 件',
    IGUI_EmberRoutesProbe_Crafting_toolAlternatives='可选替代: %1',
    IGUI_EmberRoutesProbe_Crafting_chainPlanHeading='生产链规划 (%1 步)'
}

function getTextOrNull(key)
    return (ERTestTranslations and ERTestTranslations[key]) or fallbackTranslations[key]
end

function getText(key,...)
    local val=getTextOrNull(key) or key
    for i,arg in ipairs({...}) do
        val=val:gsub('%%'..i,function() return tostring(arg) end)
    end
    return val
end

local itemDisplayNames={
    ['Base.Log']='原木',
    ['Base.Plank']='木板',
    ['Base.Saw']='手锯',
    ['Base.WoodenFork']='雕刻木叉',
    ['Base.TreeBranch']='树枝',
    ['Base.Nails']='铁钉',
    ['Base.Woodglue']='木工胶'
}
function getItemNameFromFullType(id) return itemDisplayNames[id] or id end
function getTexture() return {} end
function getScriptManager() return {FindItem=function() end} end
function getCell() return {} end
function isClient() return false end
function isServer() return false end

local actor={
    getIndex=function() return 0 end,
    getJoypadBind=function() return -1 end,
    Say=function() end
}
function getSpecificPlayer() return actor end

-- =========================================================================
-- 2. Service & Backend Mocks
-- =========================================================================
local requestIdCounter=0
package.loaded['EmberRoutesProbe/ContainerRegistry']={
    id=function()
        requestIdCounter=requestIdCounter+1
        return 'req-'..tostring(requestIdCounter)
    end,
    data=function() return {} end
}

local registeredSurfaces={{id='bench-carpentry',x=12,y=24,z=0}}
package.loaded['EmberRoutesProbe/CraftSurfaces']={
    list=function() return registeredSurfaces end
}

local sawLogsSpec={
    id='Base.SawLogs',
    name='锯原木',
    product='Base.Plank',
    yield=3,
    resultCount=3,
    category='Carpentry',
    inputs={
        {slot=0,count=1,keep=false,names={'原木'},choices={{name='原木',fullType='Base.Log'}}},
        {slot=1,count=1,keep=true,names={'手锯'},choices={{name='手锯',fullType='Base.Saw'}}}
    },
    outputs={{name='木板',fullType='Base.Plank',count=3}}
}

local carveForkSpec={
    id='Base.CarveWoodenFork',
    name='雕刻木叉',
    product='Base.WoodenFork',
    yield=1,
    resultCount=1,
    category='Carving',
    inputs={
        {slot=0,count=1,keep=false,names={'树枝'},choices={{name='树枝',fullType='Base.TreeBranch'}}}
    },
    outputs={{name='木叉',fullType='Base.WoodenFork',count=1}}
}

local catalogRecipes={sawLogsSpec,carveForkSpec}

package.loaded['EmberRoutesProbe/ProductionRecipe']={
    read=function(id)
        if id=='Base.SawLogs' then return sawLogsSpec end
        if id=='Base.CarveWoodenFork' then return carveForkSpec end
        return nil
    end,
    describe=function(spec) return spec end
}

package.loaded['EmberRoutesProbe/CraftingCatalog']={
    productionIndex=function()
        local byId,byType={},{}
        for _,rec in ipairs(catalogRecipes) do
            byId[rec.id]=rec
            if rec.product then
                byType[rec.product]=byType[rec.product] or {}
                table.insert(byType[rec.product],rec)
            end
        end
        return byId,byType
    end
}

local catalogCallbacks={}
package.loaded['EmberRoutesProbe/CraftingService']={
    status=function() return {workers={{id='npc-bob',name='Bob'}},surfaces=registeredSurfaces} end,
    watchCatalog=function(pActor,scope,q,callback)
        catalogCallbacks[#catalogCallbacks+1]=callback
        local matched={}
        local s=(q.search or ''):lower()
        for _,rec in ipairs(catalogRecipes) do
            local pName=getItemNameFromFullType(rec.product):lower()
            if s=='' or rec.name:lower():find(s,1,true) or rec.product:lower():find(s,1,true) or pName:find(s,1,true) then
                matched[#matched+1]=rec
            end
        end
        callback({
            rows=matched,
            categories={'Carpentry','Carving'},
            page=1,
            pages=1,
            total=#matched
        })
        return function() end
    end
}

local previewCallback
package.loaded['EmberRoutesProbe/PublicPreview']={
    watch=function(pActor,scope,recipeId,quantity,surfaceId,callback,preferences)
        previewCallback=callback
        local units=math.ceil((quantity or 1)/3)
        callback({
            state='READY',
            conditions={},
            counts={
                [0]={fullType='Base.Log',available=20,required=units},
                [1]={fullType='Base.Saw',available=2,required=1}
            }
        })
        return function() end
    end
}

local publicCreateCalls={}
local publicRuleCalls={}
local publicRules={
    ['Base.Plank']={minimum=30,batch=15}
}
package.loaded['EmberRoutesProbe/PublicWork']={
    available=function() return true end,
    requestId=function()
        return package.loaded['EmberRoutesProbe/ContainerRegistry'].id()
    end,
    rule=function(scope,product)
        return publicRules[product]
    end,
    create=function(pActor,scope,recipeId,qty,surfaceId,reqId,prefs)
        publicCreateCalls[#publicCreateCalls+1]={
            actor=pActor,scope=scope,recipeId=recipeId,
            qty=qty,surfaceId=surfaceId,requestId=reqId,preferences=prefs
        }
        return 'ORDER_CREATED'
    end,
    saveRule=function(pActor,scope,recipeId,minVal,batchVal,surfaceId,prefs)
        publicRuleCalls[#publicRuleCalls+1]={
            actor=pActor,scope=scope,recipeId=recipeId,
            minimum=minVal,batch=batchVal,surfaceId=surfaceId,preferences=prefs
        }
        return 'RULE_SAVED'
    end
}

local monitorCommands={}
local monitorSnapshot={rows={}}
local monitorWatchers={}
package.loaded['EmberRoutesProbe/OrderMonitorService']={
    status=function() return monitorSnapshot end,
    watch=function(pActor,scope,callback)
        monitorWatchers[#monitorWatchers+1]=callback
        callback(monitorSnapshot)
        return function() end
    end,
    command=function(pActor,scope,id,gen,action)
        monitorCommands[#monitorCommands+1]={
            actor=pActor,scope=scope,id=id,generation=gen,action=action
        }
        return 'QUEUED'
    end
}

-- Require UI classes under test
local PublicOrderDialog=require 'EmberRoutesProbe/UI/PublicOrderDialog'
local OrderMonitorCards=require 'EmberRoutesProbe/UI/OrderMonitorCards'
local OrderMonitorPage=require 'EmberRoutesProbe/UI/OrderMonitorPage'

-- Create Dashboard Owner
local owner={
    actor=actor,
    entry={id='settlement-alpha',name='Alpha Settlement'},
    fontHeight=20,
    pad=10,
    activeTab='warehouse',
    valid=function() return true end,
    selectTab=function(self,tab)
        self.activeTab=tab
        if self.pages and self.pages[tab] then
            self.pages[tab].active=true
            self.pages[tab]:activate()
        end
    end,
    openPublicOrder=function(self,ctx)
        return PublicOrderDialog.open(self,ctx)
    end,
    close=function(self) self.disposed=true end
}

print('>>> Starting Track B: Public Order & Production Journey Full Simulation <<<')

-- =========================================================================
-- Scenario 1: 公共委托弹窗开启与上下文注入 (Context Injection & Singleton Guard)
-- =========================================================================
print('--- Scenario 1: Dialog Open & Context Injection ---')

-- 1.1 Context Injection: Recipe ID & Surface ID
local dialog1=PublicOrderDialog.open(owner,{
    recipeId='Base.SawLogs',
    surfaceId='bench-carpentry'
})
check(owner.publicDialog==dialog1,'dialog registered to owner')
check(dialog1.selectedRecipe=='Base.SawLogs','recipe Base.SawLogs preselected from context')
check(dialog1.surfaceCombo.selected==2,'surface bench-carpentry preselected from context')
check(dialog1.activeTab=='order','default tab is order')
check(#dialog1.blueprintList.items>=1,'blueprint list populated on initial open')

-- 1.2 Context Injection: Product Type Pre-filling Search Box
dialog1:close()
check(owner.publicDialog==nil,'closed dialog removes owner reference')

local dialog2=PublicOrderDialog.open(owner,{
    productType='Base.Plank'
})
check(dialog2.search:getText()=='木板','productType Base.Plank pre-fills search entry with item display name')

-- 1.3 Singleton Guard: Calling open again brings existing instance to top
local dialogAgain=PublicOrderDialog.open(owner)
check(dialogAgain==dialog2,'dialog.open returns existing instance without duplicate')
check(dialog2.raised==true,'existing dialog received bringToTop()')

-- =========================================================================
-- Scenario 2: 标签页切换与步进器操作 (Tab Switch & Stepper Boundaries)
-- =========================================================================
print('--- Scenario 2: Tab Switching & Stepper Operations ---')

local dialog=dialog2
dialog:selectTab('order')
check(dialog.activeTab=='order','activeTab switched to order')
check(dialog.quantity:isVisible()==true,'quantity box visible in order mode')
check(dialog.qStepDec5:isVisible()==true,'qStepDec5 visible in order mode')
check(dialog.qStepDec1:isVisible()==true,'qStepDec1 visible in order mode')
check(dialog.qStepInc1:isVisible()==true,'qStepInc1 visible in order mode')
check(dialog.qStepInc5:isVisible()==true,'qStepInc5 visible in order mode')
check(dialog.minimum:isVisible()==false,'minimum box hidden in order mode')
check(dialog.batch:isVisible()==false,'batch box hidden in order mode')
check(dialog.actionButton.title==getText('IGUI_EmberRoutesProbe_Public_submit'),'action button titled submit')

-- Stepper Operations in Order mode
dialog.quantity:setText('1')
dialog.qStepInc1.onclick()
check(dialog.quantity:getText()=='2','+1 stepper increments 1 -> 2')
dialog.qStepInc5.onclick()
check(dialog.quantity:getText()=='7','+5 stepper increments 2 -> 7')
dialog.qStepDec1.onclick()
check(dialog.quantity:getText()=='6','-1 stepper decrements 7 -> 6')
dialog.qStepDec5.onclick()
check(dialog.quantity:getText()=='1','-5 stepper decrements 6 -> 1')

-- Boundary Clamping: Cannot decrement below 1
dialog.qStepDec5.onclick()
check(dialog.quantity:getText()=='1','-5 stepper clamped at minimum boundary 1')
dialog.qStepDec1.onclick()
check(dialog.quantity:getText()=='1','-1 stepper clamped at minimum boundary 1')

-- Maximum Boundary Clamping (9999)
dialog.quantity:setText('9998')
dialog.qStepInc5.onclick()
check(dialog.quantity:getText()=='9999','+5 stepper clamped at maximum boundary 9999')

-- Switch to Maintain Stock (维持存量) Tab
dialog:selectTab('stock')
check(dialog.activeTab=='stock','activeTab switched to stock')
check(dialog.quantity:isVisible()==false,'quantity box hidden in stock mode')
check(dialog.minimum:isVisible()==true,'minimum box visible in stock mode')
check(dialog.batch:isVisible()==true,'batch box visible in stock mode')
check(dialog.minStepDec5:isVisible()==true,'min steppers visible')
check(dialog.bStepInc10:isVisible()==true,'batch steppers visible')
check(dialog.actionButton.title==getText('IGUI_EmberRoutesProbe_Public_saveRule'),'action button titled saveRule')

-- Steppers in Stock mode: minimum threshold (min boundary = 0)
dialog.minimum:setText('0')
dialog.minStepInc1.onclick()
check(dialog.minimum:getText()=='1','minimum +1: 0 -> 1')
dialog.minStepInc5.onclick()
check(dialog.minimum:getText()=='6','minimum +5: 1 -> 6')
dialog.minStepDec1.onclick()
check(dialog.minimum:getText()=='5','minimum -1: 6 -> 5')
dialog.minStepDec5.onclick()
check(dialog.minimum:getText()=='0','minimum -5: 5 -> 0')
dialog.minStepDec5.onclick()
check(dialog.minimum:getText()=='0','minimum -5 clamped at 0')

-- Steppers in Stock mode: batch size (min boundary = 1)
dialog.batch:setText('10')
dialog.bStepInc10.onclick()
check(dialog.batch:getText()=='20','batch +10: 10 -> 20')
dialog.bStepInc5.onclick()
check(dialog.batch:getText()=='25','batch +5: 20 -> 25')
dialog.bStepDec5.onclick()
check(dialog.batch:getText()=='20','batch -5: 25 -> 20')
dialog.bStepDec10.onclick()
check(dialog.batch:getText()=='10','batch -10: 20 -> 10')
dialog.bStepDec10.onclick()
check(dialog.batch:getText()=='1','batch -10 clamped at min boundary 1')

-- =========================================================================
-- Scenario 3: 成品量 vs 配方执行次数智能换算看板 (Smart Conversion Board)
-- =========================================================================
print('--- Scenario 3: Target Output vs Execution Count Conversion Board ---')

dialog:selectTab('order')
-- Choose SawLogs (yield = 3 planks per log)
dialog.rows={sawLogsSpec,carveForkSpec}
dialog.recipeCombo.selected=1
dialog.selectedRecipe='Base.SawLogs'
dialog.currentSpec=sawLogsSpec

-- 3.1 Target = 1 -> Executions = 1, Expected = 3, Surplus = 2
dialog.quantity:setText('1')
dialog:updateConversion()
check(dialog.conversion~=nil,'conversion table calculated')
check(dialog.conversion.resultCount==3,'recipe resultCount is 3')
check(dialog.conversion.targetQty==1,'target need is 1')
check(dialog.conversion.executions==1,'required executions ceil(1/3) is 1')
check(dialog.conversion.expectedOutput==3,'expected output is 3')
check(dialog.conversion.surplus==2,'surplus is 2')
check(dialog.conversionFull:find('单次配方产出: 3 件',1,true)~=nil,'conversion full contains per batch output 3')
check(dialog.conversionFull:find('目标需求: 1 件',1,true)~=nil,'conversion full contains target need 1')
check(dialog.conversionFull:find('需执行配方: 1 次',1,true)~=nil,'conversion full contains executions 1')
check(dialog.conversionFull:find('预计实际产出: 3 件 (富余 2 件)',1,true)~=nil,'conversion full contains expected 3 and surplus 2')

-- 3.2 Target = 5 -> Executions = 2, Expected = 6, Surplus = 1
dialog.quantity:setText('5')
dialog:updateConversion()
check(dialog.conversion.targetQty==5,'target need is 5')
check(dialog.conversion.executions==2,'required executions ceil(5/3) is 2')
check(dialog.conversion.expectedOutput==6,'expected output is 6')
check(dialog.conversion.surplus==1,'surplus is 1')
check(dialog.conversionFull:find('目标需求: 5 件 => 需执行配方: 2 次 | 预计实际产出: 6 件 (富余 1 件)',1,true)~=nil,
    'conversion full text accurate for target 5')

-- 3.3 Target = 9 -> Executions = 3, Expected = 9, Surplus = 0
dialog.quantity:setText('9')
dialog:updateConversion()
check(dialog.conversion.targetQty==9,'target need is 9')
check(dialog.conversion.executions==3,'required executions ceil(9/3) is 3')
check(dialog.conversion.expectedOutput==9,'expected output is 9')
check(dialog.conversion.surplus==0,'surplus is 0')
check(dialog.conversionFull:find('目标需求: 9 件 => 需执行配方: 3 次 | 预计实际产出: 9 件 (富余 0 件)',1,true)~=nil,
    'conversion full text accurate for target 9')

-- 3.4 In Maintain Stock mode: Batch = 10 -> Executions = 4, Expected = 12, Surplus = 2
dialog:selectTab('stock')
dialog.batch:setText('10')
dialog:updateConversion()
check(dialog.conversion.targetQty==10,'stock batch target is 10')
check(dialog.conversion.executions==4,'stock executions ceil(10/3) is 4')
check(dialog.conversion.expectedOutput==12,'stock expected output is 12')
check(dialog.conversion.surplus==2,'stock surplus is 2')
check(dialog.conversionFull:find('补货批量: 10 件',1,true)~=nil,'conversion displays 补货批量 in stock mode')

-- =========================================================================
-- Scenario 4: 防连击防抖与提交锁定 (Debounce & Submit Lock)
-- =========================================================================
print('--- Scenario 4: Debounce & Submit Lock ---')

dialog:selectTab('order')
dialog.quantity:setText('5')
dialog.recipeCombo.selected=1
dialog.selectedRecipe='Base.SawLogs'

local initialCreateCount=#publicCreateCalls
local interceptCheckPassed=false

-- Override Public.create to simulate network latency and verify lock
local originalCreate=package.loaded['EmberRoutesProbe/PublicWork'].create
package.loaded['EmberRoutesProbe/PublicWork'].create=function(pActor,scope,recipeId,qty,surfaceId,reqId,prefs)
    -- Verify lock state inside in-flight request
    check(dialog.submitting==true,'dialog.submitting flag is true during request')
    check(dialog.actionButton.title=='提交中...','button title changed to 提交中...')
    check(dialog.actionButton.enable==false,'action button is disabled during request')

    -- Simulate aggressive player spamming: 5 button clicks + 5 Enter presses while submitting
    for i=1,5 do
        dialog.actionButton:onclick()
    end
    for i=1,5 do
        dialog:onKeyPress(Keyboard.KEY_RETURN)
    end

    interceptCheckPassed=true
    return 'ORDER_CREATED'
end

-- Trigger submission
dialog.actionButton:onclick()

check(interceptCheckPassed,'latency intercept block executed')
check(#publicCreateCalls==initialCreateCount,'underlying backend request strictly dispatched only once')
check(dialog.submitting==false,'submitting flag reset after completion')
check(owner.activeTab=='orders','successful submission navigates owner to orders tab')
check(dialog.disposed==true,'successful submission closes the dialog')

-- Restore Public.create
package.loaded['EmberRoutesProbe/PublicWork'].create=originalCreate

-- 4.2 Error Recovery: Failure does not close dialog and restores controls
local dialogFail=PublicOrderDialog.open(owner,{recipeId='Base.SawLogs'})
dialogFail.quantity:setText('3')
package.loaded['EmberRoutesProbe/PublicWork'].create=function()
    return 'NO_CAPACITY'
end

dialogFail.actionButton:onclick()
check(dialogFail.submitting==false,'submitting flag reset after failure')
check(dialogFail.disposed~=true,'dialog remains open after failure')
check(dialogFail.actionButton.title==getText('IGUI_EmberRoutesProbe_Public_submit'),'action button title restored to submit')
check(dialogFail.actionButton.enable==true,'action button re-enabled after failure')
check(dialogFail.notice=='委托池已满，暂无法接收新工单','notice displays translated error reason')

dialogFail:close()
package.loaded['EmberRoutesProbe/PublicWork'].create=originalCreate

-- =========================================================================
-- Scenario 5: 生产工单监控 (Order Monitor - 4 Discrete Stages & BOM Drawer)
-- =========================================================================
print('--- Scenario 5: Order Monitor 4-Stage Track & BOM Drawer ---')

local function makeStr(codepoints, utf8bytes)
    local ok, str = pcall(string.char, unpack(codepoints))
    if ok and str and #str == #codepoints then return str end
    return utf8bytes
end

local ICON_DONE = makeStr({10004}, '✔')
local ICON_ACTIVE = makeStr({9679}, '●')
local ICON_WAIT = makeStr({9675}, '○')
local ARROW_WIDE = makeStr({32, 8594, 32}, ' → ')
local BOX_BRANCH = makeStr({9500, 9472, 9472, 32}, '├── ')
local BOX_CORNER = makeStr({9492, 9472, 9472, 32}, '└── ')

local sXunYuan = makeStr({23547, 28304}, '寻源')
local sBeiLiao = makeStr({22791, 26009}, '备料')
local sZhiZuo = makeStr({21046, 20316}, '制作')
local sRuKu = makeStr({20837, 24211}, '入库')

-- Mount OrderMonitorPage
local monitorPage=OrderMonitorPage:new(owner,{x=0,y=0,width=1000,height=600})
monitorPage:initialise()
monitorPage:createChildren()
monitorPage:activate()

-- 5.1 Discrete 4-Stage Tracks
-- Stage 1: 规划阶段 (Planning / WAITING_CLAIM)
local rowStage1={
    id='CRAFT:order-1',kind='CRAFT',name='Bob',title='制作木板',
    state='WAITING',phase='PLANNING',bodyMode='PLANNING',bucket='waiting',
    target=4,produced=0,delivered=0
}
check(OrderMonitorCards.phaseIndex(rowStage1)==1,'phase index for stage 1 is 1')
-- Verify Tier 1 (full width with numbering)
local trackSegs1,trackText1=OrderMonitorCards.buildPhaseTrack(rowStage1,800)
check(trackText1:find(ICON_ACTIVE..' 1.'..sXunYuan,1,true)~=nil,'stage 1 tier 1 has active ● 1.寻源')
check(trackText1:find(ICON_WAIT..' 2.'..sBeiLiao,1,true)~=nil,'stage 1 tier 1 has waiting ○ 2.备料')
check(trackText1:find(ICON_WAIT..' 3.'..sZhiZuo,1,true)~=nil,'stage 1 tier 1 has waiting ○ 3.制作')
check(trackText1:find(ICON_WAIT..' 4.'..sRuKu,1,true)~=nil,'stage 1 tier 1 has waiting ○ 4.入库')
check(trackSegs1[1].color.r==1.0,'node 1 active gold/orange color')

-- Verify Tier 2 (compact without numbering)
local _,trackText1Compact=OrderMonitorCards.buildPhaseTrack(rowStage1,320)
check(trackText1Compact:find(ICON_ACTIVE..' '..sXunYuan..ARROW_WIDE..ICON_WAIT..' '..sBeiLiao..ARROW_WIDE..ICON_WAIT..' '..sZhiZuo..ARROW_WIDE..ICON_WAIT..' '..sRuKu,1,true)~=nil,
    'stage 1 tier 2 compact: [● 寻源] → [○ 备料] → [○ 制作] → [○ 入库]')

-- Stage 2: 备料阶段 (Staging / COLLECTING)
local rowStage2={
    id='CRAFT:order-2',kind='CRAFT',name='Bob',title='制作木板',
    state='RUNNING',phase='COLLECTING',bodyMode='COLLECT',bucket='active'
}
check(OrderMonitorCards.phaseIndex(rowStage2)==2,'phase index for stage 2 is 2')
local _,trackText2Compact=OrderMonitorCards.buildPhaseTrack(rowStage2,320)
check(trackText2Compact:find(ICON_DONE..' '..sXunYuan..ARROW_WIDE..ICON_ACTIVE..' '..sBeiLiao..ARROW_WIDE..ICON_WAIT..' '..sZhiZuo..ARROW_WIDE..ICON_WAIT..' '..sRuKu,1,true)~=nil,
    'stage 2 tier 2 compact: [✔ 寻源] → [● 备料] → [○ 制作] → [○ 入库]')

-- Stage 3: 制作阶段 (Crafting / CRAFTING with 75% progress)
local rowStage3={
    id='CRAFT:order-3',kind='CRAFT',name='Bob',title='制作木板',
    state='RUNNING',phase='CRAFTING',bodyMode='CRAFTING',bucket='active',
    target=4,produced=3,delivered=0,progressPercent=75,useColonProgress=true
}
check(OrderMonitorCards.phaseIndex(rowStage3)==3,'phase index for stage 3 is 3')
local _,trackText3Compact=OrderMonitorCards.buildPhaseTrack(rowStage3,320)
check(trackText3Compact:find(ICON_DONE..' '..sXunYuan..ARROW_WIDE..ICON_DONE..' '..sBeiLiao..ARROW_WIDE..ICON_ACTIVE..' '..sZhiZuo..': 75%'..ARROW_WIDE..ICON_WAIT..' '..sRuKu,1,true)~=nil,
    'stage 3 tier 2 compact: [✔ 寻源] → [✔ 备料] → [● 制作: 75%] → [○ 入库]')

-- Stage 4: 入库阶段 (Warehousing / STORING)
local rowStage4={
    id='CRAFT:order-4',kind='CRAFT',name='Bob',title='制作木板',
    state='RUNNING',phase='STORING',bodyMode='RETURNING',bucket='active'
}
check(OrderMonitorCards.phaseIndex(rowStage4)==4,'phase index for stage 4 is 4')
local _,trackText4Compact=OrderMonitorCards.buildPhaseTrack(rowStage4,320)
check(trackText4Compact:find(ICON_DONE..' '..sXunYuan..ARROW_WIDE..ICON_DONE..' '..sBeiLiao..ARROW_WIDE..ICON_DONE..' '..sZhiZuo..ARROW_WIDE..ICON_ACTIVE..' '..sRuKu,1,true)~=nil,
    'stage 4 tier 2 compact: [✔ 寻源] → [✔ 备料] → [✔ 制作] → [● 入库]')

-- Stage 5: 交付完毕 (Completed / DONE / Closed)
local rowStage5={
    id='CRAFT:order-5',kind='CRAFT',name='Bob',title='制作木板',
    state='DONE',closed=true,bucket='closed'
}
check(OrderMonitorCards.phaseIndex(rowStage5)==5,'phase index for stage 5 is 5')
local _,trackText5=OrderMonitorCards.buildPhaseTrack(rowStage5,800)
local _,trackText5Compact=OrderMonitorCards.buildPhaseTrack(rowStage5,320)
check(trackText5Compact:find(ICON_DONE..' '..sXunYuan..ARROW_WIDE..ICON_DONE..' '..sBeiLiao..ARROW_WIDE..ICON_DONE..' '..sZhiZuo..ARROW_WIDE..ICON_DONE..' '..sRuKu,1,true)~=nil,
    'stage 5 tier 2 compact: [✔ 寻源] → [✔ 备料] → [✔ 制作] → [✔ 入库]')
check(trackText5:find(ICON_DONE..' 1.'..sXunYuan,1,true)~=nil and trackText5:find(ICON_DONE..' 2.'..sBeiLiao,1,true)~=nil
    and trackText5:find(ICON_DONE..' 3.'..sZhiZuo,1,true)~=nil and trackText5:find(ICON_DONE..' 4.'..sRuKu,1,true)~=nil,
    'stage 5 has all 4 nodes checked ✔')

-- 5.2 BOM Drawer Verification
local rowBomOrder={
    id='CRAFT:order-bom',
    kind='CRAFT',
    name='Bob',
    title='制作强化木板',
    state='RUNNING',
    phase='CRAFTING',
    target=10,
    produced=2,
    delivered=0,
    chainIndex=2,
    nodes={
        {name='原木加工',product='Base.Log',requested=5},
        {name='精细锯切',product='Base.Plank',requested=10}
    },
    assets={
        {fullType='Base.Plank',kind='outputs',delivered=true},
        {fullType='Base.Log',kind='held',delivered=false},
        {fullType='Base.Nails',kind='materials',delivered=false},
        {fullType='Base.Woodglue',kind='cargo',delivered=false}
    }
}

monitorPage.details:set(rowBomOrder)
local detailLines=monitorPage.details.list.items
check(#detailLines>0,'detail lines populated')

local foundStored,foundProcessing,foundMissing,foundTransit=false,false,false,false
local foundLadderPrefix=false

for _,entry in ipairs(detailLines) do
    local txt=entry.text or ''
    if txt:find(BOX_BRANCH,1,true) or txt:find(BOX_CORNER,1,true) then
        foundLadderPrefix=true
    end
    if txt:find('STORED',1,true) then foundStored=true end
    if txt:find('PROCESSING',1,true) then foundProcessing=true end
    if txt:find('MISSING',1,true) then foundMissing=true end
    if txt:find('TRANSIT',1,true) then foundTransit=true end
end

check(foundLadderPrefix,'BOM topology ladder prefix ├── or └── rendered')
check(foundStored,'BOM four-state badge [STORED] rendered')
check(foundProcessing,'BOM four-state badge [PROCESSING] rendered')
check(foundTransit,'BOM four-state badge [TRANSIT] rendered')

-- =========================================================================
-- Scenario 6: 防误触取消确认弹窗 (Cancel Safeguard Modal)
-- =========================================================================
print('--- Scenario 6: Cancel Safeguard Modal ---')

local inProgressOrder={
    id='CRAFT:cancel-safe-order',
    generation=12,
    kind='CRAFT',
    name='Alice',
    title='批量制作木板',
    state='RUNNING',
    phase='CRAFTING',
    target=10,
    produced=3,
    delivered=0,
    canCancel=true
}

monitorSnapshot={rows={inProgressOrder}}
monitorPage.store:setState({snapshot=monitorSnapshot,selection=inProgressOrder.id})
check(monitorPage.selected~=nil,'in-progress order selected')
check(monitorPage.buttons['return'].enable==true,'return/cancel button enabled')

local initialCommands=#monitorCommands

-- 6.1 Player clicks Return (Cancel) button
monitorPage.buttons['return']:onclick()

check(monitorPage.cancelModal~=nil,'ISModalDialog cancel confirmation modal popped up')
check(monitorPage.cancelModal.visible==true,'modal is visible')
local expectedMsg='确定要取消该工单吗？当前已制成 3 件将安全入库，未用原料将由搬运工送回原箱。'
check(monitorPage.cancelModal.text==expectedMsg,'modal prompt message matches cancel policy')
check(#monitorCommands==initialCommands,'order is NOT cancelled yet while modal is open')

-- 6.2 Player clicks "No" (取消) on modal dialog
local modalInstance=monitorPage.cancelModal
modalInstance:onClick(modalInstance.no)

check(monitorPage.cancelModal==nil,'modal destroyed and cleared')
check(#monitorCommands==initialCommands,'order cancellation command strictly NOT issued on No')
check(monitorPage.selected.id==inProgressOrder.id,'order remains intact and active in page')

-- 6.3 Player clicks Return again, then clicks "Yes" (确定)
monitorPage.buttons['return']:onclick()
check(monitorPage.cancelModal~=nil,'modal opened again')
local modalInstance2=monitorPage.cancelModal
modalInstance2:onClick(modalInstance2.yes)

check(monitorPage.cancelModal==nil,'modal closed on Yes')
check(#monitorCommands==initialCommands+1,'cancel command officially dispatched')
check(monitorCommands[#monitorCommands].id==inProgressOrder.id,'command target matches order ID')
check(monitorCommands[#monitorCommands].generation==12,'command generation matches order revision')
check(monitorCommands[#monitorCommands].action=='return','action is return')

print('PASS '..checks..' Track B Public Order & Production Journey simulated player checks completely succeeded!')
