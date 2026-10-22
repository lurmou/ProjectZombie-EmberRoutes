local Probe = require "EmberRoutesProbe/Boot"
local Log = require "EmberRoutesProbe/Log"
local Companion = require "EmberRoutesProbe/Companion"
local Actions = require "EmberRoutesProbe/Actions"
local Samples = require "EmberRoutesProbe/PersistenceSamples"
local Persistence = {}
local restoreQueue
local function ids()
    local result={}
    if EmberRoutesProbeJava.workerCount then
        for i=0,EmberRoutesProbeJava.workerCount()-1 do result[#result+1]=EmberRoutesProbeJava.workerIdAt(i) end
    else result[1]="" end
    return result
end
local function block(reason)
    if EmberRoutesProbeJava.blockAllCheckpoints then return EmberRoutesProbeJava.blockAllCheckpoints(reason) end
    return EmberRoutesProbeJava.blockCheckpoint(reason)
end

local function restoredOrder(actor)
    return Companion.restoreState(actor, {
        id = EmberRoutesProbeJava.selectedId and EmberRoutesProbeJava.selectedId() or nil,
        mode = EmberRoutesProbeJava.checkpointMode(), hasHome = EmberRoutesProbeJava.checkpointHasHome(),
        homeX = EmberRoutesProbeJava.checkpointHomeX(), homeY = EmberRoutesProbeJava.checkpointHomeY(),
        homeZ = EmberRoutesProbeJava.checkpointHomeZ(),
    })
end

function Persistence.restore(actor)
    if not Probe.ready or not Probe.hasJava() then return Probe.unavailableCode() end
    local result = EmberRoutesProbeJava.restoreCheckpoint(actor)
    if string.find(result, "^CHECKPOINT_RESTORED") then restoredOrder(actor) end
    return result
end

function Persistence.tick()
    if not Probe.ready or not Probe.hasJava() then return end
    local actor=getSpecificPlayer(0)
    if not actor or actor:isDead() or not actor:getCurrentSquare() then return end
    if Probe.restorePending then
        Probe.restorePending=false restoreQueue={ids=ids(),position=1}
    end
    if not restoreQueue then return end
    local id=restoreQueue.ids[restoreQueue.position]
    if not id then restoreQueue=nil return end
    restoreQueue.position=restoreQueue.position+1
    local selected=EmberRoutesProbeJava.selectedId and EmberRoutesProbeJava.selectedId()
    if EmberRoutesProbeJava.selectCarrier then EmberRoutesProbeJava.selectCarrier(id) end
    local result=Persistence.restore(actor)
    if selected and selected~="" then EmberRoutesProbeJava.selectCarrier(selected) end
    Log.write("PERSISTENCE","AUTO npc="..id.." "..tostring(result))
end

local function captureOnSave()
    local all,intents=ids(),{}
    for _,id in ipairs(all) do
        local intent=Companion.exportState(id~="" and id or nil)
        intent.id=intent.id or (id~="" and id or nil) intents[id]=intent
    end
    if Probe.cancelEvery then Probe.cancelEvery("SAVE")
    else
        if Probe.pauseAllWork then Probe.pauseAllWork("SAVE") end
        if Probe.cancelEveryCompanion then Probe.cancelEveryCompanion("SAVE") end
        Probe.cancelAll("SAVE")
    end
    if Probe.cleanupHaul and not Probe.cleanupHaul() then return block("HAUL_FIXTURE_CLEANUP_BLOCKED") end
    if not Actions.cleanupForHaul() then return block("ACTION_FIXTURE_CLEANUP_BLOCKED") end
    local results={}
    for _,id in ipairs(all) do
        local intent=intents[id]
        local result
        if EmberRoutesProbeJava.saveCheckpointFor then
            result=EmberRoutesProbeJava.saveCheckpointFor(id,intent.mode,intent.hasHome,
                intent.homeX or 0,intent.homeY or 0,intent.homeZ or 0)
        else result=EmberRoutesProbeJava.saveCheckpoint(intent.mode,intent.hasHome,
            intent.homeX or 0,intent.homeY or 0,intent.homeZ or 0) end
        Log.write("PERSISTENCE","SAVE npc="..id.." "..result)
        if not string.find(result,"^CHECKPOINT_") or string.find(result,"^CHECKPOINT_BLOCKED") then
            return block("WORKER_SAVE_FAILED "..id.." "..result)
        end
        results[id]=result
    end
    local actor=getSpecificPlayer(0)
    if actor and not actor:isDead() then
        for _,id in ipairs(all) do
            if string.find(results[id],"^CHECKPOINT_SAVED") then Companion.restoreState(actor,intents[id]) end
        end
    end
    if Probe.afterCraftSave then Probe.afterCraftSave(results) end
    return "CHECKPOINT_SAVED "..#all
end

function Persistence.save()
    if Probe.enabled==false or not Probe.ready or not Probe.hasJava() then return end
    -- OnSave cannot cancel the engine's world-file write. A failed handler must
    -- poison the older NPC record explicitly, not leave it available for replay.
    local ok, result = pcall(captureOnSave)
    if not ok then
        Log.write("PERSISTENCE", "SAVE_HANDLER_FAILED " .. tostring(result))
        result = block("SAVE_HANDLER_FAILED " .. tostring(result))
    end
    if string.find(result, "^CHECKPOINT_BLOCKED") then
        local actor = getSpecificPlayer(0)
        if actor and not actor:isDead() then actor:Say(getText("IGUI_EmberRoutesProbe_SaveBlocked")) end
    end
    if not string.find(result,"^CHECKPOINT_SAVED") and Probe.afterCraftSave then Probe.afterCraftSave(nil) end
end

function Persistence.execute(actor, command)
    if not Probe.ready or not Probe.hasJava() then actor:Say(Probe.unavailableMessage()) return end
    local result
    if command == "restore" then
        Probe.restorePending = false
        restoreQueue=nil
        result = Persistence.restore(actor)
    elseif command == "report" then result = EmberRoutesProbeJava.reportCheckpoint()
    elseif command == "saveworld" then
        local nativeSave = _G.save
        if isClient() or isServer() then result = "DRIVER_UNAVAILABLE"
        elseif type(nativeSave) ~= "function" then result = "SAVE_API_UNAVAILABLE"
        else
            nativeSave(true) -- Vanilla ISSleepDialog / ISWorldObjectContextMenu SP save path.
            result = "WORLD_SAVE_REQUESTED" -- The engine owns disk completion/error reporting.
        end
    elseif command == "sample" or command == "checksample" or command == "clearsample" or command == "recover" then
        local npc = EmberRoutesProbeJava.controlledCarrier(actor)
        if not npc then result = "CARRIER_UNAVAILABLE"
        elseif command == "checksample" then
            result = Samples.check(npc, EmberRoutesProbeJava.carrierId(npc))
        else
            Probe.cancelAll("PERSISTENCE_SAMPLE")
            if (Probe.cleanupHaul and not Probe.cleanupHaul(npc)) or not Actions.cleanupForHaul(npc) then
                result = "CLEANUP_BLOCKED"
            else
                EmberRoutesProbeJava.stopCarrier(npc)
                local fn = command == "sample" and Samples.prepare or Samples.cleanup
                if command == "recover" then fn = Samples.recover end
                -- Optional fixture boundary only; retain partial sample ownership on failure.
                local ok, answer = pcall(fn, npc, EmberRoutesProbeJava.carrierId(npc))
                result = ok and answer or "SAMPLE_ERROR_RETAINED"
                if not ok then Log.write("PERSISTENCE_SAMPLE", tostring(answer)) end
            end
        end
    else return end
    actor:Say(getText("IGUI_EmberRoutesProbe_PersistenceResult") .. " " .. tostring(result))
end

Probe.tickPersistence, Probe.savePersistentCarrier = Persistence.tick, Persistence.save
Probe.resetPersistence=function() restoreQueue=nil end
return Persistence
