-- LayoutHostBuild.lua - EmberRoutes UI
-- Declarative build path: leaf registration (native/rect), descriptor
-- staging, and Host:build with its preflight / stage / commit / publish
-- phases and reverse rollback on mount failure.
-- Attached to EmberRoutesLayoutHost by LayoutHost.lua (mixin pattern:
-- this module receives the class table, so there is no circular require
-- back to the host module). Moved verbatim from the pre-split
-- LayoutHost.lua (P1 split); behaviour unchanged.
local Node = require 'EmberRoutesProbe/UI/LayoutNode'
local S = require 'EmberRoutesProbe/UI/LayoutHostShared'
local preflight = require 'EmberRoutesProbe/UI/LayoutHostValidation'
local owners = S.owners
local supported = S.supported
local finite = S.finite
local release = S.release
local register = S.register
local resolveAutoBasis = S.resolveAutoBasis

---@param Host EmberRoutesLayoutHost
local function attach(Host)
local handleMetatable = {
    setVisible = function(self, visible) return self.host:setItemVisible(self, visible) end,
    isVisible = function(self) return self.item.visible end
}
handleMetatable.__index = handleMetatable

local function makeHandle(host, item, target, kind, key, bounds)
    return setmetatable({ host = host, item = item, target = target, kind = kind, key = key, bounds = bounds }, handleMetatable)
end
local function stage(host,parentNode,spec,stagedLeaves,candidateHandles,stagedBoundItems,stagedConditionals,stagedAutoBasis)
    parentNode.direction=spec.type
    local p=spec.props or {}
    if p.gap then parentNode:setGap(p.gap) end
    if p.padding then parentNode:setPadding(p.padding) end
    if p.align then parentNode:setAlign(p.align) end
    if p.justify then parentNode:setJustify(p.justify) end

    local children=spec.children or {}
    for i=1,#children do
        local child=children[i]
        if child.isSpacer then
            local item=parentNode:add(nil,{grow=child.grow,basis=0})
            stagedLeaves[#stagedLeaves+1]={kind='spacer',target=false,item=item,key=false}
        elseif child.isLayoutItemSpec then
            local props=child.props or {}
            local inner=child.child
            local key=props.key
            local bind=props.bind
            local when=props.when
            if inner.isLayoutSpec then
                local childNode=Node.new({direction=inner.type})
                local grow=props.grow==nil and 1 or props.grow
                local itemProps={grow=grow,basis=props.basis,margin=props.margin}
                local item=parentNode:add(childNode,itemProps)
                local bounds=bind or (key and {x=0,y=0,width=0,height=0,visible=false} or false)
                if bounds then stagedBoundItems[#stagedBoundItems+1]={item=item,bind=bounds} end
                local handleKey=key or (when~=nil and ('__when_'..(#stagedConditionals+1)) or nil)
                if handleKey then
                    local h=makeHandle(host,item,false,'container',handleKey,bounds)
                    candidateHandles[handleKey]=h
                    if when~=nil then stagedConditionals[#stagedConditionals+1]={handle=h,when=when} end
                end
                stage(host,childNode,inner,stagedLeaves,candidateHandles,stagedBoundItems,stagedConditionals,stagedAutoBasis)
            elseif inner.isSpacer then
                local grow=props.grow or inner.grow
                local item=parentNode:add(nil,{grow=grow,basis=props.basis or 0,margin=props.margin})
                local entry={kind='spacer',target=false,item=item,key=key}
                stagedLeaves[#stagedLeaves+1]=entry
                local bounds=bind or (key and {x=0,y=0,width=0,height=0,visible=false} or false)
                if bounds then stagedBoundItems[#stagedBoundItems+1]={item=item,bind=bounds} end
                local handleKey=key or (when~=nil and ('__when_'..(#stagedConditionals+1)) or nil)
                if handleKey then
                    local h=makeHandle(host,item,false,'spacer',handleKey,bounds)
                    candidateHandles[handleKey]=h
                    if when~=nil then stagedConditionals[#stagedConditionals+1]={handle=h,when=when} end
                end
            else
                local kind=(type(inner)=='table' and type(inner.setX)=='function') and 'native' or 'rect'
                local wasVisible=false
                if kind=='native' then
                    wasVisible=not inner.javaObject or inner:getIsVisible()
                else
                    wasVisible=inner.visible
                end
                local stagedProps = props
                local isAuto = props and props.basis == "auto"
                if isAuto then
                    local autoBasis = resolveAutoBasis(inner, props)
                    stagedProps = {}
                    for k, v in pairs(props) do stagedProps[k] = v end
                    stagedProps.basis = autoBasis
                end
                local item=parentNode:add(inner,stagedProps)
                if isAuto then
                    stagedAutoBasis[#stagedAutoBasis+1] = { item = item, inner = inner, props = props }
                end
                local entry={kind=kind,target=inner,item=item,wasVisible=wasVisible,attached=false,key=key}
                stagedLeaves[#stagedLeaves+1]=entry
                local bounds=bind or (key and {x=0,y=0,width=0,height=0,visible=false} or false)
                if bounds then stagedBoundItems[#stagedBoundItems+1]={item=item,bind=bounds} end
                local handleKey=key or (when~=nil and ('__when_'..(#stagedConditionals+1)) or nil)
                if handleKey then
                    local h=makeHandle(host,item,inner,kind,handleKey,bounds)
                    candidateHandles[handleKey]=h
                    if when~=nil then stagedConditionals[#stagedConditionals+1]={handle=h,when=when} end
                end
            end
        else
            -- Bare native widget
            local kind=(type(child)=='table' and type(child.setX)=='function') and 'native' or 'rect'
            local wasVisible=false
            if kind=='native' then
                wasVisible=not child.javaObject or child:getIsVisible()
            else
                wasVisible=child.visible
            end
            local item=parentNode:add(child,{grow=0})
            local entry={kind=kind,target=child,item=item,wasVisible=wasVisible,attached=false,key=false}
            stagedLeaves[#stagedLeaves+1]=entry
        end
    end
end
function Host:_register(node,target,props,kind)
    assert(not self.closed and not self.closing and not self.sealed and not self._pending
        and not self._building and not self._buildPending, 'HOST_REGISTRATION_CLOSED')
    assert(node and not node.disposed and node.root==self.rootNode, 'FOREIGN_LAYOUT_NODE')
    assert(target and not owners[target], 'LEAF_ALREADY_REGISTERED')
    local wasVisible=false
    if kind=='native' then
        supported(target)
        assert(not target:getParent() or target:getParent()==self, 'FOREIGN_NATIVE_PARENT')
        wasVisible=not target.javaObject or target:getIsVisible()
    else
        assert(type(target)=='table' and finite(target.width) and finite(target.height)
            and finite(target.x) and finite(target.y) and type(target.visible)=='boolean'
            and getmetatable(target)==nil, 'INVALID_RECT_LEAF')
        wasVisible=target.visible
    end
    local entry={kind=kind,target=target,item=false,attached=false,wasVisible=wasVisible}
    self._pending=entry; owners[target]=self
    local ok,err=pcall(register,self,entry,node,props)
    if not ok then
        local cleaned,cleanupError=pcall(release,self,entry,true)
        if cleaned then self._pending=false end
        self.errorStage=cleaned and 'REGISTER_FAILED' or 'CLEANUP_PENDING'
        self.errorMessage=cleaned and err or cleanupError
        return nil,self.errorStage
    end
    self._pending=false
    return entry.item
end

function Host:addNative(node,target,props) return self:_register(node,target,props,'native') end
function Host:addRect(node,rect,props) return self:_register(node,rect,props,'rect') end
-- Retain the complete candidate until every attempted side effect is undone.
-- A failed release remains in this record for dispose() to retry.
function Host:_rollbackBuild()
    local pending=self._buildPending
    if not pending then return true end
    local failed=false
    for i=#pending.leaves,1,-1 do
        local entry=pending.leaves[i]
        if entry.target then
            if entry.touched then
                local ok,err=pcall(release,self,entry,true)
                if not ok then failed=err end
            else
                if owners[entry.target]==self then owners[entry.target]=nil end
                entry.target=false
            end
        end
    end
    if failed then self.cleanupError=failed; return nil,failed end
    pending.root:dispose()
    self._buildPending=false; self.cleanupError=false
    return true
end
local function initializeConditions(conditions,context)
    for i=1,#conditions do
        local c=conditions[i]
        if type(c.when)=='boolean' then
            c.handle.item.owner:setItemVisible(c.handle.item,c.when)
        elseif context~=nil and type(c.when)=='function' then
            c.handle.item.owner:setItemVisible(c.handle.item,c.when(context)==true)
        end
    end
end
local function commit(host,pending)
    -- Staging predicates/getters can reenter another host: recheck before reserving.
    for i=1,#pending.leaves do
        local target=pending.leaves[i].target
        assert(not target or not owners[target],'TARGET_ALREADY_REGISTERED')
    end
    for i=1,#pending.leaves do
        local target=pending.leaves[i].target
        if target then owners[target]=host end
    end
    for i=1,#pending.leaves do
        local entry=pending.leaves[i]
        if entry.kind=='native' then
            supported(entry.target)
            local parent=entry.target:getParent()
            assert(not parent or parent==host,'FOREIGN_NATIVE_PARENT')
            entry.touched=true
            host.errorSlot=entry.item.slotIndex; host.errorSetter='addChild'
            if entry.target:getParent()~=host then
                entry.attached=true -- Record BEFORE AddChild: it may throw after linking.
                host:addChild(entry.target)
            end
            assert(entry.target.javaObject and entry.target:getParent()==host
                and entry.target.javaObject:getParent()==host.javaObject,'NATIVE_PARENT_MISMATCH')
            host.errorSetter='setVisible'
            entry.target:setVisible(false)
        elseif entry.kind=='rect' then
            entry.touched=true
            host.errorSlot=entry.item.slotIndex; host.errorSetter='rect.visible'
            entry.target.visible=false
        end
    end
end
---Builds a descriptor tree without publishing partially committed native state.
function Host:build(spec, initialContext)
    assert(not self.closed and not self.closing, 'HOST_CLOSED')
    assert(not self.built, 'HOST_ALREADY_BUILT')
    assert(not self.sealed and not self._pending and not self._building
        and not self._buildPending, 'HOST_NOT_READY')
    assert(#self._leafItems==0 and #self.rootNode.items==0,'HOST_NOT_EMPTY')

    -- Accept layout item wrapping root container.
    if spec and spec.isLayoutItemSpec and spec.child and spec.child.isLayoutSpec then
        local rootItemProps = spec.props
        spec = spec.child
        if rootItemProps and rootItemProps.bind and not spec.props.bind then
            spec.props.bind = rootItemProps.bind
        end
    end
    self._building=true
    local seenSpecs,seenKeys,seenTargets={},{},{}
    local okPre,errPre=pcall(preflight,self,spec,seenSpecs,seenKeys,seenTargets)
    if not okPre then self._building=false; return nil,errPre end

    -- Stage against a separate root; the live root survives any build failure.
    local originalRoot=self.rootNode
    local candidateRoot=Node.new({direction=originalRoot.direction,gap=originalRoot.gap,
        padding=originalRoot.padding,align=originalRoot.align,justify=originalRoot.justify})
    candidateRoot:claimRoot()
    local leaves,handles,bounds,conditions,autoBasis={},{},{},{},{}
    local okStage,errStage=pcall(stage,self,candidateRoot,spec,leaves,handles,bounds,conditions,autoBasis)
    if okStage then okStage,errStage=pcall(initializeConditions,conditions,initialContext) end
    if not okStage then
        candidateRoot:dispose(); self._building=false
        return nil,errStage
    end

    -- Reserve all targets and publish cleanup responsibility before native calls.
    local pending={root=candidateRoot,leaves=leaves}
    self._buildPending=pending
    local okCommit,errCommit=pcall(commit,self,pending)
    if not okCommit then
        local cleaned=self:_rollbackBuild()
        self._building=false
        self.errorStage=cleaned and 'BUILD_FAILED' or 'BUILD_CLEANUP_REQUIRED'
        self.errorMessage=errCommit
        return nil,self.errorStage
    end

    -- Publish only after native mounting, hiding and initial predicates succeed.
    self.rootNode=candidateRoot
    self._leafItems=leaves; self._boundSnapshots=bounds
    self._conditionals=conditions; self._autoBasisItems=autoBasis
    self._buildPending=false; self._building=false
    originalRoot:dispose()
    self.built=true
    self.rootNode:markDirty()
    self.errorStage=false; self.errorMessage=false; self.cleanupError=false
    self.errorSlot=false; self.errorSetter=false
    return handles,nil
end

end

return attach
