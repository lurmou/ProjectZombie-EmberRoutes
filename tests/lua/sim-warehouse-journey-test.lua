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
    Say = function() end
}
function getSpecificPlayer() return mockActor end

local mockRoot = {}
local mockSettlement = { id = "settlement_alpha", name = "余烬根据地" }
local settlements = { settlement_alpha = mockSettlement }
package.loaded['EmberRoutesProbe/SettlementLedger'] = {
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
package.loaded['EmberRoutesProbe/WarehouseIndex'] = {
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
package.loaded['EmberRoutesProbe/WarehouseLocator'] = {
    new = function()
        return {
            clear = function() locatorClears = locatorClears + 1 end,
            locate = function(_, sourceId) return mockLocatorPos, "located" end
        }
    end
}
package.loaded['EmberRoutesProbe/UI/TooltipAnchor'] = { attach = function() end, clear = function() end }

-- Global PublicOrder recording spy
local publicOrderCalls = {}
package.loaded['EmberRoutesProbe/PublicWork'] = {
    available = function() return true end,
    create = function(_, scope, recipe, n, surface, token)
        publicOrderCalls[#publicOrderCalls + 1] = { scope = scope, recipe = recipe, n = n, surface = surface }
        return 'ORDER_CREATED'
    end,
    rule = function() return { minimum = 50, batch = 10 } end,
}

-- Module references
local Query = require "EmberRoutesProbe/WarehouseQuery"
local PinyinHelper = require "EmberRoutesProbe/PinyinHelper"
local LiquidRegistry = require "EmberRoutesProbe/LiquidRegistry"
local Dashboard = require "EmberRoutesProbe/SettlementDashboard"
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
local shell = Dashboard.open(mockActor, mockSettlement.id)
check(shell ~= nil, "据点管理面板成功打开")
check(shell.activeTab == "warehouse", "主导航默认选中并在初始加载 warehouse 仓储标签页")
local page = shell.pages.warehouse
check(page ~= nil, "仓储页面实例成功构建")
check(page.active == true, "仓储页面处于激活生命周期")
check(page.visible == true, "仓储页面处于可见状态")
check(page.width <= screenW and page.height <= screenH, "仓储主页面在 1080p 下完全容纳于屏幕")
check(page.summary ~= nil and page.summary.bounds.width > 0, "Summary 概览区完成布局")
check(page.controls ~= nil and page.controls.search ~= nil, "Controls 搜索与筛选区完成布局")
check(page.itemList ~= nil and page.itemList.width > 0, "ItemList 列表视图完成布局")
check(page.itemGrid ~= nil and page.itemGrid.width > 0, "ItemGrid 网格视图完成布局")
check(page.details ~= nil and page.details.hero ~= nil, "WarehouseDetails 详情面板完成布局")
check(page.pad == math.ceil(fontHeight * 0.6), "标准分辨率下使用正常内边距")
check(page.details.compact == false, "标准分辨率下详情面板处于标准 (非紧凑) 布局模式")

-- 1.2 紧凑小分辨率自适应布局 (如 800x480 或 4K 大字体)
shell:close()
screenW, screenH = 800, 480
local shellCompact = Dashboard.open(mockActor, mockSettlement.id)
local pageCompact = shellCompact.pages.warehouse
check(pageCompact.width <= 800 and pageCompact.height <= 480, "仓储主页面在 800x480 下自适应缩放无溢出")
check(pageCompact.pad == math.ceil(fontHeight * 0.35), "紧凑分辨率下自适应收缩内边距以保证可视密度")
check(pageCompact.details.compact == true, "小分辨率下详情面板自适应切换为紧凑 (compact) 三口径横向布局")
shellCompact:close()

-- 恢复标准 1080p 用于后续完整交互流程
screenW, screenH = 1920, 1080
shell = Dashboard.open(mockActor, mockSettlement.id)
page = shell.pages.warehouse

print("  -> Step 1 PASS: 默认加载仓储主页及 1080p / 768p 响应式自适应布局验证通过")

-- =============================================================================
-- 2. 视图切换 (Grid vs List)
-- =============================================================================
print("\n[Step 2] 验证视图切换按钮交互 (Grid vs List 互斥与按钮更新)...")

-- 2.1 初始默认状态：AE2 风格网格视图
check(page.viewMode == "grid", "初始默认视图模式为 'grid' 网格视图")
check(page.itemGrid.visible == true, "网格组件处于可见状态")
check(page.itemList.visible == false, "列表组件处于隐藏状态 (互斥展示)")
local initialBtnTitle = page.controls.viewToggle.title
check(initialBtnTitle == getText("IGUI_EmberRoutesProbe_Settlement_viewGrid") or initialBtnTitle == "⊞ 网格", "按钮初始标题显示 '⊞ 网格'")
check(page.controls.viewToggle.tooltip == getText("IGUI_EmberRoutesProbe_Settlement_viewToggleHint"), "按钮提示文本正确匹配 viewToggleHint")

-- 2.2 模拟玩家点击右上角视图切换按钮 (切换到 ☰ 列表)
page.controls.viewToggle.onclick(page.controls.viewToggle.target)
check(page.viewMode == "list", "点击后 self.viewMode 正确切换为 'list'")
check(page.itemGrid.visible == false, "网格组件变为隐藏")
check(page.itemList.visible == true, "列表组件变为可见 (互斥展示)")
local listBtnTitle = page.controls.viewToggle.title
check(listBtnTitle == getText("IGUI_EmberRoutesProbe_Settlement_viewList") or listBtnTitle == "☰ 列表", "按钮标题动态更新为 '☰ 列表'")
check(page.controls.viewToggle.tooltip == getText("IGUI_EmberRoutesProbe_Settlement_viewToggleHint"), "提示信息依然正确保持")

-- 2.3 模拟玩家再次点击按钮 (切回 ⊞ 网格)
page.controls.viewToggle.onclick(page.controls.viewToggle.target)
check(page.viewMode == "grid", "再次点击后 self.viewMode 恢复为 'grid'")
check(page.itemGrid.visible == true, "网格组件重新可见")
check(page.itemList.visible == false, "列表组件重新隐藏")
check(page.controls.viewToggle.title == getText("IGUI_EmberRoutesProbe_Settlement_viewGrid") or page.controls.viewToggle.title == "⊞ 网格", "按钮标题恢复为 '⊞ 网格'")

print("  -> Step 2 PASS: 视图切换网格/列表互斥渲染、标题与提示动态更新验证通过")

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
check(#page.itemList.items == 5, "全量数据装载后显示 5 种物品")
check(#page.itemGrid.cells == 5, "网格视图同步装载 5 个方格")

-- 3.1 模拟玩家在搜索框输入 "mfc" -> 匹配 Base.WoodenFork (木制餐叉)
page.search:setText("mfc")
check(#page.itemList.items == 1, "输入 'mfc' 精准过滤出 1 个物品")
check(page.itemList.items[1].item.value.fullType == "Base.WoodenFork", "输入 'mfc' 准确检索出 Base.WoodenFork (木制餐叉)")
check(#page.itemGrid.cells == 1 and page.itemGrid.cells[1].fullType == "Base.WoodenFork", "网格视图同步仅显示木制餐叉")
check(page.controls.clear.enable == true, "搜索框有内容时清除按钮被启用")

-- 3.2 模拟玩家在搜索框输入 "dz" -> 匹配 Base.Nails (钉子)
page.search:setText("dz")
check(#page.itemList.items == 1, "输入 'dz' 精准过滤出 1 个物品")
check(page.itemList.items[1].item.value.fullType == "Base.Nails", "输入 'dz' 准确检索出 Base.Nails (钉子)")
check(#page.itemGrid.cells == 1 and page.itemGrid.cells[1].fullType == "Base.Nails", "网格视图同步仅显示钉子")

-- 3.3 模拟玩家在搜索框输入 "hammer" -> 匹配 Base.Hammer (铁锤)
page.search:setText("hammer")
check(#page.itemList.items == 1, "输入 'hammer' 精准过滤出 1 个物品")
check(page.itemList.items[1].item.value.fullType == "Base.Hammer", "输入 'hammer' 准确检索出 Base.Hammer (铁锤)")
check(#page.itemGrid.cells == 1 and page.itemGrid.cells[1].fullType == "Base.Hammer", "网格视图同步仅显示铁锤")

-- 3.4 模拟玩家点击“清除”按钮
page.controls.clear.onclick(page.controls.clear.target)
check(page.search:getText() == "", "点击清除按钮后搜索框内容被清空")
check(#page.itemList.items == 5, "列表全量恢复显示 5 种物品")
check(#page.itemGrid.cells == 5, "网格全量恢复显示 5 个方格")
check(page.controls.clear.enable == false, "搜索框为空时清除按钮自动禁用")

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
check(#page.itemList.items == 4, "选择 'tools' 后只显示 4 种工具类物品")
for _, entry in ipairs(page.itemList.items) do
    check(entry.item.value.node == "tools", "过滤后的所有物品所属类别均为 tools: " .. entry.item.value.fullType)
end

-- 4.2 切换为“食物”
page.categories.selected = foodOptionIdx
page:queryChanged()
check(#page.itemList.items == 1, "选择 'food' 后只显示 1 种食物物品")
check(page.itemList.items[1].item.value.fullType == "Base.Apple", "食物分类仅显示 Base.Apple")

-- 4.3 切回“全部类别”
page.categories.selected = 1
page:queryChanged()
check(#page.itemList.items == 5, "切回全部类别后全量恢复 5 种物品")

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
check(page.itemList.items[1].item.value.fullType == "Base.WoodenFork", "初始第一项为木制餐叉")
check(page.itemList.items[2].item.value.fullType == "Base.Nails", "初始第二项为钉子")
check(nailRow.pinned ~= true, "初始钉子未被置顶")
local pinTitle = details.pinButton.title
check(pinTitle == getText("IGUI_EmberRoutesProbe_Settlement_pin") or pinTitle == "★ 收藏置顶", "置顶按钮初始显示 '★ 收藏置顶'")

-- 6.1 模拟玩家点击“★ 置顶”按钮
details.pinButton.onclick(details.pinButton.target)
check(details.row.pinned == true, "点击后 details.row.pinned 置为 true")
check(page.pinnedItems["Base.Nails"] == true, "页面 pinnedItems 注册钉子置顶状态")
local unpinTitle = details.pinButton.title
check(unpinTitle == getText("IGUI_EmberRoutesProbe_Settlement_unpin") or unpinTitle == "取消置顶", "置顶按钮文字更新为 '取消置顶'")
check(page.itemList.items[1].item.value.fullType == "Base.Nails", "列表重新排序后，置顶物品 Base.Nails 跃居列表第一项！")
check(page.itemGrid.cells[1].fullType == "Base.Nails", "网格视图中 Base.Nails 同步跃居第一个方格！")

-- 6.2 模拟玩家再次点击“取消置顶”按钮
details.pinButton.onclick(details.pinButton.target)
check(details.row.pinned == false, "再次点击后 details.row.pinned 置为 false")
check(page.pinnedItems["Base.Nails"] == false, "页面 pinnedItems 解除钉子置顶")
check(details.pinButton.title == getText("IGUI_EmberRoutesProbe_Settlement_pin") or details.pinButton.title == "★ 收藏置顶", "按钮文字恢复为 '★ 收藏置顶'")
check(page.itemList.items[1].item.value.fullType == "Base.WoodenFork", "取消置顶后列表恢复原排序，木制餐叉回归第一位")
check(page.itemList.items[2].item.value.fullType == "Base.Nails", "钉子回归第二位")

print("  -> Step 6 PASS: 置顶与取消置顶、列表/网格首位重排与按钮标题流转验证通过")

-- =============================================================================
-- 7. 世界固定家具液体扫描与水质
-- =============================================================================
print("\n[Step 7] 验证固定家具液体扫描 (仅限雨水桶/水槽/马桶)、移动容器过滤与停水前后水质...")

-- 构建真实测试世界物体
local mockRainBarrel = {
    category = "RainCollectorBarrel",
    waterAmount = 80.0,
    tainted = true,
    hasWater = true,
    x = 15, y = 25, z = 0
}
local mockSink = {
    category = "Sink",
    waterAmount = 20.0,
    tainted = false,
    hasWater = true,
    x = 10, y = 20, z = 0
}
local mockToilet = {
    category = "Toilet",
    waterAmount = 15.0,
    tainted = false,
    hasWater = true,
    x = 10, y = 21, z = 0
}

-- 地面散落的移动物体（必须被严格忽略）
local mockGroundBucket = {
    isWorldItem = true,
    category = "RainCollectorBarrel",
    waterAmount = 10.0
}
local mockLooseWaterBucket = {
    getItem = function() return { getName = function() return "Water Bucket" end } end
}
local mockLooseWaterBottle = {
    isItem = true,
    category = "Sink",
    waterAmount = 5.0
}
local mockLooseKettle = {
    isItem = true,
    getName = function() return "Kettle" end,
    waterAmount = 3.0
}

-- 7.1 验证 LiquidRegistry 严格只扫描固定家具，彻底拒绝地面散落水桶水壶
check(LiquidRegistry.classify(mockRainBarrel) == "RainCollectorBarrel", "雨水桶被正确识别为固定储水设施")
check(LiquidRegistry.classify(mockSink) == "Sink", "洗手台/水槽被正确识别为固定供水家具")
check(LiquidRegistry.classify(mockToilet) == "Toilet", "马桶被正确识别为固定家具")
check(LiquidRegistry.classify(mockGroundBucket) == nil, "地面散落水桶被严格拒绝 (返回 nil)")
check(LiquidRegistry.classify(mockLooseWaterBucket) == nil, "松散移动水桶被严格拒绝 (返回 nil)")
check(LiquidRegistry.classify(mockLooseWaterBottle) == nil, "地面水瓶被严格拒绝 (返回 nil)")
check(LiquidRegistry.classify(mockLooseKettle) == nil, "散落水壶被严格拒绝 (返回 nil)")

local testSquare = {
    objects = {
        mockRainBarrel,
        mockSink,
        mockToilet,
        mockGroundBucket,
        mockLooseWaterBucket,
        mockLooseWaterBottle,
        mockLooseKettle
    }
}
local scannedSources = LiquidRegistry.scanSquare(testSquare)
check(#scannedSources == 3, "扫描包含 7 个物体的地块，严格仅识别出 3 个固定家具，完全忽略全部 4 个地面散落物品！")

-- 7.2 模拟未停水状态 (Municipal Water ON)
local mockWaterShut = false
_G.getGameTime = function()
    return {
        isWaterShutOff = function() return mockWaterShut end,
        getNights = function() return 1 end,
        getWorldAgeHours = function() return 24 end
    }
end

local sumOn = LiquidRegistry.summary(LiquidRegistry.scanSquare(testSquare))
check(sumOn.isInfinite == true, "未停水状态下市政水源洗手台/马桶具备无限水供给")
check(sumOn.displayClean == "无限 (∞)", "纯净水总览显示为 '无限 (∞)'")
check(sumOn.taintedAmount == 80.0, "雨水桶独立统计为 80L 污染水")

for _, s in ipairs(sumOn.sources) do
    if s.kind == "Sink" or s.kind == "Toilet" then
        check(s.isInfinite == true and s.displayAmount == "无限 (∞)", s.kind .. " 未停水前显示无限 (∞)")
        check(s.isTainted == false, s.kind .. " 市政自来水质纯净")
    elseif s.kind == "RainCollectorBarrel" then
        check(s.isInfinite == false and s.amount == 80.0, "雨水桶收集自然降水，无论停水与否均为 80L 有限存量")
        check(s.isTainted == true, "雨水桶水质为污染水质")
    end
end

-- 7.3 模拟停水后状态 (Municipal Water Shut Off)
mockWaterShut = true
local sumOff = LiquidRegistry.summary(LiquidRegistry.scanSquare(testSquare))
check(sumOff.isInfinite == false, "停水后失去无限供给，转为残留真实升数")
check(sumOff.cleanAmount == 35.0, "洗手台 (20L) + 马桶 (15L) 合计纯净水真实残留 35.0L")
check(sumOff.taintedAmount == 80.0, "雨水桶保持 80.0L 污染水")
check(sumOff.totalFinite == 115.0, "停水后据点总物理储水量严格为 115.0L")
check(sumOff.displayClean == "35.0", "纯净水显示真实升数 35.0")
check(sumOff.displayTainted == "80.0", "污染水显示真实升数 80.0")

for _, s in ipairs(sumOff.sources) do
    if s.kind == "Sink" then
        check(s.isInfinite == false and s.amount == 20.0 and s.displayAmount == "20.0", "水槽停水后准确显示管网残留 20.0L")
        check(s.isTainted == false and s.displayQuality:find("Clean", 1, true) ~= nil or s.displayQuality:find("纯净", 1, true) ~= nil, "水槽水质保持纯净")
    elseif s.kind == "Toilet" then
        check(s.isInfinite == false and s.amount == 15.0 and s.displayAmount == "15.0", "马桶停水后准确显示水箱残留 15.0L")
        check(s.isTainted == false, "马桶水箱水质保持纯净")
    elseif s.kind == "RainCollectorBarrel" then
        check(s.amount == 80.0 and (s.displayQuality:find("Tainted", 1, true) ~= nil or s.displayQuality:find("污染", 1, true) ~= nil), "雨水桶显示污染水质")
    end
end

print("  -> Step 7 PASS: 固定家具严格扫描、地面容器忽略、停水前无限(∞)与停水后残留升数/水质分立验证通过")

-- =============================================================================
-- 8. 跳转公共委托下单
-- =============================================================================
print("\n[Step 8] 验证详情面板按钮、网格双击与手柄快捷键跳转公共委托下单...")

local orderOpenedCalls = {}
shell.openPublicOrder = function(self, ctx)
    orderOpenedCalls[#orderOpenedCalls + 1] = ctx
end

-- 8.1 模拟玩家在详情面板点击“下单 (Create Order)”按钮
page:selectItem(nailRow)
check(details.maintainStock.enable == true, "选中钉子后委托下单按钮处于可用状态")
details.maintainStock.onclick(details.maintainStock.target)
check(#orderOpenedCalls == 1, "点击下单按钮成功触发公共委托下单调用")
check(orderOpenedCalls[1].productType == "Base.Nails", "公共委托携带准确的目标产品 fullType: Base.Nails")

-- 8.2 模拟玩家在 AE2 方格网格视图中快速双击某个方格 (如双击铁锤方格)
local hammerCell = nil
for _, c in ipairs(page.itemGrid.cells) do
    if c.fullType == "Base.Hammer" then hammerCell = c end
end
check(hammerCell ~= nil, "找到铁锤网格单元")
-- 第一次点击：选中方格
page.itemGrid:onMouseDown(hammerCell.x + 2, hammerCell.y + 2)
check(page.itemGrid.selected == hammerCell.index, "单击成功选中铁锤方格")
-- 第二次点击 (30ms 后快速连击)：触发公共委托
simulatedTimeMs = simulatedTimeMs + 30
page.itemGrid:onMouseDown(hammerCell.x + 2, hammerCell.y + 2)
check(#orderOpenedCalls == 2, "网格双击操作无缝联动触发委托下单")
check(orderOpenedCalls[2].productType == "Base.Hammer", "双击委托携带目标产品 Base.Hammer")

-- 8.3 模拟玩家使用游戏手柄选中方格并按下 X 键 (Joypad.XButton)
page.itemGrid:onJoypadDown(Joypad.XButton)
check(#orderOpenedCalls == 3, "手柄 X 键快捷操作成功触发委托下单")
check(orderOpenedCalls[3].productType == "Base.Hammer", "手柄快捷下单携带当前选中的 Base.Hammer")

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
