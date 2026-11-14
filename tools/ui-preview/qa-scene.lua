require 'env'
require 'ISUI/ISLabel'
local Launch=require 'EmberRoutesProbe/UI/QaLaunchButton'
NativePreview=ISPanel:new(0,0,900,500)
NativePreview:initialise() NativePreview:instantiate()
local note=ISLabel:new(28,110,28,'QA launcher - native controls, synthetic main-menu background',1,1,1,1,UIFont.Small,true)
note:initialise() NativePreview:addChild(note)
local launches=0
local control=Launch.new(NativePreview,function() launches=launches+1 return true end)
NativePreview.smoke=function(self)
    local b=control.button
    self.javaObject:onMouseDown(b:getX()+8,b:getY()+8)
    self.javaObject:onMouseUp(b:getX()+8,b:getY()+8)
    assert(launches==1,'QA native button did not dispatch')
    assert(not b:isEnabled(),'QA launch must disable duplicate start')
    control:dispose()
    assert(not self.children[b.ID],'QA button leaked after disposal')
    control=Launch.new(self,function() return false end)
    local failed=control.button
    self.javaObject:onMouseDown(failed:getX()+8,failed:getY()+8)
    self.javaObject:onMouseUp(failed:getX()+8,failed:getY()+8)
    assert(failed:isEnabled(),'QA failure must allow a retry')
    assert(failed:getTitle()==getText('IGUI_EmberRoutesProbe_QA_StartFailed'),'QA failure feedback missing')
    control:dispose()
    control=Launch.new(self,function() return true end)
    self.smokeSummary='QA launch, duplicate guard, failure/retry, disposal'
end
