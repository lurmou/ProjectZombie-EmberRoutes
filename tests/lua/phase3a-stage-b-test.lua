-- =========================================================================
-- Phase 3A Stage B Unit Tests: LaborClaims (F2/F3) & LaborStore Atomic Operations
-- =========================================================================

package.path = './Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;./Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;./tests/lua/?.lua;' .. package.path

local Claims = require 'EmberRoutesProbe/LaborClaims'
local Store = require 'EmberRoutesProbe/LaborStore'
local JobStore = require 'EmberRoutesProbe/JobStore'
local TaskJobs = require 'EmberRoutesProbe/TaskJobs'
local ContainerRegistry = require 'EmberRoutesProbe/ContainerRegistry'

local function assertTrue(cond, msg)
    if not cond then error("ASSERTION_FAILED: " .. tostring(msg)) end
end

local function assertFalse(cond, msg)
    if cond then error("ASSERTION_FAILED_EXPECTED_FALSE: " .. tostring(msg)) end
end

local function assertEq(actual, expected, msg)
    if actual ~= expected then
        error("ASSERTION_FAILED: " .. tostring(msg) .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
    end
end

print("Starting Phase 3A Stage B Tests...")

-- =========================================================================
-- Part 1: LaborClaims F2 & F3 Invariants
-- =========================================================================

local claims = Claims.new()
assertTrue(claims ~= nil, "Claims.new() should succeed")
assertEq(claims.revision, 0, "Initial revision should be 0")

-- Test 1.1: acquireNew succeeds for unique taskId and resources
local t1, err1 = claims:acquireNew("task-1", 1, { "item:101", "item:102" })
assertTrue(t1 ~= nil, "acquireNew should succeed: " .. tostring(err1))
assertEq(t1.taskId, "task-1", "Token taskId match")
assertTrue(claims:valid(t1, "item:101"), "item:101 should be valid for t1")
assertTrue(claims:valid(t1, "item:102"), "item:102 should be valid for t1")
assertEq(claims.revision, 1, "Revision incremented to 1")

-- Test 1.2: F2 - acquireNew MUST reject duplicate taskId (TASK_ALREADY_HAS_CLAIMS)
local t1_dup, err1_dup = claims:acquireNew("task-1", 2, { "item:103" })
assertFalse(t1_dup ~= nil, "acquireNew with duplicate taskId MUST be rejected")
assertEq(err1_dup, "TASK_ALREADY_HAS_CLAIMS", "Error must be TASK_ALREADY_HAS_CLAIMS")
-- Verify original claims for task-1 were not corrupted
assertTrue(claims:valid(t1, "item:101"), "Original claim 101 intact")
assertFalse(claims.owners["item:103"] ~= nil, "item:103 was not claimed")

-- Test 1.3: acquireNew rejects conflicting item
local t2_conflict, err2_conflict = claims:acquireNew("task-2", 1, { "item:101", "item:104" })
assertFalse(t2_conflict ~= nil, "acquireNew with already claimed item MUST fail")
assertEq(err2_conflict, "ITEM_RESERVED", "Error must be ITEM_RESERVED")
assertFalse(claims.owners["item:104"] ~= nil, "item:104 not claimed on conflict")

-- Test 1.4: acquireNew rejects duplicate items within arguments
local t3_dup, err3_dup = claims:acquireNew("task-3", 1, { "item:105", "item:105" })
assertFalse(t3_dup ~= nil, "acquireNew with duplicated arguments must fail")
assertEq(err3_dup, "RESOURCE_DUPLICATED", "Error must be RESOURCE_DUPLICATED")

-- Test 1.5: F3 - Quarantine kernel ownership & acquire blocking
claims:quarantine("item:999")
assertEq(claims.owners["item:999"].kind, "SYSTEM_QUARANTINE", "Owner kind must be SYSTEM_QUARANTINE")

local t_quar, err_quar = claims:acquireNew("task-q", 1, { "item:999" })
assertFalse(t_quar ~= nil, "acquireNew on quarantined item MUST fail")
assertEq(err_quar, "RESOURCE_SYSTEM_QUARANTINED", "Error must be RESOURCE_SYSTEM_QUARANTINED")

local t_quar_old, err_quar_old = claims:acquire("task-q", 1, { "item:999" })
assertFalse(t_quar_old ~= nil, "acquire on quarantined item MUST fail")
assertEq(err_quar_old, "RESOURCE_SYSTEM_QUARANTINED", "Error must be RESOURCE_SYSTEM_QUARANTINED")

-- Test 1.6: extend & replace respect quarantine
local t_norm = claims:acquireNew("task-norm", 1, { "item:201" })
assertTrue(t_norm ~= nil, "acquireNew task-norm")
local okExt, errExt = claims:extend(t_norm, { "item:999" })
assertFalse(okExt, "extend on quarantined item must fail")
assertEq(errExt, "RESOURCE_SYSTEM_QUARANTINED", "Error must be RESOURCE_SYSTEM_QUARANTINED")

local okRep, errRep = claims:replace(t_norm, { "item:999" })
assertFalse(okRep, "replace on quarantined item must fail")
assertEq(errRep, "RESOURCE_SYSTEM_QUARANTINED", "Error must be RESOURCE_SYSTEM_QUARANTINED")

-- Test 1.7: unquarantine allows subsequent claim
assertTrue(claims:unquarantine("item:999"), "unquarantine should succeed")
local t_post_q, err_post_q = claims:acquireNew("task-post-q", 1, { "item:999" })
assertTrue(t_post_q ~= nil, "acquireNew on unquarantined item should succeed: " .. tostring(err_post_q))

-- Test 1.8: release cleans up tokensByTaskId and owners
claims:release(t1)
assertFalse(claims:valid(t1, "item:101"), "item:101 released")
assertFalse(claims:valid(t1, "item:102"), "item:102 released")
-- task-1 can now be acquired as a fresh task
local t1_new, err1_new = claims:acquireNew("task-1", 1, { "item:101" })
assertTrue(t1_new ~= nil, "acquireNew with task-1 after release should succeed")

-- Test 1.9: B.1 - Quarantine independent per-resource ownership
claims:quarantine("item:901")
claims:quarantine("item:902")
local q1 = claims.owners["item:901"]
local q2 = claims.owners["item:902"]
assertTrue(q1 ~= nil and q2 ~= nil, "Quarantine records exist")
assertEq(q1.kind, "SYSTEM_QUARANTINE", "q1 is SYSTEM_QUARANTINE")
assertEq(q2.kind, "SYSTEM_QUARANTINE", "q2 is SYSTEM_QUARANTINE")
assertEq(q1.resource, "item:901", "q1 resource key matches")
assertEq(q2.resource, "item:902", "q2 resource key matches")
assertTrue(q1 ~= q2, "Each quarantined resource MUST have independent ownership record")

-- Test 1.10: B.1 - Quarantine strips resource from original token without breaking shrink
local t_strip, err_strip = claims:acquireNew("task-strip", 1, { "item:501", "item:502" })
assertTrue(t_strip ~= nil, "acquireNew task-strip")
assertEq(#t_strip.resources, 2, "Original resources length is 2")
-- Quarantine item:501
claims:quarantine("item:501")
local q_stripped = claims.owners["item:501"]
assertEq(q_stripped.originalTaskId, "task-strip", "Quarantine records original taskId")
assertTrue(q_stripped.originalToken == t_strip, "Quarantine records original token")
assertEq(#t_strip.resources, 1, "item:501 stripped from token resources")
assertEq(t_strip.resources[1], "item:502", "item:502 remains in token resources")
-- Normal shrink on remaining resource MUST NOT fail with STALE_CLAIM!
local okShrinkRem, errShrinkRem = claims:shrink(t_strip, { "item:502" })
assertTrue(okShrinkRem, "shrink on remaining resource must succeed: " .. tostring(errShrinkRem))
assertFalse(claims:valid(t_strip, "item:502"), "item:502 released")

-- Test 1.11: B.1 - canShrink non-destructive pre-validation
local t_cs, err_cs = claims:acquireNew("task-cs", 1, { "item:601", "item:602" })
assertTrue(t_cs ~= nil, "acquireNew task-cs")
local revBefore = claims.revision
-- Valid shrink precheck
assertTrue(claims:canShrink(t_cs, { "item:601" }), "canShrink valid key returns true")
assertEq(claims.revision, revBefore, "canShrink MUST NOT mutate revision")
assertTrue(claims:valid(t_cs, "item:601"), "canShrink MUST NOT release owner")
-- Invalid prechecks
assertFalse(claims:canShrink(t_cs, { "item:99999" }), "canShrink non-owned key returns false")
assertFalse(claims:canShrink(t_cs, { "item:601", "item:601" }), "canShrink duplicate keys returns false")
assertFalse(claims:canShrink(nil, { "item:601" }), "canShrink nil token returns false")

-- Test 1.12: B.1 - shrink handles quarantined resource cleanup & deferred capacity release
local t_def, err_def = claims:acquireNew("task-deferred", 1, { "item:701" })
assertTrue(t_def ~= nil, "acquireNew task-deferred")
local okResDef, errResDef = claims:reserve(t_def, "box-def", 701, 10.0, 20.0)
assertTrue(okResDef, "reserve on box-def must succeed: " .. tostring(errResDef))
assertEq(claims.capacity["box-def"].total, 10.0, "Capacity reserved is 10.0")

-- Quarantine item:701; capacity must be DEFERRED, not released prematurely
claims:quarantine("item:701")
assertEq(claims.capacity["box-def"].total, 10.0, "Capacity remains deferred in bucket on quarantine")

-- Another token CANNOT shrink task-deferred's quarantined item
local t_other, _ = claims:acquireNew("task-other", 1, { "item:702" })
assertFalse(claims:canShrink(t_other, { "item:701" }), "Foreign token cannot shrink other token's quarantine")
assertFalse(claims:shrink(t_other, { "item:701" }), "Foreign token shrink must fail")

-- Original token CAN shrink its quarantined item to release deferred capacity
assertTrue(claims:canShrink(t_def, { "item:701" }), "Original token canShrink quarantined item returns true")
local okShrinkDef, errShrinkDef = claims:shrink(t_def, { "item:701" })
assertTrue(okShrinkDef, "shrink quarantined item by original owner must succeed: " .. tostring(errShrinkDef))
-- Verify deferred capacity is cleanly released!
assertTrue(claims.capacity["box-def"] == nil or claims.capacity["box-def"].total == 0, "Capacity cleanly released after shrink")
-- Verify resource itself remains quarantined from world
assertEq(claims.owners["item:701"].kind, "SYSTEM_QUARANTINE", "Item remains system quarantined")
assertFalse(claims.owners["item:701"].originalTaskId ~= nil, "Original taskId unlinked after shrink")

-- Test 1.13: B.1 - reserve enforces mandatory realtime free capacity
local t_cap, err_cap = claims:acquireNew("task-cap", 1, { "item:801" })
assertTrue(t_cap ~= nil, "acquireNew task-cap")
-- Missing free capacity (nil) MUST fail with CAPACITY_UNAVAILABLE
local okNoFree, errNoFree = claims:reserve(t_cap, "box-cap", 801, 5.0, nil)
assertFalse(okNoFree, "reserve without free capacity MUST fail")
assertEq(errNoFree, "CAPACITY_UNAVAILABLE", "Error must be CAPACITY_UNAVAILABLE")

-- Negative or NaN free capacity MUST fail
assertFalse(claims:reserve(t_cap, "box-cap", 801, 5.0, -1.0), "Negative free must fail")
assertFalse(claims:reserve(t_cap, "box-cap", 801, 5.0, 0/0), "NaN free must fail")

-- Exceeding free capacity MUST fail with CAPACITY_RESERVED
local okOver, errOver = claims:reserve(t_cap, "box-cap", 801, 10.0, 5.0)
assertFalse(okOver, "Exceeding capacity must fail")
assertEq(errOver, "CAPACITY_RESERVED", "Error must be CAPACITY_RESERVED")

-- Valid realtime free capacity succeeds
local okValidCap, errValidCap = claims:reserve(t_cap, "box-cap", 801, 10.0, 15.0)
assertTrue(okValidCap, "reserve with valid free capacity must succeed: " .. tostring(errValidCap))
assertEq(claims.capacity["box-cap"].total, 10.0, "Capacity reserved total matches")

-- Test 1.14: B.5 - Quarantine ownership prevents unauthorized shrink by new token with same taskId
do
    local t_gen1, _ = claims:acquireNew("task-gen-test", 1, { "item:850" })
    assertTrue(t_gen1 ~= nil, "acquireNew task-gen-test gen 1")
    claims:quarantine("item:850")
    assertEq(claims.owners["item:850"].originalGeneration, 1, "originalGeneration is 1")

    -- Release gen 1 token
    claims:release(t_gen1)

    -- Create a new token with same taskId but generation = 2
    local t_gen2, _ = claims:acquireNew("task-gen-test", 2, { "item:851" })
    assertTrue(t_gen2 ~= nil, "acquireNew task-gen-test gen 2")

    -- Attempt by new token (gen 2) to canShrink old quarantined item 850 MUST FAIL!
    assertFalse(claims:canShrink(t_gen2, { "item:850" }), "New token with same taskId cannot shrink old generation quarantine")
    assertFalse(claims:shrink(t_gen2, { "item:850" }), "shrink by new token must fail")

    -- Attempt by recreated token with SAME generation (1) but different claimId MUST ALSO FAIL!
    claims:release(t_gen2)
    local t_gen1_recreated, _ = claims:acquireNew("task-gen-test", 1, { "item:852" })
    assertTrue(t_gen1_recreated ~= nil, "acquireNew task-gen-test recreated at gen 1")
    assertFalse(claims:canShrink(t_gen1_recreated, { "item:850" }), "Recreated token with same taskId and generation cannot shrink old quarantine (non-reusable claimId)")
    assertFalse(claims:shrink(t_gen1_recreated, { "item:850" }), "shrink by recreated token must fail")
end

-- Test 1.15: B.5 - Capacity quarantine lifecycle: reserve -> quarantine -> release(token) -> capacity remains reserved -> unquarantine/shrink -> released
do
    local t_cap_life, _ = claims:acquireNew("task-cap-life", 1, { "item:860" })
    assertTrue(t_cap_life ~= nil, "acquireNew task-cap-life")
    local okResLife, _ = claims:reserve(t_cap_life, "box-life", 860, 20.0, 50.0)
    assertTrue(okResLife, "reserve 20 on box-life")
    assertEq(claims.capacity["box-life"].total, 20.0, "Capacity is 20")

    -- Step 1: Quarantine item:860
    claims:quarantine("item:860")
    assertEq(claims.capacity["box-life"].total, 20.0, "Capacity remains 20 after quarantine")

    -- Step 2: Release original token: capacity MUST REMAIN RESERVED in bucket.total!
    claims:release(t_cap_life)
    assertEq(claims.capacity["box-life"].total, 20.0, "Capacity MUST REMAIN 20 after release(originalToken)")

    -- Another task trying to reserve 35 (when container only had 50 free, 50 - 20 = 30 available) MUST BE BLOCKED!
    local t_other_cap, _ = claims:acquireNew("task-other-cap", 1, { "item:861" })
    local okOverLife, errOverLife = claims:reserve(t_other_cap, "box-life", 861, 35.0, 50.0)
    assertFalse(okOverLife, "Reservation exceeding available space blocked because quarantined capacity is retained")
    assertEq(errOverLife, "CAPACITY_RESERVED", "Error is CAPACITY_RESERVED")

    -- Reservation within available space (30) succeeds (e.g. 25)
    local okValidLife, _ = claims:reserve(t_other_cap, "box-life", 861, 25.0, 50.0)
    assertTrue(okValidLife, "Reservation within remaining space succeeds")
    assertEq(claims.capacity["box-life"].total, 45.0, "Capacity is now 20 + 25 = 45")

    -- Step 3: Formally unquarantine item:860: its 20 units of capacity are now cleanly released!
    claims:unquarantine("item:860")
    assertEq(claims.capacity["box-life"].total, 25.0, "Capacity reduced to 25 after unquarantine")
end

print("PASS Part 1: LaborClaims F2 & F3 invariants.")

-- =========================================================================
-- Part 2: LaborStore Quarantine & Snapshot Isolation
-- =========================================================================

-- Setup mock game root environment
local mockRoot = {
    format = 1,
    taskJobs = { format = 1, byId = {} },
    containers = {},
    quarantineResources = {}
}
ContainerRegistry.data = function() return mockRoot end
Store.data()

-- Test 2.1: Store.quarantineResource persists and acquires quarantine lock
Store.quarantineResource("item:888", "ITEM_CORRUPTED", { note = "test corruption" })
assertTrue(mockRoot.quarantineResources["item:888"] ~= nil, "quarantineResources must be persisted in root")
assertEq(mockRoot.quarantineResources["item:888"].reason, "ITEM_CORRUPTED", "Quarantine reason recorded")

-- Test 2.2: Store.owner & Store.resourceOwner return read-only snapshots
local snap1 = Store.owner(888)
assertTrue(snap1 ~= nil, "Owner snapshot exists")
assertEq(snap1.kind, "SYSTEM_QUARANTINE", "Snapshot kind is SYSTEM_QUARANTINE")

-- Mutating the snapshot does not mutate the internal table
snap1.kind = "HACKED"
local snap2 = Store.owner(888)
assertEq(snap2.kind, "SYSTEM_QUARANTINE", "Internal table was not mutated by snapshot mutation")

-- Test 2.3: Store.claimsVersion returns integer revision
local ver = Store.claimsVersion()
assertTrue(type(ver) == "number" and ver >= 0, "claimsVersion must be a non-negative number")

print("PASS Part 2: LaborStore Quarantine & Snapshot Isolation.")

-- =========================================================================
-- Part 3: Store.createClaimedJob Atomic Creation & Rollback
-- =========================================================================

local validCraftJob = {
    id = "craft-stage-b-1",
    npcId = "npc-b1",
    providerType = "CRAFT",
    scopeId = "settlement-1",
    revision = 1,
    state = "PREPARING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        format = 4,
        id = "craft-stage-b-1",
        npcId = "npc-b1",
        sequence = 1,
        recipeId = "Base.MakeAxe",
        target = 1,
        produced = 0,
        materials = { { id = 301, consumed = false } },
        tools = { { id = 302 } },
        outputs = {},
        claims = { "item:301", "item:302" }
    }
}

-- Test 3.1: createClaimedJob successfully creates valid job
local okCreate, jobIdCreated = Store.createClaimedJob(validCraftJob)
assertTrue(okCreate, "createClaimedJob should succeed: " .. tostring(jobIdCreated))
assertEq(jobIdCreated, "craft-stage-b-1", "Created jobId match")

-- Token and owners verified
local token = Store.getToken("craft-stage-b-1")
assertTrue(token ~= nil, "Runtime token exists for created job")
assertEq(token.taskId, "craft-stage-b-1", "Token taskId matches")
local owner301 = Store.owner(301)
assertEq(owner301.taskId, "craft-stage-b-1", "Item 301 owned by craft-stage-b-1")

-- Test 3.2: Repeating createClaimedJob with same ID fails (F2: duplicate takeover prevented)
local dupJob = {
    id = "craft-stage-b-1",
    npcId = "npc-b2",
    providerType = "CRAFT",
    scopeId = "settlement-1",
    revision = 1,
    state = "PREPARING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        format = 4,
        id = "craft-stage-b-1",
        npcId = "npc-b1",
        sequence = 1,
        recipeId = "Base.MakeAxe",
        target = 1,
        produced = 0,
        materials = { { id = 303, consumed = false } },
        tools = {},
        outputs = {},
        claims = { "item:303" }
    }
}
local okDup, errDup = Store.createClaimedJob(dupJob)
assertFalse(okDup, "createClaimedJob with duplicate ID MUST fail")
assertTrue(string.find(errDup, "TASK_ALREADY_HAS_CLAIMS") ~= nil, "Error should indicate TASK_ALREADY_HAS_CLAIMS: " .. tostring(errDup))
-- Original token and claims are untouched!
local tokenPostDup = Store.getToken("craft-stage-b-1")
assertTrue(tokenPostDup == token, "Original token remains unchanged")
assertFalse(Store.owner(303) ~= nil, "Item 303 was not claimed")

-- Test 3.3: Capacity failure rolls back acquired claims
local haulWithCapFail = {
    id = "haul-cap-fail",
    npcId = "npc-b3",
    providerType = "HAUL",
    scopeId = "settlement-1",
    revision = 1,
    state = "PREPARING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        format = 3,
        sequence = 1,
        source = "cont-a",
        destination = "cont-b",
        manifest = { { itemId = 401, custodyState = "UNCOLLECTED" } },
        claims = { "item:401" },
        reservation = {
            format = 2,
            key = "cont-b",
            items = { [99999] = 50.0 } -- item 99999 is not in claims, so capacity reserve fails
        }
    }
}
local okCapFail, errCapFail = Store.createClaimedJob(haulWithCapFail)
assertFalse(okCapFail, "Job creation with capacity failure must fail")
assertEq(errCapFail, "CAPACITY_RESERVE_FAILED", "Error should be CAPACITY_RESERVE_FAILED")
-- Item 401 must be rolled back and NOT owned
assertFalse(Store.owner(401) ~= nil, "Item 401 claim was cleanly rolled back")

-- Test 3.4: B.1 - createClaimedJob without free capacity fact MUST fail and rollback
local haulNoFree = {
    id = "haul-no-free",
    npcId = "npc-b4",
    providerType = "HAUL",
    scopeId = "settlement-1",
    revision = 1,
    state = "PREPARING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        format = 3,
        sequence = 1,
        source = "cont-a",
        destination = "cont-b",
        manifest = { { itemId = 402, custodyState = "UNCOLLECTED" } },
        claims = { "item:402" },
        reservation = {
            format = 2,
            key = "cont-b",
            items = { [402] = 5.0 } -- item 402 is in claims, but no free capacity fact
        }
    }
}
local okNoFreeJob, errNoFreeJob = Store.createClaimedJob(haulNoFree)
assertFalse(okNoFreeJob, "Job creation without free capacity must fail")
assertEq(errNoFreeJob, "CAPACITY_RESERVE_FAILED", "Error should be CAPACITY_RESERVE_FAILED")
assertFalse(Store.owner(402) ~= nil, "Item 402 claim was cleanly rolled back")

-- Test 3.5: B.1 - createClaimedJob with valid free capacity fact succeeds
local haulWithFree = {
    id = "haul-with-free",
    npcId = "npc-b5",
    providerType = "HAUL",
    scopeId = "settlement-1",
    revision = 1,
    state = "PREPARING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        format = 3,
        sequence = 1,
        source = "cont-a",
        destination = "cont-b",
        manifest = { { itemId = 403, custodyState = "UNCOLLECTED" } },
        claims = { "item:403" },
        reservation = {
            format = 2,
            key = "cont-b",
            items = { [403] = 5.0 },
            free = 15.0 -- Valid realtime free capacity
        }
    }
}
local okWithFree, jobIdWithFree = Store.createClaimedJob(haulWithFree)
assertTrue(okWithFree, "createClaimedJob with valid free capacity must succeed: " .. tostring(jobIdWithFree))
assertEq(jobIdWithFree, "haul-with-free", "Job ID match")
local tokenWithFree = Store.getToken("haul-with-free")
assertTrue(tokenWithFree ~= nil, "Token exists for created haul job")
local claimsInst = Store.claimsInstance()
assertEq(claimsInst.capacity["cont-b"].total, 5.0, "Capacity reserved in bucket")

print("PASS Part 3: Store.createClaimedJob Atomic Creation & Rollback.")

-- =========================================================================
-- Part 4: Store.mutateJob CAS & Resource Lifecycle
-- =========================================================================

-- Test 4.1: mutateJob fails on stale revision
local okStale, errStale = Store.mutateJob("craft-stage-b-1", 99, validCraftJob.payload, {})
assertFalse(okStale, "mutateJob with stale revision must fail")
assertEq(errStale, "STALE_REVISION", "Error must be STALE_REVISION")

-- Test 4.2: mutateJob extends claims and updates revision
-- Simulate advancing craft job to produce output 305
local pAdv = {
    format = 4,
    id = "craft-stage-b-1",
    npcId = "npc-b1",
    sequence = 2,
    recipeId = "Base.MakeAxe",
    target = 1,
    produced = 1,
    materials = { { id = 301, consumed = false } },
    tools = { { id = 302 } },
    outputs = { { id = 305, delivered = false } },
    claims = { "item:301", "item:302", "item:305" }
}
local okMut, nextRev = Store.mutateJob("craft-stage-b-1", 1, pAdv, {
    state = "RUNNING",
    addKeys = { "item:305" }
})
assertTrue(okMut, "mutateJob advancing craft job: " .. tostring(nextRev))
assertEq(nextRev, 2, "Next revision should be 2")
assertEq(Store.owner(305).taskId, "craft-stage-b-1", "Output item 305 is now claimed")

-- Test 4.3: mutateJob to DONE releases claims and clears token
-- Test 4.3: mutateJob through SETTLING to DONE releases claims and clears token
-- Iron invariant F6: RUNNING -> SETTLING -> DONE
local okSettling, revSettling = Store.mutateJob("craft-stage-b-1", 2, pAdv, {
    state = "SETTLING"
})
assertTrue(okSettling, "mutateJob to SETTLING: " .. tostring(revSettling))
assertEq(revSettling, 3, "Revision is now 3")

local pDone = {
    format = 4,
    id = "craft-stage-b-1",
    npcId = "npc-b1",
    sequence = 3,
    recipeId = "Base.MakeAxe",
    target = 1,
    produced = 1,
    materials = { { id = 301, consumed = true } },
    tools = {},
    outputs = { { id = 305, delivered = true } },
    released = true,
    claims = {}
}
local okDone, revDone = Store.mutateJob("craft-stage-b-1", 3, pDone, {
    state = "DONE",
    removeKeys = { "item:301", "item:302", "item:305" }
})
assertTrue(okDone, "mutateJob to DONE: " .. tostring(revDone))
assertEq(revDone, 4, "Revision is now 4")
assertFalse(Store.owner(301) ~= nil, "item:301 released on DONE")
assertFalse(Store.owner(302) ~= nil, "item:302 released on DONE")
assertFalse(Store.owner(305) ~= nil, "item:305 released on DONE")
assertFalse(Store.getToken("craft-stage-b-1") ~= nil, "Token removed on terminal state")

-- Test 4.4: B.3 - CAS failure isolates real added resource without fictitious key
local casJob = {
    id = "craft-cas-fail",
    npcId = "npc-cas",
    providerType = "CRAFT",
    scopeId = "settlement-1",
    revision = 1,
    state = "PREPARING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        format = 4,
        id = "craft-cas-fail",
        npcId = "npc-cas",
        sequence = 1,
        recipeId = "Base.MakeAxe",
        target = 1,
        produced = 0,
        materials = { { id = 4001, consumed = false } },
        tools = {},
        outputs = {},
        claims = { "item:4001" }
    }
}
local okCreateCas, idCas = Store.createClaimedJob(casJob)
assertTrue(okCreateCas, "createClaimedJob for CAS test: " .. tostring(idCas))

-- Now simulate a CAS collision by passing an invalid payload that causes store:update to fail
local badPayload = {
    format = 4,
    id = "craft-cas-fail",
    npcId = "npc-cas",
    sequence = 2,
    recipeId = "Base.MakeAxe",
    target = 1,
    produced = 1,
    materials = { { id = 4001, consumed = false } },
    tools = {},
    outputs = { { id = 9001, delivered = false } },
    claims = { "item:4001", "item:9001" },
    released = "INVALID_TYPE_EXPECTED_BOOLEAN" -- Schema violation causes JobStore:update to fail
}

local okMutFail, errMutFail = Store.mutateJob("craft-cas-fail", 1, badPayload, {
    state = "RUNNING",
    addKeys = { "item:9001" }
})
assertFalse(okMutFail, "mutateJob with bad payload must fail CAS")
assertTrue(string.find(errMutFail, "CAS_FAILED_ISOLATED") ~= nil, "Error indicates CAS failure")

-- CRITICAL B.3 VERIFICATION:
-- 1. Real added item 9001 MUST be quarantined!
local owner9001 = Store.owner(9001)
assertTrue(owner9001 ~= nil, "Real item 9001 must have owner")
assertEq(owner9001.kind, "SYSTEM_QUARANTINE", "Real item 9001 MUST be SYSTEM_QUARANTINE")

-- 2. Fictitious key "craft-cas-fail:mutation_fail" MUST NOT exist!
local fakeOwner = Store.resourceOwner("craft-cas-fail:mutation_fail")
assertFalse(fakeOwner ~= nil, "Fictitious key MUST NOT be quarantined")

-- 3. The job must be demoted to RECONCILE_REQUIRED
local storeInstance = TaskJobs.current()
local demotedJob = storeInstance:get("craft-cas-fail")
assertEq(demotedJob.state, "RECONCILE_REQUIRED", "Job demoted to RECONCILE_REQUIRED on CAS failure")
assertEq(demotedJob.effects, "UNKNOWN", "Job effects demoted to UNKNOWN")

-- Test 4.5: B.3 - Terminal cleanup cleans up all token dictionaries
local CookingRecord = require 'EmberRoutesProbe/CookingRecord'
local cookJobLife = CookingRecord.new("cook-lifecycle", "npc-life", "settlement-1", "Soup", "AUTO", "policy:base", 0.5, 0.5)
cookJobLife.payload.assets = { { id = 5001, fullType = "Base.Pot", custody = "HELD", role = "TOOL" } }
cookJobLife.payload.claims = { "item:5001" }

local okCreateLife, _ = Store.createClaimedJob(cookJobLife)
assertTrue(okCreateLife, "createClaimedJob cook-lifecycle")
assertTrue(Store.getToken("cook-lifecycle") ~= nil, "Token exists for cook-lifecycle")

local pCookSettling = CookingRecord.copy(cookJobLife.payload)
pCookSettling.phase = "RETURNING"
pCookSettling.claims = {}
pCookSettling.assets[1].custody = "RETURNED"

-- Advance to SETTLING then DONE
local okSetLife, revSetLife = Store.mutateJob("cook-lifecycle", 1, pCookSettling, {
    state = "SETTLING",
    removeKeys = { "item:5001" }
})
assertTrue(okSetLife, "mutateJob to SETTLING: " .. tostring(revSetLife))

local pCookDone = CookingRecord.copy(pCookSettling)
pCookDone.phase = "SETTLED"
local okDoneLife, revDoneLife = Store.mutateJob("cook-lifecycle", revSetLife, pCookDone, {
    state = "DONE"
})
assertTrue(okDoneLife, "mutateJob to DONE: " .. tostring(revDoneLife))
-- Verification: Token is completely cleaned from all dictionaries
assertFalse(Store.getToken("cook-lifecycle") ~= nil, "Token removed from all dictionaries on terminal state")
assertFalse(Store.owner(5001) ~= nil, "item:5001 released on DONE")

-- Test 4.6: B.3 - mutateJob rejects shrink failure without silent ignore
local testShrinkJob = {
    id = "craft-shrink-test",
    npcId = "npc-shrink",
    providerType = "CRAFT",
    scopeId = "settlement-1",
    revision = 1,
    state = "PREPARING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        format = 4,
        id = "craft-shrink-test",
        npcId = "npc-shrink",
        sequence = 1,
        recipeId = "Base.MakeAxe",
        target = 1,
        produced = 0,
        materials = { { id = 6001, consumed = false } },
        tools = {},
        outputs = {},
        claims = { "item:6001" }
    }
}
Store.createClaimedJob(testShrinkJob)

-- Try to shrink an unowned key item:99999
local okBadShrink, errBadShrink = Store.mutateJob("craft-shrink-test", 1, testShrinkJob.payload, {
    removeKeys = { "item:99999" }
})
assertFalse(okBadShrink, "mutateJob with invalid shrink MUST fail")
assertTrue(string.find(errBadShrink, "SHRINK_FAILED") ~= nil, "Error indicates SHRINK_FAILED: " .. tostring(errBadShrink))

-- CRITICAL B.5 ATOMICITY VERIFICATION:
-- JobStore must have ZERO partial modifications: revision is still 1, state is PREPARING, payload untouched!
local storeAfterFail = TaskJobs.current():get("craft-shrink-test")
assertEq(storeAfterFail.revision, 1, "Job revision MUST remain 1 on shrink precheck failure (zero partial commit)")
assertEq(storeAfterFail.state, "PREPARING", "Job state MUST remain PREPARING")
assertEq(storeAfterFail.effects, "KNOWN", "Job effects MUST remain KNOWN")
assertEq(#storeAfterFail.payload.claims, 1, "Job claims count MUST remain 1")
assertEq(storeAfterFail.payload.claims[1], "item:6001", "Job claim item:6001 untouched")

-- Test 4.7: B.5 - Algebraic payload.claims mismatch rejection (newClaims == oldClaims + addKeys - removeKeys)
local badClaimsPayload = {}
for k, v in pairs(testShrinkJob.payload) do badClaimsPayload[k] = v end
badClaimsPayload.claims = { "item:6001", "item:99999" } -- Undeclared phantom claim in payload!
local okMis, errMis = Store.mutateJob("craft-shrink-test", 1, badClaimsPayload)
assertFalse(okMis, "mutateJob with undeclared claim in payload must fail algebraic check")
assertEq(errMis, "CLAIMS_PAYLOAD_MISMATCH", "Rejection reason is CLAIMS_PAYLOAD_MISMATCH")

-- Test 4.8: B.5 - addKeys and removeKeys mutually exclusive violation
local okOverlap, errOverlap = Store.mutateJob("craft-shrink-test", 1, testShrinkJob.payload, {
    addKeys = { "item:7001" },
    removeKeys = { "item:7001" }
})
assertFalse(okOverlap, "mutateJob with intersecting addKeys and removeKeys MUST fail")
assertEq(errOverlap, "MUTATION_KEYS_MUTUALLY_EXCLUSIVE_VIOLATION", "Rejection reason is MUTATION_KEYS_MUTUALLY_EXCLUSIVE_VIOLATION")

-- Test 4.9: B.5 - addKeys already owned by current token must be rejected
local okAddOwned, errAddOwned = Store.mutateJob("craft-shrink-test", 1, testShrinkJob.payload, {
    addKeys = { "item:6001" }
})
assertFalse(okAddOwned, "mutateJob with addKeys already owned MUST fail")
assertEq(errAddOwned, "ADD_KEYS_ALREADY_OWNED", "Rejection reason is ADD_KEYS_ALREADY_OWNED")

print("PASS Part 4: Store.mutateJob CAS & Resource Lifecycle.")

-- =========================================================================
-- Part 5: Two-Pass Cold Boot Recovery with Quarantine Precedence
-- =========================================================================

-- Setup mock save with:
-- 1. Quarantined resource "item:777"
-- 2. Job "craft-saved" attempting to claim "item:777"
local recoveryRoot = {
    taskJobs = {
        format = 1,
        byId = {
            ["craft-saved"] = {
                id = "craft-saved",
                npcId = "npc-saved",
                providerType = "CRAFT",
                scopeId = "settlement-1",
                revision = 1,
                state = "RUNNING",
                effects = "KNOWN",
                obligations = {},
                payload = {
                    format = 4,
                    id = "craft-saved",
                    npcId = "npc-saved",
                    sequence = 1,
                    recipeId = "Base.MakeAxe",
                    target = 1,
                    produced = 0,
                    materials = { { id = 777, consumed = false } },
                    tools = {},
                    outputs = {},
                    claims = { "item:777" }
                }
            }
        }
    },
    quarantineResources = {
        ["item:777"] = { reason = "MANUAL_QUARANTINE", evidence = "save test" }
    }
}

recoveryRoot.format = 1
recoveryRoot.containers = {}
ContainerRegistry.data = function() return recoveryRoot end
-- Trigger Store.data() cold boot recovery
Store.data()

-- Verify Pass 1 quarantined item 777
assertEq(Store.owner(777).kind, "SYSTEM_QUARANTINE", "Item 777 must be SYSTEM_QUARANTINE")

-- Verify Pass 2 isolated the conflicting job without crashing
local savedJob = recoveryRoot.taskJobs.byId["craft-saved"]
assertEq(savedJob.state, "RECONCILE_REQUIRED", "Job conflicting with quarantine must be marked RECONCILE_REQUIRED")
assertEq(savedJob.effects, "UNKNOWN", "Job effects demoted to UNKNOWN")

-- Test 5.2: B.2 - Multi-provider immunity against Quarantine crash
-- Verify COOKING, FIELD_WORK, ACTIVITY, SELF_CARE, and HAUL all demote gracefully on quarantine
local CookingRecord = require 'EmberRoutesProbe/CookingRecord'
local SelfCareRecord = require 'EmberRoutesProbe/SelfCareRecord'
local ActivityRecord = require 'EmberRoutesProbe/ActivityRecord'
local LeisureRecord = require 'EmberRoutesProbe/LeisureRecord'

local cookJob = CookingRecord.new("cook-q", "npc-cook", "settlement-1", "Soup", "AUTO", "policy:base", 0.5, 0.5)
cookJob.payload.assets = { { id = 777, fullType = "Base.Pot", custody = "HELD", role = "TOOL" } }
cookJob.payload.claims = { "item:777" }

local selfJob = SelfCareRecord.create("self-q", "npc-self")
selfJob.payload.kind = "EAT"
selfJob.payload.sequence = 1
selfJob.payload.attemptId = "self-q:1"
selfJob.payload.step = "RESTORE_PENDING"
selfJob.payload.claims = { "item:777" }

local pnt = { x = 15, y = 15, z = 0 }
local tileK = LeisureRecord.tileKey(pnt)
local actJob = ActivityRecord.create("act-q", "npc-act", {
    id = "campfire-1",
    settlementId = "settlement-1",
    controlEpoch = 1,
    roster = { ["npc-act"] = { participantEpoch = 1 } }
})
actJob.payload.sequence = 1
actJob.payload.step = "WAITING"
actJob.payload.point = pnt
actJob.payload.claims = { tileK }

local fieldJob = {
    id = "field-q",
    npcId = "npc-field",
    providerType = "FIELD_WORK",
    scopeId = "settlement-1",
    revision = 1,
    state = "RUNNING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        format = 1,
        category = "farming",
        offerKey = "plot-1",
        sequence = 1,
        phase = "WORK",
        target = { x = 10, y = 10, z = 0, kind = "PLOT", identity = "plot-1" },
        assets = { { id = 777, fullType = "Base.Shovel", custody = "HELD" } },
        claims = { "item:777" }
    }
}

local haulJob = {
    id = "haul-q",
    npcId = "npc-haul",
    providerType = "HAUL",
    scopeId = "settlement-1",
    revision = 1,
    state = "RUNNING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        format = 3,
        sequence = 1,
        source = "cont-a",
        destination = "cont-b",
        manifest = { { itemId = 777, custodyState = "UNCOLLECTED" } },
        claims = { "item:777" }
    }
}

local multiProvRoot = {
    format = 1,
    containers = {},
    quarantineResources = {
        ["item:777"] = { reason = "MANUAL_QUARANTINE", evidence = "multi-provider test" },
        [tileK] = { reason = "MANUAL_QUARANTINE", evidence = "activity tile test" }
    },
    taskJobs = {
        format = 1,
        byId = {
            ["cook-q"] = cookJob,
            ["field-q"] = fieldJob,
            ["self-q"] = selfJob,
            ["act-q"] = actJob,
            ["haul-q"] = haulJob
        }
    },
    toolCustody = {
        byId = {
            ["cust-q"] = {
                format = 1,
                id = "cust-q",
                itemId = 777,
                role = "HAMMER",
                npcId = "npc-cust",
                sequence = 1,
                state = "HELD",
                claims = { "item:777" }
            }
        }
    }
}

ContainerRegistry.data = function() return multiProvRoot end
-- Cold boot recovery MUST NOT throw error on any provider!
Store.data()

assertEq(multiProvRoot.taskJobs.byId["cook-q"].state, "RECONCILE_REQUIRED", "COOKING demoted to RECONCILE_REQUIRED")
assertEq(multiProvRoot.taskJobs.byId["cook-q"].effects, "UNKNOWN", "COOKING effects demoted to UNKNOWN")
assertEq(multiProvRoot.taskJobs.byId["field-q"].state, "RECONCILE_REQUIRED", "FIELD_WORK demoted to RECONCILE_REQUIRED")
assertEq(multiProvRoot.taskJobs.byId["field-q"].effects, "UNKNOWN", "FIELD_WORK effects demoted to UNKNOWN")
assertEq(multiProvRoot.taskJobs.byId["self-q"].state, "RECONCILE_REQUIRED", "SELF_CARE demoted to RECONCILE_REQUIRED")
assertEq(multiProvRoot.taskJobs.byId["self-q"].effects, "UNKNOWN", "SELF_CARE effects demoted to UNKNOWN")
assertEq(multiProvRoot.taskJobs.byId["act-q"].state, "RECONCILE_REQUIRED", "ACTIVITY demoted to RECONCILE_REQUIRED")
assertEq(multiProvRoot.taskJobs.byId["act-q"].effects, "UNKNOWN", "ACTIVITY effects demoted to UNKNOWN")
assertEq(multiProvRoot.taskJobs.byId["haul-q"].state, "RECONCILE_REQUIRED", "HAUL demoted to RECONCILE_REQUIRED")
assertEq(multiProvRoot.taskJobs.byId["haul-q"].effects, "UNKNOWN", "HAUL effects demoted to UNKNOWN")
assertEq(multiProvRoot.toolCustody.byId["cust-q"].state, "HELD", "Tool custody remains in safe HELD state")

-- Test 5.3: B.2 - Cross-provider overlap conflict auto-quarantine (BOOT_CONFLICT arbitration)
-- Two jobs (COOKING and FIELD_WORK) contending for unquarantined item:888
local cookConflict = CookingRecord.new("cook-conflict", "npc-c1", "settlement-1", "Soup", "AUTO", "policy:base", 0.5, 0.5)
cookConflict.payload.assets = { { id = 888, fullType = "Base.Pot", custody = "HELD", role = "TOOL" } }
cookConflict.payload.claims = { "item:888" }

local fieldConflict = {
    id = "field-conflict",
    npcId = "npc-f1",
    providerType = "FIELD_WORK",
    scopeId = "settlement-1",
    revision = 1,
    state = "RUNNING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        format = 1,
        category = "farming",
        offerKey = "plot-2",
        sequence = 1,
        phase = "WORK",
        target = { x = 20, y = 20, z = 0, kind = "PLOT", identity = "plot-2" },
        assets = { { id = 888, fullType = "Base.Shovel", custody = "HELD" } },
        claims = { "item:888" }
    }
}

local innocentCraft = {
    id = "innocent-craft",
    npcId = "npc-i1",
    providerType = "CRAFT",
    scopeId = "settlement-1",
    revision = 1,
    state = "RUNNING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        format = 4,
        id = "innocent-craft",
        npcId = "npc-i1",
        sequence = 1,
        recipeId = "Base.MakeAxe",
        target = 1,
        produced = 0,
        materials = { { id = 999, consumed = false } },
        tools = {},
        outputs = {},
        claims = { "item:999" }
    }
}

local conflictRoot = {
    format = 1,
    containers = {},
    quarantineResources = {},
    taskJobs = {
        format = 1,
        byId = {
            ["cook-conflict"] = cookConflict,
            ["field-conflict"] = fieldConflict,
            ["innocent-craft"] = innocentCraft
        }
    }
}

ContainerRegistry.data = function() return conflictRoot end
-- Cold boot recovery MUST detect collision, isolate item:888, demote both contenders without crashing
Store.data()

-- item:888 must be auto-quarantined with BOOT_CONFLICT reason
assertTrue(conflictRoot.quarantineResources["item:888"] ~= nil, "Conflicted resource 888 auto-quarantined")
assertEq(conflictRoot.quarantineResources["item:888"].reason, "BOOT_CONFLICT", "Quarantine reason is BOOT_CONFLICT")
assertEq(Store.owner(888).kind, "SYSTEM_QUARANTINE", "Item 888 owner is SYSTEM_QUARANTINE")

-- Contenders demoted
assertEq(conflictRoot.taskJobs.byId["cook-conflict"].state, "RECONCILE_REQUIRED", "cook-conflict demoted")
assertEq(conflictRoot.taskJobs.byId["cook-conflict"].effects, "UNKNOWN", "cook-conflict effects UNKNOWN")
assertEq(conflictRoot.taskJobs.byId["field-conflict"].state, "RECONCILE_REQUIRED", "field-conflict demoted")
assertEq(conflictRoot.taskJobs.byId["field-conflict"].effects, "UNKNOWN", "field-conflict effects UNKNOWN")

-- Innocent job unaffected and acquired its claim
assertEq(conflictRoot.taskJobs.byId["innocent-craft"].state, "RUNNING", "Innocent job unaffected")
assertEq(Store.owner(999).taskId, "innocent-craft", "Innocent job owns item:999")
assertTrue(Store.getToken("innocent-craft") ~= nil, "Innocent job holds valid runtime token")

print("PASS Part 5: Two-Pass Cold Boot Recovery with Quarantine Precedence.")


-- =========================================================================
-- Part 6: Stage B.4 Edge Cases and Abnormal Recovery Scenarios
-- =========================================================================
print("Starting Part 6: Stage B.4 Edge Cases and Abnormal Recovery Scenarios...")

-- Test 6.1: Stale revision rejection does NOT corrupt or quarantine resources
local p6Root = {
    format = 1,
    taskJobs = { format = 1, byId = {} }
}
ContainerRegistry.data = function() return p6Root end
Store.data()

local jobP6 = {
    id = "craft-p6-stale",
    npcId = "npc-p6",
    providerType = "CRAFT",
    scopeId = "settlement-1",
    revision = 1,
    state = "PREPARING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        format = 4,
        id = "craft-p6-stale",
        npcId = "npc-p6",
        sequence = 1,
        recipeId = "Base.Axe",
        target = 1,
        produced = 0,
        materials = { { id = 7001, consumed = false } },
        tools = {},
        outputs = {},
        claims = { "item:7001" }
    }
}
local okCreateP6, _ = Store.createClaimedJob(jobP6)
assertTrue(okCreateP6, "createClaimedJob craft-p6-stale")

-- Mutation with stale expected revision (e.g. 999 instead of 1)
local okStale, errStale = Store.mutateJob("craft-p6-stale", 999, jobP6.payload, {
    state = "RUNNING",
    addKeys = { "item:7002" }
})
assertFalse(okStale, "mutateJob with stale revision must fail")
assertEq(errStale, "STALE_REVISION", "Error must be STALE_REVISION")
assertFalse(Store.owner(7002) ~= nil, "item:7002 must NOT be claimed or quarantined on stale revision")

-- Test 6.2: Dispute reconciliation and persistent unquarantine recovery
local okQ = Store.quarantineResource("item:8001", "MANUAL_DISPUTE", { reason = "test" })
assertTrue(okQ, "quarantineResource item:8001")
assertEq(Store.owner(8001).kind, "SYSTEM_QUARANTINE", "item:8001 is quarantined in memory")
assertTrue(p6Root.quarantineResources["item:8001"] ~= nil, "item:8001 is persisted in root.quarantineResources")

-- Persistent unquarantine removes memory claim AND deletes persistent root record
local okUnq = Store.unquarantineResource("item:8001", { resolvedBy = "ARBITRATION", reason = "PROOF_ACCEPTED" })
assertTrue(okUnq, "Store.unquarantineResource succeeds")
assertFalse(Store.owner(8001) ~= nil, "item:8001 is now unquarantined and unowned in memory")
assertFalse(p6Root.quarantineResources["item:8001"] ~= nil, "item:8001 is REMOVED from root.quarantineResources")
assertTrue(p6Root.quarantineAudit ~= nil and p6Root.quarantineAudit["item:8001"] ~= nil, "Audit trail recorded")

-- CRITICAL PERSISTENCE VERIFICATION:
-- Cold boot / reload with new root containing saved state: must NOT re-quarantine item:8001!
local bootReloadRoot = {
    format = 1,
    taskJobs = p6Root.taskJobs,
    containers = p6Root.containers or {},
    quarantineResources = p6Root.quarantineResources or {},
    quarantineAudit = p6Root.quarantineAudit or {}
}
ContainerRegistry.data = function() return bootReloadRoot end
Store.data()
assertFalse(Store.owner(8001) ~= nil, "item:8001 remains unquarantined after cold boot recovery")

-- An unquarantined resource can now be extended into craft-p6-stale
local pExtend = {}
for k, v in pairs(jobP6.payload) do pExtend[k] = v end
pExtend.materials = { { id = 7001, consumed = false }, { id = 8001, consumed = false } }
pExtend.claims = { "item:7001", "item:8001" }

local okExtendAfter, errExtend = Store.mutateJob("craft-p6-stale", 1, pExtend, {
    addKeys = { "item:8001" }
})
assertTrue(okExtendAfter, "mutateJob extend after unquarantine succeeds: " .. tostring(errExtend))
assertEq(Store.owner(8001).taskId, "craft-p6-stale", "craft-p6-stale now owns unquarantined item:8001")

-- Test 6.3: Format 1 legacy haul job cold-boot recovery & lifecycle
local haulF1 = {
    id = "haul-f1-test",
    npcId = "npc-haul-f1",
    providerType = "HAUL",
    scopeId = "local-world",
    revision = 1,
    state = "RUNNING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        id = "haul-f1-test",
        npcId = "npc-haul-f1",
        source = "crate-src",
        destination = "crate-dest",
        items = { 9001, 9002 },
        state = "RUNNING",
        reason = "CREATED",
        delivered = 0,
        format = 1,
        kind = "EXPLICIT_TRANSFER",
        scopeId = "local-world",
        executor = "ENTITY",
        claims = { "item:9001", "item:9002" }
    }
}
-- Place format 1 haul job alongside existing jobs in a fresh boot root to simulate cold-boot reload!
local bootRootF1 = {
    format = 1,
    taskJobs = {
        format = 1,
        byId = {
            ["craft-p6-stale"] = bootReloadRoot.taskJobs.byId["craft-p6-stale"],
            ["haul-f1-test"] = haulF1
        }
    },
    containers = {},
    quarantineResources = {}
}
ContainerRegistry.data = function() return bootRootF1 end

-- Cold-boot recovery MUST restore format 1 HAUL job with its runtime token!
Store.data()
assertTrue(Store.getToken("haul-f1-test") ~= nil, "Format 1 haul job recovered its runtime token on cold boot!")
assertEq(Store.owner(9001).taskId, "haul-f1-test", "Format 1 haul job owns item:9001 after cold boot")
assertEq(Store.owner(9002).taskId, "haul-f1-test", "Format 1 haul job owns item:9002 after cold boot")

-- Verify post-boot state and revision: cold boot correctly pauses running tasks into SUSPENDED
local jobAfterBoot = TaskJobs.current():get("haul-f1-test")
assertEq(jobAfterBoot.state, "SUSPENDED", "Format 1 haul job envelope is SUSPENDED on LOAD_RECOVERY")
local revBoot = jobAfterBoot.revision

-- Mutate to SETTLING then DONE with shrink of all claims
local pDoneF1 = {}
for k, v in pairs(haulF1.payload) do pDoneF1[k] = v end
pDoneF1.delivered = 2
pDoneF1.claims = {}

local okSetF1, revSetF1 = Store.mutateJob("haul-f1-test", revBoot, pDoneF1, {
    state = "SETTLING",
    removeKeys = { "item:9001", "item:9002" }
})
assertTrue(okSetF1, "mutateJob haul-f1-test to SETTLING: " .. tostring(revSetF1))

pDoneF1.state = "DONE"
local okDoneF1, revDoneF1 = Store.mutateJob("haul-f1-test", revSetF1, pDoneF1, {
    state = "DONE",
    obligations = {}
})
assertTrue(okDoneF1, "mutateJob haul-f1-test to DONE: " .. tostring(revDoneF1))
assertFalse(Store.getToken("haul-f1-test") ~= nil, "Token cleaned on terminal DONE for format 1 haul")
assertFalse(Store.owner(9001) ~= nil, "item:9001 released on DONE")
assertFalse(Store.owner(9002) ~= nil, "item:9002 released on DONE")

-- Test 6.4: Capacity reserve bounds (negative, NaN, overflow)
local dummyToken = Store.getToken("craft-p6-stale")
assertTrue(dummyToken ~= nil, "craft-p6-stale token available")
local currentClaims = Store.claimsInstance()
local okNeg, errNeg = currentClaims:reserve(dummyToken, "cap-target", 7001, 10, -5)
assertFalse(okNeg, "Negative free capacity must be rejected")
assertEq(errNeg, "CAPACITY_UNAVAILABLE", "Rejection reason is CAPACITY_UNAVAILABLE")

local okNan, errNan = currentClaims:reserve(dummyToken, "cap-target", 7001, 0/0, 100)
assertFalse(okNan, "NaN amount must be rejected")
assertEq(errNan, "CAPACITY_UNAVAILABLE", "Rejection reason is CAPACITY_UNAVAILABLE")

local okOverflow, errOverflow = currentClaims:reserve(dummyToken, "cap-target", 7001, 200, 100)
assertFalse(okOverflow, "Exceeding free capacity must be rejected")
assertEq(errOverflow, "CAPACITY_RESERVED", "Rejection reason is CAPACITY_RESERVED")

local okValidCap, _ = currentClaims:reserve(dummyToken, "cap-target", 7001, 50, 100)
assertTrue(okValidCap, "Valid reservation within bounds must succeed")

-- Test 6.5: B.5 - Quarantine capacity independent persistence and cold-boot recovery (B52-01 ~ B52-04)
do
    local t_p6_cap = Store.getToken("craft-p6-stale")
    currentClaims:releaseCapacity(t_p6_cap)
    local okResP6, errResP6 = currentClaims:reserve(t_p6_cap, "crate-persist-cap", 7001, 15.0, 50.0)
    assertTrue(okResP6, "reserve on crate-persist-cap succeeds: " .. tostring(errResP6))
    assertEq(currentClaims.capacity["crate-persist-cap"].total, 15.0, "Capacity reserved 15")

    -- Quarantine item:7001: capacity transferred to bucket.quarantine and persisted in root!
    Store.quarantineResource("item:7001", "CAPACITY_TEST", { test = "persist" })
    assertEq(currentClaims.capacity["crate-persist-cap"].total, 15.0, "Capacity remains 15 after quarantine")
    local qPersistRec = bootRootF1.quarantineResources["item:7001"]
    assertTrue(qPersistRec ~= nil, "quarantineResources contains item:7001")
    assertEq(qPersistRec.capacityKey, "crate-persist-cap", "Persisted capacityKey matches")
    assertEq(qPersistRec.capacityAmount, 15.0, "Persisted capacityAmount matches")

    -- Release original token: capacity stays 15!
    currentClaims:release(t_p6_cap)
    assertEq(currentClaims.capacity["crate-persist-cap"].total, 15.0, "Capacity remains 15 after release(originalToken)")

    -- Cold boot reload: Pass 1 MUST restore quarantine capacity from root.quarantineResources!
    local bootRootCap = {
        format = 1,
        taskJobs = { format = 1, byId = {} },
        containers = {},
        quarantineResources = {
            ["item:7001"] = qPersistRec
        }
    }
    ContainerRegistry.data = function() return bootRootCap end
    Store.data()
    local bootClaims = Store.claimsInstance()
    assertEq(bootClaims.owners["item:7001"].kind, "SYSTEM_QUARANTINE", "Item 7001 restored as quarantine")
    assertTrue(bootClaims.capacity["crate-persist-cap"] ~= nil, "Bucket crate-persist-cap restored")
    assertEq(bootClaims.capacity["crate-persist-cap"].total, 15.0, "Quarantined capacity total restored on cold boot Pass 1")

    -- Unquarantine item 7001: capacity is cleanly settled
    Store.unquarantineResource("item:7001", { capacityAction = "RELEASE", reason = "ARBITRATED" })
    assertEq(bootClaims.capacity["crate-persist-cap"] and bootClaims.capacity["crate-persist-cap"].total or 0, 0, "Capacity released after explicit unquarantine")
end

-- Test 6.6: B.5 - Unquarantine two-phase status recovery from RESOLVING crash (P0-1 closure: keep protected & capacity conservation)
do
    local bootRootCrash = {
        format = 1,
        taskJobs = { format = 1, byId = {} },
        containers = {},
        quarantineResources = {
            ["item:8888"] = {
                status = "RESOLVING",
                reason = "MIDWAY_CRASH",
                capacityKey = "cap:main_crate",
                capacityItemId = 8888,
                capacityAmount = 25.0,
                resolution = { reason = "MIDWAY_CRASH_1" },
                resolvingEvidence = { note = "system rebooted during first unquarantine" }
            }
        }
    }
    ContainerRegistry.data = function() return bootRootCrash end
    -- First cold boot recovery
    Store.data()
    local crashClaims1 = Store.claimsInstance()
    -- P0-1: Missing verified settlement completion evidence -> MUST REMAIN PROTECTED UNDER SYSTEM_QUARANTINE!
    assertTrue(crashClaims1.owners["item:8888"] ~= nil, "RESOLVING item remains protected under SYSTEM_QUARANTINE in claims memory")
    assertEq(crashClaims1.owners["item:8888"].kind, "SYSTEM_QUARANTINE", "Owner kind is SYSTEM_QUARANTINE")
    assertTrue(bootRootCrash.quarantineResources["item:8888"] ~= nil, "RESOLVING record is NOT cleared from active quarantine")
    assertEq(bootRootCrash.quarantineResources["item:8888"].status, "ACTIVE", "RESOLVING record restored to ACTIVE status on first cold boot")
    assertEq(bootRootCrash.quarantineResources["item:8888"].interruptedResolution.reason, "MIDWAY_CRASH_1", "Diagnostic trace preserved in interruptedResolution")
    assertTrue(crashClaims1.capacity["cap:main_crate"] ~= nil, "Capacity bucket cap:main_crate restored")
    assertEq(crashClaims1.capacity["cap:main_crate"].total, 25.0, "Capacity total restored to 25.0 on first reboot")

    -- Simulate second crash during another unquarantine attempt:
    bootRootCrash.quarantineResources["item:8888"].status = "RESOLVING"
    bootRootCrash.quarantineResources["item:8888"].resolution = { reason = "MIDWAY_CRASH_2" }
    bootRootCrash.quarantineResources["item:8888"].resolvingEvidence = { note = "system rebooted during second unquarantine" }

    -- Second consecutive cold boot recovery (re-load with fresh claims instance)
    local bootRootCrash2 = {
        format = 1,
        taskJobs = { format = 1, byId = {} },
        containers = {},
        quarantineResources = {
            ["item:8888"] = bootRootCrash.quarantineResources["item:8888"]
        }
    }
    ContainerRegistry.data = function() return bootRootCrash2 end
    Store.data()
    local crashClaims2 = Store.claimsInstance()
    assertTrue(crashClaims2.owners["item:8888"] ~= nil, "item:8888 still protected under SYSTEM_QUARANTINE on second reboot")
    assertEq(crashClaims2.owners["item:8888"].kind, "SYSTEM_QUARANTINE", "Owner kind remains SYSTEM_QUARANTINE on second reboot")
    assertEq(bootRootCrash2.quarantineResources["item:8888"].status, "ACTIVE", "Restored to ACTIVE on second consecutive reboot")
    assertEq(bootRootCrash2.quarantineResources["item:8888"].interruptedResolution.reason, "MIDWAY_CRASH_2", "Second interrupted resolution preserved")
    -- CRITICAL B.5-R3 CAPACITY CONSERVATION:
    -- Bucket total MUST remain 25.0 across multiple crashes (never double-counted to 50.0 and never leaked to 0.0)
    assertTrue(crashClaims2.capacity["cap:main_crate"] ~= nil, "Capacity bucket preserved on second reboot")
    assertEq(crashClaims2.capacity["cap:main_crate"].total, 25.0, "Capacity total strictly conserved at 25.0 across consecutive reboots")
    assertEq(bootRootCrash2.quarantineAudit and bootRootCrash2.quarantineAudit["item:8888"], nil, "No false completion audit written")
end

-- Test 6.7: B.5 - Corrupted format 1 legacy schema recovery gracefully demotes without crash (B54-02)
do
    local corruptedHaul = {
        id = "haul-corrupted",
        npcId = "npc-corrupted",
        providerType = "HAUL",
        scopeId = "local-world",
        revision = 1,
        state = "RUNNING",
        effects = "KNOWN",
        obligations = {},
        payload = {
            id = "haul-corrupted",
            npcId = "npc-corrupted",
            source = "crate-a",
            destination = "crate-b",
            items = { "NOT_A_NUMBER_CORRUPTED" },
            state = "RUNNING",
            delivered = 0,
            format = 1,
            kind = "EXPLICIT_TRANSFER"
        }
    }
    local bootRootCorrupt = {
        format = 1,
        taskJobs = {
            format = 1,
            byId = { ["haul-corrupted"] = corruptedHaul }
        },
        containers = {},
        quarantineResources = {}
    }
    ContainerRegistry.data = function() return bootRootCorrupt end
    Store.data()
    local demotedHaul = bootRootCorrupt.taskJobs.byId["haul-corrupted"]
    assertEq(demotedHaul.state, "RECONCILE_REQUIRED", "Corrupted haul job envelope demoted to RECONCILE_REQUIRED without crashing")
    assertEq(demotedHaul.effects, "UNKNOWN", "Corrupted haul job effects demoted to UNKNOWN")
    assertEq(demotedHaul.payload.state, "PAUSED", "Corrupted haul job payload state demoted to PAUSED")
    assertEq(demotedHaul.payload.reason, "SCHEMA_INVALID", "Corrupted haul job payload reason is SCHEMA_INVALID")
end

-- Test 6.8: B.5 - Non-table corrupted records in Pass 1 and Pass 2 (false, number, string, missing fields) do not crash Store.data()
do
    local bootRootNonTable = {
        format = 1,
        taskJobs = {
            format = 1,
            byId = {
                ["job-bool"] = { id = "job-bool", npcId = "npc-bool", providerType = "HAUL", scopeId = "local-world", revision = 1, state = "RUNNING", effects = "KNOWN", obligations = {}, payload = { format = 1, id = "job-bool", npcId = "npc-bool", items = { 101 }, source = "a", destination = "b", state = "RUNNING" } },
                ["job-num"] = { id = "job-num", npcId = "npc-num", providerType = "HAUL", scopeId = "local-world", revision = 1, state = "RUNNING", effects = "KNOWN", obligations = {}, payload = { format = 1, id = "job-num", npcId = "npc-num", items = { 102 }, source = "a", destination = "b", state = "RUNNING" } },
                ["job-str"] = { id = "job-str", npcId = "npc-str", providerType = "HAUL", scopeId = "local-world", revision = 1, state = "RUNNING", effects = "KNOWN", obligations = {}, payload = { format = 1, id = "job-str", npcId = "npc-str", items = { 103 }, source = "a", destination = "b", state = "RUNNING" } },
                ["job-missing"] = { id = "job-missing", npcId = "npc-missing", providerType = "HAUL", scopeId = "local-world", revision = 1, state = "RUNNING", effects = "KNOWN", obligations = {}, payload = { format = 1, id = "job-missing", npcId = "npc-missing", items = { 104 }, source = "a", destination = "b", state = "RUNNING" } }
            }
        },
        containers = {},
        quarantineResources = {}
    }
    local oldHauls = require('EmberRoutesProbe/BusinessJobs').hauls
    local mockHaulData = {
        format = 2,
        tasks = {
            ["job-bool"] = false,
            ["job-num"] = 12345,
            ["job-str"] = "corrupt-string",
            ["job-missing"] = { id = "job-missing" } -- missing npcId, items, etc.
        },
        byNpc = {
            ["npc-bool"] = "job-bool",
            ["npc-num"] = "job-num"
        },
        routes = {}
    }
    require('EmberRoutesProbe/BusinessJobs').hauls = function() return mockHaulData end
    ContainerRegistry.data = function() return bootRootNonTable end

    -- Must not throw any unhandled error when scanning non-table tasks in Pass 1 or Pass 2!
    local okNonTableLoad, errNonTableLoad = pcall(Store.data)
    require('EmberRoutesProbe/BusinessJobs').hauls = oldHauls
    assertTrue(okNonTableLoad, "Store.data() MUST survive non-table corrupted task records: " .. tostring(errNonTableLoad))

    -- Verify non-table corrupted records are isolated into corruptedTasks and removed from tasks ledger
    assertTrue(bootRootNonTable.corruptedTasks ~= nil, "corruptedTasks ledger created")
    assertTrue(bootRootNonTable.corruptedTasks["job-bool"] ~= nil, "job-bool isolated to corruptedTasks")
    assertEq(bootRootNonTable.corruptedTasks["job-bool"].raw, false, "Original boolean preserved")
    assertEq(mockHaulData.tasks["job-bool"], nil, "job-bool removed from tasks ledger")
    assertEq(mockHaulData.tasks["job-num"], nil, "job-num removed from tasks ledger")
    assertEq(mockHaulData.tasks["job-str"], nil, "job-str removed from tasks ledger")
    assertEq(mockHaulData.byNpc["npc-bool"], nil, "Corrupted npc mapping removed from byNpc")

    -- Verify envelopes for all corrupted tasks are demoted
    assertEq(bootRootNonTable.taskJobs.byId["job-bool"].state, "RECONCILE_REQUIRED", "job-bool envelope demoted")
    assertEq(bootRootNonTable.taskJobs.byId["job-bool"].effects, "UNKNOWN", "job-bool envelope effects UNKNOWN")
    assertEq(bootRootNonTable.taskJobs.byId["job-missing"].state, "RECONCILE_REQUIRED", "job-missing envelope demoted")
    -- And for malformed table record, state is demoted to PAUSED / SCHEMA_INVALID
    assertEq(mockHaulData.tasks["job-missing"].state, "PAUSED", "job-missing table record state is PAUSED")
    assertEq(mockHaulData.tasks["job-missing"].reason, "SCHEMA_INVALID", "job-missing table record reason is SCHEMA_INVALID")
end

-- Test 6.9: B.5 - Authority-level claimId persistence across cold boots preventing claimId collision
do
    local bootRootClaims = {
        format = 1,
        taskJobs = { format = 1, byId = {} },
        containers = {},
        quarantineResources = {},
        nextClaimSeq = 10
    }
    ContainerRegistry.data = function() return bootRootClaims end
    Store.data()
    local jobP9 = {
        id = "task-persistent-claim-1",
        npcId = "npc-p9",
        providerType = "CRAFT",
        scopeId = "settlement-1",
        revision = 1,
        state = "PREPARING",
        effects = "KNOWN",
        obligations = {},
        payload = {
            format = 4,
            id = "task-persistent-claim-1",
            npcId = "npc-p9",
            sequence = 1,
            recipeId = "Base.MakeAxe",
            target = 1,
            produced = 0,
            materials = { { id = 9101, consumed = false } },
            tools = {},
            outputs = {},
            claims = { "item:9101" }
        }
    }
    local okCreateP9, _ = Store.createClaimedJob(jobP9)
    assertTrue(okCreateP9, "createClaimedJob task-persistent-claim-1")
    local t_p9 = Store.getToken("task-persistent-claim-1")
    assertTrue(t_p9 ~= nil, "Token exists for task-persistent-claim-1")
    assertEq(t_p9.claimId, "task-persistent-claim-1:c11", "claimId assigned monotonically from root.nextClaimSeq (11)")
    assertEq(bootRootClaims.nextClaimSeq, 11, "root.nextClaimSeq updated to 11")

    -- Quarantine item:9101 with owner.originalClaimId = "task-persistent-claim-1:c11"
    Store.quarantineResource("item:9101", "PERSIST_TEST", { test = "claimId" })
    assertEq(bootRootClaims.quarantineResources["item:9101"].originalClaimId, "task-persistent-claim-1:c11", "originalClaimId persisted")

    -- Simulate full game restart / cold boot reload with new Claims instance:
    local bootRootReloadP9 = {
        format = 1,
        taskJobs = { format = 1, byId = {} },
        containers = {},
        quarantineResources = {
            ["item:9101"] = bootRootClaims.quarantineResources["item:9101"]
        },
        nextClaimSeq = 11 -- Persisted from previous run!
    }
    ContainerRegistry.data = function() return bootRootReloadP9 end
    Store.data()

    -- Attempt to create a NEW job with the SAME taskId and generation:
    local jobP9_recreated = {
        id = "task-persistent-claim-1",
        npcId = "npc-p9-new",
        providerType = "CRAFT",
        scopeId = "settlement-1",
        revision = 1,
        state = "PREPARING",
        effects = "KNOWN",
        obligations = {},
        payload = {
            format = 4,
            id = "task-persistent-claim-1",
            npcId = "npc-p9-new",
            sequence = 1,
            recipeId = "Base.MakeAxe",
            target = 1,
            produced = 0,
            materials = { { id = 9102, consumed = false } },
            tools = {},
            outputs = {},
            claims = { "item:9102" }
        }
    }
    local okCreateRecreated, _ = Store.createClaimedJob(jobP9_recreated)
    assertTrue(okCreateRecreated, "Recreating job with same taskId succeeds")
    local t_p9_recreated = Store.getToken("task-persistent-claim-1")
    assertEq(t_p9_recreated.claimId, "task-persistent-claim-1:c12", "Recreated job receives NEW monotonic claimId (12)")

    -- Recreated token CANNOT canShrink or shrink old quarantined item:9101!
    local reloadedClaims = Store.claimsInstance()
    assertFalse(reloadedClaims:canShrink(t_p9_recreated, { "item:9101" }), "Recreated token with new claimId CANNOT shrink old quarantine")
    assertFalse(reloadedClaims:shrink(t_p9_recreated, { "item:9101" }), "shrink on old quarantine by recreated token fails")
end

-- Test 6.10: B.5 - unquarantineResource failure retains persistent quarantine record
do
    local bootRootUnqFail = {
        format = 1,
        taskJobs = { format = 1, byId = {} },
        containers = {},
        quarantineResources = {
            ["item:unq-fail-test"] = {
                status = "ACTIVE",
                reason = "FAIL_RETAIN_TEST",
                at = 12345
            }
        }
    }
    ContainerRegistry.data = function() return bootRootUnqFail end
    Store.data()
    -- Item is restored to claims owners in Pass 1. Now remove it from claims memory to simulate memory inconsistency:
    Store.claimsInstance().owners["item:unq-fail-test"] = nil

    -- Attempt unquarantine: claims:unquarantine will return false (not found in memory)
    local okUnqFail, errUnqFail = Store.unquarantineResource("item:unq-fail-test", "SHOULD_FAIL")
    assertFalse(okUnqFail, "unquarantine on non-existent memory owner must return false")
    -- CRITICAL B.5 VERIFICATION: Persistent quarantine record MUST NOT be deleted!
    assertTrue(bootRootUnqFail.quarantineResources["item:unq-fail-test"] ~= nil, "Persistent quarantine record RETAINED on unquarantine failure")
    assertEq(bootRootUnqFail.quarantineResources["item:unq-fail-test"].status, "ACTIVE", "Status restored to ACTIVE")
end

-- Test 6.11: P0-2 - capacityAction = 'RETAIN' requires explicit recipient token; atomic capacity transfer vs rejection
do
    local bootRootRetain = {
        format = 1,
        taskJobs = { format = 1, byId = {} },
        containers = {},
        quarantineResources = {
            ["item:cap-retain-test"] = {
                status = "ACTIVE",
                reason = "RETAIN_TEST",
                at = 1000,
                capacityKey = "crate-retain-bucket",
                capacityItemId = 777,
                capacityAmount = 10.0
            }
        }
    }
    ContainerRegistry.data = function() return bootRootRetain end
    Store.data()
    local claims = Store.claimsInstance()
    assertTrue(claims.capacity["crate-retain-bucket"] ~= nil, "Bucket crate-retain-bucket restored")
    assertEq(claims.capacity["crate-retain-bucket"].total, 10.0, "Bucket total reflects quarantined capacity")

    -- 1. Attempt unquarantine with capacityAction = 'RETAIN' WITHOUT targetToken: MUST BE REJECTED!
    local okNoTarget, errNoTarget = Store.unquarantineResource("item:cap-retain-test", { capacityAction = "RETAIN" })
    assertFalse(okNoTarget, "RETAIN without recipient token must be rejected")
    assertEq(errNoTarget, "CAPACITY_RETAIN_WITHOUT_RECIPIENT_REJECTED", "Rejection error code matches contract")
    assertEq(bootRootRetain.quarantineResources["item:cap-retain-test"].status, "ACTIVE", "Quarantine record status remains ACTIVE")
    assertEq(claims.capacity["crate-retain-bucket"].total, 10.0, "Bucket total remains unchanged after rejected retain")

    -- 2. Create a valid recipient token and transfer capacity via RETAIN:
    local recipientToken, _ = claims:acquire("job-recipient-1", 1, {})
    assertTrue(recipientToken ~= nil, "Recipient token acquired")
    local okWithTarget, errWithTarget = Store.unquarantineResource("item:cap-retain-test", {
        capacityAction = "RETAIN",
        targetToken = recipientToken,
        reason = "HANDOFF_TRANSFER"
    })
    assertTrue(okWithTarget, "RETAIN with valid recipient token succeeds: " .. tostring(errWithTarget))
    assertEq(bootRootRetain.quarantineResources["item:cap-retain-test"], nil, "Active quarantine record cleared on successful transfer")
    assertEq(recipientToken.capacityKey, "crate-retain-bucket", "Recipient token assigned capacityKey")
    local b = claims.capacity["crate-retain-bucket"]
    assertEq(b.quarantine["item:cap-retain-test"], nil, "Quarantine entry cleared in bucket")
    assertTrue(b.entries["job-recipient-1"] ~= nil, "Recipient entry created in bucket")
    assertEq(b.entries["job-recipient-1"].amount, 10.0, "Capacity amount transferred to recipient")
    assertEq(b.entries["job-recipient-1"].items[777], 10.0, "Item capacity transferred to recipient")
    assertEq(b.total, 10.0, "Bucket total correctly preserved without leak or orphan")
    assertEq(bootRootRetain.quarantineAudit["item:cap-retain-test"].action, "UNQUARANTINE", "Audit action is UNQUARANTINE")
    assertEq(bootRootRetain.quarantineAudit["item:cap-retain-test"].capacityAction, "RETAIN", "Audit logs capacityAction = RETAIN")
    assertEq(bootRootRetain.quarantineAudit["item:cap-retain-test"].recipientTaskId, "job-recipient-1", "Audit logs recipientTaskId")
end

-- Test 6.12: P1 - Authoritative monotonic claimId across creation and cold boot reconstruction
do
    local SelfCareRecord = require('EmberRoutesProbe/SelfCareRecord')
    local careJob = SelfCareRecord.create("care-p1", "npc-care")
    careJob.state = "RUNNING"
    careJob.payload.kind = "EAT"
    careJob.payload.attemptId = "care-p1:1"
    careJob.payload.step = "RESTORE_PENDING"
    careJob.payload.sequence = 1
    careJob.payload.claims = { "item:9988" }

    local bootRootP1 = {
        format = 1,
        nextClaimSeq = 50,
        taskJobs = {
            format = 1,
            byId = {
                ["care-p1"] = careJob,
                ["craft-p1"] = {
                    id = "craft-p1",
                    npcId = "npc-craft",
                    providerType = "CRAFT",
                    scopeId = "settlement-1",
                    revision = 1,
                    state = "RUNNING",
                    effects = "KNOWN",
                    obligations = {},
                    payload = {
                        format = 4,
                        id = "craft-p1",
                        npcId = "npc-craft",
                        sequence = 1,
                        recipeId = "Base.MakeAxe",
                        target = 1,
                        produced = 0,
                        materials = { { id = 7711, consumed = false } },
                        tools = {},
                        outputs = {},
                        claims = { "item:7711" }
                    }
                }
            }
        },
        toolCustody = {
            format = 1,
            byId = {
                ["custody-p1"] = {
                    format = 1,
                    id = "custody-p1",
                    npcId = "npc-custody",
                    itemId = 9999,
                    role = "BUILDER",
                    state = "HELD",
                    sequence = 1,
                    claims = { "item:9999" }
                }
            },
            byNpc = {},
            byItem = {}
        },
        containers = {},
        quarantineResources = {}
    }
    ContainerRegistry.data = function() return bootRootP1 end
    Store.data()
    local t_care = Store.getToken("care-p1")
    assertTrue(t_care ~= nil, "care token recovered")
    assertTrue(t_care.claimId ~= nil, "care token has non-nil claimId")
    assertEq(t_care.claimId, "care-p1:c51", "care token receives authoritative claimId (51)")

    local t_craft = Store.getToken("craft-p1")
    assertTrue(t_craft ~= nil, "craft token recovered")
    assertTrue(t_craft.claimId ~= nil, "craft token has non-nil claimId")
    assertEq(t_craft.claimId, "craft-p1:c52", "craft token receives authoritative claimId (52)")

    local t_custody = Store.getToken("custody-p1")
    assertTrue(t_custody ~= nil, "custody token recovered")
    assertTrue(t_custody.claimId ~= nil, "custody token has non-nil claimId")
    assertEq(t_custody.claimId, "custody-p1:c53", "custody token receives authoritative claimId (53)")

    -- Verify createClaimedJob forces new monotonic claimId even if caller injects an untrusted one:
    local jobWithInjectedClaim = {
        id = "craft-injected-test",
        npcId = "npc-craft-inj",
        providerType = "CRAFT",
        scopeId = "settlement-1",
        revision = 1,
        state = "PREPARING",
        effects = "KNOWN",
        obligations = {},
        claimId = "FORGED_OLD_CLAIM_ID", -- Untrusted injected identity!
        payload = {
            format = 4,
            id = "craft-injected-test",
            npcId = "npc-craft-inj",
            sequence = 1,
            recipeId = "Base.MakeAxe",
            target = 1,
            produced = 0,
            materials = { { id = 8881, consumed = false } },
            tools = {},
            outputs = {},
            claims = { "item:8881" }
        }
    }
    local okCreateInj, _ = Store.createClaimedJob(jobWithInjectedClaim)
    assertTrue(okCreateInj, "createClaimedJob succeeds")
    assertEq(jobWithInjectedClaim.claimId, "craft-injected-test:c54", "Injected claimId is overwritten with authoritative monotonic sequence (54)")
    local t_inj = Store.getToken("craft-injected-test")
    assertEq(t_inj.claimId, "craft-injected-test:c54", "Runtime token receives authoritative claimId (54)")
end

-- Test 6.13: Real cold boot end-to-end integration (TaskJobs.current -> JobStore.open -> BusinessJobs -> LaborStore)
do
    -- Boundary 1: Envelope / root corrupted with legacy data
    local legacyRoot = {
        format = 1,
        job = { id = "legacy-envelope" }, -- violates JobStore legacy guard
        taskJobs = { format = 1, byId = {} }
    }
    ContainerRegistry.data = function() return legacyRoot end
    local okLegacy, errLegacy = pcall(function()
        local TaskJobs = require('EmberRoutesProbe/TaskJobs')
        TaskJobs.current()
    end)
    assertFalse(okLegacy, "TaskJobs.current() must reject legacy root envelope")
    assertTrue(string.find(tostring(errLegacy), "LEGACY_TASK_RESET_REQUIRED") ~= nil, "Rejection error code is LEGACY_TASK_RESET_REQUIRED")

    -- Boundary 2: Valid JobStore envelope containing corrupted payload
    local bootRootE2E = {
        format = 1,
        containers = {},
        quarantineResources = {},
        taskJobs = {
            format = 1,
            byId = {
                ["haul-e2e-corrupt"] = {
                    id = "haul-e2e-corrupt",
                    npcId = "npc-e2e-corrupt",
                    providerType = "HAUL",
                    scopeId = "local-world",
                    revision = 1,
                    state = "RUNNING",
                    effects = "KNOWN",
                    obligations = {},
                    payload = {
                        format = 1,
                        id = "haul-e2e-corrupt",
                        npcId = "npc-e2e-corrupt",
                        source = "crate-a",
                        destination = "crate-b",
                        items = { "NOT_A_VALID_NUMBER" },
                        state = "RUNNING"
                    }
                }
            }
        }
    }
    ContainerRegistry.data = function() return bootRootE2E end
    -- Real production boot chain without mocking BusinessJobs.hauls:
    local TaskJobs = require('EmberRoutesProbe/TaskJobs')
    local service = TaskJobs.current()
    assertTrue(service ~= nil, "JobStore.open and TaskJobs.current succeed for valid envelope structure")

    local okE2ELoad, errE2ELoad = pcall(Store.data)
    assertTrue(okE2ELoad, "LaborStore.data() must survive corrupted payload in real boot chain: " .. tostring(errE2ELoad))
    local env = bootRootE2E.taskJobs.byId["haul-e2e-corrupt"]
    assertEq(env.state, "RECONCILE_REQUIRED", "Envelope demoted to RECONCILE_REQUIRED")
    assertEq(env.effects, "UNKNOWN", "Envelope effects demoted to UNKNOWN")
    assertEq(env.payload.state, "PAUSED", "Payload demoted to PAUSED")
    assertTrue(env.payload.uncertain == true, "Payload marked uncertain")

    -- Normal Path: Valid jobs recover cleanly through real boot chain
    local bootRootE2EGood = {
        format = 1,
        containers = {},
        quarantineResources = {},
        taskJobs = {
            format = 1,
            byId = {
                ["haul-e2e-good"] = {
                    id = "haul-e2e-good",
                    npcId = "npc-e2e-good",
                    providerType = "HAUL",
                    scopeId = "local-world",
                    revision = 1,
                    state = "RUNNING",
                    effects = "KNOWN",
                    obligations = {},
                    payload = {
                        format = 1,
                        id = "haul-e2e-good",
                        npcId = "npc-e2e-good",
                        source = "crate-a",
                        destination = "crate-b",
                        items = { 7701 },
                        state = "RUNNING"
                    }
                }
            }
        }
    }
    ContainerRegistry.data = function() return bootRootE2EGood end
    local serviceGood = TaskJobs.current()
    assertTrue(serviceGood ~= nil, "TaskJobs.current succeeds for normal job")
    local okGoodLoad, errGoodLoad = pcall(Store.data)
    assertTrue(okGoodLoad, "LaborStore.data succeeds for normal job: " .. tostring(errGoodLoad))
    local t_good = Store.getToken("haul-e2e-good")
    assertTrue(t_good ~= nil, "Token acquired for normal job")
    assertEq(Store.claimsInstance().owners["item:7701"], t_good, "Claims owner assigned to token")
end

-- Test 6.14: B.5-R1 - RETAIN recipient verification, capacity conservation, and fail-close guards
do
    local bootRootRetainAudit = {
        format = 1,
        taskJobs = { format = 1, byId = {} },
        containers = {},
        quarantineResources = {
            ["item:retain-audit-1"] = {
                status = "ACTIVE",
                reason = "RETAIN_AUDIT",
                at = 2000,
                capacityKey = "crate-audit-bucket",
                capacityItemId = 501,
                capacityAmount = 12.5
            },
            ["item:no-cap-quarantine"] = {
                status = "ACTIVE",
                reason = "NO_CAP_TEST",
                at = 2001
            }
        }
    }
    ContainerRegistry.data = function() return bootRootRetainAudit end
    Store.data()
    local claims = Store.claimsInstance()
    assertEq(claims.capacity["crate-audit-bucket"].total, 12.5, "Bucket total initial quarantined capacity is 12.5")

    -- Case A: Fake token (arbitrary unauthenticated table) -> MUST FAIL with CAPACITY_RETAIN_RECIPIENT_TOKEN_INVALID
    local fakeToken = { taskId = "fake-job-id" }
    local okFake, errFake = Store.unquarantineResource("item:retain-audit-1", {
        capacityAction = "RETAIN",
        targetToken = fakeToken
    })
    assertFalse(okFake, "RETAIN with unauthenticated fake token MUST fail")
    assertEq(errFake, "CAPACITY_RETAIN_RECIPIENT_TOKEN_INVALID", "Rejection code matches CAPACITY_RETAIN_RECIPIENT_TOKEN_INVALID")
    assertEq(claims.capacity["crate-audit-bucket"].total, 12.5, "Bucket total untouched after fake token rejection")
    assertEq(bootRootRetainAudit.quarantineResources["item:retain-audit-1"].status, "ACTIVE", "Quarantine remains ACTIVE")

    -- Case B: Released token (previously valid token that was released) -> MUST FAIL
    local validTokenA, _ = claims:acquire("job-released-test", 1, {})
    assertTrue(validTokenA ~= nil, "Token A acquired")
    claims:release(validTokenA)
    local okRel, errRel = Store.unquarantineResource("item:retain-audit-1", {
        capacityAction = "RETAIN",
        targetToken = validTokenA
    })
    assertFalse(okRel, "RETAIN with released token MUST fail")
    assertEq(errRel, "CAPACITY_RETAIN_RECIPIENT_TOKEN_INVALID", "Rejection code matches CAPACITY_RETAIN_RECIPIENT_TOKEN_INVALID")

    -- Case C: Mismatched token object (registered token replaced/tampered)
    local validTokenB, _ = claims:acquire("job-mismatch-test", 1, {})
    local forgedTokenB = { taskId = "job-mismatch-test", generation = 1 }
    local okMis, errMis = Store.unquarantineResource("item:retain-audit-1", {
        capacityAction = "RETAIN",
        targetToken = forgedTokenB
    })
    assertFalse(okMis, "RETAIN with mismatched token object MUST fail")
    assertEq(errMis, "CAPACITY_RETAIN_RECIPIENT_TOKEN_INVALID", "Rejection code matches CAPACITY_RETAIN_RECIPIENT_TOKEN_INVALID")

    -- Case D: Quarantine without capacity entry requesting RETAIN -> MUST FAIL with QUARANTINE_CAPACITY_ENTRY_NOT_FOUND
    local okNoCap, errNoCap = Store.unquarantineResource("item:no-cap-quarantine", {
        capacityAction = "RETAIN",
        targetToken = validTokenB
    })
    assertFalse(okNoCap, "RETAIN on resource without capacity entry MUST fail")
    assertEq(errNoCap, "QUARANTINE_CAPACITY_ENTRY_NOT_FOUND", "Rejection code matches QUARANTINE_CAPACITY_ENTRY_NOT_FOUND")
    assertTrue(bootRootRetainAudit.quarantineResources["item:no-cap-quarantine"] ~= nil, "Resource without capacity entry remains quarantined")

    -- Case E: Target token with mismatched capacityKey -> MUST FAIL with CAPACITY_TARGET_CHANGED
    validTokenB.capacityKey = "different-capacity-bucket"
    local okCapChange, errCapChange = Store.unquarantineResource("item:retain-audit-1", {
        capacityAction = "RETAIN",
        targetToken = validTokenB
    })
    assertFalse(okCapChange, "RETAIN with conflicting capacityKey MUST fail")
    assertEq(errCapChange, "CAPACITY_TARGET_CHANGED", "Rejection code matches CAPACITY_TARGET_CHANGED")
    validTokenB.capacityKey = nil -- reset

    -- Case F: Valid RETAIN transfer with legitimate recipient token
    local okValidRetain, errValidRetain = Store.unquarantineResource("item:retain-audit-1", {
        capacityAction = "RETAIN",
        targetToken = validTokenB,
        reason = "AUDIT_APPROVED"
    })
    assertTrue(okValidRetain, "Valid RETAIN unquarantine succeeds: " .. tostring(errValidRetain))
    assertEq(bootRootRetainAudit.quarantineResources["item:retain-audit-1"], nil, "Quarantine record settled and removed from active")
    assertEq(validTokenB.capacityKey, "crate-audit-bucket", "Token B capacityKey updated to crate-audit-bucket")
    local bucketAudit = claims.capacity["crate-audit-bucket"]
    assertEq(bucketAudit.quarantine["item:retain-audit-1"], nil, "Bucket quarantine entry cleared")
    assertTrue(bucketAudit.entries["job-mismatch-test"] ~= nil, "Recipient claim entry exists in bucket")
    assertEq(bucketAudit.entries["job-mismatch-test"].amount, 12.5, "Recipient claim amount is 12.5")
    assertEq(bucketAudit.total, 12.5, "Bucket total strictly conserved (12.5)")

    -- Repeat call: idempotent/safely rejected
    local okRepeat, _ = Store.unquarantineResource("item:retain-audit-1", {
        capacityAction = "RETAIN",
        targetToken = validTokenB
    })
    assertTrue(okRepeat, "Repeat unquarantine is safely idempotent")
end

-- Test 6.15: B.5-R2 - Authoritative claimId forged injection & cross-provider identity collision isolation
do
    -- Part A: Direct JobStore:create with forged or mismatched claimId
    local TaskJobs = require('EmberRoutesProbe/TaskJobs')
    local jobStoreRoot = {
        format = 1,
        taskJobs = { format = 1, byId = {} },
        containers = {},
        nextClaimSeq = 100
    }
    ContainerRegistry.data = function() return jobStoreRoot end
    local jStore = TaskJobs.current()

    -- A.1: Invalid claimId format (prefix mismatch) rejected by JobStore validation
    local badPrefixJob = {
        id = "job-auth-1",
        npcId = "npc-auth-1",
        providerType = "CRAFT",
        scopeId = "settlement-1",
        revision = 1,
        state = "PREPARING",
        effects = "KNOWN",
        obligations = {},
        claimId = "wrong-prefix:c1", -- prefix does not match id!
        payload = {
            format = 4,
            id = "job-auth-1",
            npcId = "npc-auth-1",
            sequence = 1,
            recipeId = "Base.MakeAxe",
            target = 1,
            produced = 0,
            materials = {},
            tools = {},
            outputs = {},
            claims = {}
        }
    }
    local okBadPrefix, errBadPrefix = jStore:create(badPrefixJob)
    assertFalse(okBadPrefix, "Job with mismatched claimId prefix MUST be rejected by JobStore")
    assertEq(errBadPrefix, "JOB_RECORD_INVALID", "Rejection error code is JOB_RECORD_INVALID")

    -- A.2: Forged claimId (attempting to jump sequence or reuse) is authoritatively overwritten
    local forgedJob = {
        id = "job-auth-2",
        npcId = "npc-auth-2",
        providerType = "CRAFT",
        scopeId = "settlement-1",
        revision = 1,
        state = "PREPARING",
        effects = "KNOWN",
        obligations = {},
        claimId = "job-auth-2:c999", -- Forged jump to 999!
        payload = {
            format = 4,
            id = "job-auth-2",
            npcId = "npc-auth-2",
            sequence = 1,
            recipeId = "Base.MakeAxe",
            target = 1,
            produced = 0,
            materials = {},
            tools = {},
            outputs = {},
            claims = {}
        }
    }
    local okForged, errForged = jStore:create(forgedJob)
    assertTrue(okForged, "JobStore:create succeeds: " .. tostring(errForged))
    local savedForged = jStore:get("job-auth-2")
    assertEq(savedForged.claimId, "job-auth-2:c101", "Forged claimId is overwritten with authoritative sequence (101)")
    assertEq(jobStoreRoot.nextClaimSeq, 101, "root.nextClaimSeq incremented to 101")

    -- Part B: Cold boot identity collision isolation across jobs & preservation of quarantine
    local collisionBootRoot = {
        format = 1,
        nextClaimSeq = 200,
        containers = {},
        quarantineResources = {
            ["item:5555"] = {
                status = "ACTIVE",
                reason = "LEGITIMATE_QUARANTINE",
                originalTaskId = "job-primary-1",
                originalClaimId = "job-colliding-2:c1", -- Quarantine registered to primary job using this claimId
                originalGeneration = 1
            }
        },
        taskJobs = {
            format = 1,
            byId = {
                ["job-primary-1"] = {
                    id = "job-primary-1",
                    npcId = "npc-prim",
                    providerType = "CRAFT",
                    scopeId = "settlement-1",
                    revision = 1,
                    state = "RUNNING",
                    effects = "KNOWN",
                    obligations = {},
                    claimId = "job-primary-1:c1",
                    payload = {
                        format = 4,
                        id = "job-primary-1",
                        npcId = "npc-prim",
                        sequence = 1,
                        recipeId = "Base.MakeAxe",
                        target = 1,
                        produced = 0,
                        materials = { { id = 7771, consumed = false } },
                        tools = {},
                        outputs = {},
                        claims = { "item:7771" }
                    }
                },
                ["job-colliding-2"] = {
                    id = "job-colliding-2",
                    npcId = "npc-coll",
                    providerType = "CRAFT",
                    scopeId = "settlement-1",
                    revision = 1,
                    state = "RUNNING",
                    effects = "KNOWN",
                    obligations = {},
                    claimId = "job-colliding-2:c1", -- Valid prefix for JobStore, but collides with originalTaskId on originalClaimId!
                    payload = {
                        format = 4,
                        id = "job-colliding-2",
                        npcId = "npc-coll",
                        sequence = 1,
                        recipeId = "Base.MakeAxe",
                        target = 1,
                        produced = 0,
                        materials = { { id = 7772, consumed = false } },
                        tools = {},
                        outputs = {},
                        claims = { "item:7772" }
                    }
                }
            }
        }
    }
    ContainerRegistry.data = function() return collisionBootRoot end
    Store.data()

    -- Primary job recovered normally
    local env1 = collisionBootRoot.taskJobs.byId["job-primary-1"]
    assertEq(env1.claimId, "job-primary-1:c1", "Primary job retains legitimate claimId")
    local t_prim = Store.getToken("job-primary-1")
    assertTrue(t_prim ~= nil, "Primary job acquired valid runtime token")

    -- Colliding job MUST be isolated without acquiring claims!
    local env2 = collisionBootRoot.taskJobs.byId["job-colliding-2"]
    assertEq(env2.state, "RECONCILE_REQUIRED", "Colliding job demoted to RECONCILE_REQUIRED")
    assertEq(env2.effects, "UNKNOWN", "Colliding job effects UNKNOWN")
    assertEq(env2.payload.state, "PAUSED", "Colliding job payload state PAUSED")
    assertEq(env2.payload.reason, "CLAIM_IDENTITY_COLLISION", "Colliding job reason is CLAIM_IDENTITY_COLLISION")
    assertTrue(env2.payload.uncertain == true, "Colliding job marked uncertain")
    assertTrue(string.match(env2.claimId, "^job%-colliding%-2:c%d+$") ~= nil, "Colliding job retains a legal claimId")
    assertFalse(env2.claimId == "job-colliding-2:c1", "Colliding job receives a new authoritative identity")
    assertFalse(Store.getToken("job-colliding-2") ~= nil, "Colliding job MUST NOT acquire any runtime token")

    -- Colliding job CANNOT shrink or steal primary job's quarantined resource!
    local reloadedClaims = Store.claimsInstance()
    local fakeCollidingToken = { taskId = "job-colliding-2", claimId = env2.claimId, resources = {} }
    assertFalse(reloadedClaims:canShrink(fakeCollidingToken, { "item:5555" }), "Colliding job CANNOT canShrink primary quarantine")
    assertFalse(reloadedClaims:shrink(fakeCollidingToken, { "item:5555" }), "Colliding job CANNOT shrink primary quarantine")

    -- Primary quarantine item:5555 remains 100% protected under SYSTEM_QUARANTINE!
    assertEq(reloadedClaims.owners["item:5555"].kind, "SYSTEM_QUARANTINE", "item:5555 remains SYSTEM_QUARANTINE")
    assertEq(collisionBootRoot.quarantineResources["item:5555"].status, "ACTIVE", "item:5555 quarantine status remains ACTIVE")

    local function clone(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for k, v in pairs(value) do result[k] = clone(v) end
        return result
    end
    local firstClaims = Store.claimsInstance()
    for boot = 1, 2 do
        -- Fresh module handles AND a detached persisted root; no runtime token is copied.
        collisionBootRoot = clone(collisionBootRoot)
        package.loaded['EmberRoutesProbe/TaskJobs'] = nil
        package.loaded['EmberRoutesProbe/BusinessJobs'] = nil
        package.loaded['EmberRoutesProbe/LaborStore'] = nil
        ContainerRegistry.data = function() return collisionBootRoot end
        local opened, why = JobStore.open(collisionBootRoot)
        assertTrue(opened ~= nil, "Collision ledger reopens on boot " .. boot .. ": " .. tostring(why))
        local freshStore = require('EmberRoutesProbe/LaborStore')
        freshStore.data()
        assertFalse(freshStore.claimsInstance() == firstClaims, "Cold boot creates fresh Claims")
        firstClaims = freshStore.claimsInstance()
        local saved = collisionBootRoot.taskJobs.byId['job-colliding-2']
        assertEq(saved.id, 'job-colliding-2', "Stable job ID survives cold boot")
        assertEq(saved.claimId, env2.claimId, "Replacement claimId stays stable")
        assertFalse(freshStore.getToken(saved.id) ~= nil, "Isolated job cannot reacquire after boot")
        assertEq(freshStore.resourceOwner('item:5555').kind, 'SYSTEM_QUARANTINE', "Original quarantine survives")
        assertEq(freshStore.resourceOwner('item:7772').kind, 'SYSTEM_QUARANTINE', "Colliding task resources stay protected")
        local evidence = collisionBootRoot.quarantineResources['item:7772'].evidence.identityCollision
        assertEq(evidence.originalClaimId, 'job-colliding-2:c1', "Original identity preserved")
        assertTrue(evidence.taskIds['job-primary-1'] and evidence.taskIds['job-colliding-2'], "Both task identities preserved")
        assertEq(evidence.originalTaskId, saved.id, "Original task ID preserved")
        print('PASS R2 independent cold boot ' .. boot)
    end
end

-- R4: same-instance idempotency is distinct from new-instance reconstruction.
do
    local c = Claims.new()
    local q = {originalTaskId='restore-A', originalClaimId='restore-A:c12', originalGeneration=2,
        capacityKey='restore-bin', capacityItemId=21001, capacityAmount=3}
    assertTrue(c:restoreQuarantine('item:21001', q), 'First restore succeeds')
    local owner, revision = c.owners['item:21001'], c.revision
    assertTrue(c:restoreQuarantine('item:21001', q), 'Identical restore succeeds')
    assertEq(c.capacity['restore-bin'].total, 3, 'Repeated restore counts capacity once')
    assertEq(c.owners['item:21001'], owner, 'Repeated restore preserves owner identity')
    assertEq(c.revision, revision, 'Idempotent restore does not invalidate snapshots')
    for _, field in ipairs({'originalTaskId','originalClaimId','originalGeneration','capacityKey','capacityItemId','capacityAmount'}) do
        local changed = {}
        for k,v in pairs(q) do changed[k]=v end
        changed[field] = type(q[field]) == 'number' and q[field]+1 or q[field]..'-changed'
        local ok, why = c:restoreQuarantine('item:21001', changed)
        assertFalse(ok, 'Different restore metadata rejected: '..field)
        assertEq(why, 'QUARANTINE_RESTORE_CONFLICT', 'Explicit metadata conflict')
        assertEq(c.owners['item:21001'], owner, 'Conflict preserves owner')
        assertEq(c.capacity['restore-bin'].total, 3, 'Conflict preserves capacity')
        assertEq(c.revision, revision, 'Conflict is read-only')
    end
    local token = c:acquireNew('restore-other', 1, {'item:21002'})
    assertFalse(c:restoreQuarantine('item:21002', q), 'Restore cannot steal normal ownership')
    assertEq(c.owners['item:21002'], token, 'Normal owner survives failed restore')
    local fresh = Claims.new()
    assertTrue(fresh:restoreQuarantine('item:21001', q), 'New Claims rebuilds persisted record')
    assertEq(fresh.capacity['restore-bin'].total, 3, 'New-instance capacity restored once')
    print('PASS R4 same-instance idempotency, metadata conflicts, ownership and cold reconstruction')
end

-- R3: force actual enumeration order changes (insertion order alone does not
-- control Lua 5.1 pairs). All modules and claims are fresh for each variant.
do
    local function copy(v)
        if type(v)~='table' then return v end
        local r={} for k,x in pairs(v) do r[k]=copy(x) end return r
    end
    local function same(a,b)
        if type(a)~=type(b) then return false end
        if type(a)~='table' then return a==b end
        for k,v in pairs(a) do if not same(v,b[k]) then return false end end
        for k in pairs(b) do if a[k]==nil then return false end end
        return true
    end
    local function craft(id,item)
        return {id=id,npcId='npc-'..id,providerType='CRAFT',scopeId='local-world',revision=1,
            state='RUNNING',effects='KNOWN',obligations={},claimId=id..':c1',
            payload={format=4,id=id,npcId='npc-'..id,sequence=1,recipeId='Base.MakeAxe',
                target=1,produced=0,materials={{id=item}},tools={},outputs={},claims={'item:'..item}}}
    end
    local function boot(saved,reverse)
        local world=copy(saved)
        ContainerRegistry.data=function() return world end
        for _,name in ipairs({'TaskJobs','BusinessJobs','LaborStore'}) do
            package.loaded['EmberRoutesProbe/'..name]=nil
        end
        local basePairs=pairs
        _G.pairs=function(t)
            if t~=world.quarantineResources and t~=world.taskJobs.byId
                and t~=(world.toolCustody and world.toolCustody.byId) then return basePairs(t) end
            local keys={} for k in basePairs(t) do keys[#keys+1]=k end
            table.sort(keys,function(a,b) if reverse then return a>b end return a<b end)
            local n=0
            return function() n=n+1 local k=keys[n] if k then return k,t[k] end end
        end
        local ok,result=pcall(function()
            local s=require('EmberRoutesProbe/LaborStore')
            assertTrue(JobStore.open(world)~=nil,'Variant ledger opens before reconstruction')
            s.data()
            assertTrue(JobStore.open(world)~=nil,'Variant ledger opens after reconstruction')
            return s
        end)
        _G.pairs=basePairs
        assertTrue(ok,'Ordered boot succeeds: '..tostring(result))
        return world,result
    end
    -- Same task, three isolated resources plus one free original: no collision.
    local legitimate={nextClaimSeq=100,containers={},taskJobs={format=1,byId={A=craft('A',22001)}},quarantineResources={}}
    for _,item in ipairs({22002,22003,22004}) do
        legitimate.quarantineResources['item:'..item]={status='ACTIVE',originalTaskId='A',originalClaimId='A:c1'}
    end
    local normal1,s1=boot(legitimate,false)
    assertTrue(s1.getToken('A')~=nil,'Same task with three quarantines recovers free originals')
    local normal2,s2=boot(legitimate,true)
    assertTrue(s2.getToken('A')~=nil,'Reverse scan does not invent same-task collision')
    assertTrue(same(normal1,normal2),'Same-task persisted results are order-independent')

    local conflict=copy(legitimate)
    conflict.quarantineResources['item:22003'].originalTaskId='B'
    conflict.quarantineResources['item:22004'].originalTaskId='C'
    local w1,t1=boot(conflict,false)
    assertFalse(t1.getToken('A')~=nil,'Cross-task quarantine identity blocks A')
    local w2,t2=boot(conflict,true)
    assertFalse(t2.getToken('A')~=nil,'Reverse scan cannot choose A as winner')
    assertTrue(same(w1,w2),'Cross-task persisted results are order-independent')
    local ev=w2.quarantineResources['item:22001'].evidence.identityCollision
    assertTrue(ev.taskIds.A and ev.taskIds.B and ev.taskIds.C,'All conflicting task IDs preserved')
    for _,item in ipairs({22001,22002,22003,22004}) do
        assertEq(t2.resourceOwner('item:'..item).kind,'SYSTEM_QUARANTINE','Every original remains quarantined')
        assertTrue(ev.resourceKeys['item:'..item],'Every resource appears in evidence')
    end
    local again,sAgain=boot(w2,false)
    assertEq(again.taskJobs.byId.A.claimId,w2.taskJobs.byId.A.claimId,'Repeated recovery does not rekey again')
    assertFalse(sAgain.getToken('A')~=nil,'Rekey does not permit reacquisition')

    -- Two custody entries share the same original claim identity. Neither may
    -- escape collision detection through prefix normalization or recover first.
    local custody={nextClaimSeq=100,containers={},taskJobs={format=1,byId={}},quarantineResources={},
        toolCustody={byId={},byNpc={},byItem={}}}
    for i,id in ipairs({'custody-A','custody-B'}) do
        custody.toolCustody.byId[id]={format=1,id=id,npcId='npc-'..i,itemId=23000+i,
            role='CLEAN_TOOL',state='HELD',sequence=1,claims={'item:'..(23000+i)},claimId='custody-A:c1'}
    end
    local c1,cs1=boot(custody,false)
    local c2,cs2=boot(custody,true)
    assertTrue(same(c1,c2),'Two live claimants have identical results in both scan orders')
    for _,id in ipairs({'custody-A','custody-B'}) do
        assertFalse(cs2.getToken(id)~=nil,'No custody collision winner: '..id)
        assertTrue(string.match(c2.toolCustody.byId[id].claimId,'^'..id:gsub('%-','%%-')..':c%d+$')~=nil,
            'Custody replacement identity has legal prefix')
    end
    print('PASS R3 same-task resources, cross-task quarantine sets, live claimants: forward/reverse scans')

    -- P0-2: keep RETAIN production behavior; exercise successive transfers into
    -- an existing reservation and a rejection without any partial mutation.
    local c=Claims.new()
    local t=c:acquireNew('retain-existing',1,{'item:24000'})
    assertTrue(c:reserve(t,'retain-bin',24000,2,100),'Existing reservation initialized')
    for _,item in ipairs({24001,24002}) do
        assertTrue(c:restoreQuarantine('item:'..item,{capacityKey='retain-bin',capacityItemId=item,capacityAmount=3}),
            'Quarantine capacity restored')
    end
    assertEq(c.capacity['retain-bin'].total,8,'Initial ordinary + quarantine capacity is 8')
    for _,item in ipairs({24001,24002}) do
        assertTrue(c:unquarantine('item:'..item,{capacityAction='RETAIN',targetToken=t}),'Same-bucket transfer succeeds')
        assertEq(c.capacity['retain-bin'].total,8,'Each RETAIN conserves total capacity')
    end
    assertEq(c.capacity['retain-bin'].entries[t.taskId].amount,8,'Existing and two transferred amounts merged')
    print('PASS RETAIN existing reservation + two transfers: total=8, recipient=8')
end

print("PASS Part 6: Stage B.4 Edge Cases and Abnormal Recovery Scenarios.")

print("PASS: All Phase 3A Stage B LaborClaims & LaborStore tests passed successfully!")
