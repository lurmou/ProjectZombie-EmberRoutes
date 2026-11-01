-- LifecycleScope (Dual Scope Infrastructure) Regression Test Suite
--
-- Tests:
-- 1. ActivationScope core activation & token invalidation
-- 2. Explicit own(resource, disposer) with premature release handle
-- 3. Explicit defer(cleanupFn) with premature release handle
-- 4. Reverse execution order (LIFO)
-- 5. Error isolation during disposal
-- 6. Repeated dispose() idempotency
-- 7. Disposed scope rejects late resources without leak
-- 8. wrapCallback stale token gate (anti-orphan)
-- 9. Synchronous watch disposal defense (late release called immediately)
-- 10. Store subscription gate & unsubscribe
-- 11. PageLifetimeScope core lifecycle & cascade disposal
-- 12. Real business integration: Personnel DossierDrawer (persistent across tabs)
-- 13. Real business integration: Warehouse CartDrawer (transient)
-- 14. Real business integration: CraftingPage cached sub-views
-- 15. Real business integration: DefensePage instance Store subscription
-- 16. Stress test: 100 consecutive tab switches (0 leaks)
-- 17. Backward compatibility: Lifecycle.mount and Lifecycle.unmount

local checks = 0
local function check(value, message)
    assert(value, message or "Assertion failed")
    checks = checks + 1
end

-- Preserve & mock minimal PZ environment
local TooltipManager = require 'EmberRoutesProbe/UI/TooltipManager'
TooltipManager.clearAll()

local Lifecycle = require 'EmberRoutesProbe/UI/PageLifecycle'

local function makeMockPage(name)
    return {
        name = name or "TestPage",
        active = false,
        disposed = false,
        owner = {
            valid = function() return true end,
            close = function() end
        }
    }
end

----------------------------------------------------------------
-- Section 1: ActivationScope Core Activation & Token Invalidation
----------------------------------------------------------------
do
    local page = makeMockPage("S1")
    local scope = Lifecycle.createActivationScope(page)
    check(scope ~= nil, "ActivationScope created")
    check(page.active == true, "page.active set to true")
    check(type(page.activation) == "table", "page.activation token assigned")
    check(scope.token == page.activation, "scope token matches page token")
    check(scope:isCurrent() == true, "scope:isCurrent() is true")

    -- Cannot create another activation scope while active
    local scope2 = Lifecycle.createActivationScope(page)
    check(scope2 == nil, "Cannot create activation scope on already active page")

    scope:dispose()
    check(page.active == false, "page.active set to false after dispose")
    check(page.activation == nil, "page.activation token cleared after dispose")
    check(scope:isCurrent() == false, "scope:isCurrent() is false after dispose")
    check(scope.disposed == true, "scope.disposed is true")

    -- Cannot create activation scope on disposed page
    page.disposed = true
    local scope3 = Lifecycle.createActivationScope(page)
    check(scope3 == nil, "Cannot create activation scope on disposed page")
end

----------------------------------------------------------------
-- Section 2: Explicit own(resource, disposer)
----------------------------------------------------------------
do
    local page = makeMockPage("S2")
    local scope = Lifecycle.createActivationScope(page)

    -- Must require explicit disposer function
    local ok = pcall(function() scope:own({}, "not-a-function") end)
    check(not ok, "own requires an explicit disposer function")

    local disposedResource = nil
    local resource = { id = "res-1" }
    scope:own(resource, function(res)
        disposedResource = res
    end)

    check(disposedResource == nil, "Disposer not called before scope dispose")
    scope:dispose()
    check(disposedResource == resource, "Disposer called with resource on scope dispose")

    -- Premature release via handle
    local page2 = makeMockPage("S2-handle")
    local scope2 = Lifecycle.createActivationScope(page2)
    local handleResource = nil
    local resource2 = { id = "res-2" }
    local handle = scope2:own(resource2, function(res)
        handleResource = res
    end)

    check(handleResource == nil, "Disposer not called before handle release")
    handle:release()
    check(handleResource == resource2, "Disposer called on handle:release()")

    -- Handle is idempotent
    handle:release()
    handle()
    check(handleResource == resource2, "Disposer not called multiple times")

    -- On scope dispose, already-released resource is not called again
    local secondCallCount = 0
    handleResource = nil
    scope2:dispose()
    check(handleResource == nil, "Already released handle not invoked on scope:dispose()")
end

----------------------------------------------------------------
-- Section 3: Explicit defer(cleanupFn)
----------------------------------------------------------------
do
    local page = makeMockPage("S3")
    local scope = Lifecycle.createActivationScope(page)

    local ok = pcall(function() scope:defer("not-a-function") end)
    check(not ok, "defer requires a cleanup function")

    local cleanupCalled = false
    scope:defer(function()
        cleanupCalled = true
    end)

    check(not cleanupCalled, "Cleanup not called before scope dispose")
    scope:dispose()
    check(cleanupCalled, "Cleanup called on scope dispose")

    -- Premature cancel via handle
    local page2 = makeMockPage("S3-handle")
    local scope2 = Lifecycle.createActivationScope(page2)
    local cancelCalled = 0
    local handle = scope2:defer(function()
        cancelCalled = cancelCalled + 1
    end)

    check(cancelCalled == 0, "Cleanup not called before release")
    handle() -- callable handle syntax
    check(cancelCalled == 1, "Cleanup called on handle()")
    handle:release() -- idempotent
    check(cancelCalled == 1, "Handle release is idempotent")

    scope2:dispose()
    check(cancelCalled == 1, "Cleanup not called again on scope dispose")
end

----------------------------------------------------------------
-- Section 4: Reverse Execution Order (LIFO)
----------------------------------------------------------------
do
    local page = makeMockPage("S4")
    local scope = Lifecycle.createActivationScope(page)
    local order = {}

    scope:defer(function() order[#order + 1] = 1 end)
    scope:own({ id = 2 }, function(r) order[#order + 1] = r.id end)
    scope:defer(function() order[#order + 1] = 3 end)
    scope:own({ id = 4 }, function(r) order[#order + 1] = r.id end)

    scope:dispose()
    check(#order == 4, "All 4 cleanups executed")
    check(order[1] == 4 and order[2] == 3 and order[3] == 2 and order[4] == 1,
        "Reverse execution order verified (LIFO: 4, 3, 2, 1)")
end

----------------------------------------------------------------
-- Section 5: Error Isolation During Disposal
----------------------------------------------------------------
do
    local page = makeMockPage("S5")
    local scope = Lifecycle.createActivationScope(page)
    local secondExecuted = false

    scope:defer(function()
        secondExecuted = true
    end)
    scope:defer(function()
        error("Simulated cleanup crash")
    end)

    -- Disposal must not rethrow or interrupt remaining cleanups
    scope:dispose()
    check(secondExecuted == true, "Second cleanup executed despite first cleanup throwing error")
    check(scope.disposed == true, "Scope marked disposed despite error")
end

----------------------------------------------------------------
-- Section 6: Repeated dispose() Idempotency
----------------------------------------------------------------
do
    local page = makeMockPage("S6")
    local scope = Lifecycle.createActivationScope(page)
    local calls = 0

    scope:defer(function()
        calls = calls + 1
    end)

    scope:dispose()
    scope:dispose()
    scope:dispose()
    check(calls == 1, "Cleanup executed exactly once across multiple scope:dispose() calls")
end

----------------------------------------------------------------
-- Section 7: Disposed Scope Rejects Late Resources Without Leak
----------------------------------------------------------------
do
    local page = makeMockPage("S7")
    local scope = Lifecycle.createActivationScope(page)
    scope:dispose()

    local lateResourceDisposed = false
    local res = { id = "late" }
    local handle = scope:own(res, function(r)
        lateResourceDisposed = true
    end)
    check(lateResourceDisposed == true, "Late resource disposer invoked immediately on disposed scope")
    handle:release() -- safe no-op

    local lateCleanupExecuted = false
    local handle2 = scope:defer(function()
        lateCleanupExecuted = true
    end)
    check(lateCleanupExecuted == true, "Late cleanup invoked immediately on disposed scope")
    handle2:release() -- safe no-op
end

----------------------------------------------------------------
-- Section 8: wrapCallback Token Gate & Anti-Orphan
----------------------------------------------------------------
do
    local page = makeMockPage("S8")
    local scope = Lifecycle.createActivationScope(page)
    local executions = 0

    local cb = scope:wrapCallback(function(arg)
        executions = executions + 1
        return arg * 2
    end)

    local res = cb(5)
    check(executions == 1 and res == 10, "Callback executed normally while scope is current")

    -- Dispose scope: callback must be silently ignored
    scope:dispose()
    local res2 = cb(5)
    check(executions == 1 and res2 == nil, "Callback silently discarded after scope disposal")

    -- New activation session must not accept callbacks from previous session
    local scope2 = Lifecycle.createActivationScope(page)
    check(scope2 ~= nil, "Second activation session created")
    local res3 = cb(5)
    check(executions == 1 and res3 == nil, "Callback from old token rejected in new activation session")

    local cb2 = scope2:wrapCallback(function(arg)
        executions = executions + 1
        return arg * 3
    end)
    local res4 = cb2(4)
    check(executions == 2 and res4 == 12, "New callback executes in new activation session")
    scope2:dispose()
end

----------------------------------------------------------------
-- Section 9: Synchronous Watch Notification Close Defense
----------------------------------------------------------------
do
    local page = makeMockPage("S9")
    local scope = Lifecycle.createActivationScope(page)
    local releaseCalled = false

    local function fakeWatch(cb)
        -- Synchronously notify before returning release handle!
        cb({ reason = "WORLD_RESET" })
        return function()
            releaseCalled = true
        end, nil
    end

    local release, reason = scope:watch(fakeWatch, function(snapshot)
        if snapshot.reason == "WORLD_RESET" then
            -- Close dashboard / deactivate page synchronously!
            scope:dispose()
        end
    end)

    check(scope.disposed == true, "Scope was disposed during synchronous notification")
    check(releaseCalled == true, "Late-returned release function was invoked immediately upon return")
    check(release == nil, "scope:watch returned nil release handle when closed during watch")
end

----------------------------------------------------------------
-- Section 10: Store Subscription Gate
----------------------------------------------------------------
do
    local page = makeMockPage("S10")
    local scope = Lifecycle.createActivationScope(page)

    local unsubs = 0
    local mockStore = {
        subscribe = function(self, fn)
            self.listener = fn
            return function()
                unsubs = unsubs + 1
                self.listener = nil
            end
        end
    }

    local projected = 0
    scope:subscribe(mockStore, function(val)
        projected = projected + 1
    end)

    check(mockStore.listener ~= nil, "Store subscribed")
    mockStore.listener({ count = 1 })
    check(projected == 1, "Store projection executed while current")

    scope:dispose()
    check(unsubs == 1, "Store unsubscribed on scope dispose")
    check(mockStore.listener == nil, "Store listener cleared")
end

----------------------------------------------------------------
-- Section 11: PageLifetimeScope Core Lifecycle
----------------------------------------------------------------
do
    local page = makeMockPage("S11")
    local lifetime = Lifecycle.createLifetimeScope(page)
    check(lifetime ~= nil, "PageLifetimeScope created")
    check(page.lifetimeScope == lifetime, "page.lifetimeScope assigned")
    check(lifetime:isDisposed() == false, "lifetime:isDisposed() is false")

    -- 3 activation/deactivation cycles
    for i = 1, 3 do
        local act = Lifecycle.createActivationScope(page)
        check(act:isCurrent() == true, "Session " .. i .. " active")
        act:dispose()
        check(act:isCurrent() == false, "Session " .. i .. " deactivated")
        check(lifetime:isDisposed() == false, "Lifetime scope still alive after session " .. i)
    end

    local ownedDisposed = false
    lifetime:own({ id = "long-term-widget" }, function(res)
        ownedDisposed = true
    end)

    -- Active session when lifetime disposed
    local activeSession = Lifecycle.createActivationScope(page)
    check(page.active == true, "Active session before lifetime dispose")

    lifetime:dispose()
    check(page.disposed == true, "page.disposed is true")
    check(page.active == false, "Cascade disposed active session")
    check(activeSession.disposed == true, "Active session marked disposed")
    check(ownedDisposed == true, "Long-term widget disposer invoked")
    check(lifetime:isDisposed() == true, "Lifetime scope marked disposed")
end

----------------------------------------------------------------
-- Section 12: Real Business Simulation - Personnel DossierDrawer
-- (Drawer instance preserved across page switches, closed on deactivate, disposed on page dispose)
----------------------------------------------------------------
do
    local page = makeMockPage("PersonnelPage")
    local lifetime = Lifecycle.createLifetimeScope(page)

    local drawerClosed = 0
    local drawerDisposed = 0
    local mockDossierDrawer = {
        visible = false,
        close = function(self)
            self.visible = false
            drawerClosed = drawerClosed + 1
        end,
        dispose = function(self)
            drawerDisposed = drawerDisposed + 1
            self:close()
        end
    }

    -- Long-term drawer ownership on LifetimeScope
    lifetime:own(mockDossierDrawer, function(d)
        d:dispose()
    end)

    -- Activate page 1st time
    local act1 = Lifecycle.createActivationScope(page)
    mockDossierDrawer.visible = true
    act1:defer(function()
        if mockDossierDrawer.visible then
            mockDossierDrawer:close()
        end
    end)

    -- Deactivate page 1st time: drawer must CLOSE, but NOT DISPOSE
    act1:dispose()
    check(drawerClosed == 1, "Drawer closed on first page deactivate")
    check(drawerDisposed == 0, "Drawer NOT disposed on page deactivate (instance preserved)")
    check(mockDossierDrawer.visible == false, "Drawer hidden")

    -- Activate page 2nd time: re-open existing drawer instance
    local act2 = Lifecycle.createActivationScope(page)
    mockDossierDrawer.visible = true
    act2:defer(function()
        if mockDossierDrawer.visible then
            mockDossierDrawer:close()
        end
    end)

    -- Deactivate page 2nd time
    act2:dispose()
    check(drawerClosed == 2, "Drawer closed on second page deactivate")
    check(drawerDisposed == 0, "Drawer still NOT disposed")

    -- Finally Dashboard closes and disposes page instance
    lifetime:dispose()
    check(drawerDisposed == 1, "Drawer permanently disposed when page lifetime scope is disposed")
end

----------------------------------------------------------------
-- Section 13: Real Business Simulation - Warehouse CartDrawer (Transient)
----------------------------------------------------------------
do
    local page = makeMockPage("WarehousePage")

    local cartDrawerDisposed = 0
    local function makeCartDrawer()
        return {
            dispose = function()
                cartDrawerDisposed = cartDrawerDisposed + 1
            end
        }
    end

    -- 1st activation: user opens cart drawer
    local act1 = Lifecycle.createActivationScope(page)
    local cart1 = makeCartDrawer()
    act1:own(cart1, function(drawer)
        drawer:dispose()
    end)

    -- Deactivate: transient drawer MUST be disposed
    act1:dispose()
    check(cartDrawerDisposed == 1, "Cart drawer disposed on page deactivate")

    -- 2nd activation: user opens new cart drawer
    local act2 = Lifecycle.createActivationScope(page)
    local cart2 = makeCartDrawer()
    act2:own(cart2, function(drawer)
        drawer:dispose()
    end)

    act2:dispose()
    check(cartDrawerDisposed == 2, "Second cart drawer disposed on second page deactivate")
end

----------------------------------------------------------------
-- Section 14: Real Business Simulation - CraftingPage Cached Subviews
----------------------------------------------------------------
do
    local page = makeMockPage("CraftingPage")
    local lifetime = Lifecycle.createLifetimeScope(page)

    local subviews = {}
    local subviewsDisposed = 0
    for _, id in ipairs({"recipes", "orders", "maintainStock"}) do
        local view = {
            id = id,
            active = false,
            activate = function(self) self.active = true end,
            deactivate = function(self) self.active = false end,
            dispose = function(self)
                self:deactivate()
                subviewsDisposed = subviewsDisposed + 1
            end
        }
        subviews[id] = view
        lifetime:own(view, function(v) v:dispose() end)
    end

    -- Tab switch between subviews
    local act1 = Lifecycle.createActivationScope(page)
    subviews.recipes:activate()
    act1:defer(function() subviews.recipes:deactivate() end)

    act1:dispose()
    check(subviews.recipes.active == false, "recipes view deactivated on page switch")
    check(subviewsDisposed == 0, "No subviews disposed during view deactivation")

    -- Page destroyed
    lifetime:dispose()
    check(subviewsDisposed == 3, "All 3 cached subviews disposed on parent page disposal")
end

----------------------------------------------------------------
-- Section 15: Real Business Simulation - DefensePage Store Subscription
----------------------------------------------------------------
do
    local page = makeMockPage("DefensePage")
    local lifetime = Lifecycle.createLifetimeScope(page)

    local unsubCalled = 0
    local mockStore = {
        subscribe = function(self, fn)
            self.fn = fn
            return function()
                unsubCalled = unsubCalled + 1
                self.fn = nil
            end
        end
    }

    local projected = 0
    page.project = function(self, val)
        projected = projected + 1
    end

    -- Subscription created once on page initialization
    local unsub = mockStore:subscribe(function(val)
        if page.active and not page.disposed then
            page:project(val)
        end
    end)
    lifetime:defer(unsub)

    -- Switch tabs 5 times
    for i = 1, 5 do
        local act = Lifecycle.createActivationScope(page)
        mockStore.fn({ alert = i })
        check(projected == i, "Project called when active (cycle " .. i .. ")")
        act:dispose()
        mockStore.fn({ alert = 999 })
        check(projected == i, "Project NOT called when inactive (cycle " .. i .. ")")
        check(unsubCalled == 0, "Store subscription preserved across tab switches")
    end

    lifetime:dispose()
    check(unsubCalled == 1, "Store subscription unsubscribed exactly once on page dispose")
end

----------------------------------------------------------------
-- Section 16: Stress Test - 100 Consecutive Tab Switches
----------------------------------------------------------------
do
    local pageA = makeMockPage("PageA")
    local pageB = makeMockPage("PageB")

    local watchesA, watchesB = 0, 0
    local unsubsA, unsubsB = 0, 0

    local function watchA(cb)
        watchesA = watchesA + 1
        return function() watchesA = watchesA - 1 end
    end
    local function watchB(cb)
        watchesB = watchesB + 1
        return function() watchesB = watchesB - 1 end
    end

    for i = 1, 100 do
        local actA = Lifecycle.createActivationScope(pageA)
        actA:watch(watchA, function() end)
        actA:defer(function() unsubsA = unsubsA + 1 end)
        check(watchesA == 1, "Watch A active")
        actA:dispose()
        check(watchesA == 0, "Watch A released immediately on switch")

        local actB = Lifecycle.createActivationScope(pageB)
        actB:watch(watchB, function() end)
        actB:defer(function() unsubsB = unsubsB + 1 end)
        check(watchesB == 1, "Watch B active")
        actB:dispose()
        check(watchesB == 0, "Watch B released immediately on switch")
    end

    check(watchesA == 0 and watchesB == 0, "0 watch leaks after 100 cycles")
    check(unsubsA == 100 and unsubsB == 100, "100 cleans performed for both pages")
end

----------------------------------------------------------------
-- Section 17: Backward Compatibility - Lifecycle.mount & unmount
----------------------------------------------------------------
do
    local page = makeMockPage("LegacyPage")
    page.store = {
        subscribe = function(self, fn)
            self.fn = fn
            return function() self.fn = nil end
        end
    }
    local legacyProjected = 0
    page.project = function(self, val)
        legacyProjected = legacyProjected + 1
    end

    local releaseCalled = false
    local watchReceived = nil
    local function legacyWatch(cb)
        cb({ state = "READY", rows = { 1, 2, 3 } })
        return function()
            releaseCalled = true
        end
    end

    local mounted = Lifecycle.mount(page, legacyWatch, function(snapshot)
        watchReceived = snapshot
    end)

    check(mounted == true, "Lifecycle.mount returned true")
    check(page.active == true, "page.active set to true by mount")
    check(page.activation ~= nil, "page.activation token assigned")
    check(page.release ~= nil, "page.release assigned")
    check(watchReceived and watchReceived.state == "READY", "Snapshot received")

    page.store.fn({ update = true })
    check(legacyProjected == 1, "page.project called via store subscription")

    Lifecycle.unmount(page)
    check(page.active == false, "page.active set to false by unmount")
    check(page.activation == nil, "page.activation token cleared")
    check(releaseCalled == true, "Legacy release called")

    -- Re-mount works cleanly
    local reMounted = Lifecycle.mount(page, legacyWatch, function() end)
    check(reMounted == true, "Lifecycle.mount can be called again on next activation")
    Lifecycle.unmount(page)
    check(page.active == false, "Lifecycle.unmount succeeds again")
end

print("lifecycle-scope: " .. checks .. " PASS")
return true
