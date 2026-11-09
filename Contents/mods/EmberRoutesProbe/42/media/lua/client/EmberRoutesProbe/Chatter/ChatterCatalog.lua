--[[
    Ember Chatter Catalog
    插槽式动态拼装 + 多变体自然口语台词库
    - 支持 Openers (语气前缀) + Cores (核心事实) + Closers (行动诉求) 自由搭配
    - 兼具全句变种与插槽装配，单场景组合空间可达 50~100 种以上，彻底告别机械重复
    - 自动依据语言环境处理自然标点与词间距
]]

local Catalog = {}

local Colors = {
    CRISIS  = { r = 1.00, g = 0.25, b = 0.25 }, -- 鲜红 (大出血/致命重伤)
    WARN    = { r = 1.00, g = 0.75, b = 0.20 }, -- 焦黄 (急迫需求/环境受挫)
    WORK    = { r = 0.40, g = 0.80, b = 1.00 }, -- 秩序蓝 (任务受阻/生产完成)
    ORDER   = { r = 0.30, g = 1.00, b = 0.50 }, -- 翠绿 (随从指令响应)
    DEFAULT = { r = 0.90, g = 0.90, b = 0.90 }, -- 柔和白 (日常闲谈)
}

local function pick(list)
    if not list or #list == 0 then return nil end
    local count = #list
    local idx = 1
    if count > 1 then
        if ZombRand then
            idx = ZombRand(count) + 1
        elseif math and math.random then
            idx = math.random(count)
        end
    end
    return list[idx]
end

local function maybe(percent)
    if ZombRand then
        return ZombRand(100) < percent
    elseif math and math.random then
        return math.random(100) <= percent
    end
    return true
end

local Entries = {
    HEALTH_BLEEDING = {
        color = Colors.CRISIS,
        urgent = true,
        slots = {
            openers = {
                "IGUI_EmberRoutesProbe_Chatter_Bleed_Open_1",
                "IGUI_EmberRoutesProbe_Chatter_Bleed_Open_2",
                "IGUI_EmberRoutesProbe_Chatter_Bleed_Open_3",
                "IGUI_EmberRoutesProbe_Chatter_Bleed_Open_4",
            },
            cores = {
                "IGUI_EmberRoutesProbe_Chatter_Bleed_Core_1",
                "IGUI_EmberRoutesProbe_Chatter_Bleed_Core_2",
                "IGUI_EmberRoutesProbe_Chatter_Bleed_Core_3",
                "IGUI_EmberRoutesProbe_Chatter_Bleed_Core_4",
            },
            closers = {
                "IGUI_EmberRoutesProbe_Chatter_Bleed_Close_1",
                "IGUI_EmberRoutesProbe_Chatter_Bleed_Close_2",
                "IGUI_EmberRoutesProbe_Chatter_Bleed_Close_3",
                "IGUI_EmberRoutesProbe_Chatter_Bleed_Close_4",
            },
        },
        variants = {
            "IGUI_EmberRoutesProbe_Chatter_Health_Bleeding_1",
            "IGUI_EmberRoutesProbe_Chatter_Health_Bleeding_2",
            "IGUI_EmberRoutesProbe_Chatter_Health_Bleeding_3",
        },
    },
    HEALTH_DEEP_WOUND = {
        color = Colors.CRISIS,
        urgent = true,
        slots = {
            openers = {
                "IGUI_EmberRoutesProbe_Chatter_Deep_Open_1",
                "IGUI_EmberRoutesProbe_Chatter_Deep_Open_2",
                "IGUI_EmberRoutesProbe_Chatter_Deep_Open_3",
            },
            cores = {
                "IGUI_EmberRoutesProbe_Chatter_Deep_Core_1",
                "IGUI_EmberRoutesProbe_Chatter_Deep_Core_2",
                "IGUI_EmberRoutesProbe_Chatter_Deep_Core_3",
            },
            closers = {
                "IGUI_EmberRoutesProbe_Chatter_Deep_Close_1",
                "IGUI_EmberRoutesProbe_Chatter_Deep_Close_2",
                "IGUI_EmberRoutesProbe_Chatter_Deep_Close_3",
            },
        },
        variants = {
            "IGUI_EmberRoutesProbe_Chatter_Health_Deep_1",
            "IGUI_EmberRoutesProbe_Chatter_Health_Deep_2",
        },
    },
    HEALTH_DIRTY_BANDAGE = {
        color = Colors.WARN,
        urgent = false,
        variants = {
            "IGUI_EmberRoutesProbe_Chatter_Health_DirtyBandage_1",
        },
    },
    WORK_STORAGE_FULL = {
        color = Colors.WORK,
        urgent = false,
        slots = {
            openers = {
                "IGUI_EmberRoutesProbe_Chatter_Storage_Open_1",
                "IGUI_EmberRoutesProbe_Chatter_Storage_Open_2",
                "IGUI_EmberRoutesProbe_Chatter_Storage_Open_3",
                "IGUI_EmberRoutesProbe_Chatter_Storage_Open_4",
            },
            cores = {
                "IGUI_EmberRoutesProbe_Chatter_Storage_Core_1",
                "IGUI_EmberRoutesProbe_Chatter_Storage_Core_2",
                "IGUI_EmberRoutesProbe_Chatter_Storage_Core_3",
            },
            closers = {
                "IGUI_EmberRoutesProbe_Chatter_Storage_Close_1",
                "IGUI_EmberRoutesProbe_Chatter_Storage_Close_2",
                "IGUI_EmberRoutesProbe_Chatter_Storage_Close_3",
            },
        },
        variants = {
            "IGUI_EmberRoutesProbe_Chatter_Work_StorageFull_1",
            "IGUI_EmberRoutesProbe_Chatter_Work_StorageFull_2",
        },
    },
    WORK_NO_TOOL = {
        color = Colors.WORK,
        urgent = false,
        slots = {
            openers = {
                "IGUI_EmberRoutesProbe_Chatter_Tool_Open_1",
                "IGUI_EmberRoutesProbe_Chatter_Tool_Open_2",
                "IGUI_EmberRoutesProbe_Chatter_Tool_Open_3",
            },
            cores = {
                "IGUI_EmberRoutesProbe_Chatter_Tool_Core_1",
                "IGUI_EmberRoutesProbe_Chatter_Tool_Core_2",
                "IGUI_EmberRoutesProbe_Chatter_Tool_Core_3",
            },
            closers = {
                "IGUI_EmberRoutesProbe_Chatter_Tool_Close_1",
                "IGUI_EmberRoutesProbe_Chatter_Tool_Close_2",
                "IGUI_EmberRoutesProbe_Chatter_Tool_Close_3",
            },
        },
        variants = {
            "IGUI_EmberRoutesProbe_Chatter_Work_MissingTool_1",
            "IGUI_EmberRoutesProbe_Chatter_Work_MissingTool_2",
        },
    },
    WORK_DONE = {
        color = Colors.WORK,
        urgent = false,
        variants = {
            "IGUI_EmberRoutesProbe_Chatter_Work_Done_1",
        },
    },
    WORK_INJURED = {
        color = Colors.CRISIS,
        urgent = true,
        variants = {
            "IGUI_EmberRoutesProbe_Chatter_Work_Injured_1",
            "IGUI_EmberRoutesProbe_Chatter_Work_Injured_2",
        },
    },
    NEEDS_HUNGER = {
        color = Colors.WARN,
        urgent = false,
        slots = {
            openers = {
                "IGUI_EmberRoutesProbe_Chatter_Hunger_Open_1",
                "IGUI_EmberRoutesProbe_Chatter_Hunger_Open_2",
                "IGUI_EmberRoutesProbe_Chatter_Hunger_Open_3",
            },
            cores = {
                "IGUI_EmberRoutesProbe_Chatter_Hunger_Core_1",
                "IGUI_EmberRoutesProbe_Chatter_Hunger_Core_2",
                "IGUI_EmberRoutesProbe_Chatter_Hunger_Core_3",
            },
            closers = {
                "IGUI_EmberRoutesProbe_Chatter_Hunger_Close_1",
                "IGUI_EmberRoutesProbe_Chatter_Hunger_Close_2",
                "IGUI_EmberRoutesProbe_Chatter_Hunger_Close_3",
            },
        },
        variants = {
            "IGUI_EmberRoutesProbe_Chatter_Needs_Hunger_1",
            "IGUI_EmberRoutesProbe_Chatter_Needs_Hunger_2",
        },
    },
    NEEDS_THIRST = {
        color = Colors.WARN,
        urgent = false,
        variants = {
            "IGUI_EmberRoutesProbe_Chatter_Needs_Thirst_1",
        },
    },
    NEEDS_SOAKED = {
        color = Colors.WARN,
        urgent = false,
        variants = {
            "IGUI_EmberRoutesProbe_Chatter_Needs_Soaked_1",
        },
    },
    CMD_FOLLOW = {
        color = Colors.ORDER,
        urgent = false,
        slots = {
            openers = {
                "IGUI_EmberRoutesProbe_Chatter_Follow_Open_1",
                "IGUI_EmberRoutesProbe_Chatter_Follow_Open_2",
                "IGUI_EmberRoutesProbe_Chatter_Follow_Open_3",
                "IGUI_EmberRoutesProbe_Chatter_Follow_Open_4",
            },
            cores = {
                "IGUI_EmberRoutesProbe_Chatter_Follow_Core_1",
                "IGUI_EmberRoutesProbe_Chatter_Follow_Core_2",
                "IGUI_EmberRoutesProbe_Chatter_Follow_Core_3",
            },
            closers = {
                "IGUI_EmberRoutesProbe_Chatter_Follow_Close_1",
                "IGUI_EmberRoutesProbe_Chatter_Follow_Close_2",
                "IGUI_EmberRoutesProbe_Chatter_Follow_Close_3",
            },
        },
        variants = {
            "IGUI_EmberRoutesProbe_Chatter_Cmd_Follow_1",
            "IGUI_EmberRoutesProbe_Chatter_Cmd_Follow_2",
        },
    },
    CMD_HOLD = {
        color = Colors.ORDER,
        urgent = false,
        slots = {
            openers = {
                "IGUI_EmberRoutesProbe_Chatter_Hold_Open_1",
                "IGUI_EmberRoutesProbe_Chatter_Hold_Open_2",
                "IGUI_EmberRoutesProbe_Chatter_Hold_Open_3",
            },
            cores = {
                "IGUI_EmberRoutesProbe_Chatter_Hold_Core_1",
                "IGUI_EmberRoutesProbe_Chatter_Hold_Core_2",
                "IGUI_EmberRoutesProbe_Chatter_Hold_Core_3",
            },
            closers = {
                "IGUI_EmberRoutesProbe_Chatter_Hold_Close_1",
                "IGUI_EmberRoutesProbe_Chatter_Hold_Close_2",
                "IGUI_EmberRoutesProbe_Chatter_Hold_Close_3",
            },
        },
        variants = {
            "IGUI_EmberRoutesProbe_Chatter_Cmd_Hold_1",
            "IGUI_EmberRoutesProbe_Chatter_Cmd_Hold_2",
        },
    },
    CMD_HOME = {
        color = Colors.ORDER,
        urgent = false,
        variants = {
            "IGUI_EmberRoutesProbe_Chatter_Cmd_Home_1",
        },
    },
}

function Catalog.getEntry(eventKey)
    return Entries[eventKey]
end

local function assembleSlots(slots)
    if not slots or not slots.cores or #slots.cores == 0 then return nil end

    local coreKey = pick(slots.cores)
    local openKey = maybe(70) and pick(slots.openers) or nil
    local closeKey = maybe(75) and pick(slots.closers) or nil

    local parts = {}
    if openKey then parts[#parts + 1] = getText(openKey) end
    if coreKey then parts[#parts + 1] = getText(coreKey) end
    if closeKey then parts[#parts + 1] = getText(closeKey) end

    local isEnglish = (Translator and Translator.getLanguage and Translator.getLanguage():name() == "EN")
    return table.concat(parts, isEnglish and " " or "")
end

function Catalog.get(eventKey, context)
    local entry = Entries[eventKey]
    if not entry then return nil end

    local line
    -- 当定义了插槽时，80% 几率走动态组合拼装，20% 几率走静态固定全句
    if entry.slots and (not entry.variants or maybe(80)) then
        line = assembleSlots(entry.slots)
    end

    -- 降级或静态变种随机挑选
    if not line and entry.variants and #entry.variants > 0 then
        local key = pick(entry.variants)
        if context and type(context) == "table" and #context > 0 and unpack then
            line = getText(key, unpack(context))
        else
            line = getText(key)
        end
    end

    if not line or line == "" then return nil end

    local col = entry.color or Colors.DEFAULT
    local font = UIFont and UIFont.Medium or nil
    return line, col.r, col.g, col.b, font, entry.urgent == true
end

Catalog.Colors = Colors
Catalog.Entries = Entries
return Catalog
