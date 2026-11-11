-- LayoutHostLifecycle.lua - EmberRoutes UI
-- Host lifecycle: activation, visibility handles, debouncer registry,
-- per-frame update, disposal with reverse leaf release, and conditional
-- (when / UI.Show) visibility sync.
-- Attached to EmberRoutesLayoutHost by LayoutHost.lua (mixin pattern:
-- this module receives the class table, so there is no circular require
-- back to the host module). Moved verbatim from the pre-split
-- LayoutHost.lua (P1 split); behaviour unchanged.
local S = require 'EmberRoutesProbe/UI/LayoutHostShared'
local Clock = require 'EmberRoutesProbe/Kernel/Clock'
local release = S.release
local detach = S.detach

local function attach(Host)
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
    self:requestLayout()
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
function Host:_tickDebouncers(now)
    local ds = self._debouncers
    if not ds or #ds == 0 then return end
    now = now or (Clock.nowMs())
    for i = 1, #ds do
        ds[i]:tick(now)
    end
end

function Host:registerDebouncer(d)
    assert(d and type(d.tick) == 'function', 'INVALID_DEBOUNCER')
    self._debouncers = self._debouncers or {}
    for i = 1, #self._debouncers do
        if self._debouncers[i] == d then return end
    end
    self._debouncers[#self._debouncers + 1] = d
end

function Host:unregisterDebouncer(d)
    if not self._debouncers then return end
    for i = 1, #self._debouncers do
        if self._debouncers[i] == d then
            table.remove(self._debouncers, i)
            return
        end
    end
end
function Host:update()
    ISPanel.update(self)
    if not self.closed and not self.closing then
        self:_tickDebouncers()
        if self:isActivationValid() then
            if self._layoutRequested or self.rootNode.dirty then
                self:flushLayout()
            end
        end
    end
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
    if self._debouncers then
        for i = 1, #self._debouncers do
            self._debouncers[i]:cancel()
        end
        self._debouncers = {}
    end
    self._autoBasisItems = {}
    self._layoutRequested = false
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

end

return attach
