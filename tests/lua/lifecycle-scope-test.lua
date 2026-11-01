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
-- 12. Contract verification: Personnel DossierDrawer pattern (persistent across tabs)
-- 13. Contract verification: Warehouse CartDrawer pattern (transient)
-- 14. Contract verification: CraftingPage cached sub-views pattern
-- 15. Contract verification: DefensePage instance Store subscription pattern
-- 16. Stress test: 100 consecutive simulated tab switches (0 leaks)
-- 17. Backward compatibility: Lifecycle.mount and Lifecycle.unmount
-- 18. Task 1.6A P1-1: unmount handle cleanup and re-entrancy defense
-- 19. Task 1.6A P1-2: unified releaseEntry reference severing (normal and error paths)
-- 20. Task 1.6A P1-3: LifetimeScope anti-duplicate and disposed state protection
-- 21. Task 1.6A P1-4: Lifecycle.dispose independent of page.disposed early exit

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

-- ================================================================
-- Task 1.6A P1 Defect Hardening Regression Tests
-- ================================================================

-- Section 18: Task 1.6A P1-1 Regression - Unmount Clears Old Handles & Re-entrancy
do
    local page = { active = false, store = { subscribe = function(self, fn) return function() end end }, project = function() end }
    local watchReleaseCalls = 0
    local unsubCalls = 0
    local function testWatch(cb)
        return function() watchReleaseCalls = watchReleaseCalls + 1 end
    end
    page.store.subscribe = function(self, fn)
        return function() unsubCalls = unsubCalls + 1 end
    end

    local ok = Lifecycle.mount(page, testWatch, function() end)
    check(ok == true, "P1-1: Mount successful")
    check(page.release ~= nil, "P1-1: page.release is non-nil after mount")
    check(page.unsubscribe ~= nil, "P1-1: page.unsubscribe is non-nil after mount")

    Lifecycle.unmount(page)
    check(page.release == nil, "P1-1: page.release is nil after unmount")
    check(page.unsubscribe == nil, "P1-1: page.unsubscribe is nil after unmount")
    check(watchReleaseCalls == 1, "P1-1: Watch release called exactly once")
    check(unsubCalls == 1, "P1-1: Unsubscribe called exactly once")

    -- Second mount establishes new session cleanly
    local ok2 = Lifecycle.mount(page, testWatch, function() end)
    check(ok2 == true, "P1-1: Second mount successful")
    check(page.release ~= nil, "P1-1: New release handle assigned")
    check(page.unsubscribe ~= nil, "P1-1: New unsubscribe handle assigned")

    Lifecycle.unmount(page)
    check(page.release == nil, "P1-1: release cleared after second unmount")
    check(page.unsubscribe == nil, "P1-1: unsubscribe cleared after second unmount")
    check(watchReleaseCalls == 2, "P1-1: Second watch release called exactly once")
    check(unsubCalls == 2, "P1-1: Second unsubscribe called exactly once")

    -- Re-entrancy defense: cleanup callback triggers re-activation
    local reentrantPage = { active = false }
    local cleanupRan = false
    local act = Lifecycle.createActivationScope(reentrantPage)
    act:defer(function()
        cleanupRan = true
        -- Synchronous re-activation attempt during unmount/dispose
        local newAct = Lifecycle.createActivationScope(reentrantPage)
        if newAct then
            reentrantPage.release = function() end
        end
    end)
    Lifecycle.unmount(reentrantPage)
    check(cleanupRan == true, "P1-1: Cleanup ran during unmount")
end

-- Section 19: Task 1.6A P1-2 Regression - releaseEntry Severing of fn and resource
do
    local page = {}
    local lifetime = Lifecycle.createLifetimeScope(page)

    -- Case 1: own resource released via handle
    local res1 = { id = "res1" }
    local disposer1Called = false
    local handle1 = lifetime:own(res1, function(r)
        disposer1Called = true
    end)
    -- Inspect internal entry
    local entry1 = lifetime.entries[#lifetime.entries]
    check(entry1.resource == res1, "P1-2: entry1 holds resource initially")
    check(type(entry1.fn) == "function", "P1-2: entry1 holds fn initially")
    handle1:release()
    check(disposer1Called == true, "P1-2: Disposer called via handle")
    check(entry1.released == true, "P1-2: entry1 marked released")
    check(entry1.resource == nil, "P1-2: entry1.resource cleared to nil after release")
    check(entry1.fn == nil, "P1-2: entry1.fn cleared to nil after release")
    -- Calling handle again is a no-op
    handle1:release()
    check(entry1.resource == nil and entry1.fn == nil, "P1-2: Redundant handle release remains clean")

    -- Case 2: own resource released via Scope:dispose()
    local res2 = { id = "res2" }
    local disposer2Called = false
    lifetime:own(res2, function(r)
        disposer2Called = true
    end)
    local entry2 = lifetime.entries[#lifetime.entries]
    check(entry2.resource == res2, "P1-2: entry2 holds resource initially")

    -- Case 3: defer released via handle
    local defer1Called = false
    local deferHandle = lifetime:defer(function()
        defer1Called = true
    end)
    local entry3 = lifetime.entries[#lifetime.entries]
    check(type(entry3.fn) == "function", "P1-2: entry3 holds fn initially")
    deferHandle:release()
    check(defer1Called == true, "P1-2: Defer callback called via handle")
    check(entry3.fn == nil, "P1-2: entry3.fn cleared to nil after handle release")

    -- Case 4: Exception during release: references STILL cleared and subsequent cleanups continue
    local crashRes = { id = "crash-res" }
    lifetime:own(crashRes, function(r)
        error("Simulated disposer error")
    end)
    local crashEntry = lifetime.entries[#lifetime.entries]

    local postCrashCalled = false
    lifetime:defer(function()
        postCrashCalled = true
    end)
    local postCrashEntry = lifetime.entries[#lifetime.entries]

    -- Dispose lifetime scope: LIFO order processes postCrashEntry, crashEntry, then entry2
    lifetime:dispose()
    check(postCrashCalled == true, "P1-2: Cleanup before crash executed")
    check(disposer2Called == true, "P1-2: Disposer after crash executed (error isolation)")
    check(crashEntry.resource == nil, "P1-2: crashEntry.resource cleared even on exception")
    check(crashEntry.fn == nil, "P1-2: crashEntry.fn cleared even on exception")
    check(entry2.resource == nil, "P1-2: entry2.resource cleared via Scope:dispose")
    check(entry2.fn == nil, "P1-2: entry2.fn cleared via Scope:dispose")
    check(postCrashEntry.fn == nil, "P1-2: postCrashEntry.fn cleared via Scope:dispose")

    -- Same check for ActivationScope
    local actPage = {}
    local actScope = Lifecycle.createActivationScope(actPage)
    local actRes = { id = "act-res" }
    actScope:own(actRes, function() end)
    local actEntry = actScope.entries[#actScope.entries]
    actScope:dispose()
    check(actEntry.resource == nil, "P1-2: ActivationScope own entry resource cleared on dispose")
    check(actEntry.fn == nil, "P1-2: ActivationScope own entry fn cleared on dispose")
end

-- Section 20: Task 1.6A P1-3 Regression - LifetimeScope Anti-Duplicate & State Guard
do
    local page = {}
    local scope1 = Lifecycle.createLifetimeScope(page)
    check(scope1 ~= nil, "P1-3: First LifetimeScope created")
    check(page.lifetimeScope == scope1, "P1-3: page.lifetimeScope set to scope1")

    -- Repeat createLifetimeScope on same page returns existing scope
    local scope2 = Lifecycle.createLifetimeScope(page)
    check(scope2 == scope1, "P1-3: Second call returns existing scope1")

    -- Resources registered in scope1 are not lost
    local cleanupCalled = false
    scope1:defer(function() cleanupCalled = true end)

    local scope3 = Lifecycle.createLifetimeScope(page)
    check(scope3 == scope1, "P1-3: Third call still returns scope1")
    check(#scope1.entries >= 1, "P1-3: scope1 entries retained")

    -- Disposing scope1
    scope1:dispose()
    check(cleanupCalled == true, "P1-3: Cleanup called upon dispose")
    check(scope1.disposed == true, "P1-3: scope1 marked disposed")

    -- Cannot create new LifetimeScope on disposed page
    local scope4 = Lifecycle.createLifetimeScope(page)
    check(scope4 == nil, "P1-3: createLifetimeScope returns nil on disposed page")

    -- Cannot create on nil page
    check(Lifecycle.createLifetimeScope(nil) == nil, "P1-3: createLifetimeScope returns nil for nil page")

    -- State mismatch test: scope is disposed while page.disposed is artificially false
    local mismatchPage = {}
    local mismatchScope = Lifecycle.createLifetimeScope(mismatchPage)
    mismatchScope:dispose()
    mismatchPage.disposed = false -- artificially altered
    local rejectedScope = Lifecycle.createLifetimeScope(mismatchPage)
    check(rejectedScope == nil, "P1-3: Rejects creation when existing scope is disposed")
end

-- Section 21: Task 1.6A P1-4 Regression - Lifecycle.dispose Unconditional Scope Checking
do
    -- Case 1: User specified contract: page.disposed is true, but LifetimeScope was NOT disposed yet
    local page1 = {}
    local lifetime1 = Lifecycle.createLifetimeScope(page1)
    local cleanup1Count = 0
    lifetime1:defer(function()
        cleanup1Count = cleanup1Count + 1
    end)
    -- External code set page.disposed = true prematurely
    page1.disposed = true

    Lifecycle.dispose(page1)
    check(lifetime1.disposed == true, "P1-4: lifetime1 disposed despite page1.disposed being true initially")
    check(cleanup1Count == 1, "P1-4: Deferred cleanup executed exactly once")

    -- Repeated Lifecycle.dispose call is idempotent
    Lifecycle.dispose(page1)
    check(cleanup1Count == 1, "P1-4: Repeated dispose does not duplicate cleanup")

    -- Case 2: No LifetimeScope, but has active ActivationScope
    local page2 = { active = false }
    local actScope = Lifecycle.createActivationScope(page2)
    local actCleanupCount = 0
    actScope:defer(function()
        actCleanupCount = actCleanupCount + 1
    end)
    check(page2.active == true, "P1-4: page2 active before dispose")

    Lifecycle.dispose(page2)
    check(page2.disposed == true, "P1-4: page2 marked disposed")
    check(page2.active == false, "P1-4: page2 deactivated by dispose")
    check(actCleanupCount == 1, "P1-4: ActivationScope cleanup executed")

    -- Case 3: No scopes, legacy mount page
    local page3 = { active = false }
    local watchReleased = false
    Lifecycle.mount(page3, function(cb)
        return function() watchReleased = true end
    end, function() end)
    check(page3.active == true, "P1-4: Legacy page3 active")

    Lifecycle.dispose(page3)
    check(page3.disposed == true, "P1-4: page3 marked disposed")
    check(page3.active == false, "P1-4: page3 deactivated")
    check(watchReleased == true, "P1-4: Legacy watch released by dispose")

    -- Case 4: dispose(nil) is safe
    Lifecycle.dispose(nil)
end

print("lifecycle-scope: " .. checks .. " PASS")
return true
