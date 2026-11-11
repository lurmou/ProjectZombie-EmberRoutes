-- LayoutHostApply.lua - EmberRoutes UI
-- Geometry application and solve scheduling: the apply() pass that writes
-- solved rectangles onto native/rect leaves and bound snapshots, resize
-- sync, layout requests, auto-basis invalidation, and Host:resolveLayout
-- with its solve/apply revision guards.
-- Attached to EmberRoutesLayoutHost by LayoutHost.lua (mixin pattern:
-- this module receives the class table, so there is no circular require
-- back to the host module). Moved verbatim from the pre-split
-- LayoutHost.lua (P1 split); behaviour unchanged.
local S = require 'EmberRoutesProbe/UI/LayoutHostShared'
local same = S.same
local supported = S.supported
local finite = S.finite
local resolveAutoBasis = S.resolveAutoBasis

local function attach(Host)
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
function Host:requestLayout()
    if self.closed or self.closing then return end
    self._layoutRequested = true
    if self.rootNode then
        self.rootNode:markDirty()
    end
end

function Host:flushLayout()
    self._layoutRequested = false
    return self:resolveLayout()
end
function Host:invalidateAutoBasis()
    local items = self._autoBasisItems
    if not items or #items == 0 then return end
    for i = 1, #items do
        local entry = items[i]
        local newBasis = resolveAutoBasis(entry.inner, entry.props)
        if entry.item and entry.item.owner then
            entry.item.owner:setItemBasis(entry.item, newBasis)
        end
    end
    self:requestLayout()
end
function Host:resolveLayout()
    if not self:isActivationValid() then return nil,'INACTIVE' end
    local parent=self:getParent()
    if not self.javaObject or not parent or self.javaObject:getParent()~=parent.javaObject then
        return nil,'HOST_NOT_MOUNTED'
    end
    self._layoutRequested = false
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

end

return attach
