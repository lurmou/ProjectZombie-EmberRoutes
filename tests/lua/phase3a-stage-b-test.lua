-- =========================================================================
-- Phase 3A Stage B Unit Tests: LaborClaims (F2/F3) & LaborStore Atomic Operations
-- =========================================================================

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

print("PASS Part 5: Two-Pass Cold Boot Recovery with Quarantine Precedence.")

print("PASS: All Phase 3A Stage B LaborClaims & LaborStore tests passed successfully!")
