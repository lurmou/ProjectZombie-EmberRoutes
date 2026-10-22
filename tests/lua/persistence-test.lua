-- Uses real action, haul and companion controllers; the Java/engine boundary is a fake.
local world = dofile("tests/lua/haul-test.lua")
local ctx, npc, actor, Haul = world.ctx, world.npc, world.actor, world.Haul
local Probe, Actions = ctx.Probe, ctx.Actions
local count, saves, restores, reports, blocked = 0, 0, 0, 0, {}
local function check(value, message) count = count + 1 assert(value, message) end
EmberRoutesProbeJava.controlledCarrier = function() return npc end
EmberRoutesProbeJava.carrierId = function(expected) return expected == npc and "persistent-npc" or "" end
function Probe.cancelAll(reason)
    if Probe.cancelCompanion then Probe.cancelCompanion(reason) end
    Actions.cancel(reason)
    Haul.cancel(reason)
end
local currentActor = actor
function actor:getCurrentSquare() return {} end
function getSpecificPlayer(index) assert(index == 0) return currentActor end
local Companion = require "EmberRoutesProbe/Companion"
local Persistence = require "EmberRoutesProbe/Persistence"
local realPrint = print
print = function() end
EmberRoutesProbeJava.blockCheckpoint = function(reason) blocked[#blocked + 1] = reason return "CHECKPOINT_BLOCKED" end
local savedIntent
EmberRoutesProbeJava.saveCheckpoint = function(mode, home, x, y, z)
    saves = saves + 1
    savedIntent = { mode = mode, home = home, x = x, y = y, z = z }
    check(npc.actions:isEmpty() and not Actions.isBusy() and not Haul.busy(), "all native action owners released before capture")
    check(not Actions.fixtures and #Haul.fixtures == 0, "fixtures removed before capture")
    return "CHECKPOINT_SAVED"
end
local restoreResult = "CHECKPOINT_RESTORED"
EmberRoutesProbeJava.restoreCheckpoint = function() restores = restores + 1 return restoreResult end
EmberRoutesProbeJava.reportCheckpoint = function() reports = reports + 1 return "CHECKPOINT_REPORT" end
EmberRoutesProbeJava.checkpointMode = function() return "FOLLOW" end
EmberRoutesProbeJava.checkpointHasHome = function() return true end
EmberRoutesProbeJava.checkpointHomeX = function() return 2 end
EmberRoutesProbeJava.checkpointHomeY = function() return 3 end
EmberRoutesProbeJava.checkpointHomeZ = function() return 1 end

Companion.execute(actor, "follow")
local home = Companion.home.x
local craftSaveResult
Probe.afterCraftSave=function(results) craftSaveResult=results or false end
Persistence.save()
check(saves == 1 and savedIntent.mode == "FOLLOW" and savedIntent.home, "save exports follow before cancellation")
check(Companion.mode == "FOLLOW" and Companion.home.x == home, "normal save resumes follow and preserves anchor")
check(craftSaveResult and craftSaveResult[""]=="CHECKPOINT_SAVED","craft continuation receives checkpoint success only after capture completes")
Haul.execute(actor, "run")
check(Haul.busy(), "active real haul prepared")
Persistence.save()
check(saves == 2 and savedIntent.mode == "HOLD" and not Haul.busy(), "haul cancelled and saved as hold, never replayed")
local oldCleanup = Probe.cleanupHaul
Probe.cleanupHaul = function() return false end
Persistence.save()
check(saves == 2 and blocked[#blocked] == "HAUL_FIXTURE_CLEANUP_BLOCKED", "failed haul cleanup poisons old checkpoint without capturing")
check(craftSaveResult==false,"failed save explicitly disarms craft continuation")
Probe.cleanupHaul = oldCleanup
Actions.execute(actor, "prepare")
local fixture = Actions.fixtures
local foreign = fixture.bag:AddItem("PLAYER_PROPERTY")
Persistence.save()
check(saves == 2 and blocked[#blocked] == "ACTION_FIXTURE_CLEANUP_BLOCKED", "foreign contents block cleanup and checkpoint")
check(foreign:getContainer() == fixture.bag, "blocked save retains actual foreign item")
fixture.bag:Remove(foreign)
Actions.execute(actor, "cleanup")
Persistence.save()
check(saves == 3, "explicitly resolving fixture blocker permits subsequent save")
Probe.restorePending = true
currentActor = nil
Persistence.tick()
check(restores == 0 and Probe.restorePending, "auto restore waits for a real local actor")
currentActor, Probe.ready = actor, false
Persistence.tick()
check(restores == 0 and Probe.restorePending, "driver not ready cannot consume restore attempt")
Probe.ready = true
Persistence.tick()
Persistence.tick()
check(restores == 1 and not Probe.restorePending, "auto restore attempts exactly once per world start")
check(Companion.mode == "FOLLOW" and Companion.home.x == 2 and Companion.home.z == 1, "native restored scalar metadata reinstates home and intent")
restoreResult, Probe.restorePending = "RESTORE_TILE_UNAVAILABLE", true
Persistence.tick()
Persistence.tick()
check(restores == 2 and not Probe.restorePending, "unloaded tile is terminal for automatic attempt")
Persistence.execute(actor, "restore")
check(restores == 3, "manual retry remains available after tile failure")
local previousMode = Companion.mode
Persistence.execute(actor, "report")
check(reports == 1 and Companion.mode == previousMode, "report does not take over companion or work")
Probe.cleanupHaul = function() error("injected cleanup exception") end
Persistence.save()
check(saves == 3 and blocked[#blocked]:find("SAVE_HANDLER_FAILED"), "thrown cleanup error also poisons old checkpoint")
check(actor.speech[#actor.speech] == "IGUI_EmberRoutesProbe_SaveBlocked", "save failure is visible in game as well as log")
Probe.cleanupHaul = oldCleanup
local worldSaves, multiplayer = 0, false
function isClient() return multiplayer end
function isServer() return false end
function save(characters) assert(characters == true) worldSaves = worldSaves + 1 Persistence.save() end
Persistence.execute(actor, "saveworld")
check(worldSaves == 1 and saves == 4, "manual world save invokes vanilla boundary and OnSave capture")
multiplayer = true
Persistence.execute(actor, "saveworld")
check(worldSaves == 1, "manual save menu cannot issue MP world writes")
multiplayer = false
Haul.execute(actor, "run")
world.tick(1)
check(Haul.busy(), "haul running before save/restart regression")
Persistence.save()
check(not Haul.busy() and #Haul.fixtures == 0 and npc.actions:isEmpty(), "mid-haul save closes old job and clears its fixtures")
Haul.execute(actor, "run")
world.tick(1)
check(Haul.busy() and Haul.batch.state == "RUNNING", "new haul after save owns a fresh batch and path request")
Haul.cancel("TEST_END")
Haul.cleanup()
local priorSaves=saves
Probe.enabled=false Persistence.save()
check(saves==priorSaves,"disabled sandbox probe does not capture or poison world checkpoints")
Probe.enabled=true
print = realPrint
print("PASS " .. count .. " persistence orchestration assertions; native save/load NOT RUN")
