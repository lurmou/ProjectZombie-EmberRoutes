local Tooltip = require "EmberRoutesProbe/UI/TooltipManager"
local Cached = require "EmberRoutesProbe/UI/CachedList"
local Filter = require "EmberRoutesProbe/Warehouse/StorageFilter"
local Editor = require "EmberRoutesProbe/Warehouse/FilterEditor"
local Flow = require "EmberRoutesProbe/UI/Text"
local Visual = require "EmberRoutesProbe/UI/StatusVisual"
local Theme = require "EmberRoutesProbe/UI/Theme"

local Rows = {}
local function text(key)
    return getTextOrNull and (getTextOrNull("IGUI_EmberRoutesProbe_Filter_" .. key) or getTextOrNull(key)) or key
end

---@param owner EmberRoutesStorageFilterPanel
---@param bounds {x:number, y:number, width:number, height:number}
---@return EmberRoutesFilterList
function Rows.create(owner, bounds)
    ---@type EmberRoutesFilterList
    local list = Cached.create(owner, bounds, nil, nil)
    list.itemheight = owner.rowHeight or 28
    list.font = UIFont.Small
    list:setWantKeyEvents(true)
    list.owner = owner
    list.doDrawItem = Rows.draw

    local function clampScroll(self)
        local total = (self.getScrollHeight and self:getScrollHeight()) or (self.items and #self.items * (self.itemheight or 0)) or 0
        local height = self.height or 0
        local maxScroll = math.max(0, total - height)
        if maxScroll <= 0 then
            if self.getYScroll and self:getYScroll() ~= 0 and self.setYScroll then self:setYScroll(0) end
            self.smoothScrollTargetY = nil
            self.smoothScrollY = nil
            return 0
        end
        local cur = self.getYScroll and self:getYScroll() or 0
        local clamped = math.max(-maxScroll, math.min(0, cur))
        if cur ~= clamped and self.setYScroll then self:setYScroll(clamped) end
        if self.smoothScrollTargetY then
            self.smoothScrollTargetY = math.max(-maxScroll, math.min(0, self.smoothScrollTargetY))
        end
        return maxScroll
    end

    local nativeMouseDown = list.onMouseDown
    list.onMouseDown = function(self, x, y)
        local rowIdx = self.rowAt and self:rowAt(x, y)
        if not rowIdx and self.items and self.itemheight then
            local curY = y - (self.getYScroll and self:getYScroll() or 0)
            rowIdx = math.floor(curY / self.itemheight) + 1
        end
        local entry = self.items and self.items[rowIdx]
        local row = entry and entry.item
        if row and row.hasChildren and x < (row.indent or 0) + 6 then
            self.owner:toggleCollapse(row)
            return true
        end
        if nativeMouseDown then return nativeMouseDown(self, x, y) end
    end

    local nativeWheel = list.onMouseWheel
    list.onMouseWheel = function(self, del)
        local maxScroll = math.max(0, self:getScrollHeight() - self.height)
        if maxScroll <= 0 then
            self:setYScroll(0)
            self.smoothScrollTargetY = nil
            self.smoothScrollY = nil
            return true
        end
        local res = nativeWheel(self, del)
        clampScroll(self)
        return res
    end

    local nativeSmooth = list.updateSmoothScrolling
    list.updateSmoothScrolling = function(self)
        local maxScroll = clampScroll(self)
        if maxScroll <= 0 then return end
        nativeSmooth(self)
        clampScroll(self)
    end

    local nativePre = list.prerender
    list.prerender = function(self)
        clampScroll(self)
        nativePre(self)
        clampScroll(self)
    end

    return list
end

---@param list EmberRoutesFilterList
---@param y number
---@param entry table
function Rows.draw(list, y, entry)
    local row = entry.item
    if not row then return y + (entry.height or list.itemheight) end
    local pad = list.owner.pad or 8
    local fh = list.owner.fontHeight or 16
    local height = entry.height or list.itemheight
    local visibleY = y + list:getYScroll()
    if visibleY + height < 0 or visibleY >= list.height then return y + height end

    -- Selection & Hover Backgrounds
    if list.selected == entry.index then
        list:drawRect(0, y, list.width, height, 0.30, 0.22, 0.38, 0.50)
        list:drawRectBorder(0, y, list.width, height, 0.6, Theme.accent.r, Theme.accent.g, Theme.accent.b)
    elseif list.mouseoverselected == entry.index then
        list:drawRect(0, y, list.width, height, 0.12, 0.65, 0.75, 0.85)
    end

    -- Bottom border line
    list:drawRect(0, y + height - 1, list.width, 1, 0.35, Theme.border.r, Theme.border.g, Theme.border.b)

    -- Root category styling
    if row.root then
        local c = row.color or {0.7, 0.7, 0.7}
        -- Left color accent (4px)
        list:drawRect(0, y, 4, height, 0.95, c[1], c[2], c[3])
        -- Subtle row tint
        list:drawRect(4, y, list.width - 4, height, 0.06, c[1], c[2], c[3])
    elseif row.kind == "enabled" or row.kind == "private" then
        -- Subtle permission row header
        list:drawRect(0, y, 4, height, 0.85, 0.4, 0.5, 0.6)
        list:drawRect(4, y, list.width - 4, height, 0.04, 0.4, 0.5, 0.6)
    end

    local x = row.indent or pad
    local box = fh
    local cy = (row.kind == "type") and (y + pad / 2) or (y + math.floor((height - box) / 2))

    -- Chevron / Folder icon
    if row.hasChildren then
        local foldCol = row.collapsed and {r=0.95, g=0.85, b=0.35, a=1} or {r=0.65, g=0.78, b=0.92, a=1}
        local ms = math.max(6, math.min(10, box - 2))
        Visual.mark(list, x - 16, cy + math.floor((box - ms) / 2), ms,
            row.collapsed and "plus" or "minus", foldCol)
    end

    -- Tri-state Checkbox Box
    list:drawRectBorder(x, cy, box, box, 0.85, 0.65, 0.72, 0.80)
    if row.mark == "[x]" then
        if list.owner.tickTexture then
            list:drawTextureScaledAspect(list.owner.tickTexture, x + 2, cy + 2, box - 4, box - 4, 1, 0.25, 0.95, 0.45)
        else
            list:drawRect(x + 3, cy + 3, box - 6, box - 6, 1, 0.25, 0.95, 0.45)
        end
    elseif row.mark == "[-]" then
        local inset = math.floor(box * 0.18)
        list:drawRect(x + inset, cy + math.floor(box / 2) - 2, box - inset * 2, 4, 1, 1.0, 0.75, 0.20)
    elseif row.mark == "[~]" then
        list:drawRect(x + 3, cy + box / 2 - 2, box - 6, 2, 1, 0.65, 0.85, 0.95)
        list:drawRect(x + 3, cy + box / 2 + 1, box - 6, 2, 1, 0.65, 0.85, 0.95)
    end

    -- Label Text
    local textColor = row.root and {0.98, 0.98, 0.95} or {0.88, 0.88, 0.86}
    list:drawText(row.caption or "", x + box + 8, cy, textColor[1], textColor[2], textColor[3], 1, UIFont.Small)
    if row.kind == "type" and row.id and row.id ~= row.caption then
        list:drawText(row.id, x + box + 8, cy + fh, 0.55, 0.65, 0.75, 1, UIFont.Small)
    end

    -- Right Status Pill (Aligned to Right Margin)
    if row.stateCaption then
        local stateColor = {r = 0.55, g = 0.60, b = 0.65}
        if row.mark == "[x]" then
            stateColor = {r = 0.35, g = 0.90, b = 0.45}
        elseif row.mark == "[-]" then
            stateColor = {r = 1.00, g = 0.75, b = 0.25}
        elseif row.mark == "[~]" then
            stateColor = {r = 0.55, g = 0.80, b = 0.95}
        end
        local sw = getTextManager():MeasureStringX(UIFont.Small, row.stateCaption)
        local pillX = list.width - pad - sw - 14
        list:drawRect(pillX, cy - 2, sw + 12, fh + 4, 0.35, stateColor.r * 0.3, stateColor.g * 0.3, stateColor.b * 0.3)
        list:drawRectBorder(pillX, cy - 2, sw + 12, fh + 4, 0.60, stateColor.r, stateColor.g, stateColor.b)
        list:drawText(row.stateCaption, pillX + 6, cy, stateColor.r, stateColor.g, stateColor.b, 1, UIFont.Small)
    end

    return y + height
end

---@param self EmberRoutesStorageFilterPanel
function Rows.refresh(self)
    local selected = self.list.selected
    Tooltip.clear(self.list)
    self.list:clear()

    local options = {
        itemsOnly = false,
        query = self.searchQuery or ""
    }

    local allowedCategories = 0
    local deniedCategories = 0

    for _, row in ipairs(Editor.rows(self.model, options)) do
        local label = row.kind == "group" and text(row.id) or text(row.label or row.kind)
        if row.kind == "type" then
            local resolveName = _G.getItemNameFromFullType
            label = type(resolveName) == "function" and resolveName(row.id) or row.id
            if not label or label == "" then label = row.id end
        end

        row.caption = label
        row.mark = Editor.mark(self.model, row)
        row.root = row.kind == "group" and row.depth == 0
        row.color = row.root and Filter.nodes[row.id] and Filter.nodes[row.id].color or nil
        row.indent = (self.pad or 8) + 18 + math.min(row.depth or 0, 4) * (self.pad or 8) * 1.8
        row.lines = Flow.wrap(label, math.max(160, self.list.width - row.indent - self.fontHeight - (self.pad or 8) * 3 - 60), UIFont.Small)
        if not row.lines or #row.lines == 0 then row.lines = { label } end

        if row.root then
            if row.mark == "[x]" or row.mark == "[-]" then
                allowedCategories = allowedCategories + 1
            else
                deniedCategories = deniedCategories + 1
            end
        end

        if row.kind == "type" then
            row.stateCaption = text(row.mark == "[~]" and "inherit" or (row.mark == "[x]" and "allow" or "deny"))
        elseif row.kind == "enabled" or row.kind == "private" then
            row.stateCaption = text(row.mark == "[x]" and "configEnabled" or "disabled")
        elseif row.mark == "[-]" then
            row.stateCaption = text("partial")
        elseif row.mark == "[x]" then
            row.stateCaption = text("all")
        else
            row.stateCaption = text("none")
        end

        local itemH = (row.kind == "type") and (self.fontHeight * 2 + self.pad) or math.max(self.rowHeight or 28, self.fontHeight + self.pad)
        self.list.itemheight = itemH
        self.list:addItem(label, row, row.kind == "type" and (label .. "\n" .. row.id) or label)
    end

    self.list.itemheight = self.rowHeight or 28
    self.list.selected = math.max(1, math.min(selected or 1, #self.list.items))
    self.allowedCategoryCount = allowedCategories
    self.deniedCategoryCount = deniedCategories
end

return Rows
