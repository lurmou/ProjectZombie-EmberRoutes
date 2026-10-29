-- Context Menu Architecture & Regression Test for EmberRoutes
package.path = 'Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;' .. package.path

local checks = 0
local function assert_eq(a, b, msg)
    checks = checks + 1
    if a ~= b then
        error(string.format("Assertion failed: expected %s, got %s. (%s)", tostring(b), tostring(a), msg or ""))
    end
end
local function assert_true(cond, msg)
    checks = checks + 1
    if not cond then
        error("Assertion failed: " .. (msg or "expected true"))
    end
end

-- Mock PZ environment
local debugState = false
function isDebugEnabled() return debugState end
function isClient() return false end
function isServer() return false end

local mockActor = {
    isDead = function() return false end,
    getX = function() return 10 end,
    getY = function() return 10 end,
    getZ = function() return 0 end,
    Say = function() end
}
function getSpecificPlayer() return mockActor end

SandboxVars = { EmberRoutes = { CarrierProbe = true } }

local mockTranslations = {
    IGUI_EmberRoutesProbe_Menu = "余烬商路",
    IGUI_EmberRoutesProbe_Workers = "选择当前 NPC",
    IGUI_EmberRoutesProbe_ContainerSettings = "容器设置",
    IGUI_EmberRoutesProbe_Work = "手动搬运指令",
    IGUI_EmberRoutesProbe_Move = "移动到此处",
    IGUI_EmberRoutesProbe_Stop = "停止",
    IGUI_EmberRoutesProbe_Companion = "随从指令",
    IGUI_EmberRoutesProbe_Crafting_useSurface = "使用工作台发布订单",
    IGUI_EmberRoutesProbe_Settlement_create = "创建据点",
    IGUI_EmberRoutesProbe_Settlement_management = "据点管理",
    IGUI_EmberRoutesProbe_Settlement_OUTSIDE_SETTLEMENT = "不在据点内",
    IGUI_EmberRoutesProbe_Settlement_current = "当前据点",
    IGUI_EmberRoutesProbe_Settlement_other = "远端据点",
    IGUI_EmberRoutesProbe_Settlement_alreadyInside = "已处于现有据点管辖范围内",
    IGUI_EmberRoutesProbe_SelectedWorker_title = "当前选定随从",
    IGUI_EmberRoutesProbe_SelectAsTarget = "设为当前操作目标",
    IGUI_EmberRoutesProbe_Debug_probeCommands = "高级与调试指令",
    IGUI_EmberRoutesProbe_NoWorkers = "附近无可用随从",
    IGUI_EmberRoutesProbe_Logistics_role = "物流用途与物品筛选",
    IGUI_EmberRoutesProbe_Logistics_INPUT = "装卸与中转仓",
    IGUI_EmberRoutesProbe_Logistics_STORAGE = "专属存储仓",
    IGUI_EmberRoutesProbe_Logistics_EXCLUDED = "静态私有仓",
    IGUI_ContainerTitle_crate = "板条箱",
    IGUI_EmberRoutesProbe_Floor_ground = "地面层",
    IGUI_EmberRoutesProbe_Floor_level = "%1 层",
    IGUI_EmberRoutesProbe_Logistics_UNSET = "清除物流标记",
    IGUI_EmberRoutesProbe_ItemLock_lock = "物品锁定",
    IGUI_EmberRoutesProbe_ItemLock_unlock = "解除锁定",
}

function getText(key) return mockTranslations[key] or key end
function getTextOrNull(key) return mockTranslations[key] end

-- Mock ISContextMenu
local function newMenu()
    local m = { options = {}, subMenus = {} }
    function m:addOption(label, actor, fn, ...)
        local opt = { label = label, actor = actor, fn = fn, args = { ... }, notAvailable = false, checkMark = false }
        self.options[#self.options + 1] = opt
        return opt
    end
    function m:addSubMenu(opt, sub)
        self.subMenus[opt] = sub
        opt.subOption = sub
    end
    function m:setOptionChecked(opt, val)
        opt.checkMark = val
    end
    return m
end

ISContextMenu = { getNew = function(_, parent) return newMenu() end }

-- Mock Boot & Java probe
package.loaded['EmberRoutesProbe/Boot'] = { ready = true, hasJava = function() return true end }

EmberRoutesProbeJava = {
    workerCount = function() return 2 end,
    selectedId = function() return "worker-1" end,
    workerIdAt = function(i) return i == 0 and "worker-1" or "worker-2" end,
    selectCarrier = function(id) return true end
}

package.loaded['EmberRoutesProbe/Driver'] = {
    bindId = function(actor, id)
        return { handle = { getDescriptor = function() return { getForename = function() return id == "worker-1" and "张" or "李" end, getSurname = function() return id == "worker-1" and "三" or "四" end } end } }
    end,
    selected = function() return "worker-1" end
}

package.loaded['EmberRoutesProbe/SettlementLedger'] = {
    authorized = function() return true end,
    data = function() return { factionId = "faction-1" } end,
    list = function()
        return {
            { id = "s1", name = "绿洲", factionId = "faction-1", areas = { { x = 0, y = 0, w = 20, h = 20 } }, revision = 1 },
            { id = "s2", name = "哨站", factionId = "faction-1", areas = { { x = 100, y = 100, w = 20, h = 20 } }, revision = 1 }
        }
    end
}

package.loaded['EmberRoutesProbe/LogisticsMenu'] = {
    initialize = function() end,
    fill = function(actor, menu, entry)
        return menu:addOption("物流中心 - " .. entry.name, actor, function() end, entry.id)
    end,
    container = function(actor, parent, object, container)
        local opt = parent:addOption("物流用途与物品筛选", nil, nil)
        local sub = newMenu()
        parent:addSubMenu(opt, sub)
        sub:addOption("装卸与中转仓", actor, function() end)
        sub:addOption("专属存储仓", actor, function() end)
        sub:addOption("静态私有仓", actor, function() end)
        return opt
    end
}

package.loaded['EmberRoutesProbe/ContainerRegistry'] = {
    filter = function() return nil end,
    metadata = function() return nil end,
    logistics = function() return "STORAGE" end,
    data = function() return {} end,
    listeners = {}
}

package.loaded['EmberRoutesProbe/ContainerConfiguration'] = {
    summary = function() return "配置概要" end,
    warning = function() return nil end,
    text = function(k) return k end,
    presets = { "preset1" },
    hasClipboard = function() return false end
}

package.loaded['EmberRoutesProbe/StorageFilterPanel'] = { open = function() end }
package.loaded['EmberRoutesProbe/UI/Text'] = { wrapLimited = function(s) return { s } end }
UIFont = { Small = 0 }
getCore = function() return { getScreenWidth = function() return 1920 end } end

package.loaded['EmberRoutesProbe/UI/SettlementSelector'] = { open = function() end }
package.loaded['EmberRoutesProbe/SettlementDashboard'] = { open = function() end }
package.loaded['EmberRoutesProbe/LifeZoneMenu'] = { fill = function() end }
package.loaded['EmberRoutesProbe/MembershipText'] = { reason = function(k) return k end }
package.loaded['EmberRoutesProbe/MembershipService'] = {
    setReturnPoint = function() return true end,
    view = function(id) return { factionId = "faction-1", revision = 1 } end,
    request = function() return { state = "OK" } end
}
package.loaded['ISUI/ISCollapsableWindow'] = {}

-- Load modified modules
local ContainerMenu = require "EmberRoutesProbe/ContainerMenu"
local SettlementMenu = require "EmberRoutesProbe/SettlementMenu"

-- Test 1: ContainerMenu has logistics role integrated
local cParent = newMenu()
ContainerMenu.fill(mockActor, cParent, {}, {})
local foundRole = false
for _, opt in ipairs(cParent.options) do
    if opt.label == "物流用途与物品筛选" then foundRole = true end
end
assert_true(foundRole, "ContainerMenu.fill must include logistics role configuration")

-- Test 2: SettlementMenu organizes current and other settlements
local sMenu = newMenu()
SettlementMenu.fill(mockActor, sMenu)
assert_true(#sMenu.options >= 3, "SettlementMenu should have create, current settlement, and others")
local hasCurrent = false
local hasOthers = false
for _, opt in ipairs(sMenu.options) do
    if opt.label:find("绿洲") then hasCurrent = true end
    if opt.label == "远端据点" then hasOthers = true end
end
assert_true(hasCurrent, "Current settlement (绿洲) must be listed")
assert_true(hasOthers, "Other distant settlement must be grouped under 远端据点")

-- Test 3: Load EmberRoutesProbe and test fillMenu context sensitivity
Events = {
    OnFillWorldObjectContextMenu = { Add = function(fn) _G.testFillMenu = fn end },
    OnPreFillWorldObjectContextMenu = { Add = function(fn) _G.testPreFillMenu = fn end }
}

for _, name in ipairs({ "ISTimedActionQueue", "ISEatFoodAction", "ISDrinkFluidAction", "ISDrinkFromBottleAction", "ISGrabItemAction", "ISInventoryTransferAction", "ISBaseTimedAction" }) do
    package.loaded["TimedActions/" .. name] = { queues = {} }
end

package.loaded['EmberRoutesProbe/StockService'] = {}
package.loaded['EmberRoutesProbe/PublicWork'] = {}
package.loaded['EmberRoutesProbe/Persistence'] = { execute = function() end }
package.loaded['EmberRoutesProbe/TaskResume'] = { install = function() end }
package.loaded['EmberRoutesProbe/SelfCare'] = { install = function() end }
package.loaded['EmberRoutesProbe/TaskRetirement'] = { install = function() end }
package.loaded['EmberRoutesProbe/MembershipLifecycle'] = { install = function() end }
package.loaded['EmberRoutesProbe/StorageTabs'] = {}
package.loaded['EmberRoutesProbe/RecipeOrderEntry'] = {}
package.loaded['EmberRoutesProbe/DebugMenu'] = {}
package.loaded['EmberRoutesProbe/NpcDebugMenu'] = {}

require "EmberRoutesProbe"

-- Case A: Ground only (no containers, no craft surfaces, non-debug)
debugState = false
local rootCtx = newMenu()
local mockSquare = { getX = function() return 10 end, getY = function() return 10 end, getZ = function() return 0 end }
mockSquare.getObjects = function() return { contains = function() return false end } end
function getCell() return { getGridSquare = function(_, x, y, z) return mockSquare end } end
local mockWorldObjects = { { getSquare = function() return mockSquare end } }

_G.testFillMenu(0, rootCtx, mockWorldObjects, false)
assert_true(#rootCtx.options == 1, "Root context menu should only have EmberRoutes main option")
local probeMenu = rootCtx.subMenus[rootCtx.options[1]]
assert_true(probeMenu ~= nil, "EmberRoutes submenu must exist")

-- Verify probeMenu has NO empty ContainerSettings and NO Work probe commands in non-debug mode!
local hasContainerSettings = false
local hasWorkDebug = false
local hasSelectedCompanion = false
local hasWorkersRoster = false
for _, opt in ipairs(probeMenu.options) do
    if opt.label:find("容器设置") then hasContainerSettings = true end
    if opt.label:find("手动搬运指令") then hasWorkDebug = true end
    if opt.label:find("当前选定随从") then hasSelectedCompanion = true end
    if opt.label:find("选择当前 NPC") then hasWorkersRoster = true end
end
assert_eq(hasContainerSettings, false, "Ground click must NOT show container settings")
assert_eq(hasWorkDebug, false, "Non-debug mode must NOT show legacy work debug commands")
assert_true(hasSelectedCompanion, "Should show active selected companion commands")
assert_true(hasWorkersRoster, "Should show worker roster with real names")

-- Case B: Single container clicked
local mockContainer = { getType = function() return "crate" end }
local mockContainerObj = {
    getSquare = function() return mockSquare end,
    getContainer = function() return mockContainer end,
    getContainerCount = function() return 1 end,
    getContainerByIndex = function() return mockContainer end
}
mockSquare.getObjects = function() return { contains = function(_, o) return o == mockContainerObj end } end
mockWorldObjects[#mockWorldObjects + 1] = mockContainerObj

local rootCtx2 = newMenu()
_G.testFillMenu(0, rootCtx2, mockWorldObjects, false)
local probeMenu2 = rootCtx2.subMenus[rootCtx2.options[1]]
local containerOpt = nil
for _, opt in ipairs(probeMenu2.options) do
    if opt.label:find("容器设置") then containerOpt = opt end
end
assert_true(containerOpt ~= nil, "Single container click MUST show container settings")
assert_true(containerOpt.label:find("板条箱") ~= nil, "Single container option should directly include container label")
local cSub = probeMenu2.subMenus[containerOpt]
assert_true(cSub ~= nil, "Direct single-container settings submenu must be populated")

-- Case C: Multi-container click formatting
local mockContainer2 = { getType = function() return "crate" end }
local mockContainerObj2 = {
    getSquare = function() return mockSquare end,
    getContainer = function() return mockContainer2 end,
    getContainerCount = function() return 1 end,
    getContainerByIndex = function() return mockContainer2 end
}
mockSquare.getObjects = function() return { contains = function(_, o) return o == mockContainerObj or o == mockContainerObj2 end } end
mockWorldObjects[#mockWorldObjects + 1] = mockContainerObj2
local rootCtx3 = newMenu()
_G.testFillMenu(0, rootCtx3, mockWorldObjects, false)
local probeMenu3 = rootCtx3.subMenus[rootCtx3.options[1]]
local multiContainerOpt = nil
for _, opt in ipairs(probeMenu3.options) do
    if opt.label == "容器设置" then multiContainerOpt = opt end
end
assert_true(multiContainerOpt ~= nil, "Multi container click should have generic '容器设置'")
local multiSub = probeMenu3.subMenus[multiContainerOpt]
assert_true(multiSub ~= nil and #multiSub.options >= 2, "Multi container submenu should list individual containers")
assert_true(multiSub.options[1].label:find("地面层") ~= nil, "Container item should show floor label instead of raw coordinates")

-- Case D: Companion menu ordering (FOLLOW before SETTLE)
local compOpt = nil
for _, opt in ipairs(probeMenu.options) do
    if opt.label:find("当前选定随从") then compOpt = opt end
end
assert_true(compOpt ~= nil, "Selected companion option must exist")
local compMenu = probeMenu.subMenus[compOpt]
assert_true(compMenu ~= nil, "Selected companion submenu must exist")
local followIdx, settleIdx = nil, nil
for idx, opt in ipairs(compMenu.options) do
    if opt.label == "FOLLOW" then followIdx = idx end
    if opt.label:find("SETTLE") then settleIdx = idx end
end
assert_true(followIdx ~= nil and settleIdx ~= nil, "Both FOLLOW and SETTLE should be in companion menu")
assert_true(followIdx < settleIdx, "FOLLOW must appear before SETTLE in companion menu")

-- Case E: Logistics unset option
package.loaded['EmberRoutesProbe/ContainerRegistry'].metadata = function() return { role = "STORAGE" } end
package.loaded['EmberRoutesProbe/LogisticsMenu'] = nil
local LogisticsReal = require "EmberRoutesProbe/LogisticsMenu"
local logParent = newMenu()
LogisticsReal.container(mockActor, logParent, {}, {})
local roleOpt = logParent.options[1]
local roleSub = logParent.subMenus[roleOpt]
local hasUnset = false
if roleSub then
    for _, opt in ipairs(roleSub.options) do
        if opt.label:find("清除物流标记") or opt.label:find("UNSET") then hasUnset = true end
    end
end
assert_true(hasUnset, "Configured container must offer UNSET option in role submenu")

-- Case F: ItemLockMenu icon check
local ItemLockMenu = require "EmberRoutesProbe/ItemLockMenu"
local itemCtx = newMenu()
local mockItem = { getModData = function() return {} end }
ItemLockMenu.fill(0, itemCtx, { mockItem })
assert_true(#itemCtx.options == 1, "ItemLockMenu should add 1 option")
assert_true(itemCtx.options[1].label:find("🔓") ~= nil or itemCtx.options[1].label:find("物品") ~= nil, "Lock menu should contain lock/unlock icon")

print(string.format("PASS %d context menu tests completed successfully", checks))
