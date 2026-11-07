require 'ISUI/ISPanel'
local Node = require 'EmberRoutesProbe/UI/LayoutNode'
local Host = ISPanel:derive('EmberRoutesLayoutHost')
local owners = setmetatable({}, {__mode='k'})

local function same(a,b) return a==b or (a~=a and b~=b) end
local function finite(n) return type(n)=='number' and n==n and n>-math.huge and n<math.huge end

local KNOWN_CONTAINER_PROPS = { padding=true, gap=true, align=true, justify=true }
local KNOWN_ITEM_PROPS = { key=true, grow=true, basis=true, margin=true, bind=true, when=true, visible=true }
local VALID_ALIGN = { stretch=true, start=true, center=true, ['end']=true }
local VALID_JUSTIFY = { start=true, center=true, ['end']=true, ['space-between']=true }

local function supported(widget)
    assert(widget and type(widget.setX)=='function' and type(widget.setY)=='function'
        and type(widget.setWidth)=='function' and type(widget.setHeight)=='function'
        and type(widget.setVisible)=='function' and type(widget.getParent)=='function', 'INVALID_NATIVE_LEAF')
    assert(not widget.anchorRight and not widget.anchorBottom and widget.anchorLeft~=false
        and widget.anchorTop~=false and widget.keepOnScreen~=true, 'CONFLICTING_NATIVE_GEOMETRY')
end

local handleMetatable = {
    setVisible = function(self, visible) return self.host:setItemVisible(self, visible) end,
    isVisible = function(self) return self.item.visible end
}
handleMetatable.__index = handleMetatable

local function makeHandle(host, item, target, kind, key, bounds)
    return setmetatable({ host = host, item = item, target = target, kind = kind, key = key, bounds = bounds }, handleMetatable)
end

function Host:new(x,y,width,height,props)
    local o=ISPanel.new(self,x,y,width,height)
    setmetatable(o,self); self.__index=self
    o.background=false; o.moveWithMouse=false; o.wantMouseEvents=false
    o.rootNode=Node.new(props); o.rootNode:claimRoot(); o._leafItems={}; o._boundSnapshots={}; o._conditionals={}; o._bounds={width=width,height=height}
    o.scope=false; o.closed=false; o.closing=false; o.sealed=false; o.built=false; o._pending=false
    o.solvedRevision=-1; o.appliedRevision=-1; o.failedSolveRevision=-1; o.failedApplyRevision=-1
    o.errorStage=false; o.errorMessage=false; o.errorSlot=false; o.errorSetter=false
    return o
end

function Host:initialise() ISPanel.initialise(self) end

local function detach(host,target)
    host:removeChild(target)
    assert(not target.javaObject or target.javaObject:getParent()==nil, 'NATIVE_DETACH_FAILED')
    if target.parent==host then target.parent=nil end
end

local function release(host,entry,rollback)
    local target=entry.target
    host.errorSlot=entry.item and entry.item.slotIndex or false
    host.errorSetter='setVisible'
    if entry.kind=='native' then
        target:setVisible(false)
        if not rollback or entry.attached then host.errorSetter='removeChild'; detach(host,target) end
        target:setVisible(entry.wasVisible)
    elseif entry.kind=='rect' then
        target.visible=rollback and entry.wasVisible or false
    elseif entry.kind=='spacer' then
        -- Virtual leaf has no physical target to detach
    end
    if entry.item and entry.item.owner then entry.item.owner:remove(entry.item) end
    if target then owners[target]=nil end
    entry.target=false; entry.item=false
end

local function register(host,entry,node,props)
    entry.item=node:add(entry.target,props)
    if entry.kind=='native' then
        if entry.target:getParent()~=host then
            entry.attached=true -- AddChild may throw after partially linking the target.
            host:addChild(entry.target)
        end
        assert(entry.target.javaObject and entry.target.javaObject:getParent()==host.javaObject, 'NATIVE_PARENT_MISMATCH')
        entry.target:setVisible(false)
    elseif entry.kind=='rect' then
        entry.target.visible=false
    end
    host._leafItems[#host._leafItems+1]=entry
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

-- Preflight validation for declarative layout descriptors
local function validateContainerProps(props)
    props=props or {}
    for k in pairs(props) do
        assert(KNOWN_CONTAINER_PROPS[k], 'UNKNOWN_CONTAINER_PROP: '..tostring(k))
    end
    if props.gap~=nil then
        assert(finite(props.gap) and props.gap>=0, 'INVALID_GAP')
    end
    if props.align~=nil then
        assert(VALID_ALIGN[props.align], 'INVALID_ALIGN: '..tostring(props.align))
    end
    if props.justify~=nil then
        assert(VALID_JUSTIFY[props.justify], 'INVALID_JUSTIFY: '..tostring(props.justify))
    end
    if props.padding~=nil then
        if type(props.padding)=='table' then
            for pk,pv in pairs(props.padding) do
                assert(pk=='top' or pk=='bottom' or pk=='left' or pk=='right', 'INVALID_PADDING_KEY: '..tostring(pk))
                assert(finite(pv) and pv>=0, 'INVALID_PADDING_VALUE')
            end
        else
            assert(finite(props.padding) and props.padding>=0, 'INVALID_PADDING')
        end
    end
end

local function validateItemProps(props)
    props=props or {}
    for k in pairs(props) do
        assert(KNOWN_ITEM_PROPS[k], 'UNKNOWN_ITEM_PROP: '..tostring(k))
    end
    if props.key~=nil then
        assert(type(props.key)=='string' and #props.key>0, 'INVALID_ITEM_KEY')
    end
    if props.grow~=nil then
        assert(finite(props.grow) and props.grow>=0, 'INVALID_GROW')
    end
    if props.basis~=nil then
        assert(finite(props.basis) and props.basis>=0, 'INVALID_BASIS')
    end
    if props.bind~=nil then
        assert(type(props.bind)=='table' and getmetatable(props.bind)==nil, 'INVALID_BIND_TABLE')
    end
    if props.when~=nil then
        assert(type(props.when)=='function' or type(props.when)=='boolean', 'INVALID_WHEN_PREDICATE')
    end
    if props.visible~=nil then
        assert(type(props.visible)=='boolean', 'INVALID_ITEM_VISIBILITY')
    end
    if props.margin~=nil then
        if type(props.margin)=='table' then
            for mk,mv in pairs(props.margin) do
                assert(mk=='top' or mk=='bottom' or mk=='left' or mk=='right', 'INVALID_MARGIN_KEY: '..tostring(mk))
                assert(finite(mv) and mv>=0, 'INVALID_MARGIN_VALUE')
            end
        else
            assert(finite(props.margin) and props.margin>=0, 'INVALID_MARGIN')
        end
    end
end

local function preflight(host,spec,seenSpecs,seenKeys,seenTargets)
    assert(type(spec)=='table' and spec.isLayoutSpec, 'INVALID_LAYOUT_SPEC')
    assert(spec.type=='row' or spec.type=='column', 'INVALID_LAYOUT_TYPE')
    assert(not seenSpecs[spec], 'DESCRIPTOR_CYCLE')
    seenSpecs[spec]=true
    validateContainerProps(spec.props)
    local children=spec.children or {}
    assert(type(children)=='table', 'INVALID_CHILDREN_LIST')
    for i=1,#children do
        local child=children[i]
        assert(child~=nil, 'CHILD_SPEC_NIL')
        if child.isSpacer then
            assert(finite(child.grow) and child.grow>=0, 'INVALID_SPACER_GROW')
        elseif child.isLayoutItemSpec then
            validateItemProps(child.props)
            if child.props and child.props.key then
                local k=child.props.key
                assert(not seenKeys[k], 'DUPLICATE_ITEM_KEY: '..k)
                seenKeys[k]=true
            end
            local inner=child.child
            if inner.isLayoutSpec then
                preflight(host,inner,seenSpecs,seenKeys,seenTargets)
            elseif inner.isSpacer then
                assert(finite(inner.grow) and inner.grow>=0, 'INVALID_SPACER_GROW')
            else
                assert(not seenTargets[inner] and not owners[inner], 'TARGET_ALREADY_REGISTERED')
                seenTargets[inner]=true
                if type(inner)=='table' and type(inner.setX)=='function' then
                    supported(inner)
                    assert(not inner:getParent() or inner:getParent()==host, 'FOREIGN_NATIVE_PARENT')
                end
            end
        elseif child.isLayoutSpec then
            error('BARE_CONTAINER_NOT_ALLOWED: nested container must be wrapped in UI.Item')
        else
            -- Bare native widget or rect leaf
            assert(not seenTargets[child] and not owners[child], 'TARGET_ALREADY_REGISTERED')
            seenTargets[child]=true
            if type(child)=='table' and type(child.setX)=='function' then
                supported(child)
                assert(not child:getParent() or child:getParent()==host, 'FOREIGN_NATIVE_PARENT')
            end
        end
    end
end

local function stage(host,parentNode,spec,stagedLeaves,candidateHandles,stagedBoundItems,stagedConditionals)
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
                stage(host,childNode,inner,stagedLeaves,candidateHandles,stagedBoundItems,stagedConditionals)
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
                local item=parentNode:add(inner,props)
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
    local okStage, errStage = pcall(stage, self, self.rootNode, spec, stagedLeaves, candidateHandles, stagedBoundItems, stagedConditionals)
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
    self.built=true
    self.rootNode:markDirty()
    return candidateHandles, nil
end

---Controls the visibility of an item handle without re-slicing.
---@param handle table Handle returned by Host:build
---@param visible boolean Desired visibility
---@return boolean success
function Host:setItemVisible(handle, visible)
    assert(not self.closed and not self.closing, 'HOST_CLOSED')
    assert(handle and handle.host==self and handle.item, 'INVALID_LAYOUT_HANDLE')
    assert(handle.item.owner and handle.item.owner.root==self.rootNode, 'STALE_LAYOUT_HANDLE')
    assert(type(visible)=='boolean', 'INVALID_VISIBILITY')
    if handle.item.visible==visible then return true end

    handle.item.owner:setItemVisible(handle.item, visible)
    if not visible then
        -- Immediate hide avoids rendering at obsolete geometry while waiting for next solve
        if handle.kind=='native' then handle.target:setVisible(false)
        elseif handle.kind=='rect' then handle.target.visible=false end
    end
    -- When visible is true, actual display is deferred to apply() after new geometry is applied
    return true
end

function Host:deactivate() self.scope=false end

function Host:setActivation(scope)
    assert(not self.closed and not self.closing and not self._pending, 'HOST_NOT_READY')
    assert(scope and scope:isCurrent(), 'INVALID_ACTIVATION')
    self.scope=scope; self.sealed=true
    self.failedSolveRevision=-1; self.failedApplyRevision=-1; self.appliedRevision=-1
    return self:resolveLayout()
end

function Host:isActivationValid()
    return not self.closed and not self.closing and self.scope and self.scope:isCurrent()
end

function Host:onResize()
    ISPanel.onResize(self)
    if self.rootNode and not self.closed and not self.closing then self:_syncBounds() end
end

function Host:_syncBounds()
    if not same(self._bounds.width,self.width) or not same(self._bounds.height,self.height) then
        self._bounds.width=self.width; self._bounds.height=self.height
        self.rootNode:markDirty()
    end
end

local function apply(host)
    local pool=host.rootNode._rectPool
    -- Validate every target before the first setter.
    for i=1,#host._leafItems do
        local e=host._leafItems[i]; local item=e.item; local target=e.target
        host.errorSlot=item.slotIndex; host.errorSetter='preflight'
        assert(item.owner and item.owner.root==host.rootNode, 'STALE_LAYOUT_ITEM')
        local r=pool[item.slotIndex]
        assert(r and finite(r.x) and finite(r.y) and finite(r.width) and finite(r.height)
            and r.width>=0 and r.height>=0 and type(r.visible)=='boolean','INVALID_RECTANGLE')
        if e.kind=='native' then
            supported(target)
            assert(target.javaObject and target:getParent()==host and target.javaObject:getParent()==host.javaObject,
                'NATIVE_PARENT_MISMATCH')
        end
    end
    for i=1,#host._leafItems do
        local e=host._leafItems[i]; local r=pool[e.item.slotIndex]; local target=e.target
        host.errorSlot=e.item.slotIndex
        if e.kind=='native' then
            if r.visible then
                host.errorSetter='setWidth'; target:setWidth(r.width)
                host.errorSetter='setHeight'; target:setHeight(r.height)
                host.errorSetter='setX'; target:setX(r.x)
                host.errorSetter='setY'; target:setY(r.y)
            end
            host.errorSetter='setVisible'; target:setVisible(r.visible)
        elseif e.kind=='rect' then
            host.errorSetter='rect'
            target.x=r.x; target.y=r.y; target.width=r.width; target.height=r.height; target.visible=r.visible
        elseif e.kind=='spacer' then
            -- Spacers have no physical target to move
        end
    end
    for i=1,#host._boundSnapshots do
        local b=host._boundSnapshots[i]
        local item=b.item; local t=b.bind
        t.x=item._x; t.y=item._y; t.width=item._width; t.height=item._height; t.visible=item._visible
    end
end

function Host:resolveLayout()
    if not self:isActivationValid() then return nil,'INACTIVE' end
    local parent=self:getParent()
    if not self.javaObject or not parent or self.javaObject:getParent()~=parent.javaObject then
        return nil,'HOST_NOT_MOUNTED'
    end
    self:_syncBounds()
    local revision=self.rootNode.revision
    if self.rootNode.dirty then
        if self.failedSolveRevision==revision then return nil,self.errorMessage end
        local pool,err=self.rootNode:resolveIfDirty(self._bounds)
        if not pool then
            self.failedSolveRevision=revision; self.errorStage='SOLVE_FAILED'; self.errorMessage=err
            self.errorSlot=false; self.errorSetter=false
            return nil,err
        end
        self.solvedRevision=revision
    end
    if self.appliedRevision==self.solvedRevision then return self.rootNode._rectPool,false end
    if self.failedApplyRevision==self.solvedRevision then return nil,'APPLY_FAILED' end
    local ok,err=pcall(apply,self)
    if not ok then
        self.failedApplyRevision=self.solvedRevision; self.errorStage='APPLY_FAILED'; self.errorMessage=err
        return nil,'APPLY_FAILED'
    end
    self.appliedRevision=self.solvedRevision
    self.errorStage=false; self.errorMessage=false; self.errorSlot=false; self.errorSetter=false
    return self.rootNode._rectPool,true
end

function Host:retryLayout()
    self.failedSolveRevision=-1; self.failedApplyRevision=-1
    self.appliedRevision=-1
    return self:resolveLayout()
end

function Host:update()
    ISPanel.update(self)
    if self:isActivationValid() then self:resolveLayout() end
end

function Host:dispose()
    if self.closed then return true end
    self.closing=true; self.scope=false
    local failed=false
    if self._pending then
        local ok,err=pcall(release,self,self._pending,true)
        if ok then self._pending=false else failed=err end
    end
    for i=#self._leafItems,1,-1 do
        local ok,err=pcall(release,self,self._leafItems[i],false)
        if ok then table.remove(self._leafItems,i) else failed=err end
    end
    if failed then self.errorStage='CLEANUP_PENDING'; self.errorMessage=failed; return nil,failed end
    local parent=self:getParent()
    if parent then
        local ok,err=pcall(detach,parent,self)
        if not ok then self.errorStage='CLEANUP_PENDING'; self.errorMessage=err; return nil,err end
    end
    self.rootNode:dispose()
    self._boundSnapshots={}
    self._conditionals={}
    self.closed=true; self.closing=false
    self.errorStage=false; self.errorMessage=false; self.errorSlot=false; self.errorSetter=false
    return true
end

---Evaluates all conditional item predicates declared via when / UI.Show.
---@param context table|nil State context passed to predicate functions
---@return boolean success
function Host:syncVisibility(context)
    assert(not self.closed and not self.closing, 'HOST_CLOSED')
    local conds=self._conditionals
    if not conds or #conds==0 then return true end
    for i=1,#conds do
        local c=conds[i]
        local visible=false
        if type(c.when)=='function' then
            visible=c.when(context)==true
        elseif type(c.when)=='boolean' then
            visible=c.when
        end
        self:setItemVisible(c.handle, visible)
    end
    return true
end

return Host
