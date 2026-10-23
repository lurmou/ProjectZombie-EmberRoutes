local Probe = require "EmberRoutesProbe/Boot"
local Log = require "EmberRoutesProbe/Log"
local Companion = require "EmberRoutesProbe/Companion"
local Actions = require "EmberRoutesProbe/Actions"
local Samples = require "EmberRoutesProbe/PersistenceSamples"
local Diagnostic=require 'EmberRoutesProbe/TaskDiagnostic'
local Persistence = {}
local restoreQueue
local legacyStockResume
local function managed() return require 'EmberRoutesProbe/TaskPersistence' end
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

function Persistence.restore(actor,id)
    if not Probe.ready or not Probe.hasJava() then return Probe.unavailableCode() end
    if Probe.controlledExecution==true then
        return managed().restore(actor,id or EmberRoutesProbeJava.selectedId())
    end
    local result = EmberRoutesProbeJava.restoreCheckpoint(actor)
    if string.find(result, "^CHECKPOINT_RESTORED") then restoredOrder(actor) end
    return result
end

function Persistence.tick()
    if not Probe.ready or not Probe.hasJava() then return end
    local actor=getSpecificPlayer(0)
    if not actor or actor:isDead() or not actor:getCurrentSquare() then return end
    if Probe.controlledExecution==true then
        local ok,why=pcall(managed().tick,actor)
        if not ok then managed().failed('LIVE_RECOVERY_ERROR '..tostring(why)) end
    elseif legacyStockResume then
        legacyStockResume=nil
        if Probe.afterStockSave then Probe.afterStockSave() end
    end
    if Probe.restorePending then
        Probe.restorePending=false restoreQueue={ids=ids(),position=1}
    end
    if not restoreQueue then return end
    local id=restoreQueue.ids[restoreQueue.position]
    if not id then restoreQueue=nil return end
    restoreQueue.position=restoreQueue.position+1
    local result
    if Probe.controlledExecution==true then result=Persistence.restore(actor,id)
    else
        local selected=EmberRoutesProbeJava.selectedId and EmberRoutesProbeJava.selectedId()
        if EmberRoutesProbeJava.selectCarrier then EmberRoutesProbeJava.selectCarrier(id) end
        result=Persistence.restore(actor)
        if selected and selected~="" then EmberRoutesProbeJava.selectCarrier(selected) end
    end
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
    legacyStockResume=nil
    if Probe.beforeStockSave then Probe.beforeStockSave() end
    local capture=Probe.controlledExecution==true and managed().capture or captureOnSave
    local ok, result = pcall(capture)
    if not ok then
        Log.write("PERSISTENCE", "SAVE_HANDLER_FAILED " .. tostring(result))
        if Probe.controlledExecution==true then result=managed().failed('SAVE_HANDLER_FAILED '..tostring(result))
        else result = block("SAVE_HANDLER_FAILED " .. tostring(result)) end
    end
    if string.find(result, "^CHECKPOINT_BLOCKED") then
        local actor = getSpecificPlayer(0)
        if actor and not actor:isDead() then actor:Say(getText("IGUI_EmberRoutesProbe_SaveBlocked")) end
    end
    if not string.find(result,"^CHECKPOINT_SAVED") and Probe.afterCraftSave then Probe.afterCraftSave(nil) end
    if Probe.controlledExecution~=true and string.find(result,'^CHECKPOINT_SAVED') then legacyStockResume=true end
    return result
end

function Persistence.prepare()
    if Probe.controlledExecution==true then return managed().prepare() end
    if Probe.beforeStockSave then Probe.beforeStockSave() end
    return true
end

local function sampleRequest(actor,command)
    return Diagnostic.submit(actor,'PERSISTENCE_SAMPLE',{
        assets=command~='recover',recovery=command=='clearsample',
        validate=function()
            return not Actions.isBusy() and (not Probe.haulBusy or not Probe.haulBusy())
        end,
        start=function(c)
            if (Probe.cleanupHaul and not Probe.cleanupHaul(c.npc,c.body)) or not Actions.cleanupForHaul(c.npc,c.body) then
                return false,'CLEANUP_BLOCKED'
            end
            if not c.body.stop() then return false,'CONTROL_REQUIRED' end
            local fn=command=='sample' and Samples.prepare or Samples.cleanup
            if command=='recover' then fn=Samples.recover end
            c.result=fn(c.npc,c.binding.id)
            c.recovered=c.result=='SAMPLE_CLEANED' or (command=='clearsample' and c.result=='SAMPLE_ABSENT_OR_STALE'
                and not c.npc:getModData().EmberRoutesPersistenceSample)
            return c.result=='SAMPLE_PREPARED' or c.result=='SAMPLE_EXISTS' or c.result=='TEST_HEALTH_RESTORED' or c.recovered,c.result
        end,
        tick=function() end,finished=function() return true end,pause=function() end,
        evidence=function(c)
            local evidence=Samples.evidence(c.npc,c.binding.id)
            local Haul=require 'EmberRoutesProbe/Haul'
            for _,module in ipairs({Actions,Haul}) do
                if module.fixtureEvidence then
                    local other=module.fixtureEvidence(c.npc)
                    for _,id in ipairs(other.ids) do evidence.ids[#evidence.ids+1]=id end
                    if other.effects~='KNOWN' then evidence.effects='UNKNOWN' end
                end
            end
            return evidence
        end})
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
            local ok,reason=Persistence.prepare()
            if not ok then result=reason
            else
                local saved,err=pcall(nativeSave,true)
                if saved then result = "WORLD_SAVE_REQUESTED"
                else
                    legacyStockResume=nil
                    if Probe.controlledExecution==true then managed().failed('NATIVE_SAVE_FAILED '..tostring(err)) end
                    result='WORLD_SAVE_FAILED'
                    Log.write('PERSISTENCE','NATIVE_SAVE_FAILED '..tostring(err))
                end
            end
        end
    elseif command == "sample" or command == "checksample" or command == "clearsample" or command == "recover" then
        if Probe.controlledExecution==true and command~='checksample' then
            result=sampleRequest(actor,command)
        else
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
        end
    else return end
    actor:Say(getText("IGUI_EmberRoutesProbe_PersistenceResult") .. " " .. tostring(result))
    return result
end

Probe.tickPersistence, Probe.savePersistentCarrier = Persistence.tick, Persistence.save
Probe.prepareTaskRecovery=function()
    if Probe.controlledExecution==true then managed().load()
    elseif Probe.resetStock then Probe.resetStock() end
end
Probe.resetPersistence=function()
    restoreQueue=nil legacyStockResume=nil
    if Probe.controlledExecution==true then managed().reset() end
    if Probe.resetStock then Probe.resetStock() end
end
return Persistence
