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
local detach = S.detach
local release = S.release
local register = S.register
local resolveAutoBasis = S.resolveAutoBasis

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
    assert(not self.closed and not self.closing and not self.sealed and not self._pending, 'HOST_REGISTRATION_CLOSED')
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
---Builds and mounts a declarative layout descriptor tree.
---@param spec table Layout descriptor created by UI.Row or UI.Column
---@param initialContext table? Optional initial state context for when predicates
---@return table|nil handles Named handles map or nil on failure
---@return string|nil err Error message if build failed
function Host:build(spec, initialContext)
    assert(not self.closed and not self.closing, 'HOST_CLOSED')
    assert(not self.built, 'HOST_ALREADY_BUILT')

    -- Accept layout item wrapping root container
    if spec and spec.isLayoutItemSpec and spec.child and spec.child.isLayoutSpec then
        local rootItemProps = spec.props
        spec = spec.child
        if rootItemProps and rootItemProps.bind and not spec.props.bind then
            spec.props.bind = rootItemProps.bind
        end
    end

    -- 1. Preflight: pure static validation without touching native widgets
    local seenSpecs, seenKeys, seenTargets = {}, {}, {}
    local okPre, errPre = pcall(preflight, self, spec, seenSpecs, seenKeys, seenTargets)
    if not okPre then return nil, errPre end

    -- 2. Stage: construct candidate LayoutNode hierarchy and leaf lists
    local stagedLeaves = {}
    local candidateHandles = {}
    local stagedBoundItems = {}
    local stagedConditionals = {}
    local stagedAutoBasis = {}
    local okStage, errStage = pcall(stage, self, self.rootNode, spec, stagedLeaves, candidateHandles, stagedBoundItems, stagedConditionals, stagedAutoBasis)
    if not okStage then
        self.rootNode:dispose()
        self.rootNode=Node.new()
        self.rootNode:claimRoot()
        return nil, errStage
    end

    -- 3. Commit: native mounting with reverse rollback on failure
    local mountedNative = {}
    for i=1,#stagedLeaves do
        local entry = stagedLeaves[i]
        if entry.kind=='native' then
            if entry.target:getParent()~=self then
                entry.attached=true
                local okMount, errMount = pcall(self.addChild, self, entry.target)
                if not okMount then
                    -- Rollback native attachments
                    local rollbackClean = true
                    for j=#mountedNative, 1, -1 do
                        local okRb = pcall(detach, self, mountedNative[j])
                        if not okRb then rollbackClean = false end
                    end
                    self.errorStage = rollbackClean and 'BUILD_FAILED' or 'BUILD_CLEANUP_REQUIRED'
                    self.errorMessage = errMount
                    return nil, self.errorStage
                end
                mountedNative[#mountedNative+1] = entry.target
            end
            entry.target:setVisible(false)
        elseif entry.kind=='rect' then
            entry.target.visible=false
        end
    end

    -- 4. Publish: commit leaf entries, mark built and dirty
    for i=1,#stagedLeaves do
        local entry = stagedLeaves[i]
        self._leafItems[#self._leafItems+1] = entry
        if entry.target then owners[entry.target] = self end
    end
    for i=1,#stagedBoundItems do
        self._boundSnapshots[#self._boundSnapshots+1] = stagedBoundItems[i]
    end
    for i=1,#stagedConditionals do
        self._conditionals[#self._conditionals+1] = stagedConditionals[i]
        local c = stagedConditionals[i]
        if type(c.when) == 'boolean' then
            self:setItemVisible(c.handle, c.when)
        elseif initialContext ~= nil and type(c.when) == 'function' then
            self:setItemVisible(c.handle, c.when(initialContext) == true)
        end
    end
    for i=1,#stagedAutoBasis do
        self._autoBasisItems[#self._autoBasisItems+1] = stagedAutoBasis[i]
    end
    self.built=true
    self.rootNode:markDirty()
    return candidateHandles, nil
end

end

return attach
