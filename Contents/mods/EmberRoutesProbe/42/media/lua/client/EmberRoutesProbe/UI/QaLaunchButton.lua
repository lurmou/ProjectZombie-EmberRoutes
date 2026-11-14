require 'ISUI/ISButton'
local Lifecycle=require 'EmberRoutesProbe/UI/PageLifecycle'
local Q={}
function Q.new(screen,start)
    local page={screen=screen}
    local lifetime=Lifecycle.createLifetimeScope(page)
    local activation=Lifecycle.createActivationScope(page)
    local height=getTextManager():getFontHeight(UIFont.Medium)+16
    local title=getText('IGUI_EmberRoutesProbe_QA_Launch')
    local width=math.max(280,getTextManager():MeasureStringX(UIFont.Medium,title)+32)
    local callback=activation:wrapCallback(function()
        page.button:setEnable(false)
        page.button:setTitle(getText('IGUI_EmberRoutesProbe_QA_Starting'))
        local ok,accepted=pcall(start)
        if not ok or accepted~=true then
            page.button:setTitle(getText('IGUI_EmberRoutesProbe_QA_StartFailed'))
            page.button:setEnable(true)
        end
    end)
    page.button=ISButton:new(0,32,width,height,title,nil,callback)
    page.button:initialise() page.button:instantiate()
    page.button:setFont(UIFont.Medium)
    screen:addChild(page.button)
    lifetime:defer(function() screen:removeChild(page.button) end)
    function page:relayout() self.button:setX(math.max(16,screen:getWidth()-width-32)) end
    function page:dispose() Lifecycle.dispose(self) end
    page:relayout()
    return page
end
return Q
