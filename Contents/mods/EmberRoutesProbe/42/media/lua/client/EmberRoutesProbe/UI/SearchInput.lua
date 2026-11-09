--[[
    SearchInput.lua - EmberRoutes UI
    Mechanism: Ergonomic Flat 2.0 Search & Text Input Component.
    
    Architectural Invariants:
      - Encapsulates embedded left search icon (StatusVisual "search").
      - Embedded dynamic clear button (StatusVisual "cross") with hover feedback and ESC reset.
      - 2px Focus Ring outline (Theme.accent) when focused.
      - Zero-GC Prerender: Reuses Theme colors and static scalar dimensions.
      - Seamless LayoutHost integration: Implements onResize for responsive resizing.
]]

require "ISUI/ISPanel"
require "ISUI/ISTextEntryBox"
local Theme = require "EmberRoutesProbe/UI/Theme"
local StatusVisual = require "EmberRoutesProbe/UI/StatusVisual"

---@class EmberRoutesSearchInput:ISPanel
---@field entry ISTextEntryBox
---@field placeholder string
---@field onTextChangeFunction function?
---@field target any
---@field pad number
---@field iconSize number
local SearchInput = ISPanel:derive("EmberRoutesSearchInput")

---@param x number
---@param y number
---@param width number
---@param height number
---@param placeholder string?
---@param target any?
---@param onChange function?
---@return EmberRoutesSearchInput
function SearchInput:new(x, y, width, height, placeholder, target, onChange)
    local o = ISPanel.new(self, x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.placeholder = placeholder or ""
    o.target = target
    o.onTextChangeFunction = onChange
    o.pad = 6
    o.iconSize = 14
    o.background = false

    o:initialise()
    return o
end

function SearchInput:initialise()
    ISPanel.initialise(self)
end

function SearchInput:createChildren()
    ISPanel.createChildren(self)

    local pad = self.pad or 6
    local iconSize = self.iconSize or 14
    local entryX = pad + iconSize + 6
    local entryW = math.max(20, self.width - entryX - (iconSize + pad + 2))
    local entryH = math.max(16, self.height - 2)

    local entry = ISTextEntryBox:new("", entryX, 1, entryW, entryH)
    entry:initialise()
    entry:instantiate()
    entry.background = false
    entry.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    entry.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    entry.textColor = Theme.textColor
    if entry.setClearButton then entry:setClearButton(false) end
    entry.target = self
    entry.onTextChange = function()
        self:onInnerChange()
    end
    entry.onTextChangeFunction = function()
        self:onInnerChange()
    end
    if self.placeholder and self.placeholder ~= "" and entry.setPlaceholderText then
        entry:setPlaceholderText(self.placeholder)
    end

    self:addChild(entry)
    self.entry = entry
end

function SearchInput:onResize()
    ISPanel.onResize(self)
    if self.entry then
        local pad = self.pad or 6
        local iconSize = self.iconSize or 14
        local entryX = pad + iconSize + 6
        local entryW = math.max(20, self.width - entryX - (iconSize + pad + 2))
        local entryH = math.max(16, self.height - 2)
        self.entry:setX(entryX)
        self.entry:setWidth(entryW)
        self.entry:setHeight(entryH)
    end
end

function SearchInput:onInnerChange()
    local val = self:getText()
    if self.onTextChangeFunction then
        self.onTextChangeFunction(self.target or self, val, self)
    end
end

function SearchInput:getText()
    return self.entry and self.entry:getText() or ""
end

function SearchInput:setText(text)
    if self.entry then
        self.entry:setText(text)
    end
end

function SearchInput:setPlaceholderText(text)
    self.placeholder = text or ""
    if self.entry and self.entry.setPlaceholderText then
        self.entry:setPlaceholderText(self.placeholder)
    end
end

function SearchInput:isFocused()
    if self.focused == true then return true end
    if not self.entry then return false end
    if self.entry.focused == true then return true end
    if self.entry.isFocused then return self.entry:isFocused() == true end
    if self.entry.javaObject and self.entry.javaObject.isFocused then
        return self.entry.javaObject:isFocused() == true
    end
    return false
end

function SearchInput:focus()
    self.focused = true
    if self.entry then
        self.entry.focused = true
        if self.entry.focus then self.entry:focus() end
    end
end

function SearchInput:unfocus()
    self.focused = false
    if self.entry then
        self.entry.focused = false
        if self.entry.unfocus then self.entry:unfocus() end
    end
end

function SearchInput:clear()
    self:setText("")
    self:onInnerChange()
end

function SearchInput:isOverClear(x, y)
    local text = self:getText()
    if not text or text == "" then return false end
    local pad = self.pad or 6
    local iconSize = self.iconSize or 14
    local clearX = self.width - iconSize - pad - 4
    return x >= clearX and x <= self.width and y >= 0 and y <= self.height
end

function SearchInput:onMouseDown(x, y)
    if self:isOverClear(x, y) then
        self:clear()
        return true
    end
    if self.entry and self.entry.focus then
        self.entry:focus()
    end
    return true
end

function SearchInput:prerender()
    -- 1. Base card / panel background
    local bg = Theme.panel
    self:drawRect(0, 0, self.width, self.height, bg.a or 0.95, bg.r, bg.g, bg.b)

    -- 2. Border & Focus Ring (2px Theme.accent when focused)
    local isFocused = self:isFocused()
    if isFocused then
        local fc = Theme.accent
        self:drawRectBorder(-1, -1, self.width + 2, self.height + 2, 0.95, fc.r, fc.g, fc.b)
    else
        local bc = Theme.border
        self:drawRectBorder(0, 0, self.width, self.height, bc.a or 0.90, bc.r, bc.g, bc.b)
    end

    -- 3. Left Search Icon
    local pad = self.pad or 6
    local iconSize = self.iconSize or 14
    local iconY = math.floor((self.height - iconSize) / 2)
    local iconColor = isFocused and Theme.accent or Theme.muted
    StatusVisual.icon(self, pad, iconY, iconSize, "search", iconColor)

    -- 4. Right Clear Button
    local text = self:getText()
    if text and text ~= "" then
        local clearX = self.width - iconSize - pad
        local mx = self:getMouseX()
        local my = self:getMouseY()
        local isHover = self:isOverClear(mx, my)
        local clearColor = isHover and Theme.textColor or Theme.muted
        StatusVisual.icon(self, clearX, iconY, iconSize, "cross", clearColor)
    end
end

return SearchInput
