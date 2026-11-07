require "ISUI/ISScrollBar"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "ISUI/ISButton"
local UI = require "EmberRoutesProbe/UI/UI"
local Theme = require "EmberRoutesProbe/UI/Theme"
local Tooltip = require "EmberRoutesProbe/UI/TooltipManager"
local Filter = require "EmberRoutesProbe/Warehouse/StorageFilter"
local Query = require "EmberRoutesProbe/Warehouse/WarehouseQuery"
local Controls = { sorts = Query.SORTS }
local function text(key) return getText("IGUI_EmberRoutesProbe_Settlement_" .. key) end

function Controls.new(owner, nativeParent, bounds)
    assert(bounds.x == 0 and bounds.y == 0, "EXPECTED_HOST_LOCAL_BOUNDS")
    local self = { host = nativeParent, categoryIds = { false }, sortIds = Controls.sorts, buttons = {} }

    self.search = ISTextEntryBox:new("", 0, 0, 0, bounds.height)
    self.search:initialise()
    self.search:instantiate()
    if self.search.setClearButton then self.search:setClearButton(true) end
    self.search.target = owner
    self.search.onTextChangeFunction = owner.queryChanged
    self.search:setPlaceholderText(text("searchPrompt"))
    self.search.tooltip = text("searchPrompt")
    self.search.backgroundColor = Theme.panel
    self.search.borderColor = Theme.border
    Tooltip.register(self.search, { method = "prerender", owner = owner })

    self.category = ISComboBox:new(0, 0, 0, bounds.height, owner, owner.queryChanged)
    self.category:initialise()
    self.category:addOption(text("allCategories"))
    for _, id in ipairs(Filter.order) do
        if not Filter.nodes[id].parent then
            self.category:addOption(getText("IGUI_EmberRoutesProbe_Filter_" .. id))
            self.categoryIds[#self.categoryIds + 1] = id
        end
    end

    self.sort = ISComboBox:new(0, 0, 0, bounds.height, owner, owner.queryChanged)
    self.sort:initialise()
    for _, id in ipairs(Controls.sorts) do self.sort:addOption(text("sort_" .. id)) end
    self.sort:setToolTipMap({ defaultTooltip = text("sortHint") })
    Tooltip.register(self.sort, { method = "prerender", owner = owner })

    for i, view in ipairs({'recipes', 'maintainStock'}) do
        local title = getText(view == 'recipes' and 'IGUI_EmberRoutesProbe_Settlement_tab_crafting' or 'IGUI_EmberRoutesProbe_Crafting_view_maintainStock')
        local button = ISButton:new(0, 0, 0, bounds.height, title, owner, function()
            local row = owner.store.value.selection
            local context = view == 'recipes' and row and row.fullType and { returnTab = 'warehouse', filterProduct = row.fullType } or { view = view }
            owner.owner:selectTab('crafting', context)
        end)
        button:initialise()
        Theme.button(button)
        self.buttons[i] = button
    end

    local spec = UI.Row({ gap = owner.pad / 2, align = "stretch" }, {
        UI.Item(self.search, { key = "search", grow = 3.0 }),
        UI.Item(self.category, { key = "category", grow = 1.8 }),
        UI.Item(self.sort, { key = "sort", grow = 1.5 }),
        UI.Item(self.buttons[1], { key = "craft", grow = 1.0 }),
        UI.Item(self.buttons[2], { key = "maintain", grow = 1.4 })
    })

    local handles, err = nativeParent:build(spec)
    assert(handles, err)
    self.items = handles

    return self
end

return Controls
