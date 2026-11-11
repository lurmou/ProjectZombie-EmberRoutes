local Probe = require "EmberRoutesProbe/Kernel/Boot"
local Log = require "EmberRoutesProbe/Kernel/Log"
local Driver = require "EmberRoutesProbe/Runtime/Driver"
local Clock = require "EmberRoutesProbe/Kernel/Clock"
local liveMotion={FOLLOW_ACTIVE=true,FOLLOW_WAITING=true,FOLLOW_WAIT_VEHICLE=true,
    FOLLOW_TRAVERSAL=true,FOLLOW_QUEUED=true,FOLLOW_YIELD_SIDE=true,FOLLOW_YIELD_BACK=true,
    FOLLOW_TIMEOUT=true,FOLLOW_PATH_FAILED=true}
local Factory={}
function Factory.new()
local Companion = { mode = "HOLD", reason = "IDLE", binding = nil, home = nil, nextPoll = 0, nextMaintenance = 0 }
local function log(message) Log.write("COMPANION", message) end

local function setMode(mode, reason)
    Companion.intentRevision=(Companion.intentRevision or 0)+1
    if Companion.mode ~= mode or Companion.reason ~= reason then
        log("STATE mode=" .. mode .. " reason=" .. reason .. " npc=" .. (Companion.binding and Companion.binding.id or "absent"))
    end
    Companion.mode, Companion.reason = mode, reason
end
local function startFollow(actor,body)
    local slot,why=require('EmberRoutesProbe/Settlement/MembershipService').followSlot(
        Companion.binding.id,actor,Companion.membershipRevision)
    if slot==nil then setMode('BLOCKED',why) return false,why end
    local ok,result=body.follow(actor,slot)
    if not ok or result~='FOLLOW_STARTED' then setMode('BLOCKED',result) return false,result end
    Companion.failedFollow=nil Companion.nextPoll=0
    return true
end

function Companion.cancel(reason)
    local wasActive = Companion.mode == "FOLLOW" or Companion.mode == "RETURNING"
    setMode("HOLD", reason or "USER")
    if wasActive and Companion.body then Companion.body.stop() end
end

local function setBinding(binding)
    if not Companion.binding or Companion.binding.id ~= binding.id then
        Companion.home = nil
    end
    Companion.binding = binding
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
    data.jobId = Companion.jobId
    if Companion.mode == "FOLLOW" or Companion.mode == "RETURNING" then data.mode = Companion.mode end
    local home = Companion.home
    if home and home.npcId == binding.id then
        data.hasHome, data.homeX, data.homeY, data.homeZ = true, home.x, home.y, home.z
    end
    return data
end

-- Only scalar intent is restored. Native action/path queues are always rebuilt.
function Companion.restoreState(actor, data,body)
    if not body then return false,'CONTROL_REQUIRED' end
    local binding = Companion.binding
    if not binding or not Driver.valid(binding) then binding = data.id and Driver.bindId(actor,data.id) or Driver.bind(actor) end
    if not binding or (data.id and data.id ~= binding.id) then
        log("ORDER_RESTORE_BLOCKED stale/missing carrier")
        return false
    end
    Companion.body=body
    Driver.stop(binding,body)
    setBinding(binding)
    Companion.actor = actor
    if data.hasHome then
        Companion.home = { id = binding.id .. "/home", npcId = binding.id,
            x = data.homeX, y = data.homeY, z = data.homeZ }
    else Companion.home = nil end
    setMode("HOLD", "RESTORED")
    if data.mode == "FOLLOW" then
        local ok,why=startFollow(actor,body)
        if not ok then return false,why end
        setMode("FOLLOW", "RESTORED")
    elseif data.mode == "RETURNING" and Companion.home then
        local result = Driver.move(binding, actor, Companion.home,Companion.body)
        if string.find(result, "^MOVE_REQUESTED") then
            Companion.nextPoll = 0
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
        .. " motion=" .. (snapshot and snapshot.motion or "UNAVAILABLE"))
    local metrics=EmberRoutesProbeJava.followMetrics()
    if metrics then
        log('METRICS segments='..tostring(metrics.segmentSubmissions)..' activeSeconds='..tostring(metrics.activeSeconds)
            ..' blockedRatio='..tostring(metrics.blockedRatio)..' queueWaitSeconds='..tostring(metrics.queueWaitSeconds)
            ..' searchWaitSeconds='..tostring(metrics.searchWaitSeconds))
    end
    return Companion.mode
end

function Companion.stopAdapter(controller,ticket,persistIntent,jobId)
    local binding=Companion.binding
    if not binding or not Driver.valid(binding) or type(persistIntent)~='function'
        or type(jobId)~='string' or jobId=='' then return nil,'INTENT_STORE_REQUIRED' end
    local revision=Companion.intentRevision
    local intent=Companion.exportState()
    return require('EmberRoutesProbe/Runtime/TaskBusinessStop').new({controller=controller,ticket=ticket,npc=binding.handle,npcId=binding.id,jobId=jobId,
        same=function(paused)
            return Companion.binding==binding and Driver.valid(binding) and Companion.intentRevision==revision
                and (not paused or Companion.mode=='HOLD')
        end,
        pause=function(reason) Companion.cancel(reason) revision=Companion.intentRevision return Companion.mode=='HOLD' end,
        effects=function() return 'KNOWN' end,
        persist=function(fact) return persistIntent(intent,fact)==true end})
end

local function execute(actor, command,body,requestedBinding)
    if command == "status" then return Companion.report() end
    if not Probe.ready or not Probe.hasJava() then return Probe.unavailableCode() end
    if not body then return 'CONTROL_REQUIRED' end
    if command ~= "follow" and command ~= "hold" and command ~= "sethome" and command ~= "home" then return "INVALID_COMMAND" end
    local binding = requestedBinding or Driver.bind(actor)
    if not binding then return "CARRIER_UNAVAILABLE" end
    setBinding(binding)
    Companion.actor = actor
    if command == "home" and not Companion.home then return "HOME_NOT_SET" end
    Companion.body=body
    Driver.stop(binding,body)
    if command == "hold" then setMode("HOLD", "USER") return "HOLD" end
    if command == "sethome" then
        if not captureHome() then return "CARRIER_UNAVAILABLE" end
        setMode("HOLD", "HOME_SET")
        return "HOME_SET"
    end
    if command == "follow" then
        if not Companion.home and not captureHome() then return "CARRIER_UNAVAILABLE" end
        local ok,why=startFollow(actor,body)
        if not ok then return why end
        setMode("FOLLOW", "USER")
        return "FOLLOW"
    end
    local home = Companion.home
    if not home or home.npcId ~= binding.id then return "STALE_HOME" end
    local result = Driver.move(binding, actor, home,Companion.body)
    if not string.find(result, "^MOVE_REQUESTED") then setMode("BLOCKED", result) return result end
    Companion.nextPoll = 0
    setMode("RETURNING", "USER")
    return "RETURNING"
end

function Companion.execute(actor, command,body,binding)
    local ok, result = pcall(execute, actor, command,body,binding)
    if not ok then Companion.cancel("ERROR") log("ERROR " .. tostring(result)) result = "ERROR" end
    log('COMMAND_RESULT '..tostring(result))
    return result
end

function Companion.tick()
    if Companion.body and not Companion.body.current() then return end
    local time = Clock.nowMs()
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
    if time<Companion.nextPoll then return end
    Companion.nextPoll=time+250
    local actor=Companion.actor
    if not Probe.ready or not actor or actor:isDead() or not Driver.valid(Companion.binding) then
        Companion.cancel("LEADER_OR_CARRIER_UNAVAILABLE")
        return
    end
    if Companion.mode == "RETURNING" then
        local motion=EmberRoutesProbeJava.motionResult(Companion.binding.handle)
        if motion == "MOVING" then return end
        -- Parked carrier: hold the return instead of declaring a blocked home.
        if require('EmberRoutesProbe/Runtime/Driver').suspended(Companion.binding.handle) then return end
        if motion == "REACHED" then setMode("HOLD", "HOME_REACHED")
        else setMode("BLOCKED", "HOME_" .. motion) Companion.body.stop() end
        return
    end
    local motion=EmberRoutesProbeJava.motionResult(Companion.binding.handle)
    if require('EmberRoutesProbe/Runtime/Driver').suspended(Companion.binding.handle) then return end
    if not liveMotion[motion] then
        -- A failed route is retried when the leader moves or a new macro
        -- command arrives, not on every MembershipRuntime retry window.
        Companion.failedFollow={reason=motion,revision=Companion.membershipRevision,
            x=actor:getX(),y=actor:getY(),z=actor:getZ()}
        Companion.body.stop()
        setMode('BLOCKED',motion)
    end
end

function Companion.reset()
    Companion.cancel("WORLD_RESET")
    Companion.binding,Companion.home,Companion.actor,Companion.body,Companion.jobId=nil,nil,nil,nil,nil
    Companion.failedFollow=nil
end
return Companion
end
return Factory
