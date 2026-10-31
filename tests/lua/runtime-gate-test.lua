package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;" .. package.path

local Gate = require 'EmberRoutesProbe/RuntimeGate'

-- 1. Uninitialized / Unknown environment (engine globals are nil)
-- Must reject execution instead of silently defaulting to single player.
_G.isClient = nil
_G.isServer = nil
assert(Gate.isClient() == nil, "uninitialized isClient must be nil")
assert(Gate.isServer() == nil, "uninitialized isServer must be nil")
assert(Gate.isSinglePlayer() == false, "uninitialized environment must NOT be treated as single player")

-- 2. Live actor checks: strictly reject objects without character contract
assert(Gate.isLiveActor(nil) == false, "nil actor is rejected")
assert(Gate.isLiveActor(123) == false, "primitive actor is rejected")
assert(Gate.isLiveActor({}) == false, "empty table without isDead function must be rejected")
assert(Gate.isLiveActor({ isDead = "not_a_function" }) == false, "invalid isDead type must be rejected")

local deadActor = { isDead = function() return true end }
local livingActor = { isDead = function() return false end }
assert(Gate.isLiveActor(deadActor) == false, "dead actor must be rejected")
assert(Gate.isLiveActor(livingActor) == true, "living actor with valid isDead method accepted")

-- 3. Initialized Single Player environment
_G.isClient = function() return false end
_G.isServer = function() return false end
assert(Gate.isClient() == false, "SP isClient is false")
assert(Gate.isServer() == false, "SP isServer is false")
assert(Gate.isSinglePlayer() == true, "SP environment verified")
assert(Gate.canExecute(livingActor) == true, "canExecute true for living actor in verified SP")
assert(Gate.canExecute(deadActor) == false, "canExecute false for dead actor")
assert(Gate.canExecute({}) == false, "canExecute false for empty table")
assert(Gate.canExecute(nil) == false, "canExecute false for nil actor")

-- 4. Mock Multiplayer Client environment
_G.isClient = function() return true end
_G.isServer = function() return false end
assert(Gate.isClient() == true, "client mock detected")
assert(Gate.isSinglePlayer() == false, "client is not single player")
assert(Gate.canExecute(livingActor) == false, "cannot execute SP on MP client")

-- 5. Mock Multiplayer Dedicated Server environment
_G.isClient = function() return false end
_G.isServer = function() return true end
assert(Gate.isServer() == true, "server mock detected")
assert(Gate.isSinglePlayer() == false, "server is not single player")
assert(Gate.isAuthoritative() == true, "server is authoritative")
assert(Gate.canExecute(livingActor) == false, "cannot execute SP on MP server")

-- 6. Consumer verification with SettlementLedger
_G.isClient = function() return false end
_G.isServer = function() return false end
package.loaded['EmberRoutesProbe/ContainerRegistry'] = { id = function() return 'faction_test' end }
local Ledger = require 'EmberRoutesProbe/SettlementLedger'
local ok, authorized = pcall(Ledger.authorized, nil)
assert(ok and not authorized, "missing actor is rejected without calling getIndex")
local actorWithoutGetIndex = { isDead = function() return false end }
local ok2, authorized2 = pcall(Ledger.authorized, actorWithoutGetIndex)
assert(ok2 and not authorized2, "actor without getIndex is safely rejected without crashing")
livingActor.getIndex = function() return 0 end
_G.getSpecificPlayer = function() return livingActor end
assert(Ledger.authorized(livingActor) == true, "local live player is authorized")
_G.getSpecificPlayer = function() return { isDead = function() return false end } end
assert(Ledger.authorized(livingActor) == false, "different player cannot impersonate actor")

-- 7. Native Field Operations Gate
Gate.resetCache()
assert(Gate.hasFieldOperations() == false, "headless test environment without ISCleanBlood must return false")
_G.ISCleanBlood = {}
Gate.resetCache()
assert(Gate.hasFieldOperations() == true, "live engine environment with ISCleanBlood must return true")
_G.ISCleanBlood = nil
Gate.resetCache()

-- 8. Naked Kahlua runtime simulation (PZ 42 does not register _G.package)
local realPackage = _G.package
_G.package = nil
assert(Gate.hasFieldOperations() == false, "naked Kahlua without package must safely return false without indexing null")
_G.ISCleanBlood = {}
Gate.resetCache()
assert(Gate.hasFieldOperations() == true, "naked Kahlua with live ISCleanBlood must return true without package")
_G.ISCleanBlood = nil
_G.package = realPackage
Gate.resetCache()

-- Cleanup globals
_G.isClient = nil
_G.isServer = nil
_G.getSpecificPlayer = nil
_G.ISCleanBlood = nil

print("PASS: runtime-gate-test (strict production guard verified)")
