-- Phase 3A: JobStore and CRAFT/HAUL validator integration tests (v1.4 Errata Revision).
-- Tests defensive structure validation, assetFree compatibility, legacy format support, and Store.validate.
local Store = require 'EmberRoutesProbe/JobStore'
local CraftJobRecord = require 'EmberRoutesProbe/CraftJobRecord'
local HaulJobRecord = require 'EmberRoutesProbe/HaulJobRecord'
local ProductionYield = require 'EmberRoutesProbe/ProductionYield'

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

print("Starting Phase 3A Defensive Validator & Compatibility Tests...")

-- =========================================================================
-- Part 1: CraftJobRecord Defensive Structure & No-Crash Tests
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

-- Defensive 1.1: Corrupted materials field (string instead of array)
local corruptedMaterials = {
    id = "c-bad-1", npcId = "npc-1", providerType = "CRAFT", scopeId = "s", revision = 1,
    state = "PREPARING", effects = "KNOWN", obligations = {},
    payload = {
        format = 4, sequence = 0, recipeId = "Base.MakeAxe", target = 1, produced = 0,
        materials = "corrupted_string_instead_of_table",
        claims = {}
    }
}
assertFalse(CraftJobRecord.valid(corruptedMaterials), "Corrupted materials must return false without crashing")

-- Defensive 1.2: Corrupted materials elements (element is not a table, or missing id)
local corruptedMaterialElement = {
    id = "c-bad-2", npcId = "npc-1", providerType = "CRAFT", scopeId = "s", revision = 1,
    state = "PREPARING", effects = "KNOWN", obligations = {},
    payload = {
        format = 4, sequence = 0, recipeId = "Base.MakeAxe", target = 1, produced = 0,
        materials = { "string_item", 123 },
        claims = {}
    }
}
assertFalse(CraftJobRecord.valid(corruptedMaterialElement), "Corrupted material element must return false")

-- Defensive 1.3: Sparse array in claims (table with hole)
local sparseClaims = {
    id = "c-bad-3", npcId = "npc-1", providerType = "CRAFT", scopeId = "s", revision = 1,
    state = "PREPARING", effects = "KNOWN", obligations = {},
    payload = {
        format = 4, sequence = 0, recipeId = "Base.MakeAxe", target = 1, produced = 0,
        materials = {}, tools = {}, outputs = {}, held = {},
        claims = { [1] = "item:1", [3] = "item:2" } -- missing [2]
    }
}
assertFalse(CraftJobRecord.valid(sparseClaims), "Sparse claims array must return false")

-- =========================================================================
-- Part 2: ProductionYield.assetFree & Format 4 Compatibility
-- =========================================================================
local assetFreeCraftJob = {
    id = "craft-free",
    npcId = "npc-1",
    providerType = "CRAFT",
    scopeId = "settlement-1",
    revision = 1,
    state = "SETTLING",
    effects = "KNOWN",
    obligations = {},
    businessGeneration = 1,
    payload = {
        format = 4,
        sequence = 1,
        recipeId = "Base.MakeBandage",
        target = 1,
        produced = 1,
        benchId = "bench-optional",
        released = false,
        materials = {},
        tools = {},
        outputs = {},
        held = {},
        claims = {}, -- assetFree allows empty claims!
        activityYield = {
            format = 1,
            eventId = "event-1",
            recipeId = "Base.MakeBandage",
            product = "Base.Bandage",
            kind = "MANUAL",
            cleared = true,
            ownerEpoch = 100,
            membershipRevision = 1
        },
        activityContinuation = {
            format = 1,
            goal = {
                recipeId = "Base.MakeBandage",
                recipeName = "Make Bandage",
                product = "Base.Bandage",
                signature = "sig",
                requested = 1,
                target = 1,
                unitYield = 1
            },
            delivered = 1,
            resumeEpoch = 100,
            membershipRevision = 1
        }
    }
}
assertTrue(ProductionYield.assetFree(assetFreeCraftJob.payload), "ProductionYield.assetFree must support format=4")
assertTrue(CraftJobRecord.valid(assetFreeCraftJob), "assetFree craft job with empty claims must be valid")

-- =========================================================================
-- Part 3: HaulJobRecord Defensive Structure & No-Crash Tests
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

-- Defensive 3.1: Corrupted manifest field (boolean or string instead of table)
local corruptedManifest = {
    id = "h-bad-1", npcId = "npc-1", providerType = "HAUL", scopeId = "s", revision = 1,
    state = "PREPARING", effects = "KNOWN", obligations = {},
    payload = { format = 3, sequence = 0, source = "c1", destination = "c2", manifest = true, claims = {} }
}
assertFalse(HaulJobRecord.valid(corruptedManifest), "Corrupted manifest must return false without crash")

-- Defensive 3.2: Corrupted line in manifest (element without itemId)
local corruptedManifestLine = {
    id = "h-bad-2", npcId = "npc-1", providerType = "HAUL", scopeId = "s", revision = 1,
    state = "PREPARING", effects = "KNOWN", obligations = {},
    payload = {
        format = 3, sequence = 0, source = "c1", destination = "c2",
        manifest = { { custodyState = "CARRIED" } }, -- missing itemId
        claims = {}
    }
}
assertFalse(HaulJobRecord.valid(corruptedManifestLine), "Corrupted manifest line must return false")

-- Defensive 3.3: Invalid custodyState in manifest
local invalidCustodyState = {
    id = "h-bad-3", npcId = "npc-1", providerType = "HAUL", scopeId = "s", revision = 1,
    state = "PREPARING", effects = "KNOWN", obligations = {},
    payload = {
        format = 3, sequence = 0, source = "c1", destination = "c2",
        manifest = { { itemId = 501, custodyState = "UNKNOWN_STATE" } },
        claims = { "item:501" }
    }
}
assertFalse(HaulJobRecord.valid(invalidCustodyState), "Invalid custodyState must return false")

-- =========================================================================
-- Part 4: Store.validate API & Legacy Format Compatibility Tests
-- =========================================================================
assertTrue(type(Store.validate) == 'function', "Store.validate must be exported as a public API")

-- Test 4.1: Store.validate with new format 4 CRAFT
assertTrue(Store.validate(validCraftJob), "Store.validate should accept valid format 4 CRAFT")
assertFalse(Store.validate(corruptedMaterials), "Store.validate should reject corrupted CRAFT without crashing")

-- Test 4.2: Store.validate with new format 3 HAUL
assertTrue(Store.validate(validHaulJob), "Store.validate should accept valid format 3 HAUL")
assertFalse(Store.validate(corruptedManifest), "Store.validate should reject corrupted HAUL without crashing")

-- Test 4.3: Legacy CRAFT format 3 job before migration (must be accepted by Store.validate)
local legacyCraftFormat3 = {
    id = "legacy-c3",
    npcId = "npc-1",
    providerType = "CRAFT",
    scopeId = "settlement-1",
    revision = 1,
    state = "PREPARING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        format = 3,
        id = "legacy-c3",
        npcId = "npc-1",
        recipeId = "Base.MakeAxe",
        recipeName = "Make Axe",
        product = "Base.Axe",
        signature = "sig-axe",
        settlementId = "settlement-1",
        requester = "player_1",
        target = 2,
        requested = 2,
        unitYield = 1,
        produced = 0,
        delivered = 0,
        released = false,
        generation = 1,
        state = "RUNNING",
        phase = "PLANNING",
        materials = { { id = 701, slot = 0 } },
        tools = {},
        outputs = {}
    }
}
assertTrue(Store.validate(legacyCraftFormat3), "Store.validate must support legacy format 3 CRAFT before migration")

-- Test 4.4: Legacy HAUL format 2 job before migration (must be accepted by Store.validate)
local legacyHaulFormat2 = {
    id = "legacy-h2",
    npcId = "npc-1",
    providerType = "HAUL",
    scopeId = "settlement-1",
    revision = 1,
    state = "PREPARING",
    effects = "KNOWN",
    obligations = {},
    payload = {
        format = 2,
        id = "legacy-h2",
        producer = "LOGISTICS",
        source = "cont-src",
        destination = "cont-dest",
        settlementId = "settlement-1",
        items = { 801 },
        manifest = {
            { itemId = 801, custodyState = "UNCOLLECTED", sourceId = "cont-src", deliveryPolicy = "AUTO_STORAGE" }
        },
        plannedCount = 1,
        routeRevision = 1,
        attemptSequence = 0
    }
}
assertTrue(Store.validate(legacyHaulFormat2), "Store.validate must support legacy format 2 HAUL before migration")

-- =========================================================================
-- Part 5: JobStore Integration (Create, Update, Done)
-- =========================================================================
local root = { taskJobs = { format = 1, byId = {} } }
local store = Store.open(root)
assertTrue(store ~= nil, "JobStore should open")

-- Create format 4 CRAFT
local okC, errC = store:create(validCraftJob)
assertTrue(okC, "store:create format 4 CRAFT: " .. tostring(errC))

-- Create format 3 HAUL
local okH, errH = store:create(validHaulJob)
assertTrue(okH, "store:create format 3 HAUL: " .. tostring(errH))

-- Create legacy format 3 CRAFT (pre-migration compatibility)
local okLegC, errLegC = store:create(legacyCraftFormat3)
assertTrue(okLegC, "store:create legacy format 3 CRAFT: " .. tostring(errLegC))

-- Create legacy format 2 HAUL (pre-migration compatibility)
local okLegH, errLegH = store:create(legacyHaulFormat2)
assertTrue(okLegH, "store:create legacy format 2 HAUL: " .. tostring(errLegH))

print("PASS: All 20 Phase 3A Defensive Validator, AssetFree, Legacy Compatibility, and Public Validate tests passed!")
