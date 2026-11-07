local PreviewLayoutArrow=require 'preview/layout-assets'
require 'env'
require 'ISUI/ISPanel'
local Host=require 'EmberRoutesProbe/UI/LayoutHost'
local Controls=require 'EmberRoutesProbe/UI/WarehouseControls'
local Lifecycle=require 'EmberRoutesProbe/UI/PageLifecycle'
local Tooltip=require 'EmberRoutesProbe/UI/TooltipManager'
local Solver=require 'EmberRoutesProbe/UI/LayoutSolver'
local Node=require 'EmberRoutesProbe/UI/LayoutNode'
local width=math.min(880,getCore():getScreenWidth()-80)
NativePreview=ISPanel:new(36,110,width,370)
NativePreview:initialise(); NativePreview:instantiate()
NativePreview.pad=12; NativePreview.store={value={selection={fullType='Base.Nails'}}}
NativePreview.changed=0; NativePreview.navigations=0
NativePreview.owner={selectTab=function(_,tab,context)
    assert(tab=='crafting' and context,'navigation lost')
    NativePreview.navigations=NativePreview.navigations+1
end}
function NativePreview:queryChanged() self.changed=self.changed+1 end
local host=Host:new(18,76,width-36,38,{direction='row',gap=6})
host:initialise(); NativePreview:addChild(host)
local controls=Controls.new(NativePreview,host,{x=0,y=0,width=host.width,height=host.height})
assert(PreviewLayoutArrow, 'Installed UI2 ArrowDown not loaded')
controls.category.image=PreviewLayoutArrow
controls.sort.image=PreviewLayoutArrow
NativePreview.controls=controls
local scope=Lifecycle.createActivationScope(NativePreview)
assert(host:setActivation(scope))
local rect={x=0,y=0,width=20,height=20,visible=true}
local rectHost=Host:new(18,270,width-36,24,{direction='row'})
rectHost:initialise(); NativePreview:addChild(rectHost)
local virtual=Node.new({direction='row',padding={left=5,right=5}})
rectHost.rootNode:add(virtual)
assert(rectHost:addRect(virtual,rect,{grow=1}))
assert(rectHost:setActivation(scope))
function NativePreview:render()
    self:drawText('Production WarehouseControls / LayoutHost',18,16,1,1,1,1,UIFont.Medium)
    self:drawText('Real native controls; fixture query/navigation; silent audio; no game world',18,45,.7,.7,.7,1,UIFont.Small)
    self:drawText('Host offset (18,76). Search, category, sort, crafting and stock rules.',18,126,.8,.8,.8,1,UIFont.Small)
    self:drawText('Scope gate + solve/apply fault injection + native cleanup retry',18,238,.8,.8,.8,1,UIFont.Small)
    if rect.visible then self:drawRect(rectHost.x+rect.x,rectHost.y+rect.y,rect.width,rect.height,.6,.2,.6,.35) end
end
local function near(a,b) assert(math.abs(a-b)<0.001,'geometry mismatch') end
function NativePreview:smoke()
    local e=host._leafItems[1];local r=host.rootNode._rectPool[e.item.slotIndex]
    near(controls.search.x,r.x);near(controls.search.javaObject:getX(),r.x)
    near(controls.search:getAbsoluteX(),self:getAbsoluteX()+host.x+r.x)
    near(controls.search:getAbsoluteY(),self:getAbsoluteY()+host.y+r.y)
    assert(controls.search.target==self,'owner replaced')
    controls.search:setText('nails');controls.search.onTextChangeFunction(controls.search.target)
    assert(self.changed>0,'query callback lost')
    controls.search:focus();assert(controls.search.javaObject:isFocused(),'native focus lost'); controls.search:unfocus()
    controls.category:showPopup()
    assert(controls.category.popup.parentCombo==controls.category,'popup owner')
    near(controls.category.popup.x,controls.category:getAbsoluteX())
    controls.category:hidePopup()
    local button=controls.buttons[1]
    local x=host.x+button.x+button.width/2;local y=host.y+button.y+button.height/2
    self.javaObject:onMouseDown(x,y);self.javaObject:onMouseUp(x,y)
    assert(self.navigations==1,'nested native click dispatch')
    -- Identical clean updates do not invoke setters again.
    local original=controls.search.setWidth;local calls=0
    controls.search.setWidth=function(target,w) calls=calls+1;return original(target,w) end
    host:update();host:update();assert(calls==0,'clean setter repeated')
    local revision=host.rootNode.revision
    host.rootNode:setGap(host.rootNode.gap)
    host.rootNode:setItemGrow(host.rootNode.items[1],host.rootNode.items[1].grow)
    assert(host.rootNode.revision==revision,'unchanged inputs advanced revision')
    -- A failing native setter leaves the solver clean, and is retried only explicitly.
    local originalThird=controls.sort.setWidth;local thirdCalls=0
    controls.sort.setWidth=function(target,w) thirdCalls=thirdCalls+1;return originalThird(target,w) end
    local originalSecond=controls.category.setWidth
    controls.category.setWidth=function() error('injected apply failure') end
    host:setWidth(host.width-20);host:update()
    assert(host.errorStage=='APPLY_FAILED' and host.errorSetter=='setWidth','apply failure missing')
    assert(not host.rootNode.dirty and host.solvedRevision~=host.appliedRevision,'solve/apply conflated')
    assert(thirdCalls==0,'continued after failed native setter')
    local firstCalls=calls;host:update();host:update();assert(calls==firstCalls,'failed apply repeated')
    controls.category.setWidth=originalSecond
    assert(host:retryLayout());assert(calls==firstCalls+1,'did not replay first native')
    assert(thirdCalls==1,'full replay skipped third native')
    controls.sort.setWidth=originalThird
    controls.search.setWidth=original
    -- Solve failure never touches native setters; same revision does not retry.
    local basis=host.rootNode.items[1].resolvedBasis
    host.rootNode:setItemBasis(host.rootNode.items[1],host.width+1)
    local solveCount=0;local originalSolve=Solver.solve
    Solver.solve=function(...) solveCount=solveCount+1;return originalSolve(...) end
    host:update();assert(host.errorStage=='SOLVE_FAILED','solve failure missing')
    host:update();host:update();assert(solveCount==1,'failed solve repeated')
    host.rootNode:setItemBasis(host.rootNode.items[1],basis)
    assert(host:resolveLayout());Solver.solve=originalSolve
    local generation=host.appliedRevision
    host:deactivate();scope:dispose();host.rootNode:setGap(7);host:update()
    assert(host.appliedRevision==generation and not host.closed and not host.rootNode.disposed,'deactivation destroyed/updated')
    scope=Lifecycle.createActivationScope(self);assert(host:setActivation(scope));assert(rectHost:setActivation(scope))
    -- Registration failures roll back topology and preserve the caller's target.
    local cold=Host:new(0,0,20,20,{direction='row'});cold:initialise();self:addChild(cold)
    assert(not pcall(function() Node.new():add(cold.rootNode) end),'unpublished host root stolen')
    local failedRect={x=1,y=2,width=3,height=4,visible=true}
    assert(not cold:addRect(cold.rootNode,failedRect,{grow=-1}))
    assert(failedRect.visible and #cold.rootNode.items==0,'rect rollback modified caller')
    local borrowed=ISButton:new(0,0,10,10,'x',nil,nil);borrowed:initialise()
    local nativeAdd=cold.addChild
    cold.addChild=function(h,w) nativeAdd(h,w);error('injected post-link registration failure') end
    local item=cold:addNative(cold.rootNode,borrowed,{grow=1})
    assert(not item and not cold._pending and #cold.rootNode.items==0 and #cold._leafItems==0,'half registration')
    assert(not borrowed:getParent() and not borrowed.javaObject:getParent(),'registration retained native parent')
    cold.addChild=nativeAdd
    assert(cold:addNative(cold.rootNode,borrowed,{grow=1}));assert(cold:setActivation(scope))
    local remove=cold.removeChild
    cold.removeChild=function() error('injected detach failure') end
    assert(not cold:dispose());assert(cold.closing and not cold.closed and #cold._leafItems==1,'cleanup responsibility lost')
    cold.removeChild=remove;assert(cold:dispose());assert(cold:dispose())
    assert(not borrowed:getParent() and not borrowed.javaObject:getParent(),'detach failed')
    local reuse=Host:new(0,0,20,20,{direction='row'});reuse:initialise();self:addChild(reuse)
    assert(reuse:addNative(reuse.rootNode,borrowed,{grow=1}));assert(reuse:setActivation(scope))
    assert(reuse:dispose())
    near(rect.x,5);near(rect.width,rectHost.width-10)
    -- Leave the real controls and shared popup visible for visual inspection.
    host:setWidth(width-36);assert(host:resolveLayout())
    controls.category:showPopup()
    self.smokeSummary='Production toolbar native input/popup, geometry, activation, solve/apply failure and cleanup retry passed'
end
function PreviewDispose()
    if controls.category.popup and controls.category.popup.parentCombo==controls.category then controls.category:hidePopup() end
    controls.search:unfocus();host:dispose();rectHost:dispose();scope:dispose();Tooltip.unregisterOwner(NativePreview)
end
