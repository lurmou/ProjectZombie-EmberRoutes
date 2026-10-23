package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local Filter=require "EmberRoutesProbe/StorageFilter"
local count,submits,measures=0,0,0
local function check(value,why) count=count+1 assert(value,why) end
local Base={}
function Base:derive(name) local cls=setmetatable({Type=name},{__index=self}) cls.__index=cls return cls end
function Base:new(x,y,w,h,title) return setmetatable({x=x,y=y,width=w,height=h,title=title,children={},selected=1,items={}},self) end
Base.__index=Base
function Base:initialise() self.initialised=true end
function Base:createChildren() self.parentCreated=true end
function Base:addChild(child) assert(child.initialised,"uninitialised child") self.children[#self.children+1]=child end
function Base:addToUIManager() self:createChildren() self.added=true end
function Base:removeFromUIManager() self.added=false end
function Base:close() self.closed=true end
function Base:titleBarHeight() return 24 end
function Base:drawText() end
function Base:drawRect() end
function Base:drawRectBorder() end
function Base:drawTextureScaledAspect() end
function Base:getAbsoluteX() return self.x end
function Base:getAbsoluteY() return self.y end
function Base:getYScroll() return self.yScroll or 0 end
function Base:setYScroll(value) self.yScroll=value end
function Base:setScrollHeight(value) self.scrollHeight=value end
function Base:prerender() self.parentRendered=true end
function Base:setWantKeyEvents(value) self.wantsKeys=value end
function Base:setEnable(value) self.enable=value end
function Base:setOnMouseDownFunction(target,fn) self.target,self.onclick=target,fn end
function Base:setOverrideAButtonFunction(target,fn) self.target,self.aButton=target,fn end
function Base:clear() self.items={} self.scrollHeight=0 self.count=0 end
function Base:addItem(text,item,tooltip)
    self.items[#self.items+1]={text=text,item=item,tooltip=tooltip,index=#self.items+1,height=self.itemheight}
    self.scrollHeight=(self.scrollHeight or 0)+self.itemheight
    self.count=(self.count or 0)+1
    return self.items[#self.items]
end
function Base:ensureVisible() end
function Base:onJoypadDown() end
function Base:addOption(opt) self.options=self.options or {} table.insert(self.options,opt) end
ISCollapsableWindow=Base
ISScrollingListBox=Base
ISButton=Base
ISComboBox=Base
for _,name in ipairs({"ISCollapsableWindow","ISScrollingListBox","ISButton","ISComboBox"}) do package.loaded['ISUI/'..name]=true end
UIFont={Small=1}
Keyboard={KEY_UP=1,KEY_DOWN=2,KEY_SPACE=3,KEY_RETURN=4,KEY_ESCAPE=5}
Joypad={AButton=1,BButton=2,XButton=3}
local fontHeight,sw,sh=16,1920,1080
function getTextManager() return {getFontHeight=function() return fontHeight end,
    MeasureStringX=function(_,_,text) measures=measures+1 return #text*fontHeight*0.5 end} end
function getCore() return {getScreenWidth=function() return sw end,getScreenHeight=function() return sh end} end
function getTextOrNull(key) return ERTestTranslations and ERTestTranslations[key] end
function getText(key) return getTextOrNull(key) or key end
function getTexture(path) return path end
local names=0
function getItemNameFromFullType(id) names=names+1 if id=='Base.Hammer' then return 'Localized hammer' end return nil end
function isClient() return false end function isServer() return false end
local live=Filter.new() live.groups.food=true live.types['Base.Hammer']=true live.types['Missing.ModItem']=false
local permit=false
local Registry={containerIndex=function(o,c) if o:getContainer()==c then return 0 end end,filter=function() return live end,
    metadata=function() return nil end,logistics=function() return "STORAGE" end,configure=function(_,_,draft)
    submits=submits+1
    if not permit then return "TOO_FAR_TO_TAG" end
    live=Filter.copy(draft) return "FILTER_CONFIGURED"
end}
package.loaded['EmberRoutesProbe/ContainerRegistry']=Registry
package.loaded['EmberRoutesProbe/Log']={write=function() end}
local actor={isDead=function() return false end,getPlayerNum=function() return 0 end,getJoypadBind=function() return -1 end}
local container={getType=function() return "crate" end,getItems=function() return {size=function() return 0 end} end}
local object={getContainer=function() return container end}
local Panel=require "EmberRoutesProbe/StorageFilterPanel"
local panel=Panel.open(actor,object)
check(panel.initialised and panel.parentCreated and panel.added,"native lifecycle delegates and adds to UI")
check(panel.list.initialised and panel.list.height>0,"list initialised with positive relative layout")
check(panel.list:doDrawItem(0,{height=panel.list.itemheight})==panel.list.itemheight,"empty native list row is safely skipped")
check(panel.width<=sw and panel.height<=sh and panel.x>=0 and panel.y>=0,"panel fits screen")
local localized,unknown=false,false
for _,entry in ipairs(panel.list.items) do
    if entry.item.id=='Base.Hammer' then localized=entry.item.caption=='Localized hammer' end
    if entry.item.id=='Missing.ModItem' then unknown=entry.item.caption=='Missing.ModItem' end
end
check(localized and unknown,"localized names resolve saved exceptions without live instances; unknown fullType retained")
local namesBefore=names
for _,entry in ipairs(panel.list.items) do panel.list:doDrawItem(0,entry) end
check(names==namesBefore,"row rendering uses cached names and states")
local totalHeight,multiLine=0,false
for _,entry in ipairs(panel.list.items) do
    local row=entry.item
    if row.kind=="type" and entry.height>=panel.fontHeight*2+panel.pad then multiLine=true end
    totalHeight=totalHeight+entry.height
end
check(multiLine,"item exceptions reserve room for name and rule state")
check(panel.list.scrollHeight==totalHeight,"variable entries contribute their actual height to scrolling")
local drawText=panel.list.drawText
panel.list.drawText=function() error("off-screen row was drawn") end
local first=panel.list.items[1]
check(panel.list:doDrawItem(10000,first)==10000+first.height and panel.list:doDrawItem(-10000,first)==-10000+first.height,"offscreen rows skip drawing while preserving height")
panel.list.drawText=drawText
panel:none()
check(live.groups.food==true and panel.model.draft.groups.food==false,"draft edits do not write live policy")
local before=measures
panel:prerender() panel:prerender()
check(panel.parentRendered and measures==before,"render delegates to parent and does not recompute text layout")
panel:apply()
check(submits==1 and panel.added and panel.store.value.status~="","rejected apply keeps draft open")
panel:close()
check(live.groups.food==true and not panel.added,"cancel leaves live state unchanged")
fontHeight,sw,sh=28,2560,1440
panel=Panel.open(actor,object)
check(panel.width<=sw and panel.height<=sh and panel.list.height>0,"larger UI font has bounded usable layout")
local selected=panel.list.selected
panel.list:onKeyPress(Keyboard.KEY_DOWN)
check(panel.list.selected==selected+1 and panel.model.draft.private==false,"keyboard navigation does not toggle rows")
panel.list:onKeyPress(Keyboard.KEY_SPACE)
check(panel.model.draft.private==true,"keyboard can toggle private row")
panel.list:onJoypadDirUp()
check(panel.model.draft.private==true,"joypad navigation does not toggle rows")
permit=true
panel.list:onJoypadDown(Joypad.XButton,{})
check(submits==2 and live.private and not panel.added,"controller apply submits then disposes view")
fontHeight,sw,sh=28,1280,720
panel=Panel.open(actor,object)
check(panel.list.height>0 and panel.list.y+panel.list.height+panel.fontHeight*3<panel.buttons[1].y,"large-font 720p reserves status space above buttons")
if ERTestRuntime then
    -- Expose the same real component instance for VM-specific Chinese/layout checks.
    UI_TEST_EXPORT={panel=panel,open=function(w,h,font)
        sw,sh,fontHeight=w,h,font
        return Panel.open(actor,object)
    end}
end
-- Model the installed native local-position write followed by tooltip draw.
local Anchor=require 'EmberRoutesProbe/UI/TooltipAnchor'
local calls=0
local tip={visible=true,followMouse=true,setX=function(self,x) self.x=x end,setY=function(self,y) self.y=y end,
    getIsVisible=function(self) return self.visible end,setVisible=function(self,v) self.visible=v end,
    removeFromUIManager=function(self) self.removed=true end}
local mx,my=700,400
local oldMouseX,oldMouseY=getMouseX,getMouseY
getMouseX=function() return mx end getMouseY=function() return my end
local control={tooltipUI=tip,updateTooltip=function(self)
    calls=calls+1 self.tooltipUI:setX(23) self.tooltipUI:setY(23) return 'native'
end}
Anchor.attach(control,'updateTooltip')
check(control:updateTooltip()=='native' and calls==1 and tip.x==732 and tip.y==410,'tooltip is at screen coordinates before prerender; native executes once')
mx,my=900,600 control:updateTooltip()
check(tip.x==932 and tip.y==610,'moving mouse updates one tooltip anchor without local-coordinate echo')
tip.followMouse=false control:updateTooltip()
check(tip.x==23 and tip.y==23,'fixed tooltip positioning remains native')
tip.followMouse=true tip.desiredX,tip.desiredY=5,6 control:updateTooltip()
check(tip.x==23 and tip.y==23,'explicit tooltip positioning remains native')
Anchor.clear(control)
check(not tip.visible and tip.removed,'closing/replacing rows releases tooltip UI')
getMouseX,getMouseY=oldMouseX,oldMouseY
print("PASS "..count.." storage panel lifecycle/layout/interaction checks; native UI rendering NOT RUN")
