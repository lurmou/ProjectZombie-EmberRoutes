-- sim-warehouse-journey-test.lua
-- Track A: 仓储与物流交互全旅程 (Warehouse & Inventory Journey) 玩家操作全流程模拟与验证

package.loaded['ISUI/ISContextMenu'] = true
package.loaded['ISUI/ISTickBox'] = true
_G.Events = _G.Events or {}
for _, name in ipairs({'OnGameStart', 'OnServerStarted', 'OnTick', 'OnTickEvenPaused', 'OnPreMapLoad', 'OnSave', 'OnContainerUpdate'}) do
    _G.Events[name] = { Add = function() end, Remove = function() end }
end

package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path

local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

-- =============================================================================
-- Native UI Mock Environment for Kahlua Host
-- =============================================================================
local Base = {}
function Base:derive(name)
    local cls = { Type = name }
    cls.__index = cls
    return setmetatable(cls, { __index = self })
end

function Base:new(x, y, w, h, title, target, callback)
    return setmetatable({
        x = x, y = y, width = w, height = h,
        title = title, target = target, onclick = callback,
        items = {}, selected = 0, children = {}, enable = true, visible = true
    }, { __index = self })
end

function Base:initialise()
    self.children = {}
    self.initialised = true
end

function Base:instantiate()
    if self.native then return end
    self.native = true
    self:createChildren()
end

function Base:createChildren() end
function Base:addChild(child)
    check(child.initialised, "native child must be initialized before mount")
    child.parent = self
    child:instantiate()
    self.children[#self.children + 1] = child
end

function Base:addToUIManager() self:instantiate() self.added = true end
function Base:removeFromUIManager() self.added = false end
function Base:setVisible(v) self.visible = v end
function Base:isVisible() return self.visible end
function Base:getIsVisible() return self.visible end
function Base:close() self:setVisible(false) end
function Base:bringToTop() self.raised = true end
function Base:clear() self.items = {} self.selected = 0 end
function Base:titleBarHeight() return 24 end
function Base:setWantKeyEvents(v) self.wantKeys = v end
function Base:update() end
function Base:prerender() end
function Base:getMouseX() return self.mouseX or -1 end
function Base:getMouseY() return self.mouseY or -1 end
function Base:setX(x) self.x = x end
function Base:setY(y) self.y = y end
function Base:getX() return self.x or 0 end
function Base:getY() return self.y or 0 end
function Base:getHeight() return self.height or 0 end
function Base:drawTextureScaledAspect() end
function Base:setHeight(h) self.height = h end
function Base:setWidth(w) self.width = w end
function Base:getWidth() return self.width end
function Base:getAbsoluteX() return self.x + (self.parent and self.parent:getAbsoluteX() or 0) end
function Base:getAbsoluteY() return self.y + (self.parent and self.parent:getAbsoluteY() or 0) end
function Base:setTitle(value) self.title = value end
function Base:setEnable(value) self.enable = value end
function Base:setOnMouseDownFunction(target, fn) self.target = target self.onclick = fn end
function Base:setOverrideAButtonFunction() end
function Base:setYScroll(value) self.scroll = value end
function Base:getYScroll() return self.scroll or 0 end
function Base:setScrollHeight(value) self.scrollHeight = value end
function Base:getScrollHeight() return self.scrollHeight or (#self.items * (self.itemheight or 20)) end
function Base:ensureVisible() end
function Base:drawText() end
function Base:drawRect() end
function Base:drawRectBorder() end
function Base:setStencilRect(x, y, w, h) self.stencilRect = {x, y, w, h} end
function Base:clearStencilRect() self.stencilRect = nil end
function Base:repaintStencilRect(x, y, w, h) self.stencilRect = {x, y, w, h} end
function Base:addItem(label, item, tooltip)
    local entry = { text = label, item = item, tooltip = tooltip, height = self.itemheight or 24, index = #self.items + 1 }
    self.items[#self.items + 1] = entry
    return entry
end

ISPanel = Base
ISCollapsableWindow = Base
ISButton = Base
ISScrollingListBox = Base

ISTextEntryBox = Base:derive("TextEntry")
function ISTextEntryBox:new(value, x, y, w, h)
    local o = Base.new(self, x, y, w, h)
    o.value = value or ""
    return o
end
function ISTextEntryBox:setPlaceholderText(value) self.placeholderText = value end
function ISTextEntryBox:setText(value)
    self.value = value
    if self.onTextChangeFunction then self.onTextChangeFunction(self.target) end
end
function ISTextEntryBox:getText() return self.value end
function ISTextEntryBox:isFocused() return self.focused end
function ISTextEntryBox:unfocus() self.focused = false end

ISComboBox = Base:derive("Combo")
function ISComboBox:new(...)
    local o = Base.new(self, ...)
    o.options = {}
    o.selected = 1
    return o
end
function ISComboBox:addOption(value) self.options[#self.options + 1] = value end
function ISComboBox:clear() self.options = {} self.selected = 1 end
function ISComboBox:setToolTipMap() end
function ISComboBox:hidePopup() self.popupHidden = true end

ISModalDialog = Base:derive("Modal")
function ISModalDialog:new(x, y, w, h, message, yesno, target, callback)
    local o = Base.new(self, x, y, w, h)
    o.text = message
    o.target = target
    o.onclick = callback
    return o
end

for _, name in ipairs({"ISPanel", "ISCollapsableWindow", "ISButton", "ISScrollingListBox", "ISTextEntryBox", "ISComboBox", "ISModalDialog"}) do
    package.loaded['ISUI/' .. name] = true
end

UIFont = { Small = 1, Medium = 2, Large = 3 }
Keyboard = {
    KEY_UP = 1, KEY_DOWN = 2, KEY_ESCAPE = 3, KEY_LEFT = 4, KEY_RIGHT = 5,
    KEY_TAB = 6, KEY_RETURN = 7, KEY_PRIOR = 8, KEY_NEXT = 9
}
Joypad = {
    AButton = 1, BButton = 2, XButton = 3, YButton = 4,
    LBumper = 5, RBumper = 6, LStickButton = 7, RStickButton = 8
}

local screenW, screenH, fontHeight = 1920, 1080, 20
function getCore() return { getScreenWidth = function() return screenW end, getScreenHeight = function() return screenH end } end
function getTextManager()
    return {
        getFontHeight = function() return fontHeight end,
        MeasureStringX = function(_, _, s) return #tostring(s) * fontHeight * 0.5 end
    }
end
function getTextOrNull(key) return ERTestTranslations and ERTestTranslations[key] end
function getText(key, ...)
    local value = getTextOrNull(key) or key
    for i, arg in ipairs({...}) do
        local replacement = tostring(arg)
        value = value:gsub("%%" .. i, function() return replacement end)
    end
    return value
end

local simulatedTimeMs = 10000
function getTimestampMs() return simulatedTimeMs end
function isClient() return false end
function isServer() return false end
function getCell() return {} end
function getTexture() return { texture = true } end
function tryGetTexture() return { texture = true } end
function getScriptManager()
    return {
        FindItem = function(_, id)
            return {
                getNormalTexture = function() return { texture = true } end,
                getIconsForTexture = function() return { isEmpty = function() return true end } end
            }
        end
    }
end

-- =============================================================================
-- UTF-8 / Kahlua UTF-16 Multi-byte String Helper
-- =============================================================================
local function makeStr(codepoints, utf8bytes)
    local ok, str = pcall(string.char, unpack(codepoints))
    if ok and str and #str == #codepoints then return str end
    return utf8bytes
end

local sMuZhiCanCha = makeStr({26408, 21046, 39184, 21449}, "\230\156\168\230\136\188\233\164\144\229\143\137") -- 木制餐叉
local sDingZi       = makeStr({38025, 23376}, "\233\146\137\229\173\144")                 -- 钉子
local sTieChui     = makeStr({38081, 38180}, "\233\147\129\233\148\164")                 -- 铁锤
local sFuTou       = makeStr({26023, 22836}, "\230\150\167\229\164\180")                 -- 斧头
local sPingGuo     = "Apple"

local itemNamesMap = {
    ["Base.WoodenFork"] = sMuZhiCanCha,
    ["Base.Nails"]      = sDingZi,
    ["Base.Hammer"]     = sTieChui,
    ["Base.Axe"]        = sFuTou,
    ["Base.Apple"]      = sPingGuo,
}
function getItemNameFromFullType(id) return itemNamesMap[id] or id end

-- Actor and Settlement Ledger Setup
local mockActor = {
    getIndex = function() return 0 end,
    getPlayerNum = function() return 0 end,
    getJoypadBind = function() return -1 end,
    Say = function() end,
    getInventoryWeight = function() return 8 end,
    getMaxWeight = function() return 16 end
}
function getSpecificPlayer() return mockActor end

local mockRoot = {}
local mockSettlement = { id = "settlement_alpha", name = "余烬根据地", areas = { { x = 0, y = 0, w = 100, h = 100 } } }
local settlements = { settlement_alpha = mockSettlement }
package.loaded['EmberRoutesProbe/Settlement/SettlementLedger'] = {
    data = function() return mockRoot end,
    authorized = function() return true end,
    get = function(id) return settlements[id] end,
    view = function(_, id) return settlements[id] end,
    listeners = {}
}

local wareWatchers = {}
local liveWarehouseSnapshot = {
    state = "READY",
    rows = {},
    counts = { loaded = 1, containers = 1, items = 0, unloaded = 0, private = 0, missing = 0, limited = 0 },
    revision = 1
}
package.loaded['EmberRoutesProbe/Warehouse/WarehouseIndex'] = {
    watch = function(id, fn)
        wareWatchers[#wareWatchers + 1] = fn
        fn(liveWarehouseSnapshot)
        return function()
            for i, w in ipairs(wareWatchers) do if w == fn then table.remove(wareWatchers, i) break end end
        end
    end,
    refresh = function(id) end
}

local locatorClears = 0
local mockLocatorPos = { x = 10, y = 20, z = 0 }
package.loaded['EmberRoutesProbe/Warehouse/WarehouseLocator'] = {
    new = function()
        return {
            clear = function() locatorClears = locatorClears + 1 end,
            locate = function(_, sourceId) return mockLocatorPos, "located" end
        }
    end
}
package.loaded['EmberRoutesProbe/UI/TooltipManager'] = { register= function() end, clear = function() end, dismissOwner = function() end, unregisterOwner = function() end,}
package.loaded['TimedActions/ISInventoryTransferAction'] = true
package.loaded['Entity/TimedActions/ISHandcraftAction'] = true
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry'] = { describe = function() return nil end, data = function() return { containers = {} } end, listeners = {}, inventoryListeners = {} }
package.loaded['EmberRoutesProbe/Work/WorkOverviewService'] = {
    status = function() return { rows = {}, reason = nil } end,
    watch = function(actor, id, callback)
        callback({ rows = {}, reason = nil })
        return function() end
    end
}

-- Global PublicOrder recording spy
local publicOrderCalls = {}
package.loaded['EmberRoutesProbe/Work/PublicWork'] = {
    available = function() return true end,
    create = function(_, scope, recipe, n, surface, token)
        publicOrderCalls[#publicOrderCalls + 1] = { scope = scope, recipe = recipe, n = n, surface = surface }
        return 'ORDER_CREATED'
    end,
    rule = function() return { minimum = 50, batch = 10 } end,
}

-- Module references
local Query = require "EmberRoutesProbe/Warehouse/WarehouseQuery"
local PinyinHelper = require "EmberRoutesProbe/Warehouse/PinyinHelper"
local Dashboard = require "EmberRoutesProbe/UI/SettlementDashboard"
local WarehousePage = require "EmberRoutesProbe/UI/WarehousePage"
local WarehouseGrid = require "EmberRoutesProbe/UI/WarehouseGrid"
local WarehouseDetails = require "EmberRoutesProbe/UI/WarehouseDetails"

print("================================================================================")
print("开始执行 Track A: 仓储与物流交互全旅程 (Warehouse & Inventory Journey) 玩家操作全流程验证")
print("================================================================================")

-- =============================================================================
-- 1. 打开仓储总览与自适应布局 (Opening warehouse overview & responsive layout)
-- =============================================================================
print("\n[Step 1] 验证打开仓储总览与不同分辨率自适应布局...")

-- 1.1 标准 1920x1080 分辨率开启
screenW, screenH = 1920, 1080
-- 1.0 验证默认首屏落地页为 overview
local defaultShell = Dashboard.open(mockActor, mockSettlement.id)
check(defaultShell ~= nil, "据点管理面板成功打开")
check(defaultShell.activeTab == "overview", "主导航默认首屏为 overview 战略指挥概览标签页")
check(defaultShell.pages.overview ~= nil, "战略指挥概览页面实例成功构建")
defaultShell:close()

local shell = Dashboard.open(mockActor, mockSettlement.id, "warehouse")
check(shell ~= nil, "据点管理面板成功打开")
check(shell.activeTab == "warehouse", "主导航成功选中并在初始加载 warehouse 仓储标签页")
local page = shell.pages.warehouse
check(page ~= nil, "仓储页面实例成功构建")
check(page.active == true, "仓储页面处于激活生命周期")
check(page.visible == true, "仓储页面处于可见状态")
check(page.width <= screenW and page.height <= screenH, "仓储主页面在 1080p 下完全容纳于屏幕")
check(page.summary ~= nil and page.summary.bounds.width > 0, "Summary 概览区完成布局")
check(page.controls ~= nil and page.controls.search ~= nil, "Controls 搜索与筛选区完成布局")

check(page.itemGrid ~= nil and page.itemGrid.width > 0, "ItemGrid 网格视图完成布局")
check(page.details ~= nil and page.details.hero ~= nil, "WarehouseDetails 详情面板完成布局")
check(page.pad == math.ceil(fontHeight * 0.6), "标准分辨率下使用正常内边距")
check(page.details.compact == false, "标准分辨率下详情面板处于标准 (非紧凑) 布局模式")

-- 1.2 紧凑小分辨率自适应布局 (如 800x480 或 4K 大字体)
shell:close()
screenW, screenH = 800, 480
local shellCompact = Dashboard.open(mockActor, mockSettlement.id, "warehouse")
local pageCompact = shellCompact.pages.warehouse
check(pageCompact.width <= 800 and pageCompact.height <= 480, "仓储主页面在 800x480 下自适应缩放无溢出")
check(pageCompact.pad == math.ceil(fontHeight * 0.35), "紧凑分辨率下自适应收缩内边距以保证可视密度")
check(pageCompact.details.compact == true, "小分辨率下详情面板自适应切换为紧凑 (compact) 三口径横向布局")
shellCompact:close()

-- 恢复标准 1080p 用于后续完整交互流程
screenW, screenH = 1920, 1080
shell = Dashboard.open(mockActor, mockSettlement.id, "warehouse")
page = shell.pages.warehouse

print("  -> Step 1 PASS: 默认加载仓储主页及 1080p / 768p 响应式自适应布局验证通过")

-- =============================================================================
-- 2. AE2 风格网格视图特性
-- =============================================================================
print("\n[Step 2] 验证 AE2 网格视图特性 (网格装载、方格尺寸与响应式列数)...")

check(page.itemGrid ~= nil, "网格组件成功实例化")
check(page.itemGrid.visible == true, "网格组件处于可见状态")
check(page.itemGrid.columns > 0, "网格根据可用宽度自动计算列数")
check(page.itemGrid.slotSize >= 38, "网格单元尺寸符合 AE2 紧凑标准")

print("  -> Step 2 PASS: AE2 网格视图初始化与布局结构验证通过")

-- =============================================================================
-- 3. 拼音首字母检索与英文检索
-- =============================================================================
print("\n[Step 3] 验证拼音首字母检索与英文检索 (mfc, dz, hammer, clear)...")

-- 装载包含真实多物理物品的仓储快照
local journeyRows = {
    { fullType = "Base.WoodenFork", node = "tools", count = 12, reserved = 2, inTransit = 1,
      sources = { { id = "box_1", x = 10, y = 20, z = 0, count = 12, kind = "wooden_box" } } },
    { fullType = "Base.Nails",      node = "tools", count = 100, reserved = 20, inTransit = 10,
      sources = { { id = "crate_1", x = 10, y = 20, z = 0, count = 60, kind = "crate" },
                  { id = "crate_2", x = 12, y = 20, z = 0, count = 40, kind = "metal_crate" } } },
    { fullType = "Base.Hammer",     node = "tools", count = 5, reserved = 1, inTransit = 0,
      sources = { { id = "tool_rack", x = 10, y = 21, z = 0, count = 5, kind = "rack" } } },
    { fullType = "Base.Axe",        node = "tools", count = 2, reserved = 0, inTransit = 0,
      sources = { { id = "tool_rack", x = 10, y = 21, z = 0, count = 2, kind = "rack" } } },
    { fullType = "Base.Apple",      node = "food",  count = 50, reserved = 0, inTransit = 0,
      sources = { { id = "fridge_1", x = 8, y = 20, z = 0, count = 50, kind = "fridge" } } }
}
local journeySnapshot = {
    state = "READY",
    rows = journeyRows,
    counts = { loaded = 1, containers = 5, items = 169, unloaded = 0, private = 0, missing = 0, limited = 0 },
    revision = 1
}
page:receive(journeySnapshot)
check(#page.itemGrid.cells == 5, "网格视图同步装载 5 个方格")

-- 3.1 模拟玩家在搜索框输入 "mfc" -> 匹配 Base.WoodenFork (木制餐叉)
page.search:setText("mfc")
check(#page.itemGrid.cells == 1 and page.itemGrid.cells[1].fullType == "Base.WoodenFork", "网格视图同步仅显示木制餐叉")

-- 3.2 模拟玩家在搜索框输入 "dz" -> 匹配 Base.Nails (钉子)
page.search:setText("dz")
check(#page.itemGrid.cells == 1 and page.itemGrid.cells[1].fullType == "Base.Nails", "网格视图同步仅显示钉子")

-- 3.3 模拟玩家在搜索框输入 "hammer" -> 匹配 Base.Hammer (铁锤)
page.search:setText("hammer")
check(#page.itemGrid.cells == 1 and page.itemGrid.cells[1].fullType == "Base.Hammer", "网格视图同步仅显示铁锤")

-- 3.4 模拟玩家清空搜索框
page.search:setText("")
check(page.search:getText() == "", "清空搜索框后内容为空")
check(#page.itemGrid.cells == 5, "网格全量恢复显示 5 个方格")

print("  -> Step 3 PASS: 拼音首字母 'mfc'、'dz' 及英文 'hammer' 与一键清空验证通过")

-- =============================================================================
-- 4. 类别下拉筛选
-- =============================================================================
print("\n[Step 4] 验证类别下拉框筛选 (工具、食物、全部类别)...")

local toolsOptionIdx, foodOptionIdx = nil, nil
for idx, catId in ipairs(page.categoryIds) do
    if catId == "tools" then toolsOptionIdx = idx end
    if catId == "food" then foodOptionIdx = idx end
end
check(toolsOptionIdx ~= nil, "筛选分类树中存在 'tools' 类别")
check(foodOptionIdx ~= nil, "筛选分类树中存在 'food' 类别")

-- 4.1 切换为“工具”
page.categories.selected = toolsOptionIdx
page:queryChanged()
check(#page.itemGrid.cells == 4, "选择 'tools' 后只显示 4 种工具类物品")
for _, cell in ipairs(page.itemGrid.cells) do
    check(cell.row.node == "tools", "过滤后的所有物品所属类别均为 tools: " .. cell.row.fullType)
end

-- 4.2 切换为“食物”
page.categories.selected = foodOptionIdx
page:queryChanged()
check(#page.itemGrid.cells == 1, "选择 'food' 后只显示 1 种食物物品")
check(page.itemGrid.cells[1].fullType == "Base.Apple", "食物分类仅显示 Base.Apple")

-- 4.3 切回“全部类别”
page.categories.selected = 1
page:queryChanged()
check(#page.itemGrid.cells == 5, "切回全部类别后全量恢复 5 种物品")

print("  -> Step 4 PASS: 类别下拉筛选与全部分类切换验证通过")

-- =============================================================================
-- 5. 物品详情与三物理口径分立 (Three Physical Calibers)
-- =============================================================================
print("\n[Step 5] 验证选中物品详情与仓内实存/工单预留/搬运在途三物理口径分立展示...")

-- 模拟玩家点击选中 Base.Nails (钉子)
local nailRow = nil
for _, r in ipairs(journeyRows) do if r.fullType == "Base.Nails" then nailRow = r end end
check(nailRow ~= nil, "找到钉子数据行")
page:selectItem(nailRow)

local details = page.details
check(details.row == nailRow, "详情面板成功装载钉子行")
check(details.stockCount == 100, "仓内实存 (In-Stock) 准确读数为 100")
check(details.reservedCount == 20, "工单预留 (Reserved) 准确读数为 20")
check(details.inTransitCount == 10, "搬运在途 (In-Transit) 准确读数为 10")

-- 【实现红线验证】：严禁机械扣减，严禁简单相加
check(details.stockCount ~= (100 - 20), "【红线校验】实存绝对不可机械扣减预留 (严禁变为 80)！")
check(details.stockCount ~= (100 + 20 + 10), "【红线校验】实存绝对不可与预留/在途混淆相加 (严禁变为 130)！")

-- 检查三个物理标签独立分列
check(details.stockLabel:find("100", 1, true) ~= nil, "实存标签包含实存读数 100: " .. details.stockLabel)
check(details.reservedLabel:find("20", 1, true) ~= nil, "预留标签包含预留读数 20: " .. details.reservedLabel)
check(details.inTransitLabel:find("10", 1, true) ~= nil, "在途标签包含在途读数 10: " .. details.inTransitLabel)
check(details.stockLabel ~= details.reservedLabel and details.reservedLabel ~= details.inTransitLabel, "三口径分列独立，标签文本互不重合")

-- 检查容器源列表 (Sources)
check(#details.list.items == 2, "详情展示 2 个来源容器")
local s1 = details.list.items[1].text
local s2 = details.list.items[2].text
check(s1:find("10, 20", 1, true) ~= nil and s1:find("60", 1, true) ~= nil, "容器 1 展示坐标 (10, 20) 与实存 60")
check(s2:find("12, 20", 1, true) ~= nil and s2:find("40", 1, true) ~= nil, "容器 2 展示坐标 (12, 20) 与实存 40")

-- 模拟玩家选中容器 1 并点击定位按钮
page:selectSource(nailRow.sources[1])
check(details.locate.enable == true, "选中容器后定位按钮启用")
details.locate.onclick(details.locate.target)
check(page.notice:find("10, 20", 1, true) ~= nil, "定位提示文本准确包含容器物理坐标 (10, 20)")

print("  -> Step 5 PASS: 三物理口径分立 (实存100/预留20/在途10)、红线防扣减防虚构、多源容器及定位验证通过")

-- =============================================================================
-- 6. 置顶操作 (Pin to Top)
-- =============================================================================
print("\n[Step 6] 验证置顶操作 (Pin to Top & Unpin)...")

-- 初始未置顶，Base.Nails 位于第二位 (在 Base.WoodenFork 之后)
check(page.itemGrid.cells[1].fullType == "Base.WoodenFork", "初始第一项为木制餐叉")
check(page.itemGrid.cells[2].fullType == "Base.Nails", "初始第二项为钉子")
check(nailRow.pinned ~= true, "初始钉子未被置顶")
local pinTitle = details.pinButton.title
check(pinTitle == getText("IGUI_EmberRoutesProbe_Settlement_pin") or pinTitle == "★ 收藏置顶", "置顶按钮初始显示 '★ 收藏置顶'")

-- 6.1 模拟玩家点击“★ 置顶”按钮
details.pinButton.onclick(details.pinButton.target)
check(details.row.pinned == true, "点击后 details.row.pinned 置为 true")
check(page.pinnedItems["Base.Nails"] == true, "页面 pinnedItems 注册钉子置顶状态")
local unpinTitle = details.pinButton.title
check(unpinTitle == getText("IGUI_EmberRoutesProbe_Settlement_unpin") or unpinTitle == "取消置顶", "置顶按钮文字更新为 '取消置顶'")
check(page.itemGrid.cells[1].fullType == "Base.Nails", "网格视图中 Base.Nails 同步跃居第一个方格！")

-- 6.2 模拟玩家再次点击“取消置顶”按钮
details.pinButton.onclick(details.pinButton.target)
check(details.row.pinned == false, "再次点击后 details.row.pinned 置为 false")
check(page.pinnedItems["Base.Nails"] == false, "页面 pinnedItems 解除钉子置顶")
check(details.pinButton.title == getText("IGUI_EmberRoutesProbe_Settlement_pin") or details.pinButton.title == "★ 收藏置顶", "按钮文字恢复为 '★ 收藏置顶'")
check(page.itemGrid.cells[1].fullType == "Base.WoodenFork", "取消置顶后列表恢复原排序，木制餐叉回归第一位")
check(page.itemGrid.cells[2].fullType == "Base.Nails", "钉子回归第二位")

print("  -> Step 6 PASS: 置顶与取消置顶、列表/网格首位重排与按钮标题流转验证通过")

-- =============================================================================
-- 7. AE2 风格来源仓库双击加购与精简右下角按钮
-- =============================================================================
print("\n[Step 7] 验证 AE2 风格来源行双击加购、右下角冗余按钮精简与可制作标记...")

-- 7.1 验证双击来源仓库行直接加入待送清单
page:selectItem(nailRow)
page:clearDeliveryCart()
page.details:onSourceDoubleClick(1)
local nailSourceKey = "Base.Nails:" .. nailRow.sources[1].id
check(page.deliveryCart[nailSourceKey] ~= nil, "双击来源行成功加入配送清单")
check(page.deliveryCart[nailSourceKey].count == 1, "双击加购数量为 1")
check(page.deliveryCart[nailSourceKey].source ~= nil and page.deliveryCart[nailSourceKey].source.id == nailRow.sources[1].id, "加购记录准确绑定选中来源容器")

-- 7.2 验证精简右下角：移除冗余按钮，保留定位来源
check(page.details.locate ~= nil, "保留定位来源按钮")
check(page.details.cartButton == nil, "【用户要求】物理移除冗余 '+待送' 按钮")
check(page.details.maintainStock == nil, "【用户要求】物理移除冗余 '生产委托' 按钮")
check(page.details.craftButton == nil, "【用户要求】物理移除冗余 '发起制作' 按钮")

-- 7.3 验证 AE2 制作标识
check(page.itemGrid.cells[1] ~= nil, "网格方格存在")
check(page.itemGrid.cells[1].craftable ~= nil, "方格元数据包含 craftable 标记")

print("  -> Step 7 PASS: AE2 风格双击来源加购、右下角冗余按钮精简与可制作标记验证通过")

-- =============================================================================
-- 8. 跳转公共委托下单
-- =============================================================================
print("\n[Step 8] 验证详情面板按钮、网格双击与手柄快捷键跳转公共委托下单...")

local orderOpenedCalls = {}
shell.openPublicOrder = function(self, ctx)
    orderOpenedCalls[#orderOpenedCalls + 1] = ctx
end

-- 8.1 验证不可制造物品中键严格阻断（不跳转委托、不误加待送清单、给出明确提示）
local uncraftableCell = page.itemGrid.cells[1]
check(uncraftableCell.craftable == false, "木制餐叉方格初始为不可制造状态")
page:clearDeliveryCart()
page.itemGrid:onMouseButtonDown(2, uncraftableCell.x + 2, uncraftableCell.y + 2)
check(#orderOpenedCalls == 0, "不可制造物品中键点击严格阻断，未触发公共委托下单")
check(page.deliveryCart[uncraftableCell.fullType] == nil, "不可制造物品中键点击严格不加入待送清单（职责完全正交）")
check(page.notice == getText("IGUI_EmberRoutesProbe_Warehouse_notCraftable"), "不可制造物品中键点击弹出准确的不可制造提示")

-- 8.2 验证可制造物品中键点击跳转公共委托下单制作页面
local nailCell = page.itemGrid.cells[2]
nailCell.craftable = true -- 模拟工单制作目录收录钉子
page.itemGrid:onMouseButtonDown(2, nailCell.x + 2, nailCell.y + 2)
check(#orderOpenedCalls == 1, "可制造物品中键点击方格成功触发公共委托下单制作调用")
check(orderOpenedCalls[1].productType == nailCell.fullType, "公共委托携带准确的目标产品 fullType (Base.Nails)")

-- 8.3 模拟玩家在 AE2 方格网格视图中双击方格加入配送清单 (AE2 风格加购保持不变)
local hammerCell = nil
for _, c in ipairs(page.itemGrid.cells) do
    if c.fullType == "Base.Hammer" then hammerCell = c end
end
check(hammerCell ~= nil, "找到铁锤网格单元")
hammerCell.craftable = true
page:clearDeliveryCart()
page.itemGrid:onMouseDoubleClick(hammerCell.x + 2, hammerCell.y + 2)
check(page.deliveryCart["Base.Hammer"] ~= nil, "网格双击操作直接加入配送清单 (AE2 风格加购保持不变)")
check(page.deliveryCart["Base.Hammer"].count == 1, "双击加购数量准确为 1")

-- 8.4 模拟玩家使用游戏手柄选中可制作方格并按下 X 键 (Joypad.XButton 快捷下单)
page.itemGrid.selected = hammerCell.index
page.itemGrid:onJoypadDown(Joypad.XButton)
check(#orderOpenedCalls == 2, "手柄 X 键快捷操作成功触发委托下单")
check(orderOpenedCalls[2].productType == "Base.Hammer", "手柄快捷下单携带当前选中的 Base.Hammer")

print("  -> Step 8 PASS: 详情面板按钮、方格双击与手柄快捷键触发公共委托下单验证通过")

-- =============================================================================
-- 全流程完成结算
-- =============================================================================
shell:close()
check(shell.disposed == true, "测试结束后统一面板正确释放并关闭")

print("\n================================================================================")
print("恭喜！【Track A: 仓储与物流交互全旅程】全部 8 项玩家操作流程测试全部 PASS！")
print("累计执行断言校验数: " .. checks)
print("================================================================================")
