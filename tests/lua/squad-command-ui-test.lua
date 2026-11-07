local ctx=dofile('tests/lua/membership-command-test.lua')
local Membership,actor=ctx.service,ctx.actor
local checks,now,binds,portraitReleases,watches,measure=0,0,0,0,0,0
local function check(v,m) checks=checks+1 assert(v,m) end
function getText(key) return key end
function getTextOrNull(key)
    if key:find('UNMAPPED_TEST') then return nil end
    return key..'_translated'
end
function getTimestampMs() return now end
local function event()
    local e={listeners={}}
    function e.Add(fn) e.listeners[fn]=true end
    function e.Remove(fn) e.listeners[fn]=nil end
    return e
end
Events={OnGameStart=event(),OnNewGame=event(),OnPreMapLoad=event(),OnKeyStartPressed=event(),OnKeyPressed=event(),OnTick=event(),OnResolutionChange=event()}
SandboxVars={EmberRoutes={CarrierProbe=true}}
local Driver=package.loaded['EmberRoutesProbe/Runtime/Driver']
local bind=Driver.bindId
Driver.bindId=function(...) binds=binds+1 return bind(...) end
local status={}
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime'].current=function() return {status=function(_,id) return status[id] end} end
package.loaded['EmberRoutesProbe/SelfCare/SelfCare']={activity=function(id) if id=='c' then return 'EAT' end end}
package.loaded['EmberRoutesProbe/Warehouse/DisplayNames']={name=function(id) return 'Member '..id end}
local Personnel={}
function Personnel.squadPortrait() return {icon='icon'} end
function Personnel.releasePortrait() portraitReleases=portraitReleases+1 end
function Personnel.watchPortrait(fn) watches=watches+1 return function() watches=watches-1 end end
package.loaded['EmberRoutesProbe/Settlement/PersonnelService']=Personnel
local Signals=require 'EmberRoutesProbe/Work/LaborSignals'
function Signals.watch(fn) watches=watches+1 return function() watches=watches-1 end end
local row=Membership.view('a')
Membership.request(actor,'a',{kind='FOLLOW',followSlot=0,expectedRevision=row.revision,requestId='ui-join'})
check(Membership.advance('a',actor,{},false),'join through production membership commit')
status.a={kind='COMPANION',state='ACTIVE',started=true}
status.b={kind='MEMBERSHIP_RETURN',state='ACTIVE',started=true}
EmberRoutesProbeJava={motionResult=function() return 'FOLLOW_QUEUED' end}
local Service=require 'EmberRoutesProbe/Settlement/SquadService'
local session=Service.new(actor,{})
check(session:refresh(now) and #session.rows==3,'three stable explicit slots')
check(session.rows[1].id=='a' and session.rows[2].id=='b' and session.rows[3].id=='c','slot ordering independent from command')
check(session.rows[1].actual:find('queued') and session.rows[2].actual:find('returning') and session.rows[3].actual:find('selfCare'),'actual activity independent from macro command')
check(session.rows[1].health==nil and session.rows[1].healthText:find('healthUnknown'),'unavailable health is not zero')
local before=binds
check(not session:refresh(100) and binds==before,'bounded cadence skips native reads')
Membership.note('a','UNMAPPED_TEST') session:invalidate('a') now=100 session:refresh(now)
check(not session.rows[1].feedback:find('UNMAPPED_TEST'),'unknown backend reason never leaks a raw code')
Membership.note('a',nil)
local targets=session:targets({}) check(#targets==3,'empty selection explicitly means all')
local single=session:targets({b=true}) check(#single==1 and single[1].id=='b','stable selection')
Membership.request(actor,'a',{kind='WAIT',expectedRevision=Membership.view('a').revision,requestId='external'})
Membership.advance('a',actor,{},false)
local results=session:command(targets,'WAIT')
check(results[1].result.reason=='STALE_MEMBERSHIP' and results[2].result.state=='PENDING' and results[3].result.state=='PENDING','group request reports individual rejection/success')
check(#Membership.squad(actor)==3,'WAIT roster persists')
now=now+100 session:refresh(now)
check(session.rows[1].feedback:find('STALE_MEMBERSHIP') and session.rows[2].pending,'feedback does not pretend acceptance is execution')
check(#session:command(targets,'FOLLOW',1)==0,'slot change requires one target')
session:close() check(portraitReleases==3,'all portrait owners released')
check(#session:command(targets,'FOLLOW')==0,'closed session cannot submit')
-- Run the real HUD/lifecycle/controller with a minimal native surface.
UIFont={Small='Small'}
local fontH,screenW,screenH=14,900,700
local pointerX,pointerY=20,0
function getTextManager() return {getFontHeight=function() measure=measure+1 return fontH end,MeasureStringX=function(_,_,text) measure=measure+1 return #text*3 end} end
local core={getScreenWidth=function() return screenW end,getScreenHeight=function() return screenH end,getKey=function() return 52 end,isDoingTextEntry=function() return false end}
function getCore() return core end
function getSpecificPlayer() return actor end
function isShiftKeyDown() return false end
function getMouseX() return 300 end
function getMouseY() return 300 end
local nativeVisible=false
function getPlayerRadialMenu() return {isReallyVisible=function() return nativeVisible end} end
UIManager={isModalVisible=function() return false end,getSpeedControls=function() return {getCurrentGameSpeed=function() return 1 end} end}
Keyboard={KEY_PERIOD=52,KEY_ESCAPE=1}
keyBinding={}
package.loaded.keyBinding=true
package.loaded['ISUI/PlayerData/ISPlayerData']=true
local Panel={}
function Panel:derive() local c={} c.__index=c setmetatable(c,{__index=self}) return c end
function Panel:new(x,y,w,h) return setmetatable({x=x,y=y,width=w,height=h,children={}},self) end
function Panel:initialise() end
function Panel:instantiate() self.javaObject={} end
function Panel:addChild(child) self.children[#self.children+1]=child end
function Panel:setHeight(h) self.height=h end
function Panel:setWidth(w) self.width=w end
function Panel:setX(x) self.x=x end
function Panel:setY(y) self.y=y end
function Panel:setCapture(v) self.capture=v end
function Panel:getMouseX() return pointerX end
function Panel:getMouseY() return pointerY end
function Panel:setVisible(v) self.visible=v end
function Panel:addToUIManager() self.inUI=true end
function Panel:removeFromUIManager() self.inUI=false end
function Panel:drawRect() end
function Panel:drawRectBorder() end
function Panel:drawText() end
function Panel:drawTextureScaledAspect() end
function Panel:setEnable(v) self.enable=v end
function Panel:getAbsoluteX() return self.x end
function Panel:getAbsoluteY() return self.y end
ISPanel=Panel ISButton=Panel:derive()
function ISButton:new(x,y,w,h,title,target,callback) local b=Panel.new(self,x,y,w,h) b.target=target b.callback=callback return b end
package.loaded['ISUI/ISPanel']=true package.loaded['ISUI/ISButton']=true
local tooltipRegistrations=0
local Tooltip={dismissOwner=function() end,unregisterOwner=function() end,position=function() end}
function Tooltip.register() tooltipRegistrations=tooltipRegistrations+1 end
function Tooltip.clear(widget) if widget.tooltipUI then widget.tooltipUI:setVisible(false) widget.tooltipUI:removeFromUIManager() end end
function Tooltip.unregister(widget) tooltipRegistrations=tooltipRegistrations-1 Tooltip.clear(widget) end
package.loaded['EmberRoutesProbe/UI/TooltipManager']=Tooltip
ISToolTip=Panel:derive()
function ISToolTip:new() return Panel.new(self,0,0,200,80) end
function ISToolTip:setOwner(owner) self.owner=owner end
function ISToolTip:setAlwaysOnTop() end
function ISToolTip:getIsVisible() return self.visible end
function ISToolTip:setDescription(text) self.description=text end
package.loaded['ISUI/ISToolTip']=true
local contextMenu={options={}}
function contextMenu:addOption(text,target,fn) local o={name=text,target=target,onSelect=fn} self.options[#self.options+1]=o return o end
function contextMenu:hideAndChildren() self.visible=false end
ISContextMenu={get=function() contextMenu.options={} contextMenu.visible=true return contextMenu end}
package.loaded['ISUI/ISContextMenu']=true
ISTextBox=Panel:derive()
function ISTextBox:new(x,y,w,h,title,current,target,onclick)
    local d=Panel.new(self,x,y,w,h) d.onclick=onclick d.target=target
    d.entry={value=current,getText=function(e) return e.value end,setMaxTextLength=function(e,n) e.max=n end,focus=function(e) e.focused=true end,unfocus=function(e) e.focused=false end}
    d.yes={} d.no={} d.colorPicker={removeFromUIManager=function(c) c.removed=true end}
    return d
end
function ISTextBox:destroy() self.visible=false self.inUI=false end
package.loaded['ISUI/ISTextBox']=true
local radial
ISRadialMenu=Panel:derive()
function ISRadialMenu:new(x,y,inner,outer,num)
    radial=Panel.new(self,x,y,outer*2,outer*2) radial.slices={} return radial
end
function ISRadialMenu:instantiate() self.javaObject={getSliceIndexFromMouse=function() return 0 end} end
function ISRadialMenu:addSlice(text,texture,fn) self.slices[#self.slices+1]={fn} end
function ISRadialMenu:getSliceCommand(i) return self.slices[i] end
function ISRadialMenu:center() end
function ISRadialMenu:undisplay() self.inUI=false end
package.loaded['ISUI/ISRadialMenu']=true
local UI=require 'EmberRoutesProbe/UI/SquadUI'
UI.install() UI.install()
local hud=UI.show(actor)
check(hud.active and watches==2,'show owns signal and portrait subscriptions')
local reads,measured=binds,measure
hud:prerender() hud:render()
check(binds==reads and measure==measured,'render only reads caches: no native scan/text measure')
hud:selectAll() UI.openWheel(hud,true)
check(radial and #radial.slices==4,'all-target wheel has executable commands only')
local oldTargets=hud.session:targets(hud.selected)
local oldRevision=Membership.view('a').revision
UI.keyRelease(52)
check(Membership.view('a').revision==oldRevision+1,'release executes hovered command once')
UI.keyRelease(52)
check(Membership.view('a').revision==oldRevision+1,'repeated release cannot duplicate command')
hud.selected={a=true} UI.openWheel(hud,false)
check(#radial.slices==7,'single-target wheel exposes three explicit slot choices')
local staleCallback=radial.slices[1][1]
local released=portraitReleases
hud:hide()
check(not hud.active and watches==0 and portraitReleases==released+3 and not radial.inUI,'hide disposes listeners portraits and floating wheel')
staleCallback()
check(Membership.view('a').revision==oldRevision+1,'expired activation callback cannot submit')
local readAt=binds now=now+1000 hud:update()
check(binds==readAt,'hidden HUD stops all refresh reads')
UI.show(actor) UI.openWheel(hud,true)
local outside=radial.onMouseDownOutside outside()
UI.keyRelease(52)
check(Membership.view('a').revision==oldRevision+1,'outside cancellation cannot execute on release')
UI.openWheel(hud,true) nativeVisible=true UI.tick()
check(not radial.inUI,'another native wheel cancels our owned wheel')
nativeVisible=false
UI.openWheel(hud,true) UI.keyStart(1)
check(not radial.inUI,'Escape cancels owned wheel')
local businessRevision=Membership.view('a').revision
local originalSlot=Membership.view('a').squadSlot
check(tooltipRegistrations==1,'visible HUD registers tooltip ownership')
local first=hud.cards[1]
pointerX,pointerY=20,first.y+10
hud:onMouseMove(0,0)
check(hud.hovered==first.id and first.opts.hover and hud.tooltipUI.inUI,'hover highlights card and shows full tooltip')
reads,measured=binds,measure hud:prerender()
check(binds==reads and measure==measured,'hover and badge render never observe or measure')
hud:onMouseMoveOutside(0,0)
check(not hud.hovered and not hud.tooltipUI.inUI,'leaving dismisses tooltip')
hud:onMouseDown(10,5) hud:onMouseMove(1000,1000) hud:onMouseUpOutside(1010,1005)
check(hud.x+hud.width<=screenW and hud.y+hud.height<=screenH,'dock drag clamps both edges')
check(actor:getModData().EmberRoutesSquadHUD.x~=nil,'dock release persists normalized position')
local oldFirst=hud.cards[1].id
first=hud.cards[1] local last=hud.cards[#hud.cards]
hud:onMouseDown(20,first.y+10) pointerY=last.y+last.height-2
hud:onMouseMove(0,pointerY-first.y-10) hud:onMouseUp(20,pointerY)
check(hud.cards[#hud.cards].id==oldFirst,'card drag reorders displayed roster')
check(Membership.view('a').squadSlot==originalSlot and Membership.view('a').revision==businessRevision,'display reorder never changes formation or issues a command')
local hp=25 local moodReads=0
MoodleType={BLEEDING='BLEEDING',HUNGRY='HUNGRY',THIRST='THIRST'}
local native=bind(actor,'a').handle
function native:getBodyDamage() return {getOverallBodyHealth=function() return hp end} end
function native:getMoodles() return {getMoodleLevel=function(_,kind)
    moodReads=moodReads+1 return (kind=='BLEEDING' or kind=='HUNGRY' or kind=='THIRST') and 4 or 0
end} end
now=now+501 hud.session:invalidate() hud:update()
local palette=require 'EmberRoutesProbe/UI/Theme'
check(hud.cards[1].healthColor==palette.status.ERROR and #hud.cards[1].badges==2,'low health tone and at most two real Moodle badges')
check(hud.cards[1].tooltip:find('bleeding') and hud.cards[1].tooltip:find('hungry') and hud.cards[1].tooltip:find('thirsty'),'complete tooltip retains statuses beyond visible badge limit')
local moodAt=moodReads reads,measured=binds,measure hud:prerender()
check(moodReads==moodAt and binds==reads and measure==measured,'badges draw without Moodle calls or native measurement')
hp=55 now=now+501 hud:update()
check(hud.cards[1].healthColor==palette.status.UPDATING,'medium health uses registered warning tone')
hp=90 now=now+501 hud:update()
check(hud.cards[1].healthColor==palette.status.READY,'high health uses registered ready tone')
local Preferences=require 'EmberRoutesProbe/Settlement/SquadPreferences'
local restored=Preferences.new(actor)
check(restored:ordered(hud.session.rows)[3].id==oldFirst,'saved display order survives a new UI instance')
first=hud.cards[1] hud:onRightMouseUp(20,first.y+10)
check(contextMenu.visible and #contextMenu.options==9,'member right-click exposes actual commands slots and callsign')
local menuCallback=contextMenu.options[1].onSelect
contextMenu.options[8].onSelect()
local dialog=hud.callsignDialog
check(dialog and dialog.entry.max==24,'callsign dialog has a native 24-character input bound')
dialog.entry.value='Scout' dialog.onclick(nil,{internal='OK',parent=dialog})
check(hud.preferences.value.callsigns[first.id]=='Scout','callsign saved independently from NPC name')
check(hud.cards[1].name:find('Scout') and hud.cards[1].tooltip:find('Member'),'tooltip retains full original name alongside callsign')
local Menus=require 'EmberRoutesProbe/UI/SquadHUDMenus'
Menus.settings(hud,20,20)
check(#contextMenu.options==9,'settings exposes four HUD sizes and four button sizes plus reset')
contextMenu.options[4].onSelect()
check(hud.preferences.value.scale==1.4,'HUD scale applies and persists')
local layoutScale=hud.preferences.value.scale
Menus.settings(hud,20,20) contextMenu.options[5].onSelect()
check(hud.preferences.value.buttonScale==0.85 and hud.preferences.value.scale==layoutScale,'button size independent from HUD scale')
screenW,screenH=420,320 UI.resolutionChanged()
check(hud.width<=screenW and hud.height<=screenH and hud.x+hud.width<=screenW and hud.y+hud.height<=screenH,'resolution shrink keeps complete HUD on screen')
check(hud.scrollMax>0,'small screens clip and scroll cards instead of losing controls')
hud:onMouseWheel(-1) check(hud.scroll>0,'wheel scroll moves bounded viewport')
reads,measured=binds,measure hud:prerender()
check(binds==reads and measure==measured,'clipped scrolling render reads prepared snapshots only')
fontH=20 now=now+501 hud:update()
check(hud.h==20 and hud.height<=screenH,'font changes trigger bounded relayout')
Menus.rename(hud,hud.cards[1].id) dialog=hud.callsignDialog
local lateDialog=dialog.onclick
hud:hide()
check(not dialog.inUI and not dialog.entry.focused and dialog.colorPicker.removed and tooltipRegistrations==0,'hide disposes dialog hidden color picker and tooltip registration')
local aliasBefore=hud.preferences.value.callsigns[first.id]
lateDialog(nil,{internal='OK',parent=dialog}) menuCallback()
check(hud.preferences.value.callsigns[first.id]==aliasBefore and Membership.view('a').revision==businessRevision,'late menu/dialog callbacks cannot write or submit')
UI.show(actor)
Menus.settings(hud,20,20)
local existingMenu=contextMenu.options[1]
Menus.member(hud,'missing',20,20)
check(contextMenu.options[1]==existingMenu,'stale member click never opens an empty menu')
contextMenu.options[1].onSelect=function() end
hud:hide()
check(contextMenu.visible,'closing HUD does not hide a shared menu reused by another owner')
UI.show(actor)
UI.reset() check(watches==0 and hud.disposed,'world reset fully disposes HUD')
local oldWorld=session.world
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry'].data=function() return {} end
check(#session:command(oldTargets,'WAIT')==0 and not session:valid(),'world change rejects old targets')
print('PASS '..checks..' squad roster/presentation/partial-command/lifecycle/radial checks; native surfaces mocked')
