require "env"
require "ISUI/ISButton"

NativePreview = ISPanel:new(56, 140, 560, 320)
NativePreview:initialise()
NativePreview:instantiate()
NativePreview.clicks = 0
NativePreview.render = function(self)
    self:drawText("Native ISPanel + ISButton (installed Lua)", 16, 16, 1, 1, 1, 1, UIFont.Medium)
    self:drawText("Data: synthetic | Audio: muted | No world loaded", 16, 48, 0.7, 0.7, 0.7, 1, UIFont.Small)
    self:drawText(PreviewChineseText, 16, 145, 1, 1, 1, 1, UIFont.Medium)
    self:drawRect(16, 180, 340, 64, 1, 0.12, 0.2, 0.25)
    self:setStencilRect(16, 180, 340, 64)
    self:drawRect(-20, 200, 440, 34, 0.45, 0.3, 0.7, 0.5)
    self:drawText("Clipped native text extends beyond the viewport >>>>>>>>>>>>>>>", 24, 210, 1, 1, 1, 1, UIFont.Small)
    self:clearStencilRect()
    self:drawText("Stencil cleared: this line must remain visible", 16, 260, 0.7, 0.8, 0.7, 1, UIFont.Small)
    self:drawTextureScaled(self.previewTexture, 460, 90, 48, 48, 1, 1, 1, 1)
end
NativePreview.previewTexture = getTexture("media/ui/Container_ClothingWasher.png")
assert(NativePreview.previewTexture, "Native texture missing")
local function onClick(self, button)
    self.clicks = self.clicks + 1
    button:setTitle("Clicked " .. self.clicks)
end
local button = ISButton:new(16, 90, 170, 36, "Native button", NativePreview, onClick)
button:initialise()
button:instantiate()
NativePreview:addChild(button)
NativePreview.button = button
NativePreview.smoke = function(self)
    self.javaObject:onMouseDown(40, 110)
    self.javaObject:onMouseUp(40, 110)
    assert(self.clicks == 1, "Native click dispatch failed")
    self.javaObject:onMouseDown(230, 110)
    self.javaObject:onMouseUp(230, 110)
    assert(self.clicks == 1, "Disabled button accepted click")
end
local disabled = ISButton:new(200, 90, 170, 36, "Disabled", NativePreview, onClick)
disabled:initialise()
disabled:instantiate()
disabled:setEnable(false)
NativePreview:addChild(disabled)
