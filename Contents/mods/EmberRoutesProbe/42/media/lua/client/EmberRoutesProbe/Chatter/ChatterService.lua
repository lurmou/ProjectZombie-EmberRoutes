--[[
    Ember Chatter Service
    统一口语台词仲裁与发声下发服务
    - 纯表现层，不侵入身体控制权，不写入业务持久化
    - 视距过滤 (<= 30格同楼层，与原生 Say 默认半径 30.0 一致)、战术潜行礼仪 (闭嘴/低语)、睡眠静默
    - 个人 8 秒冷却节流，致命伤情 (Urgent) 抢占穿透
]]

local Catalog = require "EmberRoutesProbe/Chatter/ChatterCatalog"
local Clock = require 'EmberRoutesProbe/Kernel/Clock'
local EventBus = require 'EmberRoutesProbe/Kernel/EventBus'

local ChatterService = {}

local cooldowns = setmetatable({}, { __mode = "k" })
local urgentCooldowns = setmetatable({}, { __mode = "k" })
local edgeCache = setmetatable({}, { __mode = "k" })
local needEdge = setmetatable({}, { __mode = "k" })

local function nowMs()
    if Clock.hasEngineClock() then return Clock.nowMs() end
    if getTimeInMillis then return getTimeInMillis() end
    if os and os.time then return Clock.wallSeconds() * 1000 end
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

    -- 30 格视距判定 (900 平方格)，与原生 IsoGameCharacter.Say 默认半径 30.0 一致
    local ax, ay = actor.getX and actor:getX() or 0, actor.getY and actor:getY() or 0
    local px, py = player.getX and player:getX() or 0, player.getY and player:getY() or 0
    local dx, dy = ax - px, ay - py
    if (dx * dx + dy * dy) > 900 then return false end

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

    -- 战术潜行礼仪：领队潜行时日常台词完全闭嘴，紧急呼救降级为 10 格低语
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

    -- 原生半径：Say 30.0 / SayWhisper 10.0（javap IsoGameCharacter）
    local distance = (opts.whisper or whisper) and 10.0 or 30.0

    -- 原生下发：7 参数带色签名失败时改用单参数签名；两者都失败必须如实上报
    local delivered = false
    if actor.Say then
        local ok = pcall(function()
            actor:Say(line, r, g, b, font, distance, "")
        end)
        if ok then
            delivered = true
        else
            delivered = pcall(function() actor:Say(line) end)
        end
    end
    if not delivered then return false end

    -- 仅在成功下发后更新冷却
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

-- 消费自护策略的已决结果：阈值只存在于 NeedsPolicy，此处不复制数值。
-- 纯表现层：不改 sample、不写业务状态、不参与自护派工。
function ChatterService.observeNeeds(actor, sample)
    if not actor or type(sample) ~= 'table' then return false end
    -- UNKNOWN / 近期受伤 / 采样不可用都不是「可安全说话」的证据
    if sample.safe ~= true or sample.safety ~= 'SAFE' then
        needEdge[actor] = nil
        return false
    end
    local Policy = require 'EmberRoutesProbe/SelfCare/NeedsPolicy'
    local need = Policy.choose(sample, nil, { safe = true }, { EAT = true, DRINK = true })
    if need ~= 'EAT' and need ~= 'DRINK' then
        needEdge[actor] = nil
        return false
    end
    -- 边沿触发：同一需求持续期间只说一次，退回阈值以下后才重新武装
    if needEdge[actor] == need then return false end
    local spoke = ChatterService.speak(actor, need == 'EAT' and 'NEEDS_HUNGER' or 'NEEDS_THIRST')
    if spoke then needEdge[actor] = need end
    return spoke
end

function ChatterService.purge(actor)
    if not actor then return end
    cooldowns[actor] = nil
    urgentCooldowns[actor] = nil
    edgeCache[actor] = nil
    needEdge[actor] = nil
end

-- 世界重置时清空全部派生缓存：NPC 的伤病边沿与冷却不得跨存档沿用。
-- 走 EventBus 订阅（项目唯一订阅注册表），不在业务模块里散挂清理调用。
function ChatterService.purgeAll()
    for actor in pairs(cooldowns) do cooldowns[actor] = nil end
    for actor in pairs(urgentCooldowns) do urgentCooldowns[actor] = nil end
    for actor in pairs(edgeCache) do edgeCache[actor] = nil end
    for actor in pairs(needEdge) do needEdge[actor] = nil end
end

-- 供单元测试检视内部状态
function ChatterService._inspect(actor)
    return {
        cooldown = cooldowns[actor],
        urgentCooldown = urgentCooldowns[actor],
        edge = edgeCache[actor],
    }
end

if Events and Events.OnPreMapLoad then
    EventBus.subscribeOnce(Events.OnPreMapLoad, "Chatter.reset", ChatterService.purgeAll)
end

return ChatterService
