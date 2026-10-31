-- tests/lua/vanilla-crafting-hook-test.lua
-- Verification for vanilla B42 Crafting UI hook & settlement delegation entry.

local count = 0
local function check(v, s) count = count + 1 assert(v, s) end

_G.Events = _G.Events or {}
for _, name in ipairs({'OnGameStart', 'OnServerStarted', 'OnTick'}) do
    _G.Events[name] = _G.Events[name] or { Add = function() end, Remove = function() end }
end

-- Mock ISUI primitives
local Base = {}
function Base:derive(name)
    local cls = { Type = name }
    cls.__index = cls
    return setmetatable(cls, { __index = self })
end
function Base.new(self, x, y, w, h, title, target, callback)
    if type(self) ~= 'table' then
        callback = target target = title title = h h = w w = y y = x x = self self = Base
    end
    return setmetatable({
        x = x or 0, y = y or 0, width = w or 0, height = h or 0,
        title = title or '', target = target, onclick = callback,
        children = {}, visible = true, enable = true
    }, { __index = self })
end
function Base:initialise() end
function Base:instantiate() end
function Base:addChild(c) self.children[#self.children + 1] = c end
function Base:getX() return self.x end
function Base:getY() return self.y end
function Base:getWidth() return self.width end
function Base:getHeight() return self.height end
function Base:setX(v) self.x = v end
function Base:setY(v) self.y = v end
function Base:setWidth(v) self.width = v end
function Base:setHeight(v) self.height = v end
function Base:setVisible(v) self.visible = v end
function Base:isVisible() return self.visible end

ISPanelJoypad = Base:derive('ISPanelJoypad')
ISButton = Base:derive('ISButton')
UIFont = { Small = 1, Medium = 2 }
getTextManager = function() return {
    getFontHeight = function() return 16 end,
    MeasureStringX = function(_, _, s) return #s * 8 end
} end
getText = function(key) return key end

-- Mock ISWidgetHandCraftControl
ISWidgetHandCraftControl = ISPanelJoypad:derive('ISWidgetHandCraftControl')
function ISWidgetHandCraftControl:createChildren()
    self.buttonCraft = ISButton:new(100, 200, 120, 24, 'Craft', self, function() end)
    self:addChild(self.buttonCraft)
end
function ISWidgetHandCraftControl:calculateLayout(pw, ph)
    self.width = pw or 400
    self.height = ph or 300
    self.buttonCraft:setX(200)
    self.buttonCraft:setY(250)
    self.buttonCraft:setWidth(150)
    self.buttonCraft:setHeight(24)
end
function ISWidgetHandCraftControl:onInputsChanged()
    -- vanilla disables buttonCraft if player has no materials in inventory
    self.buttonCraft.enable = false
end

-- Mock Game Actor, Recipe, Settlement Ledger & Dashboard
local openedContext = nil
local playerSaid = nil
local mockPlayer = {
    x = 100, y = 200,
    getX = function(self) return self.x end,
    getY = function(self) return self.y end,
    isRecipeKnown = function(self, r, b) return true end,
    Say = function(self, msg) playerSaid = msg end
}
getPlayer = function() return mockPlayer end

package.loaded['EmberRoutesProbe/SettlementLedger'] = {
    at = function(x, y)
        if x == 100 and y == 200 then
            return { { id = 'settlement_alpha', name = 'Alpha Sanctuary' } }
        end
        return {}
    end
}

package.loaded['EmberRoutesProbe/SettlementDashboard'] = {
    open = function(actor, id, tabId)
        return {
            openPublicOrder = function(self, ctx)
                openedContext = ctx
            end
        }
    end
}

-- 1. Install Hook
local Hook = require 'EmberRoutesProbe/VanillaCraftingHook'
Hook.install()

-- 2. Test instantiation and button injection
local widget = ISWidgetHandCraftControl:new(0, 0, 400, 300)
widget.player = mockPlayer
widget.logic = {
    getRecipe = function()
        return {
            getName = function() return 'Base.MakeWoodenSpear' end,
            getOriginalname = function() return 'Make Wooden Spear' end,
            getTranslationName = function() return '制作木矛' end
        }
    end
}
widget:createChildren()

check(widget.buttonEmberDelegate ~= nil, 'buttonEmberDelegate injected into ISWidgetHandCraftControl')
check(widget.buttonEmberDelegate.title == 'IGUI_EmberRoutesProbe_Vanilla_delegateButton', 'delegate button titled correctly')

-- 3. Test layout sizing & dual-button arrangement
widget:calculateLayout(400, 300)
check(widget.buttonCraft:getWidth() < 150, 'buttonCraft width adjusted to share space')
check(widget.buttonEmberDelegate:getX() > widget.buttonCraft:getX(), 'buttonEmberDelegate positioned alongside buttonCraft')
check(widget.buttonEmberDelegate:getWidth() > 50, 'buttonEmberDelegate has reasonable width')
check(widget.buttonEmberDelegate:getHeight() == widget.buttonCraft:getHeight(), 'buttonEmberDelegate height matches craft button')

-- 4. Test button availability independent of player personal materials
widget:onInputsChanged()
check(widget.buttonCraft.enable == false, 'vanilla craft button disabled due to no personal materials')
check(widget.buttonEmberDelegate.enable == true, 'ember delegate button remains enabled because settlement has storage')

-- 5. Test clicking delegate button opens PublicOrderDialog with recipe
widget.buttonEmberDelegate.onclick(widget.buttonEmberDelegate.target)
check(openedContext ~= nil, 'PublicOrderDialog was triggered')
check(openedContext.recipeId == 'Base.MakeWoodenSpear', 'delegated recipeId passed accurately')
check(openedContext.recipeName == '制作木矛', 'recipeName passed accurately')

-- 6. Test outside settlement territory defense
mockPlayer.x = 99999
mockPlayer.y = 99999
openedContext = nil
playerSaid = nil
widget.buttonEmberDelegate.onclick(widget.buttonEmberDelegate.target)
check(openedContext == nil, 'cannot open settlement dialog outside settlement territory')
check(playerSaid == 'IGUI_EmberRoutesProbe_Vanilla_noSettlement', 'player receives informative feedback when outside territory')

print('PASS ' .. count .. ' vanilla crafting hook and settlement delegation checks; native host mocked')
