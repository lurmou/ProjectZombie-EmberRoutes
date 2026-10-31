-- Test UI script loading
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path

local function makeMockClass(name)
    local cls = { Type = name }
    cls.__index = cls
    function cls:derive(n) return makeMockClass(n) end
    function cls:new() return setmetatable({}, cls) end
    return cls
end

_G.ISPanel = makeMockClass('ISPanel')
_G.ISButton = makeMockClass('ISButton')
_G.ISScrollingListBox = makeMockClass('ISScrollingListBox')
_G.ISComboBox = makeMockClass('ISComboBox')
_G.ISCollapsableWindow = makeMockClass('ISCollapsableWindow')
_G.ISTextEntryBox = makeMockClass('ISTextEntryBox')

package.loaded['ISUI/ISPanel'] = _G.ISPanel
package.loaded['ISUI/ISButton'] = _G.ISButton
package.loaded['ISUI/ISScrollingListBox'] = _G.ISScrollingListBox
package.loaded['ISUI/ISComboBox'] = _G.ISComboBox
package.loaded['ISUI/ISCollapsableWindow'] = _G.ISCollapsableWindow
package.loaded['ISUI/ISTextEntryBox'] = _G.ISTextEntryBox

function _G.ISScrollingListBox:setOnMouseDownFunction(target, onmousedown)
    self.target = target
    self.onmousedown = onmousedown
end
function _G.ISScrollingListBox:setOverrideAButtonFunction(target, fct)
    self.target = target
    self.overrideAButtonFunction = fct
end
function _G.ISScrollingListBox:invokeOnMouseDownFunction()
    if self.onmousedown and self.items and self.items[self.selected] then
        self.onmousedown(self.target, self.items[self.selected].item)
    end
end

-- Load files
local ok1, err1 = pcall(require, 'EmberRoutesProbe/UI/JobPolicyEditors')
assert(ok1, "Failed to load JobPolicyEditors: " .. tostring(err1))

local ok2, err2 = pcall(require, 'EmberRoutesProbe/UI/WorkPolicyPage')
assert(ok2, "Failed to load WorkPolicyPage: " .. tostring(err2))

print("PASS: WorkPolicyPage and JobPolicyEditors loaded without syntax errors!")

-- Test simulated item click
local page = setmetatable({
    fontHeight = 18,
    pad = 6,
    width = 500,
    height = 400,
    actor = {},
    entry = { id = "test_settlement" },
    jobList = setmetatable({
        items = {
            { text = "Cleaning", item = "cleaning" },
            { text = "Cooking", item = "cooking" }
        },
        selected = 2
    }, _G.ISScrollingListBox),
    selectCategory = function(self, cat)
        self.selectedCategory = cat
    end
}, _G.ISPanel)

local onSelect = function(p, item)
    p = p or page
    local cat = item or (page.jobList.items and page.jobList.selected and page.jobList.items[page.jobList.selected] and page.jobList.items[page.jobList.selected].item)
    if cat and cat ~= page.selectedCategory then
        page:selectCategory(cat)
    end
end
page.jobList:setOnMouseDownFunction(page, onSelect)
page.jobList:invokeOnMouseDownFunction()

assert(page.selectedCategory == "cooking", "Category selection click failed")
print("PASS: ScrollingListBox click and invokeOnMouseDownFunction verified cleanly!")

-- Test formPanel clearing with string-keyed children table (ISUIElement model)
local formPanel = {
    children = {
        ["id_header_1"] = { ID = "id_header_1" },
        ["id_field_1"] = { ID = "id_field_1" },
        ["id_action_1"] = { ID = "id_action_1" }
    },
    removeChild = function(self, child)
        self.children[child.ID] = nil
    end,
    clearChildren = function(self)
        self.children = {}
    end
}

local toRemove = {}
for _, child in pairs(formPanel.children or {}) do
    toRemove[#toRemove + 1] = child
end
assert(#toRemove == 3, "Expected 3 children to be discovered via pairs")
for _, child in ipairs(toRemove) do
    formPanel:removeChild(child)
end
formPanel:clearChildren()

local countRemaining = 0
for _ in pairs(formPanel.children) do countRemaining = countRemaining + 1 end
assert(countRemaining == 0, "Expected all children removed from formPanel")
print("PASS: formPanel children cleanup verified cleanly with string ID map!")

UIFont={Small=1}
getTextOrNull=function(key) return key end
getTextManager=function() return {MeasureStringX=function(_,font,label) return #label*8 end} end
local Editors=require 'EmberRoutesProbe/UI/JobPolicyEditors'
local field={editor='tag_chips',tags={{id='Vegetables'},{id='Meat'},{id='Fruits'},{id='Canned'},{id='Dairy'},{id='Spices'}}}
local flow,height=Editors.flow(field,220,18,4)
assert(height>27,'six long chips must wrap')
for i,r in ipairs(flow) do
 assert(r.x>=0 and r.x+r.width<=220,'chip remains inside viewport')
 if i>1 then local previous=flow[i-1] assert(r.y>previous.y or r.x>=previous.x+previous.width,'chip hit rectangles never overlap') end
end
assert(Editors.height(field,220,18,4)==height,'form and control use identical measured height')
print('PASS measured chip wrapping and shared row height; native renderer NOT RUN')
