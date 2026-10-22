local Probe = require "EmberRoutesProbe/Boot"
local Log = require "EmberRoutesProbe/Log"
local Driver = require "EmberRoutesProbe/Driver"
local Policy = require "EmberRoutesProbe/FollowPolicy"
local Factory={}
function Factory.new()
local Companion = { mode = "HOLD", reason = "IDLE", binding = nil, home = nil, policy = nil, nextHomePoll = 0, nextMaintenance = 0 }
local function log(message) Log.write("COMPANION", message) end

local function setMode(mode, reason)
    if Companion.mode ~= mode or Companion.reason ~= reason then
        log("STATE mode=" .. mode .. " reason=" .. reason .. " npc=" .. (Companion.binding and Companion.binding.id or "absent"))
    end
    Companion.mode, Companion.reason = mode, reason
end

function Companion.cancel(reason)
    local wasActive = Companion.mode == "FOLLOW" or Companion.mode == "RETURNING"
    Companion.policy = nil
    setMode("HOLD", reason or "USER")
    if wasActive then Driver.stop(Companion.binding) end
end

local function setBinding(binding)
    if not Companion.binding or Companion.binding.id ~= binding.id then
        Companion.home = nil
        Companion.binding = binding
    end
end

local function captureHome()
    local binding = Companion.binding
    local snapshot = Driver.snapshot(binding, Companion.actor)
    if not binding or not snapshot then return false end
    Companion.home = { id = binding.id .. "/home", npcId = binding.id,
        x = snapshot.x, y = snapshot.y, z = math.floor(snapshot.z + 0.001) }
    log("HOME_SET id=" .. Companion.home.id .. " pos=" .. Companion.home.x .. "," .. Companion.home.y .. "," .. Companion.home.z)
    return true
end

function Companion.exportState()
    local binding = Companion.binding
    local data = { mode = "HOLD", hasHome = false }
    if not binding or not Driver.valid(binding) then return data end
    data.id = binding.id
    if Companion.mode == "FOLLOW" or Companion.mode == "RETURNING" then data.mode = Companion.mode end
    local home = Companion.home
    if home and home.npcId == binding.id then
        data.hasHome, data.homeX, data.homeY, data.homeZ = true, home.x, home.y, home.z
    end
    return data
end

-- Only scalar intent is restored. Native action/path queues are always rebuilt.
function Companion.restoreState(actor, data)
    local binding = Companion.binding
    if not binding or not Driver.valid(binding) then binding = data.id and Driver.bindId(actor,data.id) or Driver.bind(actor) end
    if not binding or (data.id and data.id ~= binding.id) then
        log("ORDER_RESTORE_BLOCKED stale/missing carrier")
        return false
    end
    Driver.stop(binding)
    setBinding(binding)
    Companion.actor = actor
    Companion.policy = nil
    if data.hasHome then
        Companion.home = { id = binding.id .. "/home", npcId = binding.id,
            x = data.homeX, y = data.homeY, z = data.homeZ }
    else Companion.home = nil end
    setMode("HOLD", "RESTORED")
    if data.mode == "FOLLOW" then
        Companion.policy = Policy.new()
        setMode("FOLLOW", "RESTORED")
    elseif data.mode == "RETURNING" and Companion.home then
        local result = Driver.move(binding, actor, Companion.home)
        if string.find(result, "^MOVE_REQUESTED") then
            Companion.nextHomePoll = 0
            setMode("RETURNING", "RESTORED")
        else setMode("BLOCKED", "RESTORED_" .. result) end
    end
    return true
end

function Companion.report()
    local caps = Driver.capabilities()
    local snapshot = Driver.snapshot(Companion.binding, Companion.actor)
    log("REPORT mode=" .. Companion.mode .. " reason=" .. Companion.reason .. " driver=" .. caps.mode
        .. " npc=" .. (Companion.binding and Companion.binding.id or "absent")
        .. " home=" .. (Companion.home and Companion.home.id or "unset")
        .. " motion=" .. (snapshot and snapshot.motion or "UNAVAILABLE")
        .. " failures=" .. (Companion.policy and Companion.policy.failures or 0))
    return Companion.mode
end

local function execute(actor, command)
    if command == "status" then return Companion.report() end
    if not Probe.ready or not Probe.hasJava() then return Probe.unavailableCode() end
    if command ~= "follow" and command ~= "hold" and command ~= "sethome" and command ~= "home" then return "INVALID_COMMAND" end
    local binding = Driver.bind(actor)
    if not binding then return "CARRIER_UNAVAILABLE" end
    setBinding(binding)
    Companion.actor = actor
    if command == "home" and not Companion.home then return "HOME_NOT_SET" end
    Probe.cancelAll("COMPANION_ORDER",binding.id)
    Driver.stop(binding)
    if command == "hold" then setMode("HOLD", "USER") return "HOLD" end
    if command == "sethome" then
        if not captureHome() then return "CARRIER_UNAVAILABLE" end
        setMode("HOLD", "HOME_SET")
        return "HOME_SET"
    end
    if command == "follow" then
        if not Companion.home and not captureHome() then return "CARRIER_UNAVAILABLE" end
        Companion.policy = Policy.new()
        setMode("FOLLOW", "USER")
        return "FOLLOW"
    end
    local home = Companion.home
    if not home or home.npcId ~= binding.id then return "STALE_HOME" end
    local result = Driver.move(binding, actor, home)
    if not string.find(result, "^MOVE_REQUESTED") then setMode("BLOCKED", result) return result end
    Companion.nextHomePoll = 0
    setMode("RETURNING", "USER")
    return "RETURNING"
end

function Companion.execute(actor, command)
    local ok, result = pcall(execute, actor, command)
    if not ok then Companion.cancel("ERROR") log("ERROR " .. tostring(result)) result = "ERROR" end
    actor:Say(getText("IGUI_EmberRoutesProbe_CompanionResult") .. " " .. tostring(result))
end

function Companion.tick()
    local time = getTimestampMs()
    if Companion.mode ~= "FOLLOW" and Companion.mode ~= "RETURNING" then
        if time >= Companion.nextMaintenance then
            Companion.nextMaintenance = time + 1000
            if Companion.binding and not Driver.valid(Companion.binding) then
                Companion.binding, Companion.home, Companion.actor = nil, nil, nil
                setMode("HOLD", "CARRIER_REMOVED")
            end
        end
        return
    end
    local sample = Driver.snapshot(Companion.binding, Companion.actor)
    if not Probe.ready or not sample then
        Companion.cancel("LEADER_OR_CARRIER_UNAVAILABLE")
        return
    end
    if Companion.mode == "RETURNING" then
        if time < Companion.nextHomePoll then return end
        Companion.nextHomePoll = time + 500
        if sample.motion == "MOVING" then return end
        if sample.motion == "REACHED" then setMode("HOLD", "HOME_REACHED")
        else setMode("BLOCKED", "HOME_" .. sample.motion) Driver.stop(Companion.binding) end
        return
    end
    local policy = Companion.policy
    if not policy then Companion.cancel("POLICY_UNAVAILABLE") return end
    local intent, data = policy:tick(sample, time)
    if intent == "BLOCK" then
        setMode("BLOCKED", data)
        Driver.stop(Companion.binding)
    elseif intent == "STOP" then Driver.stop(Companion.binding)
    elseif intent == "MOVE" then
        local result = Driver.move(Companion.binding, Companion.actor, data)
        if string.find(result, "^MOVE_REQUESTED") then policy:accepted(sample, time)
        else
            log("MOVE_REFUSED " .. result)
            if policy:rejected(time) then setMode("BLOCKED", "REQUEST_FAILURE_LIMIT") Driver.stop(Companion.binding) end
        end
    end
end

function Companion.reset()
    Companion.cancel("WORLD_RESET")
    Companion.binding,Companion.home,Companion.actor=nil,nil,nil
end
return Companion
end
return Factory
