--[[
    WorkPolicyPage.lua - EmberRoutes UI
    Settlement Work Policies & Directives Management Page.
    Left Column: List of registered jobs/categories.
    Right Column: Metadata-driven policy editor form for the selected job.
--]]

require 'ISUI/ISPanel'
require 'ISUI/ISButton'
require 'ISUI/ISScrollingListBox'
local Layout = require 'EmberRoutesProbe/UI/Layout'
local Theme = require 'EmberRoutesProbe/UI/Theme'
local Text = require 'EmberRoutesProbe/UI/Text'
local Registry = require 'EmberRoutesProbe/JobPolicyRegistry'
local PolicyService = require 'EmberRoutesProbe/JobPolicyService'
local Editors = require 'EmberRoutesProbe/UI/JobPolicyEditors'

---@class EmberRoutesWorkPolicyPage:ISPanel
---@field owner EmberRoutesSettlementDashboard
---@field actor IsoPlayer
---@field entry table
---@field fontHeight number
---@field pad number
EmberRoutesWorkPolicyPage = ISPanel:derive('EmberRoutesWorkPolicyPage')

---@param owner EmberRoutesSettlementDashboard
---@param bounds table
---@return EmberRoutesWorkPolicyPage
function EmberRoutesWorkPolicyPage:new(owner, bounds)
    local o = ISPanel.new(self, bounds.x, bounds.y, bounds.width, bounds.height)
    o.owner = owner
    o.actor, o.entry = owner.actor, owner.entry
    o.fontHeight, o.pad = owner.fontHeight, owner.pad
    o.background = false
    o.categories = {}
    o.selectedCategory = nil
    o.draft = {}
    o.isDirty = false
    o.noticeText = ""
    o.noticeColor = Theme.muted
    return o
end

function EmberRoutesWorkPolicyPage:initialise()
    ISPanel.initialise(self)
end

function EmberRoutesWorkPolicyPage:createChildren()
    ISPanel.createChildren(self)
    local h, p = self.fontHeight, self.pad

    -- Split main area into Left (job list, 28%) and Right (policy form, 72%)
    local cols = assert(Layout.axis({ x = 0, y = 0, width = self.width, height = self.height },
        { { grow = 28 }, { grow = 72 } },
        { direction = 'row', padding = p, gap = p }))
    self.leftBounds = cols[1]
    self.rightBounds = cols[2]

    -- Left Column: Job Categories List
    self.jobList = ISScrollingListBox:new(self.leftBounds.x, self.leftBounds.y, self.leftBounds.width, self.leftBounds.height)
    self.jobList:initialise()
    self.jobList:instantiate()
    self.jobList.itemheight = math.floor(h * 2.2)
    self.jobList.font = UIFont.Small
    self.jobList.drawBorder = true
    Theme.list(self.jobList)

    self.jobList.doDrawItem = function(list, y, item, alt)
        local rowH = item.height
        if list.selected == item.index then
            Theme.rect(list, 0, y, list.width, rowH, Theme.selected)
        elseif list.mouseoverselected == item.index then
            Theme.rect(list, 0, y, list.width, rowH, Theme.hover)
        end
        Theme.rect(list, 0, y, list.width, rowH, Theme.border, true)

        local dotColor = Theme.accent
        Theme.rect(list, p, y + (rowH - 6) / 2, 6, 6, dotColor)

        local title = item.text or item.item
        Theme.text(list, title, p + 14, y + (rowH - h) / 2, Theme.textColor)
        return y + rowH
    end

    local onSelect = function(page, item)
        page = page or self
        local cat = item or (self.jobList.items and self.jobList.selected and self.jobList.items[self.jobList.selected] and self.jobList.items[self.jobList.selected].item)
        if cat and cat ~= self.selectedCategory then
            self:selectCategory(cat)
        end
    end
    self.jobList:setOnMouseDownFunction(self, onSelect)
    self.jobList:setOverrideAButtonFunction(self, onSelect)

    self:addChild(self.jobList)

    -- Right Column: Form Panel
    self.formPanel = ISPanel:new(self.rightBounds.x, self.rightBounds.y, self.rightBounds.width, self.rightBounds.height)
    self.formPanel:initialise()
    self.formPanel.background = false
    self:addChild(self.formPanel)

    self:populateCategories()
end

---Populate the job list from JobPolicyRegistry.
function EmberRoutesWorkPolicyPage:populateCategories()
    self.jobList:clear()
    self.categories = Registry.categories()

    for _, cat in ipairs(self.categories) do
        local def = Registry.get(cat)
        local title = def and def.titleKey and getTextOrNull(def.titleKey) or cat
        self.jobList:addItem(title, cat)
    end

    if #self.categories > 0 then
        self.jobList.selected = 1
        self:selectCategory(self.categories[1])
    else
        self:buildForm(nil)
    end
end

---Switch selected category and reload draft.
function EmberRoutesWorkPolicyPage:selectCategory(cat)
    self.selectedCategory = cat
    local settlementId = self.entry and self.entry.id
    self.draft, self.policyError = PolicyService.getDraft(settlementId, cat)
    self.isDirty = false
    self.noticeText = ""
    self.noticeColor = Theme.muted
    self:buildForm(cat)
end

---Rebuild the right-hand policy editor form.
function EmberRoutesWorkPolicyPage:buildForm(cat)
    -- Safely clear all old controls in formPanel and ensure panel is visible
    if self.formPanel.clearChildren then
        self.formPanel:clearChildren()
    end
    self.formPanel:setVisible(true)
    self.saveBtn = nil
    if self.policyError then
        local label = getText('IGUI_EmberRoutesProbe_Policy_err_' .. self.policyError)
        local lines = Text.wrapLimited(label, self.formPanel.width-self.pad*2, UIFont.Small, 6)
        self.formPanel.prerender = function(panel)
            ISPanel.prerender(panel)
            for i, line in ipairs(lines) do Theme.text(panel, line, self.pad, self.pad+(i-1)*self.fontHeight, Theme.danger) end
        end
        return
    end
    self.formPanel.prerender = ISPanel.prerender

    if not cat then
        return
    end

    local def = Registry.get(cat)
    if not def then return end

    local h, p = self.fontHeight, self.pad
    local settlementId = self.entry and self.entry.id
    local fields = def.getFields and def.getFields(settlementId) or {}

    -- Form layout: Top Header (h*3), Field Rows (scrollable), Bottom Action Bar (h*2.2)
    local headerH = math.floor(h * 3)
    local bottomH = math.floor(h * 2.2)
    local availableH = self.formPanel.height - headerH - bottomH - p * 2

    -- 1. Header Display
    local headerPanel = ISPanel:new(0, 0, self.formPanel.width, headerH)
    headerPanel:initialise()
    headerPanel.background = false
    headerPanel.prerender = function(panel)
        ISPanel.prerender(panel)
        Theme.rect(panel, 0, 0, panel.width, panel.height, Theme.panel)
        Theme.rect(panel, 0, 0, panel.width, panel.height, Theme.border, true)

        local title = def.titleKey and getTextOrNull(def.titleKey) or cat
        local desc = def.descKey and getTextOrNull(def.descKey) or ""
        Theme.text(panel, title, p, p, Theme.gold)
        if desc ~= "" then
            Theme.text(panel, desc, p, p + h + 2, Theme.muted)
        end
    end
    self.formPanel:addChild(headerPanel)

    -- 2. Scrollable Field Container
    local fieldContainer = ISPanel:new(0, headerH + p, self.formPanel.width, availableH)
    fieldContainer:initialise()
    fieldContainer.background = false
    fieldContainer:setScrollChildren(true)
    fieldContainer:addScrollBars()
    self.formPanel:addChild(fieldContainer)

    local rowH = math.floor(h * 2.0)
    local curY = 0

    for _, field in ipairs(fields) do
        local measureWidth=fieldContainer.width-math.floor(fieldContainer.width*.45)-p*2
        local controlH=Editors.height(field,measureWidth,h,p)
        rowH=math.max(math.floor(h*2),controlH+p)
        local rowPanel = ISPanel:new(0, curY, fieldContainer.width, rowH)
        rowPanel:initialise()
        rowPanel.background = false

        -- Left label (45%) and right control (55%)
        local labelW = math.floor(rowPanel.width * 0.45)
        local ctrlW = rowPanel.width - labelW - p

        rowPanel.prerender = function(panel)
            ISPanel.prerender(panel)
            local label = field.label and getTextOrNull(field.label) or field.key
            Theme.text(panel, label, p, (panel.height - h) / 2, Theme.textColor)
        end

        local editor = Editors.get(field.editor)
        local initialVal = self.draft[field.key]
        local ctrlBounds = { x = labelW, y = (rowH-controlH)/2, width = ctrlW-p, height = controlH }

        local catDef = Registry.get(cat)
        local catTitle = catDef and catDef.titleKey and getTextOrNull(catDef.titleKey) or cat
        local context = { settlementId = settlementId, actor = self.actor, category = cat, categoryTitle = catTitle }
        editor.create(rowPanel, ctrlBounds, field, initialVal, function(key, newVal)
            self.draft[key] = newVal
            self.isDirty = true
            self.noticeText = getText("IGUI_EmberRoutesProbe_Policy_hasUnsaved")
            self.noticeColor = Theme.gold
            if self.saveBtn then Theme.button(self.saveBtn, true) end
        end, context)

        fieldContainer:addChild(rowPanel)
        curY = curY + rowH + p / 2
    end
    fieldContainer:setScrollHeight(curY)

    -- 3. Bottom Action Bar
    local actionPanel = ISPanel:new(0, self.formPanel.height - bottomH, self.formPanel.width, bottomH)
    actionPanel:initialise()
    actionPanel.background = false

    actionPanel.prerender = function(panel)
        ISPanel.prerender(panel)
        Theme.rect(panel, 0, 0, panel.width, panel.height, Theme.panel)
        Theme.rect(panel, 0, 0, panel.width, panel.height, Theme.border, true)

        if self.noticeText ~= "" then
            Theme.text(panel, self.noticeText, p, (panel.height - h) / 2, self.noticeColor)
        end
    end

    local btnW = math.max(80, math.floor(h * 5))
    local btnH = math.floor(h * 1.6)
    local btnY = (bottomH - btnH) / 2

    -- Reset Button
    local resetBtn = ISButton:new(actionPanel.width - btnW * 2 - p * 2, btnY, btnW, btnH, getText("IGUI_EmberRoutesProbe_Policy_reset"), self, function()
        self:selectCategory(cat)
    end)
    resetBtn:initialise()
    Theme.button(resetBtn, false)
    actionPanel:addChild(resetBtn)

    -- Save & Apply Button
    local saveBtn = ISButton:new(actionPanel.width - btnW - p, btnY, btnW, btnH, getText("IGUI_EmberRoutesProbe_Policy_save"), self, function()
        self:saveCurrent()
    end)
    saveBtn:initialise()
    Theme.button(saveBtn, self.isDirty)
    actionPanel:addChild(saveBtn)
    self.saveBtn = saveBtn

    self.formPanel:addChild(actionPanel)
end

---Save current draft to PolicyService.
function EmberRoutesWorkPolicyPage:saveCurrent()
    if not self.selectedCategory or self.policyError then return end
    local settlementId = self.entry and self.entry.id
    local ok, why = PolicyService.save(self.actor, settlementId, self.selectedCategory, self.draft)

    if ok then
        self.isDirty = false
        self.noticeText = getText("IGUI_EmberRoutesProbe_Policy_saved")
        self.noticeColor = Theme.status.READY
        if self.saveBtn then Theme.button(self.saveBtn, false) end
    else
        self.noticeText = getTextOrNull("IGUI_EmberRoutesProbe_Policy_err_" .. tostring(why)) or tostring(why)
        self.noticeColor = Theme.danger
    end
end

function EmberRoutesWorkPolicyPage:activate()
    self.active = true
end

function EmberRoutesWorkPolicyPage:deactivate()
    self.active = false
end

function EmberRoutesWorkPolicyPage:dispose()
    self.disposed = true
    self:deactivate()
end

return EmberRoutesWorkPolicyPage
