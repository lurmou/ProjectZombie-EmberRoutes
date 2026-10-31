-- Phase 3A: JobStore and CRAFT/HAUL validator integration tests.
local Store = require 'EmberRoutesProbe/JobStore'
local CraftJobRecord = require 'EmberRoutesProbe/CraftJobRecord'
local HaulJobRecord = require 'EmberRoutesProbe/HaulJobRecord'

local function assertEq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("ASSERTION_FAILED: %s (expected %s, got %s)", tostring(msg), tostring(expected), tostring(actual)))
    end
end

local function assertTrue(val, msg)
    if not val then error("ASSERTION_FAILED: " .. tostring(msg)) end
end

local function assertFalse(val, msg)
    if val then error("ASSERTION_FAILED: " .. tostring(msg)) end
end

print("Starting Phase 3A Validator Tests...")

-- =========================================================================
-- Part 1: CraftJobRecord direct tests
-- =========================================================================
local validCraftJob = {
    id = "craft-1",
    npcId = "npc-1",
    providerType = "CRAFT",
    scopeId = "settlement-1",
    revision = 1,
    state = "PREPARING",
    effects = "KNOWN",
    obligations = {},
    businessGeneration = 1,
    payload = {
        format = 4,
        sequence = 0,
        recipeId = "Base.MakeAxe",
        target = 5,
        produced = 0,
        benchId = "bench-1",
        released = false,
        materials = { { id = 101, consumed = false }, { id = 102, consumed = false } },
        tools = { { id = 201 } },
        outputs = {},
        held = {},
        claims = {
            "craft-surface:bench-1",
            "item:101",
            "item:102",
            "item:201"
        }
    }
}

assertTrue(CraftJobRecord.valid(validCraftJob), "validCraftJob should be valid")

-- Test 1.1: Format mismatch
local invalidCraft = {
    id = "craft-2", npcId = "npc-1", providerType = "CRAFT", scopeId = "s", revision = 1,
    state = "PREPARING", effects = "KNOWN", obligations = {},
    payload = { format = 3, sequence = 0, recipeId = "Base.MakeAxe", target = 1, produced = 0, claims = {} }
}
assertFalse(CraftJobRecord.valid(invalidCraft), "format=3 should be rejected by CraftJobRecord")

-- Test 1.2: Claims mismatch (missing one item)
local craftMissingClaim = {
    id = "craft-3", npcId = "npc-1", providerType = "CRAFT", scopeId = "s", revision = 1,
    state = "PREPARING", effects = "KNOWN", obligations = {},
    payload = {
        format = 4, sequence = 0, recipeId = "Base.MakeAxe", target = 1, produced = 0,
        benchId = "b1", released = false,
        materials = { { id = 101, consumed = false } },
        tools = {}, outputs = {}, held = {},
        claims = {} -- Should have craft-surface:b1 and item:101
    }
}
assertFalse(CraftJobRecord.valid(craftMissingClaim), "Craft job missing claims should be rejected")

-- Test 1.3: Terminal state with remaining claims
local terminalCraftWithClaims = {
    id = "craft-4", npcId = "npc-1", providerType = "CRAFT", scopeId = "s", revision = 1,
    state = "DONE", effects = "KNOWN", obligations = {},
    payload = {
        format = 4, sequence = 1, recipeId = "Base.MakeAxe", target = 1, produced = 1,
        released = true,
        claims = { "item:101" } -- Terminal state MUST have 0 claims!
    }
}
assertFalse(CraftJobRecord.valid(terminalCraftWithClaims), "Terminal craft job with claims must be rejected")

-- Test 1.4: Terminal state with released=false
local terminalCraftUnreleased = {
    id = "craft-5", npcId = "npc-1", providerType = "CRAFT", scopeId = "s", revision = 1,
    state = "DONE", effects = "KNOWN", obligations = {},
    payload = {
        format = 4, sequence = 1, recipeId = "Base.MakeAxe", target = 1, produced = 1,
        released = false, -- Must be released=true
        claims = {}
    }
}
assertFalse(CraftJobRecord.valid(terminalCraftUnreleased), "Terminal craft job with released=false must be rejected")

-- Test 1.5: Valid terminal craft job
local validTerminalCraft = {
    id = "craft-6", npcId = "npc-1", providerType = "CRAFT", scopeId = "s", revision = 1,
    state = "DONE", effects = "KNOWN", obligations = {},
    payload = {
        format = 4, sequence = 1, recipeId = "Base.MakeAxe", target = 1, produced = 1,
        released = true,
        claims = {}
    }
}
assertTrue(CraftJobRecord.valid(validTerminalCraft), "Valid terminal craft job should pass")

-- =========================================================================
-- Part 2: HaulJobRecord direct tests
-- =========================================================================
local validHaulJob = {
    id = "haul-1",
    npcId = "npc-1",
    providerType = "HAUL",
    scopeId = "settlement-1",
    revision = 1,
    state = "PREPARING",
    effects = "KNOWN",
    obligations = {},
    businessGeneration = 1,
    payload = {
        format = 3,
        sequence = 0,
        source = "cont-1",
        destination = "cont-2",
        manifest = {
            { itemId = 501, custodyState = "UNCOLLECTED" },
            { itemId = 502, custodyState = "CARRIED" }
        },
        claims = { "item:501", "item:502" }
    }
}

assertTrue(HaulJobRecord.valid(validHaulJob), "validHaulJob should be valid")

-- Test 2.1: Terminal haul job with remaining reservation
local terminalHaulWithReservation = {
    id = "haul-2", npcId = "npc-1", providerType = "HAUL", scopeId = "s", revision = 1,
    state = "DONE", effects = "KNOWN", obligations = {},
    payload = {
        format = 3, sequence = 1, source = "c1", destination = "c2", manifest = {},
        claims = {},
        reservation = { format = 2, key = "dest", items = { [501] = 1 } } -- Terminal MUST not have reservation
    }
}
assertFalse(HaulJobRecord.valid(terminalHaulWithReservation), "Terminal haul job with reservation must be rejected")

-- Test 2.2: Terminal haul job with claims
local terminalHaulWithClaims = {
    id = "haul-3", npcId = "npc-1", providerType = "HAUL", scopeId = "s", revision = 1,
    state = "DONE", effects = "KNOWN", obligations = {},
    payload = {
        format = 3, sequence = 1, source = "c1", destination = "c2", manifest = {},
        claims = { "item:501" } -- Terminal MUST not have claims
    }
}
assertFalse(HaulJobRecord.valid(terminalHaulWithClaims), "Terminal haul job with claims must be rejected")

-- =========================================================================
-- Part 3: JobStore integration tests
-- =========================================================================
local root = { taskJobs = { format = 1, byId = {} } }
local store = Store.open(root)
assertTrue(store ~= nil, "JobStore should open with format=1")

-- Test 3.1: Create valid CRAFT job via JobStore
local okCraft, errCraft = store:create(validCraftJob)
assertTrue(okCraft, "Store should create valid CRAFT job: " .. tostring(errCraft))

-- Test 3.2: Create invalid CRAFT job via JobStore
local okBadCraft, errBadCraft = store:create(craftMissingClaim)
assertFalse(okBadCraft, "Store must reject invalid CRAFT job")
assertEq(errBadCraft, "JOB_RECORD_INVALID", "Error should be JOB_RECORD_INVALID")

-- Test 3.3: Create valid HAUL job via JobStore
local okHaul, errHaul = store:create(validHaulJob)
assertTrue(okHaul, "Store should create valid HAUL job: " .. tostring(errHaul))

-- Test 3.4: Try updating craft job to DONE while claims remain
-- Transitions: PREPARING -> SETTLING -> DONE
local okSet, errSet = store:update("craft-1", 1, { state = "SETTLING" })
assertTrue(okSet, "PREPARING -> SETTLING should succeed: " .. tostring(errSet))

local okDoneBad, errDoneBad = store:update("craft-1", 2, { state = "DONE" })
assertFalse(okDoneBad, "Updating to DONE with remaining claims MUST fail validation")
assertEq(errDoneBad, "JOB_RECORD_INVALID", "Error should be JOB_RECORD_INVALID")

-- Test 3.5: Clean claims & release, then update to DONE succeeds
local pClean = validCraftJob.payload
pClean.claims = {}
pClean.released = true
pClean.materials = { { id = 101, consumed = true }, { id = 102, consumed = true } }
pClean.tools = {}
pClean.outputs = {}
pClean.benchId = nil

local okDoneGood, errDoneGood = store:update("craft-1", 2, {
    state = "DONE",
    payload = pClean
})
assertTrue(okDoneGood, "Updating to DONE with empty claims & released=true should succeed: " .. tostring(errDoneGood))

print("PASS: 12 Phase 3A JobStore & CRAFT/HAUL validator integration checks.")
