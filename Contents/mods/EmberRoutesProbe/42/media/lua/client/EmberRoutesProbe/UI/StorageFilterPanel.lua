local Tooltip = require "EmberRoutesProbe/UI/TooltipManager"
local Gate = require "EmberRoutesProbe/Kernel/RuntimeGate"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
local Registry = require "EmberRoutesProbe/Warehouse/ContainerRegistry"
local Filter = require "EmberRoutesProbe/Warehouse/StorageFilter"
local Editor = require "EmberRoutesProbe/Warehouse/FilterEditor"
local Log = require "EmberRoutesProbe/Kernel/Log"
local Flow = require "EmberRoutesProbe/UI/Text"
local State = require "EmberRoutesProbe/UI/State"
local Rows = require "EmberRoutesProbe/UI/FilterList"
local Configuration = require "EmberRoutesProbe/Warehouse/ContainerConfiguration"
local ConfigControls = require "EmberRoutesProbe/UI/ContainerConfigControls"
local SearchInput = require "EmberRoutesProbe/UI/SearchInput"
local Theme = require "EmberRoutesProbe/UI/Theme"
local GhostLens = require "EmberRoutesProbe/UI/GhostLens"
local NearbyContainers = require "EmberRoutesProbe/Warehouse/NearbyContainers"
local Dropdown = require "EmberRoutesProbe/UI/Dropdown"
local Clock = require "EmberRoutesProbe/Kernel/Clock"

---@class EmberRoutesFilterList: ISScrollingListBox
---@field owner EmberRoutesStorageFilterPanel
---@class EmberRoutesStorageFilterPanel: ISCollapsableWindow
---@field actor IsoPlayer
---@field object IsoObject
---@field fontHeight number
---@field pad number
---@field rowHeight number
---@field statusY number
---@field store EmberRoutesUIStore
---@field container ItemContainer
---@field unsubscribe function?
---@field model {draft:table, descriptions:table[], collapsed:table, status:string}
---@field statusLines string[]
---@field tickTexture Texture?
---@field list EmberRoutesFilterList
---@field searchInput EmberRoutesSearchInput
---@field searchQuery string
---@field buttons ISButton[]
---@field registered boolean
---@field configControls EmberRoutesContainerConfigControls
---@field remoteMode boolean
---@field isGhosting boolean
---@field nearbyList table[]
---@field containerCombo EmberRoutesDropdown
---@field prevBtn ISButton
---@field nextBtn ISButton
---@field ghostButton ISButton
EmberRoutesStorageFilterPanel = ISCollapsableWindow:derive("EmberRoutesStorageFilterPanel")
local opened = setmetatable({}, { __mode = "v" })

local function text(key)
    return getTextOrNull and (getTextOrNull("IGUI_EmberRoutesProbe_Filter_" .. key) or getTextOrNull(key)) or key
end

---@param actor IsoPlayer
---@param object IsoObject
---@param container ItemContainer?
---@param initial any?
function EmberRoutesStorageFilterPanel:new(actor, object, container, initial)
    container = container or object:getContainer()
    local fontHeight = getTextManager():getFontHeight(UIFont.Small)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local width = math.min(sw * 0.90, math.max(780, fontHeight * 46))
    local height = math.min(sh * 0.85, math.max(540, fontHeight * 32))

    ---@type EmberRoutesStorageFilterPanel
    local o = ISCollapsableWindow.new(self, (sw - width) / 2, (sh - height) / 2, width, height)
    o.actor, o.object, o.fontHeight = actor, object, fontHeight
    o.pad = math.ceil(fontHeight * 0.6)
    o.container = container
    local contName = getTextOrNull and (getTextOrNull("IGUI_ContainerTitle_" .. container:getType()) or container:getType()) or container:getType()
    o.title = text("title") .. " - " .. contName
    o.resizable = false
    o.backgroundColor, o.borderColor = Theme.window, Theme.border
    o.searchQuery = ""
    o.remoteMode = false

    local descriptions, seen = {}, {}
    local items = container:getItems()
    local itemCount = items and items:size() or 0
    for i = 0, math.min(itemCount, 2000) - 1 do
        local item = items:get(i)
        local id = item:getFullType()
        if not seen[id] and #descriptions < 128 then
            local descriptor = Filter.describe(item)
            descriptor.node = Filter.classify(descriptor, item)
            descriptions[#descriptions + 1] = descriptor
            seen[id] = true
        end
    end
    table.sort(descriptions, function(a, b) return a.fullType < b.fullType end)

    o.model = Editor.new(Registry.filter(object, container), descriptions)
    -- Default collapse root groups that have children for clean initial UI
    o.model.collapsed = {}
    for _, id in ipairs(Filter.order) do
        local node = Filter.nodes[id]
        if node and not node.parent and node.hasChildren then
            o.model.collapsed[id] = true
        end
    end

    if initial then
        local draft
        if type(initial) == "string" then
            draft = Configuration.preset(o.model.draft, initial)
        else
            draft = Configuration.replace(o.model.draft, initial)
        end
        if draft then o.model.draft = draft end
    end

    o.registered = Registry.metadata(object, container) ~= nil
    o.store = State.new({
        model = o.model,
        status = "",
        statusError = false,
        role = Registry.logistics({ object = object, container = container }) or "STORAGE"
    })
    o.statusLines = {}
    o.tickTexture = getTexture("media/ui/inventoryPanes/Tickbox_Tick.png")
    return o
end

function EmberRoutesStorageFilterPanel:initialise()
    ISCollapsableWindow.initialise(self)
end

function EmberRoutesStorageFilterPanel:getCurrentTargetPosition()
    local sq = self.object and self.object.getSquare and self.object:getSquare()
    if sq then return { x = sq:getX(), y = sq:getY(), z = sq:getZ() } end
    return nil
end

function EmberRoutesStorageFilterPanel:createChildren()
    ISCollapsableWindow.createChildren(self)
    local p, h = self.pad, self.fontHeight
    self.rowHeight = h + p + 2

    local bar = self:titleBarHeight()
    if self.closeButton then
        self.closeButton:setX(self.width - bar + 2)
        self.closeButton:setY(2)
        self.closeButton:setWidth(bar - 4)
        self.closeButton:setHeight(bar - 4)
    end

    -- Header Peek/Ghost Button (Right beside Close button)
    self.ghostButton = GhostLens.attachHeaderButton(self, self.width - bar * 2, 2, bar - 4, function()
        return self:getCurrentTargetPosition()
    end)

    -- Top Container Switcher Strip (Nearby Containers)
    local navH = 24
    local navY = bar + math.floor(p * 0.5)
    local navBtnW = 64

    self.nearbyList = NearbyContainers.scan(self.actor, self.object, self.container, 8)
    if not self.nearbyList or #self.nearbyList == 0 then
        local sq = self.object and self.object.getSquare and self.object:getSquare()
        local cName = getTextOrNull and (getTextOrNull("IGUI_ContainerTitle_" .. self.container:getType()) or self.container:getType()) or self.container:getType()
        self.nearbyList = { {
            object = self.object,
            container = self.container,
            name = cName,
            dist = 0,
            isCurrent = true,
            x = sq and sq:getX() or 0,
            y = sq and sq:getY() or 0,
            z = sq and sq:getZ() or 0
        } }
    end

    self.prevBtn = ISButton:new(p, navY, navBtnW, navH, "< " .. text("prevContainer"), self, EmberRoutesStorageFilterPanel.onPrevContainer)
    self.prevBtn:initialise()
    Theme.button(self.prevBtn)
    self:addChild(self.prevBtn)

    local comboX = p + navBtnW + math.floor(p / 2)
    local comboW = self.width - p * 2 - (navBtnW * 2 + p)
    self.containerCombo = Dropdown:new(comboX, navY, comboW, navH, self, EmberRoutesStorageFilterPanel.onSelectContainerCombo)
    self.containerCombo:initialise()
    self:populateContainerCombo()
    self:addChild(self.containerCombo)

    self.nextBtn = ISButton:new(self.width - p - navBtnW, navY, navBtnW, navH, text("nextContainer") .. " >", self, EmberRoutesStorageFilterPanel.onNextContainer)
    self.nextBtn:initialise()
    Theme.button(self.nextBtn)
    self:addChild(self.nextBtn)

    -- Workspace coordinates
    local top = navY + navH + math.floor(p * 0.5)
    local btnH = math.max(28, h + math.floor(p * 0.4))
    local footerHeight = h * 3 + p + btnH
    local workspaceY = top
    local workspaceHeight = self.height - workspaceY - footerHeight - p

    -- Left Column (35%) vs Right Column (65%)
    local leftW = math.floor((self.width - p * 3) * 0.35)
    local rightW = self.width - p * 3 - leftW
    local leftBounds = { x = p, y = workspaceY, width = leftW, height = workspaceHeight }
    local rightBounds = { x = p * 2 + leftW, y = workspaceY, width = rightW, height = workspaceHeight }

    -- 1. Left Column: Container Strategy, Priority & Automation Controls
    self.configControls = ConfigControls.new(self, leftBounds)

    -- 2. Right Column Top: Real-Time Search Bar
    local searchH = 28
    local function onSearchChange(target, textVal)
        target.searchQuery = textVal or ""
        target:refreshRows()
    end
    self.searchInput = SearchInput:new(rightBounds.x, rightBounds.y, rightBounds.width, searchH, text("searchPlaceholder"), self, onSearchChange)
    self:addChild(self.searchInput)

    -- 3. Right Column Sub-header: Batch Actions Toolbar (Tree Controls)
    local barY = rightBounds.y + searchH + p / 2
    local barH = 24
    local actBtnW = math.max(68, math.floor(h * 3.8))
    local curBtnX = rightBounds.x + rightBounds.width - actBtnW * 2 - math.floor(p / 2)

    local function makeActBtn(labelKey, fn)
        local btn = ISButton:new(curBtnX, barY, actBtnW, barH, text(labelKey), self, fn)
        btn:initialise()
        Theme.button(btn)
        self:addChild(btn)
        curBtnX = curBtnX + actBtnW + math.floor(p / 2)
        return btn
    end

    self.expandBtn = makeActBtn("expandAll", self.expandAll)
    self.collapseBtn = makeActBtn("collapseAll", self.collapseAll)

    -- 4. Right Column: Scrolling Categories & Item Exceptions List
    local listY = barY + barH + p / 2
    local listH = rightBounds.height - (listY - rightBounds.y)
    local listBounds = { x = rightBounds.x, y = listY, width = rightBounds.width, height = listH }
    self.list = Rows.create(self, listBounds)
    self.list:setOnMouseDownFunction(self, EmberRoutesStorageFilterPanel.toggle)
    self.list:setOverrideAButtonFunction(self, EmberRoutesStorageFilterPanel.toggle)
    self:addChild(self.list)

    -- 5. Footer Buttons: Cancel & Apply
    local footerY = self.height - p - btnH
    local cancelBtn = ISButton:new(self.width - p - 100 - p - 120, footerY, 100, btnH, text("cancel"), self, EmberRoutesStorageFilterPanel.close)
    cancelBtn:initialise()
    Theme.button(cancelBtn)
    self:addChild(cancelBtn)

    local applyBtn = ISButton:new(self.width - p - 120, footerY, 120, btnH, text("apply"), self, EmberRoutesStorageFilterPanel.apply)
    applyBtn:initialise()
    Theme.button(applyBtn, true) -- Primary Accent Style
    self:addChild(applyBtn)

    self.buttons = { cancelBtn, applyBtn }

    self.statusY = footerY - h * 3 - math.floor(p / 2)

    -- State Store Subscription
    self.unsubscribe = self.store:subscribe(function(snapshot, changed)
        self.model = snapshot.model
        if changed.model then self:refreshRows() end
        self.configControls:refresh()
        local warning = self.configControls.warning or ""
        local caption = snapshot.status == "" and warning or (snapshot.statusError and (snapshot.status .. " | " .. warning) or (warning .. " | " .. snapshot.status))
        self.statusLines = Flow.wrapLimited(caption, self.width - p * 3 - 240, UIFont.Small, 2)
    end)

    self:refreshRows()
    self.configControls:refresh()
    self.statusLines = Flow.wrapLimited(self.configControls.warning or "", self.width - p * 3 - 240, UIFont.Small, 2)

    -- Keyboard Navigation
    self.list.onKeyPress = function(list, key)
        if key == Keyboard.KEY_UP then
            list.selected = math.max(1, list.selected - 1)
            list:ensureVisible(list.selected)
        elseif key == Keyboard.KEY_DOWN then
            list.selected = math.min(#list.items, list.selected + 1)
            list:ensureVisible(list.selected)
        elseif key == Keyboard.KEY_SPACE then
            local entry = list.items[list.selected]
            if entry then EmberRoutesStorageFilterPanel.toggle(self, entry.item) end
        elseif key == Keyboard.KEY_RIGHT then
            local entry = list.items[list.selected]
            if entry and entry.item and entry.item.hasChildren and entry.item.collapsed then
                self:toggleCollapse(entry.item)
            end
        elseif key == Keyboard.KEY_LEFT then
            local entry = list.items[list.selected]
            if entry and entry.item and entry.item.hasChildren and not entry.item.collapsed then
                self:toggleCollapse(entry.item)
            end
        elseif key == Keyboard.KEY_RETURN then
            self:apply()
        elseif key == Keyboard.KEY_ESCAPE then
            self:close()
        end
    end

    self.list.isKeyConsumed = function(_, key)
        return key == Keyboard.KEY_UP or key == Keyboard.KEY_DOWN or key == Keyboard.KEY_SPACE
            or key == Keyboard.KEY_RETURN or key == Keyboard.KEY_ESCAPE
            or key == Keyboard.KEY_LEFT or key == Keyboard.KEY_RIGHT
    end

    self.list.onJoypadDown = function(list, button, joypadData)
        if button == Joypad.AButton then
            local entry = list.items[list.selected]
            if entry then self:toggle(entry.item) end
        elseif button == Joypad.XButton then
            self:apply()
        elseif button == Joypad.BButton then
            self:close()
        else
            ISScrollingListBox.onJoypadDown(list, button, joypadData)
        end
    end

    self.list.onJoypadDirUp = function(list)
        list.selected = math.max(1, list.selected - 1)
        list:ensureVisible(list.selected)
    end

    self.list.onJoypadDirDown = function(list)
        list.selected = math.min(#list.items, list.selected + 1)
        list:ensureVisible(list.selected)
    end
end

function EmberRoutesStorageFilterPanel:populateContainerCombo()
    if not self.containerCombo then return end
    local options = {}
    local curItem = nil
    for i, item in ipairs(self.nearbyList or {}) do
        local distStr = item.dist > 0 and (" (" .. tostring(item.dist) .. "m)") or ""
        local label = item.name .. distStr
        if item.isCurrent then
            label = "[*] " .. label
            curItem = item
        end
        options[#options + 1] = { id = item, label = label }
    end
    self.containerCombo:setOptions(options, curItem)
    local hasMultiple = self.nearbyList and #self.nearbyList > 1
    if self.prevBtn then Theme.enable(self.prevBtn, hasMultiple) end
    if self.nextBtn then Theme.enable(self.nextBtn, hasMultiple) end
end

function EmberRoutesStorageFilterPanel:switchToContainer(target)
    if not target or not target.object or not target.container then return end
    if target.object == self.object and target.container == self.container then return end

    -- 1. Silent auto-apply current draft to preserve changes
    self:apply(true)

    -- 2. Switch container targets
    self.object = target.object
    self.container = target.container
    for _, item in ipairs(self.nearbyList or {}) do
        item.isCurrent = (item.object == self.object and item.container == self.container)
    end

    -- 3. Rescan container descriptions
    local descriptions, seen = {}, {}
    local items = self.container:getItems()
    local count = items and items:size() or 0
    for i = 0, math.min(count, 2000) - 1 do
        local item = items:get(i)
        local id = item:getFullType()
        if not seen[id] and #descriptions < 128 then
            local descriptor = Filter.describe(item)
            descriptor.node = Filter.classify(descriptor, item)
            descriptions[#descriptions + 1] = descriptor
            seen[id] = true
        end
    end
    table.sort(descriptions, function(a, b) return a.fullType < b.fullType end)

    -- 4. Rebuild model, carrying forward collapse map
    local prevCollapsed = self.model and self.model.collapsed or {}
    self.model = Editor.new(Registry.filter(self.object, self.container), descriptions)
    self.model.collapsed = prevCollapsed

    -- 5. Update title and store
    local contName = getTextOrNull and (getTextOrNull("IGUI_ContainerTitle_" .. self.container:getType()) or self.container:getType()) or self.container:getType()
    self.title = text("title") .. " - " .. contName
    self.store:setState({
        model = self.model,
        status = "",
        statusError = false,
        role = Registry.logistics({ object = self.object, container = self.container }) or "STORAGE"
    })

    -- 6. Refresh combo display
    self:populateContainerCombo()

    -- 7. Trigger 800ms ground halo pulse on new target
    local pos = self:getCurrentTargetPosition()
    if pos and Events and Events.OnRenderTick and type(_G.addAreaHighlightForPlayer) == "function" then
        local actorIdx = self.actor and self.actor.getIndex and self.actor:getIndex() or 0
        local started = Clock.nowMs()
        local function haloTick()
            local now = Clock.nowMs()
            if now - started > 800 then
                Events.OnRenderTick.Remove(haloTick)
                return
            end
            _G.addAreaHighlightForPlayer(actorIdx, pos.x, pos.y, pos.x + 1, pos.y + 1, pos.z or 0, 0.85, 0.72, 0.30, 0.75)
        end
        Events.OnRenderTick.Add(haloTick)
    end
end

function EmberRoutesStorageFilterPanel:onPrevContainer()
    local list = self.nearbyList or {}
    if #list <= 1 then return end
    local curIdx = self.containerCombo and self.containerCombo.selected or 1
    local prevIdx = (curIdx > 1) and (curIdx - 1) or #list
    self:switchToContainer(list[prevIdx])
end

function EmberRoutesStorageFilterPanel:onNextContainer()
    local list = self.nearbyList or {}
    if #list <= 1 then return end
    local curIdx = self.containerCombo and self.containerCombo.selected or 1
    local nextIdx = (curIdx < #list) and (curIdx + 1) or 1
    self:switchToContainer(list[nextIdx])
end

function EmberRoutesStorageFilterPanel:onSelectContainerCombo(item)
    local target = item
    if not target or not target.object or not target.container then
        if self.containerCombo and self.containerCombo.getSelectedData then
            target = self.containerCombo:getSelectedData()
        elseif self.containerCombo and self.containerCombo.getOptionData then
            target = self.containerCombo:getOptionData(self.containerCombo.selected)
        end
    end
    if target then self:switchToContainer(target) end
end

function EmberRoutesStorageFilterPanel:refreshRows()
    Rows.refresh(self)
end

function EmberRoutesStorageFilterPanel:edit(change)
    local model = Editor.new(self.model.draft, self.model.descriptions)
    model.collapsed = self.model.collapsed or {}
    change(model)
    self.store:setState({ model = model, status = "", statusError = false })
end

function EmberRoutesStorageFilterPanel:toggle(row)
    self:edit(function(model) Editor.toggle(model, row) end)
end

function EmberRoutesStorageFilterPanel:toggleCollapse(row)
    if not row or not row.hasChildren or not row.id then return end
    self:edit(function(model)
        Editor.toggleCollapse(model, row.id)
    end)
end

function EmberRoutesStorageFilterPanel:all()
    self:edit(function(model) Editor.all(model, true) end)
end

function EmberRoutesStorageFilterPanel:none()
    self:edit(function(model) Editor.all(model, false) end)
end

function EmberRoutesStorageFilterPanel:expandAll()
    self:edit(function(model) Editor.expandAll(model) end)
end

function EmberRoutesStorageFilterPanel:collapseAll()
    self:edit(function(model) Editor.collapseAll(model) end)
end

function EmberRoutesStorageFilterPanel:apply(silent)
    local bypassDistance = (self.remoteMode == true)
    local ok, result = pcall(Registry.configure, self.actor, self.object, self.model.draft, self.container, self.store.value.role, bypassDistance)
    if not ok then
        Log.write("STORAGE_FILTER", "APPLY_ERROR " .. tostring(result))
        result = "ERROR"
    end
    local tag = Registry.metadata(self.object, self.container)
    local square = self.object and self.object.getSquare and self.object:getSquare()
    local groupsList = {}
    for g, v in pairs(self.model and self.model.draft and self.model.draft.groups or {}) do
        if v then groupsList[#groupsList + 1] = g end
    end
    Log.write("STORAGE_FILTER", "APPLY " .. result
        .. " id=" .. tostring(tag and tag.id or "unknown")
        .. " role=" .. tostring(tag and tag.logisticsRole or self.store.value.role or "?")
        .. " contType=" .. tostring(self.container and self.container:getType() or "nil")
        .. " groups=" .. table.concat(groupsList, ",")
        .. (square and " at=" .. square:getX() .. "," .. square:getY() .. "," .. square:getZ() or ""))

    if result == "FILTER_CONFIGURED" then
        if not silent then self:close() end
    else
        local key = "IGUI_EmberRoutesProbe_WorkCode_" .. result
        local message = getText(key)
        local statusCaption = text("failed") .. (message == key and result or message)
        self.store:setState({ status = statusCaption, statusError = true })
    end
end

function EmberRoutesStorageFilterPanel:prerender()
    GhostLens.update(self)
    ISCollapsableWindow.prerender(self)

    if self.isGhosting then
        GhostLens.drawHint(self)
        return
    end

    -- Draw Left Cards
    if self.configControls then
        self.configControls:draw()
    end

    -- Draw Right Toolbar Summary Text
    local p = self.pad or 10
    local fh = self.fontHeight or 16
    local rightX = self.searchInput.x
    local summaryY = self.searchInput.y + self.searchInput.height + p / 2 + 4
    local summaryStr = text("rulesCount"):gsub("%%1", tostring(self.allowedCategoryCount or 0)):gsub("%%2", tostring(self.deniedCategoryCount or 0))
    self:drawText(summaryStr, rightX, summaryY, Theme.accent.r, Theme.accent.g, Theme.accent.b, 1, UIFont.Small)

    -- Draw Footer Status Lines
    local color = self.store.value.statusError and Theme.status.ERROR or Theme.muted
    for index, line in ipairs(self.statusLines or {}) do
        self:drawText(line, p, self.statusY + (index - 1) * fh, color.r, color.g, color.b, color.a or 1, UIFont.Small)
    end
end

function EmberRoutesStorageFilterPanel:close()
    if self.isGhosting then GhostLens.restore(self) end
    Tooltip.clear(self.list)
    if self.configControls then self.configControls:close() end
    if self.unsubscribe then self.unsubscribe() self.unsubscribe = nil end
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if self.actor and self.actor:getJoypadBind() ~= -1 then
        ---@diagnostic disable-next-line: deprecated
        setJoypadFocus(self.actor:getPlayerNum(), nil)
    end
end

---@param actor IsoPlayer
---@param object IsoObject
---@param container ItemContainer?
---@param initial any?
function EmberRoutesStorageFilterPanel.open(actor, object, container, initial)
    if not Gate.canExecute(actor) or not actor then return end
    if not object then return end
    container = container or object:getContainer()
    if Registry.containerIndex(object, container) == nil then return end
    local previous = opened[actor:getPlayerNum()]
    if previous then previous:close() end
    local panel = EmberRoutesStorageFilterPanel:new(actor, object, container, initial)
    panel:initialise()
    panel:addToUIManager()
    opened[actor:getPlayerNum()] = panel
    if actor:getJoypadBind() ~= -1 then setJoypadFocus(actor:getPlayerNum(), panel.list) end
    return panel
end

return EmberRoutesStorageFilterPanel
