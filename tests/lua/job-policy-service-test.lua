-- Unit test for JobPolicyRegistry, JobPolicyService, and built-in policy definitions.
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path

local checks = 0
local function check(cond, msg)
    assert(cond, msg or "Assertion failed")
    checks = checks + 1
end

-- Mock Ledger and Signals
local fakeRoot = {
    format = 1,
    entries = {
        ["settlement_test"] = {
            id = "settlement_test",
            name = "Test Camp",
            factionId = "player_faction",
            areas = {{ x = 100, y = 100, w = 20, h = 20 }}
        }
    }
}

package.loaded['EmberRoutesProbe/SettlementLedger'] = {
    data = function() return fakeRoot end,
    authorized = function(actor) return actor == 'actor' end,
    view = function(actor, id)
        if actor ~= 'actor' then return nil, 'UNAUTHORIZED' end
        return fakeRoot.entries[id], 'SETTLEMENT_MISSING'
    end
}

local notified = 0
local Signals = require 'EmberRoutesProbe/LaborSignals'
Signals.watch(function() notified = notified + 1 end)

local Registry = require 'EmberRoutesProbe/JobPolicyRegistry'
local Service = require 'EmberRoutesProbe/JobPolicyService'
local CleaningDef = require 'EmberRoutesProbe/CleaningPolicyDef'
local CookingDef = require 'EmberRoutesProbe/CookingPolicyDef'

print("=== Running Job Policy Unit Tests ===")

-- 1. Test Registry
local categories = Registry.categories()
check(#categories >= 2, "Expected at least 2 categories registered")
check(Registry.get('cleaning') ~= nil, "Cleaning policy definition should be registered")
check(Registry.get('cooking') ~= nil, "Cooking policy definition should be registered")
print("PASS: Registry registration verified.")

-- 2. Test Defaults
local cleanDefaults = Service.get("settlement_test", "cleaning")
check(cleanDefaults.corpseZoneId == '', "corpseZoneId should default to empty string")
check(cleanDefaults.cleanRadius == 20, "cleanRadius should default to 20")
check(cleanDefaults.haulRottenFood == true, "haulRottenFood should default to true")
check(cleanDefaults.cleanBloodOnly == false, "cleanBloodOnly should default to false")
print("PASS: Default value resolution verified.")

-- 3. Test Draft Isolation (Deep Clone)
local draft = Service.getDraft("settlement_test", "cleaning")
draft.cleanRadius = 45
draft.corpseZoneId = "zone_dump_1"
draft.haulRottenFood = false
local liveBeforeSave = Service.get("settlement_test", "cleaning")
check(liveBeforeSave.cleanRadius == 20, "Mutating draft MUST NOT mutate live store before save!")
check(liveBeforeSave.corpseZoneId == '', "Mutating draft MUST NOT mutate live store before save!")
print("PASS: Draft isolation verified.")

-- 4. Test Validation Interception
local badDraft = Service.getDraft("settlement_test", "cleaning")
badDraft.cleanRadius = -5 -- Invalid!
local ok, err = Service.save('actor', "settlement_test", "cleaning", badDraft)
check(ok == false, "Saving invalid cleanRadius should fail")
check(err == "INVALID_CLEAN_RADIUS", "Expected INVALID_CLEAN_RADIUS, got: " .. tostring(err))
print("PASS: Validation interception verified.")

-- 5. Test Successful Commit & Sanitization
draft.cleanRadius = 35
draft.corpseZoneId = "zone_graveyard_9"
draft.injectedGarbage = "hack" -- Should be stripped!
local savedOk, saveErr = Service.save('actor', "settlement_test", "cleaning", draft)
check(savedOk == true, "Save valid draft should succeed: " .. tostring(saveErr))
check(notified > 0, "Real LaborSignals.changed should be triggered on save")

local updatedLive = Service.get("settlement_test", "cleaning")
check(updatedLive.cleanRadius == 35, "cleanRadius should be 35 after save")
check(updatedLive.corpseZoneId == "zone_graveyard_9", "corpseZoneId should be updated after save")
check(updatedLive.injectedGarbage == nil, "Undeclared field MUST be sanitized/stripped from ModData!")
print("PASS: Successful commit and sanitization verified.")

-- 6. Test Cooking Policy
local cookDraft = Service.getDraft("settlement_test", "cooking")
check(cookDraft.spoilageStrategy == "EXPIRE_SOON_FIRST", "Default spoilage strategy should be EXPIRE_SOON_FIRST")
check(cookDraft.allowedFoodCategories.Meat == true, "Meat should be enabled by default")
check(cookDraft.allowedFoodCategories.Canned == false, "Canned should be disabled by default")

cookDraft.spoilageStrategy = "FRESH_FIRST"
cookDraft.allowedFoodCategories.Canned = true
cookDraft.allowRotten = true
local cookSaved = Service.save('actor', "settlement_test", "cooking", cookDraft)
check(cookSaved == true, "Cooking draft save should succeed")
local cookLive = Service.get("settlement_test", "cooking")
check(cookLive.spoilageStrategy == "FRESH_FIRST", "Cooking live strategy should be FRESH_FIRST")
check(cookLive.allowedFoodCategories.Canned == true, "Cooking live Canned should be true")
check(cookLive.allowRotten == true, "Cooking live allowRotten should be true")
print("PASS: Cooking policy workflow verified.")

local before = fakeRoot.jobPolicies
local revision = before.revision
check(not Service.save(nil, 'settlement_test', 'cleaning', draft), 'missing actor rejected')
check(not Service.save('actor', 'missing', 'cleaning', draft), 'missing settlement rejected')
check(before.revision == revision and before.byScope.missing == nil, 'rejected writes leave policy untouched')
local unsupported = {format=99,revision=7,byScope={original={cleaning={cleanRadius=45}}}}
fakeRoot.jobPolicies = unsupported
local value, why = Service.getDraft('settlement_test', 'cleaning')
check(value == nil and why == 'POLICY_FORMAT_UNSUPPORTED', 'unknown format yields no editable default draft')
check(not pcall(Service.get, 'settlement_test', 'cleaning'), 'unknown format cannot drive work with defaults')
check(not Service.save('actor', 'settlement_test', 'cleaning', draft), 'unknown format cannot be overwritten by save')
check(fakeRoot.jobPolicies == unsupported and unsupported.byScope.original.cleaning.cleanRadius == 45, 'original unknown data preserved')
fakeRoot.jobPolicies = before
check(Service.get('settlement_test', 'cleaning').cleanRadius == 35, 'supported root can reopen after blocked data')
print(string.format("=== ALL %d CHECKS PASSED ===", checks))
