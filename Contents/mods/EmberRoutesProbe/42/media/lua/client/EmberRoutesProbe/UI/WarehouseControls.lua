require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "ISUI/ISButton"
local Layout=require "EmberRoutesProbe/UI/Layout"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Tooltip=require "EmberRoutesProbe/UI/TooltipAnchor"
local Filter=require "EmberRoutesProbe/StorageFilter"
local Query=require "EmberRoutesProbe/WarehouseQuery"
local Controls={sorts=Query.SORTS}
local function text(key) return getText("IGUI_EmberRoutesProbe_Settlement_"..key) end
function Controls.new(owner,bounds)
    local p=owner.pad
    local r=assert(Layout.axis(bounds,{{grow=3.5},{grow=2},{grow=2}},{gap=p/2}))
    local self={categoryIds={false},sortIds=Controls.sorts}
    self.search=ISTextEntryBox:new("",r[1].x,r[1].y,r[1].width,r[1].height)
    self.search:initialise()
    self.search:instantiate()
    if self.search.setClearButton then self.search:setClearButton(true) end
    self.search.target=owner
    self.search.onTextChangeFunction=owner.queryChanged
    self.search:setPlaceholderText(text("searchPrompt"))
    self.search.tooltip=text("searchPrompt")
    self.search.backgroundColor=Theme.panel
    self.search.borderColor=Theme.border
    Tooltip.attach(self.search,"prerender")
    owner:addChild(self.search)

    self.category=ISComboBox:new(r[2].x,r[2].y,r[2].width,r[2].height,owner,owner.queryChanged)
    self.category:initialise()
    self.category:addOption(text("allCategories"))
    for _,id in ipairs(Filter.order) do
        if not Filter.nodes[id].parent then
            self.category:addOption(getText("IGUI_EmberRoutesProbe_Filter_"..id))
            self.categoryIds[#self.categoryIds+1]=id
        end
    end
    owner:addChild(self.category)

    self.sort=ISComboBox:new(r[3].x,r[3].y,r[3].width,r[3].height,owner,owner.queryChanged)
    self.sort:initialise()
    for _,id in ipairs(Controls.sorts) do self.sort:addOption(text("sort_"..id)) end
    self.sort:setToolTipMap({defaultTooltip=text("sortHint")})
    owner:addChild(self.sort)
    Tooltip.attach(self.sort,"prerender")

    return self
end
return Controls
