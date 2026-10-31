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

-- Test 6.2: Dispute reconciliation and unquarantine recovery
local okQ = Store.quarantineResource("item:8001", "MANUAL_DISPUTE", { reason = "test" })
assertTrue(okQ, "quarantineResource item:8001")
assertEq(Store.owner(8001).kind, "SYSTEM_QUARANTINE", "item:8001 is quarantined")

-- Unquarantine via claims instance restores availability
local claimsInst = Store.claimsInstance()
claimsInst:unquarantine("item:8001")
assertFalse(Store.owner(8001) ~= nil, "item:8001 is now unquarantined and unowned")

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

-- Test 6.3: Format 1 legacy haul job lifecycle & terminal cleanup in JobStore
local haulF1 = {
    id = "haul-f1-test",
    npcId = "npc-haul-f1",
    providerType = "HAUL",
    scopeId = "local-world",
    revision = 1,
    state = "PREPARING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        id = "haul-f1-test",
        npcId = "npc-haul-f1",
        source = "crate-src",
        destination = "crate-dest",
        items = { 9001, 9002 },
        state = "PAUSED",
        reason = "CREATED",
        delivered = 0,
        format = 1,
        kind = "EXPLICIT_TRANSFER",
        claims = { "item:9001", "item:9002" }
    }
}
local okCreateF1, _ = Store.createClaimedJob(haulF1)
assertTrue(okCreateF1, "createClaimedJob format 1 haul job")
assertTrue(Store.getToken("haul-f1-test") ~= nil, "Token exists for haul-f1-test")

-- Mutate to RUNNING
local okRunF1, revRunF1 = Store.mutateJob("haul-f1-test", 1, haulF1.payload, {
    state = "RUNNING"
})
assertTrue(okRunF1, "mutateJob haul-f1-test to RUNNING")

-- Mutate to SETTLING then DONE with shrink of all claims
local pDoneF1 = {}
for k, v in pairs(haulF1.payload) do pDoneF1[k] = v end
pDoneF1.delivered = 2
pDoneF1.claims = {}

local okSetF1, revSetF1 = Store.mutateJob("haul-f1-test", revRunF1, pDoneF1, {
    state = "SETTLING",
    removeKeys = { "item:9001", "item:9002" }
})
assertTrue(okSetF1, "mutateJob haul-f1-test to SETTLING: " .. tostring(revSetF1))

pDoneF1.state = "DONE"
local okDoneF1, revDoneF1 = Store.mutateJob("haul-f1-test", revSetF1, pDoneF1, {
    state = "DONE"
})
assertTrue(okDoneF1, "mutateJob haul-f1-test to DONE: " .. tostring(revDoneF1))
assertFalse(Store.getToken("haul-f1-test") ~= nil, "Token cleaned on terminal DONE for format 1 haul")
assertFalse(Store.owner(9001) ~= nil, "item:9001 released on DONE")
assertFalse(Store.owner(9002) ~= nil, "item:9002 released on DONE")

-- Test 6.4: Capacity reserve bounds (negative, NaN, overflow)
local dummyToken = Store.getToken("craft-p6-stale")
assertTrue(dummyToken ~= nil, "craft-p6-stale token available")
local okNeg, errNeg = claimsInst:reserve(dummyToken, "cap-target", 7001, 10, -5)
assertFalse(okNeg, "Negative free capacity must be rejected")
assertEq(errNeg, "CAPACITY_UNAVAILABLE", "Rejection reason is CAPACITY_UNAVAILABLE")

local okNan, errNan = claimsInst:reserve(dummyToken, "cap-target", 7001, 0/0, 100)
assertFalse(okNan, "NaN amount must be rejected")
assertEq(errNan, "CAPACITY_UNAVAILABLE", "Rejection reason is CAPACITY_UNAVAILABLE")

local okOverflow, errOverflow = claimsInst:reserve(dummyToken, "cap-target", 7001, 200, 100)
assertFalse(okOverflow, "Exceeding free capacity must be rejected")
assertEq(errOverflow, "CAPACITY_RESERVED", "Rejection reason is CAPACITY_RESERVED")

local okValidCap, _ = claimsInst:reserve(dummyToken, "cap-target", 7001, 50, 100)
assertTrue(okValidCap, "Valid reservation within bounds must succeed")

print("PASS Part 6: Stage B.4 Edge Cases and Abnormal Recovery Scenarios.")

print("PASS: All Phase 3A Stage B LaborClaims & LaborStore tests passed successfully!")
