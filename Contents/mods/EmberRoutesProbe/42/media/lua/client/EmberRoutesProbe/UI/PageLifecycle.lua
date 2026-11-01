-- EmberRoutes UI Lifecycle & Dual Scope Infrastructure
--
-- Responsibilities:
-- 1. Dual Scope Architecture:
--    - PageLifetimeScope (instance level): lives from page creation until page disposal.
--    - ActivationScope (viewport session level): lives from page activation to page deactivation.
-- 2. Explicit Disposer Protocol: own(resource, disposer) requires an explicit disposer function.
--    No guessing or Duck Typing of method names (dispose vs destroy vs close vs removeFromUIManager).
-- 3. Idempotent cleanup handles: handles support premature cancellation/release and idempotent disposal.
-- 4. Error isolation: Individual resource release failures are logged and do not interrupt subsequent cleanups.
-- 5. Stale token rejection: wrapCallback discards late notifications from expired activation sessions.
-- 6. Synchronous watch disposal defense: Late-returned release handles on synchronous close are called immediately.
-- 7. Tooltip separation: dismissOwner on session deactivate, unregisterOwner on page instance destruction.
-- 8. Backward compatibility: mount() and unmount() preserved with 100% semantic parity for existing pages.

local Lifecycle = {}
local TooltipManager = require 'EmberRoutesProbe/UI/TooltipManager'

local function safeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        print("[PageLifecycle] Error during resource release: " .. tostring(err))
    end
    return ok, err
end

---Unified internal release entry processor.
---Strict order:
---1. Mark entry.released = true (anti-reentrancy)
---2. Save local references to fn and resource
---3. Clear entry.fn and entry.resource to sever memory links
---4. safeCall fn (resource severed even if callback throws)
---@param entry table
local function releaseEntry(entry)
    if not entry or entry.released then return end
    entry.released = true

    local entryType = entry.type
    local fn = entry.fn
    local resource = entry.resource

    -- Clear references immediately before execution so handle retention does not leak memory
    entry.fn = nil
    entry.resource = nil

    if entryType == "resource" then
        safeCall(fn, resource)
    else
        safeCall(fn)
    end
end

local function makeHandle(entry)
    local handle = {}
    setmetatable(handle, {
        __call = function(t) t:release() end
    })
    function handle:release()
        releaseEntry(entry)
    end
    return handle
end

----------------------------------------------------------------
-- PageLifetimeScope (Page Instance Lifetime)
----------------------------------------------------------------

---@class EmberRoutesLifetimeScope
local LifetimeScope = {}
LifetimeScope.__index = LifetimeScope

function LifetimeScope.new(page)
    return setmetatable({
        page = page,
        disposed = false,
        entries = {}
    }, LifetimeScope)
end

function LifetimeScope:isDisposed()
    return self.disposed == true or (self.page ~= nil and self.page.disposed == true)
end

---Own a long-term resource with an explicit disposer function.
---@param resource any
---@param disposer fun(resource:any)
---@return table handle with release() method
function LifetimeScope:own(resource, disposer)
    assert(type(disposer) == "function", "PageLifetimeScope:own requires an explicit disposer function")
    if resource == nil then
        return { release = function() end }
    end
    if self:isDisposed() then
        safeCall(disposer, resource)
        return { release = function() end }
    end

    local entry = {
        type = "resource",
        resource = resource,
        fn = disposer,
        released = false
    }
    self.entries[#self.entries + 1] = entry
    return makeHandle(entry)
end

---Register a deferred cleanup function.
---@param cleanupFn fun()
---@return table handle with release() method
function LifetimeScope:defer(cleanupFn)
    assert(type(cleanupFn) == "function", "PageLifetimeScope:defer requires a cleanup function")
    if self:isDisposed() then
        safeCall(cleanupFn)
        return { release = function() end }
    end

    local entry = {
        type = "cleanup",
        fn = cleanupFn,
        released = false
    }
    self.entries[#self.entries + 1] = entry
    return makeHandle(entry)
end

---Dispose the lifetime scope and all owned resources.
function LifetimeScope:dispose()
    if self.disposed then return end
    self.disposed = true

    local page = self.page
    if page then
        page.disposed = true
        if page.activationScope and not page.activationScope.disposed then
            page.activationScope:dispose()
        end
    end

    -- Reverse execution (LIFO)
    local entries = self.entries
    for i = #entries, 1, -1 do
        releaseEntry(entries[i])
    end
    self.entries = {}

    if page then
        TooltipManager.unregisterOwner(page)
    end
end

----------------------------------------------------------------
-- ActivationScope (Viewport Session Lifetime)
----------------------------------------------------------------

---@class EmberRoutesActivationScope
local ActivationScope = {}
ActivationScope.__index = ActivationScope

function ActivationScope.new(page)
    local token = {}
    page.active = true
    page.activation = token
    return setmetatable({
        page = page,
        token = token,
        active = true,
        disposed = false,
        entries = {}
    }, ActivationScope)
end

function ActivationScope:isCurrent()
    return self.active == true
        and not self.disposed
        and self.page ~= nil
        and self.page.active == true
        and self.page.activation == self.token
        and not self.page.disposed
end

function ActivationScope:wrapCallback(fn)
    if type(fn) ~= "function" then return fn end
    return function(...)
        if not self:isCurrent() then return end
        return fn(...)
    end
end

---Own a temporary resource with an explicit disposer function.
---@param resource any
---@param disposer fun(resource:any)
---@return table handle with release() method
function ActivationScope:own(resource, disposer)
    assert(type(disposer) == "function", "ActivationScope:own requires an explicit disposer function")
    if resource == nil then
        return { release = function() end }
    end
    if not self:isCurrent() then
        safeCall(disposer, resource)
        return { release = function() end }
    end

    local entry = {
        type = "resource",
        resource = resource,
        fn = disposer,
        released = false
    }
    self.entries[#self.entries + 1] = entry
    return makeHandle(entry)
end

---Register a deferred cleanup function.
---@param cleanupFn fun()
---@return table handle with release() method
function ActivationScope:defer(cleanupFn)
    assert(type(cleanupFn) == "function", "ActivationScope:defer requires a cleanup function")
    if not self:isCurrent() then
        safeCall(cleanupFn)
        return { release = function() end }
    end

    local entry = {
        type = "cleanup",
        fn = cleanupFn,
        released = false
    }
    self.entries[#self.entries + 1] = entry
    return makeHandle(entry)
end

---Subscribe to a store with automatic token gate.
---@param store table
---@param projectFn fun(value:any, changed:any)
---@return table handle with release() method
function ActivationScope:subscribe(store, projectFn)
    if not store or type(store.subscribe) ~= "function" then
        return { release = function() end }
    end
    if not self:isCurrent() then
        return { release = function() end }
    end

    local wrappedProject = self:wrapCallback(projectFn)
    local unsubscribe = store:subscribe(wrappedProject)
    if type(unsubscribe) == "function" then
        return self:defer(unsubscribe)
    end
    return { release = function() end }
end

---Watch a service with token gate, owner guard, and sync teardown defense.
---@param watchFn fun(cb:fun(snapshot:any)):fun()?, string?
---@param receiveFn fun(snapshot:any)
---@param guardFn (fun(page:table, snapshot:any):boolean)?
---@return fun()?, string?
function ActivationScope:watch(watchFn, receiveFn, guardFn)
    if type(watchFn) ~= "function" then
        return nil, "INVALID_WATCH_FN"
    end
    if not self:isCurrent() then
        return nil, "SCOPE_NOT_CURRENT"
    end

    local wrappedReceive = self:wrapCallback(function(snapshot)
        if guardFn then
            local ok = guardFn(self.page, snapshot)
            if ok == false then return end
        end
        if receiveFn then
            receiveFn(snapshot)
        end
    end)

    local release, reason = watchFn(wrappedReceive)

    if not self:isCurrent() then
        -- Synchronous notification closed the page before release handle was returned!
        if type(release) == "function" then
            safeCall(release)
        end
        return nil, reason
    end

    if type(release) == "function" then
        self:defer(release)
    elseif release == nil and receiveFn then
        receiveFn({ state = "ERROR", rows = {}, counts = {}, reason = reason })
    end

    return release, reason
end

---Dispose the activation session.
---Strict order:
---1. page.active = false
---2. page.activation = nil (token invalidated immediately)
---3. scope.active = false, scope.disposed = true (prevent re-entrancy)
---4. TooltipManager.dismissOwner(page)
---5. Reverse execute cleanups and resource disposers with error isolation
---6. Clear references
function ActivationScope:dispose()
    if self.disposed then return end
    self.disposed = true
    self.active = false

    local page = self.page
    if page then
        page.active = false
        page.activation = nil
        TooltipManager.dismissOwner(page)
    end

    local entries = self.entries
    for i = #entries, 1, -1 do
        releaseEntry(entries[i])
    end
    self.entries = {}

    if page and page.activationScope == self then
        page.activationScope = nil
    end
end

----------------------------------------------------------------
-- Factory & Facade API
----------------------------------------------------------------

---Create a long-term PageLifetimeScope for a page instance.
---Guards:
---1. Returns nil if page is nil.
---2. Returns nil if page.disposed is true (cannot resurrect disposed page).
---3. Returns existing scope if page.lifetimeScope exists and is active.
---4. Logs error and returns nil if existing scope is disposed (state mismatch).
---@param page table
---@return EmberRoutesLifetimeScope?
function Lifecycle.createLifetimeScope(page)
    if not page then return nil end
    if page.disposed then return nil end

    local existing = page.lifetimeScope
    if existing then
        if not existing.disposed then
            return existing
        else
            print("[PageLifecycle] Error: attempted to create LifetimeScope for page with disposed scope")
            return nil
        end
    end

    local scope = LifetimeScope.new(page)
    page.lifetimeScope = scope
    return scope
end

---Create an ActivationScope for a page activation session.
---@param page table
---@return EmberRoutesActivationScope?
function Lifecycle.createActivationScope(page)
    if not page or page.active or page.disposed then return nil end
    local scope = ActivationScope.new(page)
    page.activationScope = scope
    return scope
end

---Convenience disposal for a page instance.
---Does NOT rely solely on page.disposed; inspects scope's own disposed state.
---@param page table?
function Lifecycle.dispose(page)
    if not page then return end

    local lifetime = page.lifetimeScope
    if lifetime then
        if not lifetime.disposed then
            lifetime:dispose()
        end
        return
    end

    if page.activationScope then
        if not page.activationScope.disposed then
            page.activationScope:dispose()
        end
    elseif page.active then
        Lifecycle.unmount(page)
    end

    page.disposed = true
    TooltipManager.unregisterOwner(page)
end

----------------------------------------------------------------
-- Backward-compatible mount / unmount API
----------------------------------------------------------------

function Lifecycle.mount(page, watch, receive)
    if not page or page.active or page.disposed then return false end
    local scope = Lifecycle.createActivationScope(page)
    if not scope then return false end

    if page.store and page.project then
        page.unsubscribe = scope:subscribe(page.store, function(value, changed)
            page:project(value, changed)
        end)
    end

    local release, reason = scope:watch(watch, receive, function(p, snapshot)
        if p.owner and type(p.owner.valid) == "function" and not p.owner:valid() then
            if type(p.owner.close) == "function" then p.owner:close() end
            return false
        end
        return true
    end)

    page.release = release
    return true
end

function Lifecycle.unmount(page)
    if not page then return end

    local scope = page.activationScope
    local oldRelease = page.release
    local oldUnsubscribe = page.unsubscribe

    -- Clear page handles first to prevent re-entrant activations from having their new handles wiped
    page.release = nil
    page.unsubscribe = nil

    if scope then
        scope:dispose()
    else
        -- Fallback if activationScope was not used
        page.active = false
        page.activation = nil
        if oldUnsubscribe then
            if type(oldUnsubscribe) == "table" and type(oldUnsubscribe.release) == "function" then
                oldUnsubscribe:release()
            elseif type(oldUnsubscribe) == "function" then
                safeCall(oldUnsubscribe)
            end
        end
        if oldRelease then
            if type(oldRelease) == "table" and type(oldRelease.release) == "function" then
                oldRelease:release()
            elseif type(oldRelease) == "function" then
                safeCall(oldRelease)
            end
        end
        TooltipManager.dismissOwner(page)
    end
end

return Lifecycle
