require "env"
require "ISUI/ISPanel"
require "ISUI/ISButton"
local Visual = require "EmberRoutesProbe/UI/StatusVisual"
local Theme = require "EmberRoutesProbe/UI/Theme"
local Skeleton = require "EmberRoutesProbe/UI/SkeletonView"
local EmptyState = require "EmberRoutesProbe/UI/EmptyState"
local InlineAlert = require "EmberRoutesProbe/UI/InlineAlert"
local Toast = require "EmberRoutesProbe/UI/ToastManager"

-- Dedicated Native UI Style & Infrastructure Showcase Scene for EmberRoutes Flat 2.0
NativePreview = ISPanel:new(0, 0, 1200, 800)
NativePreview:initialise()
NativePreview:instantiate()
NativePreview.background = false

local function drawRect(self, x, y, w, h, c)
    if not c then return end
    self:drawRect(x, y, w, h, c.a or 1, c.r or 1, c.g or 1, c.b or 1)
end

local function drawRectBorder(self, x, y, w, h, c)
    if not c then return end
    self:drawRectBorder(x, y, w, h, c.a or 1, c.r or 1, c.g or 1, c.b or 1)
end

NativePreview.prerender = function(self)
    -- Background
    drawRect(self, 0, 0, self.width, self.height, { r = 0.045, g = 0.055, b = 0.070, a = 1.0 })

    -- Page Header
    self:drawText("EmberRoutes Flat 2.0 UI Infrastructure & Icon System", 24, 14, 0.95, 0.97, 1.0, 1, UIFont.Medium)
    self:drawText("Vanilla Priority Textures | Primer Vector Glyphs | State Matrix | Skeleton | EmptyState | Alerts | Toasts", 24, 36, 0.55, 0.60, 0.65, 1, UIFont.Small)

    -- Divider
    drawRect(self, 24, 56, self.width - 48, 1, { r = 0.18, g = 0.22, b = 0.28, a = 0.85 })

    local startY = 66
    local colW = 360
    local colGap = 20

    -- =========================================================================
    -- COLUMN 1: Six-State Button Matrix & Form Helper
    -- =========================================================================
    local x1 = 24
    drawRect(self, x1, startY, colW, 440, { r = 0.07, g = 0.09, b = 0.12, a = 0.95 })
    drawRectBorder(self, x1, startY, colW, 440, Theme.border)
    self:drawText("1. Complete State Matrix", x1 + 12, startY + 10, Theme.accent.r, Theme.accent.g, Theme.accent.b, 1, UIFont.Medium)
    self:drawText("Default -> Hover -> Focus -> Active -> Disabled -> Loading", x1 + 12, startY + 30, Theme.muted.r, Theme.muted.g, Theme.muted.b, 1, UIFont.Small)

    local btnY = startY + 54
    local btnW = colW - 32
    local btnH = 26

    -- 1. Default State
    drawRect(self, x1 + 16, btnY, btnW, btnH, Theme.control)
    drawRectBorder(self, x1 + 16, btnY, btnW, btnH, Theme.border)
    self:drawText("State: Default (Idle)", x1 + 24, btnY + 6, Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 1, UIFont.Small)
    btnY = btnY + 36

    -- 2. Hover State
    drawRect(self, x1 + 16, btnY, btnW, btnH, { r = Theme.control.r + 0.08, g = Theme.control.g + 0.08, b = Theme.control.b + 0.08, a = 0.95 })
    drawRectBorder(self, x1 + 16, btnY, btnW, btnH, Theme.accent)
    self:drawText("State: Hover (Cursor Over Glow)", x1 + 24, btnY + 6, Theme.accent.r, Theme.accent.g, Theme.accent.b, 1, UIFont.Small)
    btnY = btnY + 36

    -- 3. Focus State (Keyboard Tab / Controller 2px Focus Ring)
    drawRect(self, x1 + 16, btnY, btnW, btnH, Theme.control)
    drawRectBorder(self, x1 + 16, btnY, btnW, btnH, Theme.border)
    Theme.focusRing(self, x1 + 16, btnY, btnW, btnH, Theme.accent)
    self:drawText("State: Focus (2px Focus Ring Tab-nav)", x1 + 24, btnY + 6, Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 1, UIFont.Small)
    btnY = btnY + 36

    -- 4. Active State (1px Inset Press)
    drawRect(self, x1 + 17, btnY + 1, btnW - 2, btnH - 1, { r = Theme.control.r - 0.03, g = Theme.control.g - 0.03, b = Theme.control.b - 0.03, a = 1 })
    drawRectBorder(self, x1 + 16, btnY, btnW, btnH, Theme.borderFocus)
    self:drawText("State: Active (1px Inset Pressed)", x1 + 25, btnY + 7, Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 0.9, UIFont.Small)
    btnY = btnY + 36

    -- 5. Disabled State with Auxiliary Reason Helper
    drawRect(self, x1 + 16, btnY, btnW, btnH, { r = 0.10, g = 0.12, b = 0.15, a = 0.50 })
    drawRectBorder(self, x1 + 16, btnY, btnW, btnH, { r = 0.20, g = 0.24, b = 0.28, a = 0.40 })
    self:drawText("State: Disabled", x1 + 24, btnY + 6, Theme.muted.r, Theme.muted.g, Theme.muted.b, 0.45, UIFont.Small)
    Theme.formHelper(self, x1 + 16, btnY + btnH + 3, btnW, "Prerequisite: Requires Level 2 Carpentry Bench", false)
    btnY = btnY + 46

    -- 6. Loading State (Submitting + Animated Dots)
    drawRect(self, x1 + 16, btnY, btnW, btnH, { r = Theme.control.r + 0.02, g = Theme.control.g + 0.02, b = Theme.control.b + 0.02, a = 0.85 })
    drawRectBorder(self, x1 + 16, btnY, btnW, btnH, Theme.border)
    local dotCount = math.floor((getTimestampMs() / 350) % 4)
    local dots = string.rep(".", dotCount)
    self:drawText("Submitting" .. dots, x1 + 24, btnY + 6, Theme.accent.r, Theme.accent.g, Theme.accent.b, 1, UIFont.Small)

    -- 7. SearchInput Component Demo (Idle & Focused)
    btnY = btnY + 38
    self:drawText("[SearchInput Component]", x1 + 16, btnY, Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 1, UIFont.Small)
    btnY = btnY + 16
    -- Idle Search Input
    drawRect(self, x1 + 16, btnY, btnW, 26, Theme.panel)
    drawRectBorder(self, x1 + 16, btnY, btnW, 26, Theme.border)
    Visual.icon(self, x1 + 22, btnY + 6, 14, "search", Theme.muted)
    self:drawText("Search items or recipes...", x1 + 42, btnY + 6, Theme.muted.r, Theme.muted.g, Theme.muted.b, 0.7, UIFont.Small)
    btnY = btnY + 32

    -- Active/Focused Search Input with Clear Button
    drawRect(self, x1 + 16, btnY, btnW, 26, Theme.panel)
    drawRectBorder(self, x1 + 15, btnY - 1, btnW + 2, 28, Theme.accent)
    Visual.icon(self, x1 + 22, btnY + 6, 14, "search", Theme.accent)
    self:drawText("WoodPlank", x1 + 42, btnY + 6, Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 1.0, UIFont.Small)
    Visual.icon(self, x1 + 16 + btnW - 20, btnY + 6, 14, "cross", Theme.textColor)

    -- =========================================================================
    -- COLUMN 2: SkeletonView & EmptyState
    -- =========================================================================
    local x2 = x1 + colW + colGap
    drawRect(self, x2, startY, colW, 440, { r = 0.07, g = 0.09, b = 0.12, a = 0.95 })
    drawRectBorder(self, x2, startY, colW, 440, Theme.border)
    self:drawText("2. Skeleton & EmptyState", x2 + 12, startY + 10, Theme.accent.r, Theme.accent.g, Theme.accent.b, 1, UIFont.Medium)
    self:drawText("Zero-GC Shimmer Pulse & Primer Blankslate", x2 + 12, startY + 30, Theme.muted.r, Theme.muted.g, Theme.muted.b, 1, UIFont.Small)

    -- Skeleton Shimmer Demo
    local skelY = startY + 54
    self:drawText("[Skeleton Loading Shimmer]", x2 + 16, skelY, Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 1, UIFont.Small)
    skelY = skelY + 18
    Skeleton.card(self, { x = x2 + 16, y = skelY, width = btnW, height = 70 })
    skelY = skelY + 80
    Skeleton.list(self, { x = x2 + 16, y = skelY, width = btnW, height = 50 }, 2, 22, 6)

    -- EmptyState Blankslate Demo
    local emptyY = skelY + 64
    self:drawText("[EmptyState Zero-Data Guidance]", x2 + 16, emptyY, Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 1, UIFont.Small)
    emptyY = emptyY + 18
    drawRect(self, x2 + 16, emptyY, btnW, 110, { r = 0.05, g = 0.065, b = 0.085, a = 0.85 })
    drawRectBorder(self, x2 + 16, emptyY, btnW, 110, Theme.border)
    EmptyState.draw(self, { x = x2 + 16, y = emptyY, width = btnW, height = 110 }, {
        icon = "box",
        iconSize = 28,
        title = "No Work Orders Dispatched",
        hint = "Select a workstation or territory to assign production policies",
        action = "Dispatch New Order"
    })

    -- =========================================================================
    -- COLUMN 3: InlineAlert (4 Tiers) & Toast Notification
    -- =========================================================================
    local x3 = x2 + colW + colGap
    drawRect(self, x3, startY, colW, 440, { r = 0.07, g = 0.09, b = 0.12, a = 0.95 })
    drawRectBorder(self, x3, startY, colW, 440, Theme.border)
    self:drawText("3. InlineAlerts & Toast", x3 + 12, startY + 10, Theme.accent.r, Theme.accent.g, Theme.accent.b, 1, UIFont.Medium)
    self:drawText("4-Tier Semantic Banners & Floating Snackbars", x3 + 12, startY + 30, Theme.muted.r, Theme.muted.g, Theme.muted.b, 1, UIFont.Small)

    local alertY = startY + 54
    self:drawText("[4-Tier Semantic Inline Banners]", x3 + 16, alertY, Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 1, UIFont.Small)
    alertY = alertY + 18

    InlineAlert.draw(self, x3 + 16, alertY, btnW, 36, {
        type = "info",
        title = "Information",
        message = "Syncing warehouse container cache (48 units)"
    })
    alertY = alertY + 44

    InlineAlert.draw(self, x3 + 16, alertY, btnW, 36, {
        type = "success",
        title = "Order Settled",
        message = "Delivered 18 planks to Construction Yard"
    })
    alertY = alertY + 44

    InlineAlert.draw(self, x3 + 16, alertY, btnW, 36, {
        type = "warning",
        title = "Reserves Warning",
        message = "Water supply drops below 1.5 days"
    })
    alertY = alertY + 44

    InlineAlert.draw(self, x3 + 16, alertY, btnW, 36, {
        type = "danger",
        title = "Critical Breach",
        message = "Northern wall perimeter under zombie attack!"
    })
    alertY = alertY + 46

    self:drawText("[Floating Non-blocking Toast Preview]", x3 + 16, alertY, Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 1, UIFont.Small)
    alertY = alertY + 18
    drawRect(self, x3 + 16, alertY, btnW, 36, { r = 0.06, g = 0.08, b = 0.11, a = 0.96 })
    drawRectBorder(self, x3 + 16, alertY, btnW, 36, Theme.accent)
    drawRect(self, x3 + 16, alertY, 3, 36, Theme.accent)
    Visual.mark(self, x3 + 24, alertY + 10, 14, "check", Theme.status.READY)
    self:drawText("Toast: Auto-dismissed after 3000ms", x3 + 46, alertY + 10, Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 1, UIFont.Small)

    -- 4-Tier Dark Surface Elevation System
    alertY = alertY + 46
    self:drawText("[4-Tier Surface Elevation Hierarchy]", x3 + 16, alertY, Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 1, UIFont.Small)
    alertY = alertY + 16
    local elevW = math.floor((btnW - 12) / 4)
    local elevList = {
        { name = "L0 Canvas", bg = { r = 0.05, g = 0.07, b = 0.09, a = 1.0 }, border = Theme.borderSubtle },
        { name = "L1 Card",   bg = { r = 0.086, g = 0.106, b = 0.133, a = 1.0 }, border = Theme.border },
        { name = "L2 Float",  bg = { r = 0.13, g = 0.15, b = 0.18, a = 1.0 }, border = Theme.accent },
        { name = "L3 Modal",  bg = { r = 0.18, g = 0.21, b = 0.25, a = 1.0 }, border = Theme.gold }
    }
    for i, el in ipairs(elevList) do
        local ex = x3 + 16 + (i - 1) * (elevW + 4)
        drawRect(self, ex, alertY, elevW, 30, el.bg)
        drawRectBorder(self, ex, alertY, elevW, 30, el.border)
        local strW = getTextManager():MeasureStringX(UIFont.Small, el.name)
        self:drawText(el.name, ex + math.floor((elevW - strW) / 2), alertY + 8, Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 0.9, UIFont.Small)
    end

    -- =========================================================================
    -- BOTTOM FOOTER: Two-Tier Icon System Gallery
    -- =========================================================================
    local footY = startY + 452
    local footW = self.width - 48
    drawRect(self, 24, footY, footW, 168, { r = 0.07, g = 0.09, b = 0.12, a = 0.95 })
    drawRectBorder(self, 24, footY, footW, 168, Theme.border)

    -- Row A: Vanilla In-Game Prioritized Icons
    self:drawText("Tier 1: Authentic Vanilla In-Game Priority Textures (Food, Water, Medical, Wood, Job Disciplines)", 36, footY + 8, Theme.accent.r, Theme.accent.g, Theme.accent.b, 1, UIFont.Small)
    local vanillaList = {
        { name = "food", label = "Food" },
        { name = "water", label = "Water" },
        { name = "medical", label = "Medical" },
        { name = "wood", label = "Wood" },
        { name = "farming", label = "Farming" },
        { name = "cleaning", label = "Clean" },
        { name = "combat", label = "Defense" },
        { name = "hauling", label = "Cargo" },
        { name = "tools", label = "Tools" },
        { name = "books", label = "Policy" },
        { name = "sleep", label = "Leisure" }
    }
    local vx = 36
    local vy = footY + 26
    for _, item in ipairs(vanillaList) do
        drawRect(self, vx, vy, 48, 44, { r = 0.12, g = 0.15, b = 0.19, a = 0.85 })
        drawRectBorder(self, vx, vy, 48, 44, Theme.border)
        Visual.icon(self, vx + 15, vy + 4, 18, item.name)
        local strW = getTextManager():MeasureStringX(UIFont.Small, item.label)
        self:drawText(item.label, vx + math.floor((48 - strW) / 2), vy + 26, Theme.muted.r, Theme.muted.g, Theme.muted.b, 0.9, UIFont.Small)
        vx = vx + 54
    end

    -- Row B: Flat 2.0 Monochromatic Vector Icons
    self:drawText("Tier 2: Flat 2.0 Extended Semantic Vector Library (38 Antialiased 32x32 Masks)", 36, footY + 76, Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 0.85, UIFont.Small)
    local vectorList = {
        { name = "apple", label = "apple" },
        { name = "droplet", label = "droplet" },
        { name = "cross", label = "cross" },
        { name = "tree", label = "tree" },
        { name = "cart", label = "cart" },
        { name = "wrench", label = "wrench" },
        { name = "book", label = "book" },
        { name = "clock", label = "clock" },
        { name = "lock", label = "lock" },
        { name = "trash", label = "trash" },
        { name = "search", label = "search" },
        { name = "filter", label = "filter" },
        { name = "bell", label = "bell" },
        { name = "star", label = "star" },
        { name = "info", label = "info" },
        { name = "gear", label = "gear" },
        { name = "shield", label = "shield" },
        { name = "heart", label = "heart" },
        { name = "person", label = "person" },
        { name = "box", label = "box" },
        { name = "hammer", label = "hammer" }
    }
    local mx = 36
    local my = footY + 96
    for idx, ic in ipairs(vectorList) do
        drawRect(self, mx, my, 48, 42, { r = 0.12, g = 0.15, b = 0.19, a = 0.85 })
        drawRectBorder(self, mx, my, 48, 42, Theme.border)
        Visual.glyph(self, mx + 16, my + 6, 16, ic.name, Theme.textColor)
        local strW = getTextManager():MeasureStringX(UIFont.Small, ic.label)
        self:drawText(ic.label, mx + math.floor((48 - strW) / 2), my + 26, Theme.muted.r, Theme.muted.g, Theme.muted.b, 0.9, UIFont.Small)
        mx = mx + 54
        if idx == 11 then
            mx = 36
            my = my + 44
        end
    end
end

NativePreview.smoke = function(self)
    local texBox = getTexture("media/ui/EmberRoutes/ICON/box.png")
    assert(texBox ~= nil, "TEXTURE_BOX_PNG_IS_NIL")
    local texFood = getTexture("media/ui/Moodles/32/Status_Hunger.png")
    assert(texFood ~= nil, "TEXTURE_FOOD_VANILLA_IS_NIL")
    self.smokeSummary = "EmberRoutes Flat 2.0 Infrastructure: Two-Tier Icon System (Vanilla Priority + Extended Vectors) Verified"
end
