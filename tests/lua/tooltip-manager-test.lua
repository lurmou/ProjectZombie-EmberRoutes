-- Unit test for TooltipManager
local checks=0
local function check(v,m) assert(v,m) checks=checks+1 end

local sw,sh=1920,1080
getCore=function() return {getScreenWidth=function() return sw end,getScreenHeight=function() return sh end} end
local mouseX,mouseY=100,200
getMouseX=function() return mouseX end
getMouseY=function() return mouseY end

local TooltipManager=require 'EmberRoutesProbe/UI/TooltipManager'

local function makeTooltip()
    return {
        x=0,y=0,w=200,h=50,visible=false,added=false,
        followMouse=true,
        getIsVisible=function(s) return s.visible end,
        setVisible=function(s,v) s.visible=v end,
        getWidth=function(s) return s.w end,
        getHeight=function(s) return s.h end,
        setX=function(s,v) s.x=v end,
        setY=function(s,v) s.y=v end,
        setName=function(s,v) s.name=v end,
        removeFromUIManager=function(s) s.added=false s.visible=false end
    }
end

local function makeWidget(owner)
    local tip=makeTooltip()
    return {
        owner=owner,
        tooltipUI=tip,
        tooltip='initial',
        rendered=false,
        prerender=function(s) s.rendered=true end
    }
end

-- 1. Test register and attach
local page={name='PageA'}
local w1=makeWidget(page)
TooltipManager.attach(w1,'prerender',page)

check(type(w1.prerender)=='function','attach hooks prerender')
w1.tooltipUI:setVisible(true)
w1:prerender()
check(w1.rendered==true,'original prerender executed')
check(w1.tooltipUI.x==132 and w1.tooltipUI.y==210,'position offset anchored (100+32, 200+10)')

-- 2. Test screen bounds clamping
mouseX,mouseY=1850,1050 -- near screen bottom-right
w1:prerender()
check(w1.tooltipUI.x<=1920-200 and w1.tooltipUI.y<=1080-50,'position clamped within screen bounds')

-- 3. Test update
TooltipManager.update(w1,'Updated text')
check(w1.tooltip=='Updated text' and w1.tooltipUI.name=='Updated text','tooltip text updated')

-- 4. Test clear single widget
TooltipManager.clear(w1)
check(w1.tooltipUI:getIsVisible()==false,'single clear sets visible false')

-- 5. Test clearOwner cascading
local w2=makeWidget(page)
w2.tooltipUI:setVisible(true)
TooltipManager.attach(w2,'prerender',page)

local w3=makeWidget(page)
w3.tooltipUI:setVisible(true)
TooltipManager.attach(w3,'prerender',page)

-- Another page
local otherPage={name='PageB'}
local wOther=makeWidget(otherPage)
wOther.tooltipUI:setVisible(true)
TooltipManager.attach(wOther,'prerender',otherPage)

TooltipManager.clearOwner(page)
check(w2.tooltipUI:getIsVisible()==false,'cascading clearOwner clears w2')
check(w3.tooltipUI:getIsVisible()==false,'cascading clearOwner clears w3')
check(wOther.tooltipUI:getIsVisible()==true,'other page tooltips remain unaffected')

TooltipManager.clearOwner(otherPage)
check(wOther.tooltipUI:getIsVisible()==false,'clearOwner clears other page')

-- 6. Test sub-panel cascading
local complexPage={
    details={locate=makeWidget(),pinButton=makeWidget()},
    controls={sort=makeWidget()},
    buttons={b1=makeWidget(),b2=makeWidget()}
}
complexPage.details.locate.tooltipUI:setVisible(true)
complexPage.details.pinButton.tooltipUI:setVisible(true)
complexPage.controls.sort.tooltipUI:setVisible(true)
complexPage.buttons.b1.tooltipUI:setVisible(true)

TooltipManager.clearOwner(complexPage)
check(complexPage.details.locate.tooltipUI:getIsVisible()==false,'clears sub-panel details.locate')
check(complexPage.details.pinButton.tooltipUI:getIsVisible()==false,'clears sub-panel details.pinButton')
check(complexPage.controls.sort.tooltipUI:getIsVisible()==false,'clears sub-panel controls.sort')
check(complexPage.buttons.b1.tooltipUI:getIsVisible()==false,'clears sub-panel buttons')

print('tooltip-manager: '..checks..' PASS')
