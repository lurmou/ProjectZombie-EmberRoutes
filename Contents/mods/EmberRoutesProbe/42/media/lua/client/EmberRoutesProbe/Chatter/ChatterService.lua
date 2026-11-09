--[[
    Ember Chatter Service
    统一口语台词仲裁与发声下发服务
    - 纯表现层，不侵入身体控制权，不写入业务持久化
    - 视距过滤 (<= 20格同楼层)、战术潜行礼仪 (闭嘴/低语)、睡眠静默
    - 个人 8 秒冷却节流，致命伤情 (Urgent) 抢占穿透
]]

local Catalog = require "EmberRoutesProbe/Chatter/ChatterCatalog"

local ChatterService = {}

local cooldowns = setmetatable({}, { __mode = "k" })
local urgentCooldowns = setmetatable({}, { __mode = "k" })
local edgeCache = setmetatable({}, { __mode = "k" })

local function nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getTimeInMillis then return getTimeInMillis() end
    if os and os.time then return os.time() * 1000 end
    return 0
end

local function nearbyPlayer(actor)
    if not actor then return false end
    if actor.isDead and actor:isDead() then return false end

    local player = getSpecificPlayer and getSpecificPlayer(0) or (getPlayer and getPlayer())
    if not player then return false end
    if player.isDead and player:isDead() then return false end

    -- 同楼层检查
    local actorZ = actor.getZ and actor:getZ() or 0
    local playerZ = player.getZ and player:getZ() or 0
    if math.floor(actorZ) ~= math.floor(playerZ) then return false end

    -- 20 格视距判定 (400 平方格)
    local ax, ay = actor.getX and actor:getX() or 0, actor.getY and actor:getY() or 0
    local px, py = player.getX and player:getX() or 0, player.getY and player:getY() or 0
    local dx, dy = ax - px, ay - py
    if (dx * dx + dy * dy) > 400 then return false end

    return true, player
end

local function isAsleep(actor)
    return actor and actor.isAsleep and actor:isAsleep() == true
end

local function isSneaking(player)
    return player and player.isSneaking and player:isSneaking() == true
end

function ChatterService.canSpeak(actor, eventKey, isUrgent)
    local ok, player = nearbyPlayer(actor)
    if not ok then return false end

    -- 睡眠静默 (即使是流血，睡觉时也无法清晰呼救)
    if isAsleep(actor) then return false end

    -- 战术潜行礼仪：领队潜行时日常台词完全闭嘴，紧急呼救降级为 5 格低语
    local whisper = false
    if isSneaking(player) then
        if not isUrgent then return false end
        whisper = true
    end

    local now = nowMs()
    if isUrgent then
        -- 紧急求救绕过常规冷却，但享有同事件 4 秒防刷屏保护
        local byEvent = urgentCooldowns[actor]
        if byEvent and (byEvent[eventKey] or 0) > now then return false end
    else
        -- 常规台词享有单人 8 秒全局冷却
        if (cooldowns[actor] or 0) > now then return false end
    end

    return true, whisper
end

function ChatterService.speak(actor, eventKey, opts)
    opts = opts or {}
    local entry = Catalog.getEntry(eventKey)
    if not entry then return false end

    local isUrgent = opts.urgent == true or entry.urgent == true
    local can, whisper = ChatterService.canSpeak(actor, eventKey, isUrgent)
    if not can then return false end

    local line, r, g, b, font = Catalog.get(eventKey, opts.context)
    if not line or line == "" then return false end

    local distance = (opts.whisper or whisper) and 5.0 or 20.0

    -- 原生下发：优先调用 PZ v42 原生 7 参数带色签名，降级兼容单参数
    if actor.Say then
        local ok = pcall(function()
            actor:Say(line, r, g, b, font, distance, "")
        end)
        if not ok then
            pcall(function() actor:Say(line) end)
        end
    end

    -- 更新冷却
    local now = nowMs()
    cooldowns[actor] = now + 8000
    if isUrgent then
        local byEvent = urgentCooldowns[actor] or {}
        byEvent[eventKey] = now + 4000
        urgentCooldowns[actor] = byEvent
    end

    return true, line
end

function ChatterService.onActionResult(actor, result)
    if not actor or not result then return false end
    if result == "INJURED" then
        return ChatterService.speak(actor, "WORK_INJURED", { urgent = true })
    elseif result == "STORAGE_FULL" or result == "FULL" then
        return ChatterService.speak(actor, "WORK_STORAGE_FULL")
    elseif result == "NO_TOOL" or result == "TOOL_MISSING" then
        return ChatterService.speak(actor, "WORK_NO_TOOL")
    end
    return false
end

function ChatterService.observeHealth(actor, facts)
    if not actor or not facts then return false end
    local prev = edgeCache[actor]
    if not prev then
        edgeCache[actor] = {
            bleeding = facts.bleeding == true,
            deep = facts.deep == true,
            replace = facts.replace == true,
        }
        if facts.bleeding then
            ChatterService.speak(actor, "HEALTH_BLEEDING", { urgent = true })
        end
        return true
    end

    if facts.bleeding and not prev.bleeding then
        ChatterService.speak(actor, "HEALTH_BLEEDING", { urgent = true })
    elseif facts.deep and not prev.deep then
        ChatterService.speak(actor, "HEALTH_DEEP_WOUND", { urgent = true })
    elseif facts.replace and not prev.replace then
        ChatterService.speak(actor, "HEALTH_DIRTY_BANDAGE")
    end

    prev.bleeding = facts.bleeding == true
    prev.deep = facts.deep == true
    prev.replace = facts.replace == true
    return true
end

function ChatterService.purge(actor)
    if not actor then return end
    cooldowns[actor] = nil
    urgentCooldowns[actor] = nil
    edgeCache[actor] = nil
end

-- 供单元测试检视内部状态
function ChatterService._inspect(actor)
    return {
        cooldown = cooldowns[actor],
        urgentCooldown = urgentCooldowns[actor],
        edge = edgeCache[actor],
    }
end

return ChatterService
