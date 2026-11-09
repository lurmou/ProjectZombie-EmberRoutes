require "env"
ISInventoryPage = ISInventoryPage or {}
require "ISUI/ISPanel"
require "ISUI/ISScrollBar"
require "ISUI/ISCollapsableWindow"
local StorageFilterPanel = require "EmberRoutesProbe/UI/StorageFilterPanel"
local Filter = require "EmberRoutesProbe/Warehouse/StorageFilter"

-- Create a mock container with realistic safehouse items
local mockItems = {}
local function addItem(fullType, cat, disp)
    local item = {
        _fullType = fullType,
        _category = cat or "Item",
        _display = disp or "Item"
    }
    function item:getFullType() return self._fullType end
    function item:getCategory() return self._category end
    function item:getDisplayCategory() return self._display end
    function item:isFood() return false end
    function item:isRanged() return false end
    function item:getAge() return 0 end
    function item:getOffAgeMax() return 100 end
    function item:isRotten() return false end
    function item:isCooked() return false end
    function item:IsClothing() return false end
    function item:IsContainer() return false end
    mockItems[#mockItems + 1] = item
end

addItem("Base.CannedBeans", "Food", "Food")
addItem("Base.Hammer", "Weapon", "Tool")
addItem("Base.Screwdriver", "Weapon", "Tool")
addItem("Base.Bandage", "Medical", "Medical")
addItem("Base.Pills", "Medical", "Medical")
addItem("Base.Shotgun", "Weapon", "Weapon")
addItem("Base.ShotgunShellsBox", "Item", "Ammo")
addItem("Base.Pen", "Weapon", "Item")
addItem("Base.BookCarpentry1", "Literature", "Literature")
addItem("Base.Plank", "Item", "Material")
addItem("Base.NailsBox", "Item", "Material")

local mockContainer = {
    _items = mockItems,
    _type = "crate"
}
function mockContainer:getType() return self._type end
function mockContainer:getItems()
    local list = { _raw = self._items }
    function list:size() return #self._raw end
    function list:get(i) return self._raw[i + 1] end
    return list
end

local square = {
    getX = function() return 1000 end,
    getY = function() return 1000 end,
    getZ = function() return 0 end,
    getRoom = function()
        return {
            getName = function() return "kitchen" end
        }
    end
}

local mockData = {
    EmberRoutesContainer = {
        tag = "storage",
        filter = Filter.new(),
        logisticsRole = "STORAGE"
    }
}

local mockObject = {
    _container = mockContainer,
    getContainer = function(self) return self._container end,
    getSquare = function() return square end,
    getModData = function() return mockData end,
    getSprite = function() return { getName = function() return "carpentry_01_16" end } end
}

local function makeMockCont(contType, items)
    local cont = { _items = items or {}, _type = contType }
    function cont:getType() return self._type end
    function cont:getItems()
        local list = { _raw = self._items }
        function list:size() return #self._raw end
        function list:get(i) return self._raw[i + 1] end
        return list
    end
    return cont
end

local function makeMockObj(cont, sq, spriteName)
    return {
        _container = cont,
        getContainer = function(self) return self._container end,
        getSquare = function() return sq end,
        getModData = function() return {
            EmberRoutesContainer = { tag = "storage", filter = Filter.new(), logisticsRole = "STORAGE" }
        } end,
        getSprite = function() return { getName = function() return spriteName or "carpentry_01_16" end } end
    }
end

local obj2 = makeMockObj(makeMockCont("metal_shelves"), { getX = function() return 1002 end, getY = function() return 1000 end, getZ = function() return 0 end }, "metal_shelves_01")
local obj3 = makeMockObj(makeMockCont("freezer"), { getX = function() return 1000 end, getY = function() return 1003 end, getZ = function() return 0 end }, "appliances_refrigeration_01")

_G.getCell = function()
    return {
        getGridSquare = function(_, x, y, z)
            local list = {}
            if x == 1000 and y == 1000 then list[1] = mockObject
            elseif x == 1002 and y == 1000 then list[1] = obj2
            elseif x == 1000 and y == 1003 then list[1] = obj3
            end
            if #list == 0 then return nil end
            return {
                getX = function() return x end,
                getY = function() return y end,
                getZ = function() return z end,
                getObjects = function()
                    return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
                end
            }
        end
    }
end

local actor = {
    _num = 0,
    getPlayerNum = function(self) return self._num end,
    getJoypadBind = function() return -1 end,
    getX = function() return 1000 end,
    getY = function() return 1000 end,
    getZ = function() return 0 end,
    Say = function(_, msg) end,
    getModData = function() return {} end
}
function getSpecificPlayer(index) if index == 0 then return actor end end

-- Backdrop host
local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
local host = ISPanel:new(0, 0, sw, sh)
host:initialise()
host:instantiate()
host.background = true
host.backgroundColor = { r = 0.08, g = 0.09, b = 0.11, a = 1.0 }

host.render = function(self)
    self:drawText("EmberRoutes Storage Filter Configuration Preview", 24, 14, 0.9, 0.92, 0.95, 1, UIFont.Medium)
    self:drawText("Testing Layout, Typography, Controls, Priority and Smart Zoning in Native OpenGL", 24, 36, 0.55, 0.60, 0.65, 1, UIFont.Small)
end

-- Open StorageFilterPanel
local panel = StorageFilterPanel:new(actor, mockObject, mockContainer)
panel:initialise()
panel:instantiate()
host:addChild(panel)

NativePreview = host
NativePreview.smoke = function(self)
    assert(panel ~= nil, "StorageFilterPanel created")
    assert(panel.list ~= nil, "FilterList created")
    assert(#panel.list.items > 0, "FilterList populated with category tree")
    self.smokeSummary = "StorageFilterPanel native preview successfully rendered"
end
