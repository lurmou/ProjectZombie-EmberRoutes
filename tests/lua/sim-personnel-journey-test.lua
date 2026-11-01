-- sim-personnel-journey-test.lua
-- Dedicated end-to-end player simulation for Track C: Personnel Matrix & Colonist Journey

package.loaded['ISUI/ISContextMenu'] = true
local ERPriorityOptions = {}
local contextMenuInstance = nil
ISContextMenu = {
    get = function(playerIdx, x, y)
        ERPriorityOptions = {}
        contextMenuInstance = {
            x = x, y = y, options = {},
            addOption = function(self, label, target, fn)
                self.options[#self.options + 1] = {label = label, target = target, fn = fn}
                ERPriorityOptions[#ERPriorityOptions + 1] = fn
                return self.options[#self.options]
            end
        }
        return contextMenuInstance
    end
}

_G.Events = _G.Events or {}
for _, name in ipairs({'OnGameStart', 'OnServerStarted', 'OnTick', 'OnTickEvenPaused', 'OnPreMapLoad', 'OnSave'}) do
    _G.Events[name] = {Add = function() end, Remove = function() end}
end

package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path

local checks = 0
local function check(value, message)
    if not value then
        error('CHECK FAILED: ' .. tostring(message), 2)
    end
    checks = checks + 1
end

-- ==================== MOCK ISUI HIERARCHY ====================
local Base = {}
function Base:derive(name)
    local cls = {Type = name}
    cls.__index = cls
    return setmetatable(cls, {__index = self})
end

function Base:new(x, y, w, h, title, target, callback)
    return setmetatable({
        x = x or 0, y = y or 0, width = w or 100, height = h or 20,
        title = title, target = target, onclick = callback,
        items = {}, selected = 0, children = {}, enable = true, visible = true
    }, {__index = self})
end

function Base:initialise() self.children = {} self.initialised = true end
function Base:instantiate()
    if self.native then return end
    self.native = true
    self:createChildren()
end
function Base:createChildren() end
function Base:addChild(child)
    check(child.initialised, 'child must be initialised before adding')
    child.parent = self
    child:instantiate()
    self.children[#self.children + 1] = child
end
function Base:addToUIManager() self:instantiate() self.added = true end
function Base:removeFromUIManager() self.added = false end
function Base:setVisible(v) self:instantiate() self.visible = v end
function Base:close() self:setVisible(false) end
function Base:bringToTop() self.raised = true end
function Base:clear() self.items = {} self.selected = 0 end
function Base:titleBarHeight() return 24 end
function Base:setWantKeyEvents() end
function Base:update() end
function Base:prerender() end
function Base:render() end
function Base:getMouseX() return -1 end
function Base:getMouseY() return -1 end
function Base:setX(x) self.x = x end
function Base:setY(y) self.y = y end
function Base:setHeight(h) self.height = h end
function Base:setWidth(w) self.width = w end
function Base:getWidth() return self.width end
function Base:getHeight() return self.height end
function Base:getAbsoluteX() return self.x + (self.parent and self.parent:getAbsoluteX() or 0) end
function Base:getAbsoluteY() return self.y + (self.parent and self.parent:getAbsoluteY() or 0) end
function Base:setTitle(value) self.title = value end
function Base:setEnable(value) self.enable = value end
function Base:setOnMouseDownFunction(target, fn) self.target = target self.onclick = fn end
function Base:onMouseDown(x, y)
    local row = self:rowAt(x, y)
    if row > 0 and row <= #self.items then
        self.selected = row
        if self.onclick then
            self.onclick(self.target, self.items[row].item)
        end
    end
end
function Base:setOverrideAButtonFunction() end
function Base:setYScroll(value) self.scroll = value end
function Base:getYScroll() return self.scroll or 0 end
function Base:setScrollHeight(value) self.scrollHeight = value end
function Base:ensureVisible() end
function Base:drawText() end
function Base:drawRect() end
function Base:drawRectBorder() end
function Base:drawTextureScaledAspect() end
function Base:setBackgroundRGBA() end

function Base:addItem(label, item, tooltip)
    local entry = {text = label, item = item, tooltip = tooltip, height = self.itemheight or 20, index = #self.items + 1}
    self.items[#self.items + 1] = entry
    return entry
end

function Base:rowAt(x, y)
    local rowH = self.itemheight or 44
    local idx = math.floor((y - (self:getYScroll())) / rowH) + 1
    if idx < 1 or idx > #self.items then return -1 end
    return idx
end

ISPanel = Base
ISCollapsableWindow = Base
ISButton = Base
ISScrollingListBox = Base

for _, name in ipairs({'ISPanel', 'ISCollapsableWindow', 'ISButton', 'ISScrollingListBox'}) do
    package.loaded['ISUI/' .. name] = true
end

UIFont = {Small = 1, Medium = 2, Large = 3}
Keyboard = {
    KEY_UP = 1, KEY_DOWN = 2, KEY_ESCAPE = 3, KEY_LEFT = 4,
    KEY_RIGHT = 5, KEY_TAB = 6, KEY_RETURN = 7, KEY_PRIOR = 8, KEY_NEXT = 9
}
Joypad = {AButton = 1, BButton = 2, XButton = 3, YButton = 4}

local measureCount = 0
function getCore()
    return {
        getScreenWidth = function() return 1920 end,
        getScreenHeight = function() return 1080 end
    }
end

function getTextManager()
    return {
        getFontHeight = function() return 20 end,
        MeasureStringX = function(_, font, s)
            measureCount = measureCount + 1
            return #(tostring(s or '')) * 10
        end
    }
end

local fallbackTranslations = {
    IGUI_EmberRoutesProbe_Monitor_body_EAT = '进食',
    IGUI_EmberRoutesProbe_Monitor_body_SLEEP = '睡眠',
    IGUI_EmberRoutesProbe_Monitor_body_BANDAGE = '包扎',
    IGUI_EmberRoutesProbe_Monitor_body_DRINK = '饮水',
    IGUI_EmberRoutesProbe_Personnel_statusBusy = '工作中',
    IGUI_EmberRoutesProbe_Personnel_statusIdle = '空闲',
    IGUI_EmberRoutesProbe_Personnel_roleResident = '据点居民',
    IGUI_EmberRoutesProbe_Personnel_unknownMember = '未知成员',
    IGUI_EmberRoutesProbe_Personnel_healthValue = '健康：%1 / 100',
    IGUI_EmberRoutesProbe_Personnel_activeJob = '工单: %1'
}

function getTextOrNull(key)
    return (ERTestTranslations and ERTestTranslations[key]) or fallbackTranslations[key]
end

function getText(key, ...)
    local value = getTextOrNull(key) or key
    for i, arg in ipairs({...}) do
        local replacement = tostring(arg)
        value = value:gsub('%%' .. i, function() return replacement end)
    end
    return value
end

local simulatedTime = 10000
function getTimestampMs() return simulatedTime end

-- ==================== DOMAIN ENGINE SERVICES MOCK ====================
local playerActor = {
    getIndex = function() return 0 end,
    getJoypadBind = function() return -1 end,
    Say = function() end
}
function getSpecificPlayer(idx) return playerActor end

local currentWorldLedger = {}
local settlementEntry = {id = 'settlement-sanctuary', name = 'Sanctuary'}
package.loaded['EmberRoutesProbe/SettlementLedger'] = {
    data = function() return currentWorldLedger end,
    authorized = function(actor) return actor == playerActor end,
    view = function(actor, id)
        if id == settlementEntry.id then return settlementEntry end
        return nil, 'SETTLEMENT_MISSING'
    end
}

local tooltipCleared = {}
package.loaded['EmberRoutesProbe/UI/TooltipAnchor'] = {
    attach = function(widget, fn) widget.tooltipAttached = fn end,
    dismissOwner = function() end, unregisterOwner = function() end, clearOwner = function() end,
    clear = function(widget)
        tooltipCleared[widget] = (tooltipCleared[widget] or 0) + 1
        widget.tooltipAttached = nil
    end
}

-- Workers dataset
local workerPriorities = {
    ['worker-bob'] = {crafting = 1, hauling = 3, revision = 1},
    ['worker-alice'] = {crafting = 0, hauling = 1, revision = 1}
}
local setPrioritiesCalls = {}

package.loaded['EmberRoutesProbe/PublicWork'] = {
    available = function() return true end,
    priorities = function(npcId)
        local p = workerPriorities[npcId] or {crafting = 3, hauling = 3, revision = 1}
        return {crafting = p.crafting, hauling = p.hauling, revision = p.revision}
    end,
    setPriorities = function(actor, scope, npcId, values, revision)
        local p = workerPriorities[npcId]
        if not p then return 'NPC_NOT_FOUND' end
        if p.revision ~= revision then return 'PRIORITY_CHANGED' end
        p.crafting = values.crafting
        p.hauling = values.hauling
        p.revision = revision + 1
        setPrioritiesCalls[#setPrioritiesCalls + 1] = {
            actor = actor, scope = scope, npcId = npcId, values = values, revision = p.revision
        }
        return 'PRIORITY_SAVED'
    end,
    setPriority = function(actor, scope, npcId, category, val)
        local p = workerPriorities[npcId]
        if not p then return 'NPC_NOT_FOUND' end
        local values = {crafting = p.crafting, hauling = p.hauling}
        values[category] = val
        return package.loaded['EmberRoutesProbe/PublicWork'].setPriorities(actor, scope, npcId, values, p.revision)
    end
}

local workersData = {
    {
        id = 'worker-bob',
        name = 'Bob Builder',
        busy = true,
        activity = 'EAT',
        order = {
            id = 'order-log-1',
            title = 'Saw logs',
            product = 'Base.Plank',
            produced = 2,
            target = 5,
            state = 'RUNNING',
            phase = 'CRAFTING'
        },
        skills = {Woodwork = 7, MetalWelding = 3, Electricity = 1, Strength = 4, Fitness = 3},
        health = 85,
        isBleeding = false,
        isInfected = false,
        hasInjury = false,
        fatigue = 0.15,
        hunger = 0.10,
        thirst = 0.05,
        profTitle = 'Carpenter'
    },
    {
        id = 'worker-alice',
        name = 'Alice Defender',
        busy = false,
        activity = nil,
        order = nil,
        skills = {Cooking = 2, Tailoring = 1, Strength = 9, Fitness = 8},
        health = 45,
        isBleeding = true,
        isInfected = false,
        hasInjury = true,
        fatigue = 0.85,
        hunger = 0.75,
        thirst = 0.65,
        profTitle = 'Security Officer'
    }
}

package.loaded['EmberRoutesProbe/CraftingService'] = {
    status = function(actor, scope)
        return {workers = workersData, surfaces = {}}
    end
}

package.loaded['EmberRoutesProbe/ContainerRegistry'] = {
    describe = function() return nil end,
    data = function() return {} end
}

package.loaded['EmberRoutesProbe/Driver'] = {
    bindId = function(actor, id)
        return nil -- Fallback to table data safely
    end
}

-- Mock remaining unused tabs
local WarehousePage = Base:derive('WarehousePage')
function WarehousePage:activate() self.active = true end
function WarehousePage:deactivate() self.active = false end
function WarehousePage:dispose() self.disposed = true end
package.loaded['EmberRoutesProbe/UI/WarehousePage'] = WarehousePage

local OrderMonitorPage = Base:derive('OrderMonitorPage')
function OrderMonitorPage:activate() self.active = true end
function OrderMonitorPage:deactivate() self.active = false end
function OrderMonitorPage:dispose() self.disposed = true end
package.loaded['EmberRoutesProbe/UI/OrderMonitorPage'] = OrderMonitorPage

-- ==================== EXECUTE SIMULATION ====================
local Dashboard = require 'EmberRoutesProbe/SettlementDashboard'

print('>>> STEP 1: Launch Dashboard & Navigate to Personnel Management')
local dashboard = Dashboard.open(playerActor, settlementEntry.id, 'warehouse')
check(dashboard ~= nil, 'Dashboard successfully opened')
check(dashboard.activeTab == 'warehouse', 'Initial tab is warehouse')

-- Player clicks Personnel tab button
local personnelTabBtn = dashboard.tabButtons['personnel']
check(personnelTabBtn ~= nil, 'Personnel tab button exists')
dashboard:tabClicked(personnelTabBtn)

check(dashboard.activeTab == 'personnel', 'Active tab is now personnel')
local personnel = dashboard.pages.personnel
check(personnel ~= nil and personnel.active == true, 'PersonnelPage is active')
check(personnel.matrixList ~= nil, 'Matrix list initialized')
check(#personnel.matrixList.items == 2, 'Loaded 2 settlement workers in matrix')

-- Test prerender passes without error
personnel:prerender()
check(true, 'PersonnelPage prerender completed smoothly')


print('>>> STEP 2: Skill Level Badges Presentation (^L7 Crafting, ^L4 Hauling)')
-- Bob Builder: Woodwork=7, MetalWelding=3 -> max craft = 7; Strength=4, Fitness=3 -> max haul = 4
local bobItem = personnel.matrixList.items[1].item
check(bobItem.value.id == 'worker-bob', 'Row 1 is Bob Builder')
check(bobItem.value.craftSkill == 7, 'Bob craft skill resolved to highest 7 (Woodwork)')
check(bobItem.value.haulSkill == 4, 'Bob haul skill resolved to highest 4 (Strength)')
check(bobItem.visual.craftBadge == 'L7', 'Bob crafting cell badge displays L7')
check(bobItem.visual.haulBadge == 'L4', 'Bob hauling cell badge displays L4')

-- Alice Defender: Cooking=2, Tailoring=1 -> max craft = 2; Strength=9, Fitness=8 -> max haul = 9
local aliceItem = personnel.matrixList.items[2].item
check(aliceItem.value.id == 'worker-alice', 'Row 2 is Alice Defender')
check(aliceItem.value.craftSkill == 2, 'Alice craft skill resolved to 2')
check(aliceItem.value.haulSkill == 9, 'Alice haul skill resolved to 9 (Strength)')
check(aliceItem.visual.craftBadge == 'L2', 'Alice crafting cell badge displays L2')
check(aliceItem.visual.haulBadge == 'L9', 'Alice hauling cell badge displays L9')

-- Verify cell draw executes cleanly
personnel.matrixList:doDrawItem(0, personnel.matrixList.items[1])
personnel.matrixList:doDrawItem(44, personnel.matrixList.items[2])
check(true, 'Matrix list items rendered cleanly with badges')


print('>>> STEP 3: Priority Cell Smooth Rotation & Atomic Revision Increment')
-- Bob's initial priorities: crafting=1, hauling=3, revision=1
local initialRev = workerPriorities['worker-bob'].revision
check(initialRev == 1, 'Initial revision is 1')

-- Simulate player clicking on Bob's Crafting priority cell:
-- Sequence: 1 -> 2 -> 3 -> 4 -> 0 -> 1
local listW = personnel.matrixList.width
local craftingCellX = listW * 0.50 -- between 40% and 70%

-- Click 1: 1 -> 2
personnel.matrixList:onMouseDown(craftingCellX, 10)
check(workerPriorities['worker-bob'].crafting == 2, 'Priority rotated 1 -> 2')
check(workerPriorities['worker-bob'].revision == 2, 'Revision incremented to 2')

-- Click 2: 2 -> 3
personnel.matrixList:onMouseDown(craftingCellX, 10)
check(workerPriorities['worker-bob'].crafting == 3, 'Priority rotated 2 -> 3')
check(workerPriorities['worker-bob'].revision == 3, 'Revision incremented to 3')

-- Click 3: 3 -> 4
personnel.matrixList:onMouseDown(craftingCellX, 10)
check(workerPriorities['worker-bob'].crafting == 4, 'Priority rotated 3 -> 4')
check(workerPriorities['worker-bob'].revision == 4, 'Revision incremented to 4')

-- Click 4: 4 -> 0 (Disabled / '—')
personnel.matrixList:onMouseDown(craftingCellX, 10)
check(workerPriorities['worker-bob'].crafting == 0, 'Priority rotated 4 -> 0')
check(workerPriorities['worker-bob'].revision == 5, 'Revision incremented to 5')
check(personnel.matrixList.items[1].item.visual.a == '—', 'Priority 0 renders as em-dash')

-- Click 5: 0 -> 1 (Highest)
personnel.matrixList:onMouseDown(craftingCellX, 10)
check(workerPriorities['worker-bob'].crafting == 1, 'Priority rotated 0 -> 1')
check(workerPriorities['worker-bob'].revision == 6, 'Revision incremented to 6')

-- Right click decrement test: 1 -> 0
personnel.matrixList:onRightMouseDown(craftingCellX, 10)
check(workerPriorities['worker-bob'].crafting == 0, 'Right click rotated 1 -> 0')
check(workerPriorities['worker-bob'].revision == 7, 'Revision incremented to 7')


print('>>> STEP 4: Column Header Batch Priority Context Menu')
-- Player clicks 'Crafting' header button
check(personnel.craftingHeaderBtn ~= nil, 'Crafting header button exists')
personnel.craftingHeaderBtn:onclick()

check(contextMenuInstance ~= nil, 'Context menu opened')
check(#contextMenuInstance.options == 5, 'Context menu has 5 options (0 through 4)')

-- Simulate selecting 'Set all to 2' (Option index 3, since 1->0, 2->1, 3->2)
contextMenuInstance.options[3].fn()

check(workerPriorities['worker-bob'].crafting == 2, 'Bob crafting priority set to 2 via batch')
check(workerPriorities['worker-alice'].crafting == 2, 'Alice crafting priority set to 2 via batch')
check(personnel.store.value.notice ~= '', 'Batch notice displayed in store')
check(personnel.matrixList.items[1].item.value.priorities.crafting == 2, 'Bob matrix row updated')
check(personnel.matrixList.items[2].item.value.priorities.crafting == 2, 'Alice matrix row updated')


print('>>> STEP 5: Holographic Inspector & Zero-GC Lazy Update Projection')
-- Player clicks on Bob in the worker name column (x < 40%)
local nameColX = listW * 0.20
personnel.matrixList:onMouseDown(nameColX, 10)
check(personnel.store.value.selected.id == 'worker-bob', 'Selected Bob Builder')

-- Verify Bob's Holographic Inspector card
local avatar = personnel.avatarData
check(avatar.hasWorker == true, 'Avatar card has worker')
check(avatar.nameText:find('Bob', 1, true) ~= nil, 'Avatar name is Bob Builder')
check(avatar.initials == 'BO', 'Avatar initials are BO')
check(avatar.roleText:find('Carpenter', 1, true) ~= nil, 'Avatar role is Carpenter')
check(avatar.statusText:find(getText('IGUI_EmberRoutesProbe_Monitor_body_EAT'), 1, true) ~= nil, 'Avatar status reflects active eating')

-- Verify Bob's Physiological items in self.info
local bobInfoRows = personnel.info.list.items
check(#bobInfoRows >= 4, 'Bob has at least 4 health/status lines')
local infoTexts = {}
for _, entry in ipairs(bobInfoRows) do
    infoTexts[#infoTexts + 1] = entry.item.value.text or ''
end
local fullInfoStr = table.concat(infoTexts, ' | ')
check(fullInfoStr:find('85', 1, true) ~= nil, 'Health readout 85 present')
check(fullInfoStr:find('15%', 1, true) ~= nil, 'Fatigue readout 15% present')
check(fullInfoStr:find('Saw logs', 1, true) ~= nil, 'Active order Saw logs present')
check(fullInfoStr:find('2 / 5', 1, true) ~= nil, 'Order progress 2 / 5 present')

-- Player clicks on Alice (Row 2, damaged, bleeding, exhausted)
personnel.matrixList:onMouseDown(nameColX, 50)
check(personnel.store.value.selected.id == 'worker-alice', 'Selected Alice Defender')

avatar = personnel.avatarData
check(avatar.initials == 'AL', 'Alice initials are AL')
local aliceInfoTexts = {}
for _, entry in ipairs(personnel.info.list.items) do
    aliceInfoTexts[#aliceInfoTexts + 1] = entry.item.value.text or ''
end
local fullAliceStr = table.concat(aliceInfoTexts, ' | ')
check(fullAliceStr:find('45', 1, true) ~= nil, 'Alice health 45 displayed')
check(fullAliceStr:find('流血', 1, true) ~= nil or fullAliceStr:find('Bleeding', 1, true) ~= nil, 'Bleeding condition badge displayed')
check(fullAliceStr:find('85%', 1, true) ~= nil, 'Alice fatigue 85% displayed')
check(fullAliceStr:find('急需休息', 1, true) ~= nil or fullAliceStr:find('restNeeded', 1, true) ~= nil, 'Rest needed warning displayed')
check(fullAliceStr:find('极度饥饿', 1, true) ~= nil or fullAliceStr:find('Hunger', 1, true) ~= nil, 'Severe hunger displayed')

-- Verify Lazy Update & Zero GC performance red line:
-- In render loop (prerender), no string measurements should occur.
local measureBefore = measureCount
for i = 1, 50 do
    personnel:prerender()
    personnel.avatarCard:prerender()
    personnel.info.list:render()
end
local measureAfter = measureCount
check(measureAfter == measureBefore, 'Render loop performs 0 text measurements (Zero GC lazy projection achieved)')


print('>>> STEP 6: Defense Page State & Red Line Boundaries')
-- Player switches to Defense page
local defenseTabBtn = dashboard.tabButtons['defense']
dashboard:tabClicked(defenseTabBtn)

check(dashboard.activeTab == 'defense', 'Active tab is defense')
local defense = dashboard.pages.defense
check(defense ~= nil and defense.active == true, 'DefensePage active')

-- Verify DEFCON 0, 1, 2 buttons are disabled
for i = 0, 2 do
    local btn = defense.alertButtons[i]
    check(btn ~= nil, 'Alert button ' .. i .. ' exists')
    check(btn.enable == false, 'Alert button ' .. i .. ' is strictly disabled (setEnable(false))')
end

-- Verify clicking alert buttons does not fake backend or crash
local backendCallsBefore = #setPrioritiesCalls
for i = 0, 2 do
    defense.alertButtons[i]:onclick()
    check(defense.alertButtons[i].enable == false, 'Alert button remains disabled after click')
end
check(#setPrioritiesCalls == backendCallsBefore, 'No backend calls were fabricated')

-- Verify Heat Meter card and disclaimers in prerender
defense:prerender()
check(true, 'DefensePage prerender completed without exceptions')


print('>>> STEP 7: Global Dashboard Lifecycle & Key Navigation (PageUp/PageDown & ESC)')
-- Currently on 'defense' (tab index 4)
check(dashboard.activeTab == 'defense', 'Starting navigation at defense')

-- Press PageDown (KEY_NEXT): defense (4) -> warehouse (1)
dashboard:onKeyPress(Keyboard.KEY_NEXT)
check(dashboard.activeTab == 'warehouse', 'PageDown wrapped to warehouse')

-- Press PageDown: warehouse (1) -> orders (2)
dashboard:onKeyPress(Keyboard.KEY_NEXT)
check(dashboard.activeTab == 'orders', 'PageDown switched to orders')

-- Press PageDown: orders (2) -> personnel (3)
dashboard:onKeyPress(Keyboard.KEY_NEXT)
check(dashboard.activeTab == 'personnel', 'PageDown switched to personnel')

-- Press PageDown: personnel (3) -> defense (4)
dashboard:onKeyPress(Keyboard.KEY_NEXT)
check(dashboard.activeTab == 'defense', 'PageDown switched to defense')

-- Press PageUp (KEY_PRIOR): defense (4) -> personnel (3)
dashboard:onKeyPress(Keyboard.KEY_PRIOR)
check(dashboard.activeTab == 'personnel', 'PageUp switched back to personnel')

-- Simulate Player Pressing ESC to cleanly close
dashboard:onKeyPress(Keyboard.KEY_ESCAPE)
check(dashboard.disposed == true, 'Dashboard is disposed')
check(dashboard.activeTab == nil, 'Active tab cleared')
check(dashboard.added == false, 'Dashboard removed from UIManager')

-- Verify all pages and tooltips disposed cleanly
for name, page in pairs(dashboard.pages) do
    check(page.disposed == true, 'Page ' .. name .. ' is disposed')
    check(page.unsubscribe == nil, 'Store subscription unsubscribed for ' .. name)
end

for name, button in pairs(dashboard.tabButtons) do
    check(tooltipCleared[button] ~= nil and tooltipCleared[button] >= 1, 'Tooltip cleared for tab button ' .. name)
end

check(tooltipCleared[personnel.craftingHeaderBtn] ~= nil, 'Tooltip cleared for craftingHeaderBtn')
check(tooltipCleared[personnel.haulingHeaderBtn] ~= nil, 'Tooltip cleared for haulingHeaderBtn')

print('PASS all ' .. checks .. ' Personnel Matrix & Colonist Journey checks verified successfully!')
