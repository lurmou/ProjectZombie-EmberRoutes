require "preview/native-scene"
require "ISUI/ISScrollBar"
require "ISUI/ISScrollingListBox"
local StepperInput = require "EmberRoutesProbe/UI/StepperInput"
local CardPanel = require "EmberRoutesProbe/UI/CardPanel"

NativePreview:setWidth(800)
NativePreview:setHeight(390)
NativePreview.moveWithMouse = true
local baseRender = NativePreview.render
local cardOptions = {title = "Real project CardPanel", selected = true}
local stepper = StepperInput:new(400, 210, 360, 34, 5, 1, 20, nil, function(value)
    NativePreview.sampleValue = value
end)
stepper:instantiate()
NativePreview:addChild(stepper)
NativePreview.sampleValue = 5
local list = ISScrollingListBox:new(400, 260, 360, 105)
list:initialise()
list:instantiate()
list:setFont(UIFont.Small, 4)
for index = 1, 12 do list:addItem("Native scrolling row " .. index, index) end
NativePreview:addChild(list)
NativePreview.render = function(self)
    CardPanel.draw(self, 400, 16, 360, 130, cardOptions)
    baseRender(self)
    self:drawText("Drag the panel background | Hover and click the stepper", 16, 300, 1, 1, 1, 1, UIFont.Small)
    self:drawText("StepperInput + native UITextBox2", 400, 170, 0.7, 0.8, 0.9, 1, UIFont.Small)
end
local baseSmoke = NativePreview.smoke
NativePreview.smoke = function(self)
    baseSmoke(self)
    local plus = stepper.stepButtons[3]
    local x, y = stepper.x + plus.x + 8, stepper.y + plus.y + 8
    self.javaObject:onMouseDown(x, y)
    self.javaObject:onMouseUp(x, y)
    assert(stepper.value == 6 and self.sampleValue == 6, "Real stepper +1 callback failed")
    stepper:setValue(20)
    plus:forceClick()
    assert(stepper.value == 20, "Real stepper maximum guard failed")
    list:onMouseWheel(1)
    assert(list.smoothScrollTargetY and list.smoothScrollTargetY < 0, "Native list scroll target did not advance")
    self.smokeSummary = "Project StepperInput +1/max and native scroll target passed"
    print("PASS project StepperInput callback and maximum guard")
end
