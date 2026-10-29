-- Real dialog and Layout/Text/Theme in installed Kahlua; native ISUI is a host substitute.
local checks=0
local function check(v,m) assert(v,m) checks=checks+1 end
local fh,sw,sh=20,1280,900
UIFont={Small=1}
getCore=function() return {getScreenWidth=function() return sw end,getScreenHeight=function() return sh end} end
getTextManager=function() return {getFontHeight=function() return fh end,MeasureStringX=function(_,font,s) return #s*fh*.45 end} end
getTextOrNull=function(key) return ERTestTranslations and ERTestTranslations[key] end
getText=function(key,...)
    local s=getTextOrNull(key) or key
    for i,v in ipairs({...}) do s=s:gsub('%%'..i,function() return tostring(v) end) end return s
end
getTimestampMs=function() return 10000 end
getGameTime=function() return {getWorldAgeHours=function() return 10 end} end
local Base={}
function Base:derive(name) local c={Type=name} c.__index=c return setmetatable(c,{__index=self}) end
function Base:new(x,y,w,h,title,target,callback)
    return setmetatable({x=x,y=y,width=w,height=h,title=title,target=target,onclick=callback,items={},selected=0},{__index=self})
end
function Base:initialise() self.children={} end
function Base:createChildren() end
function Base:instantiate() if self.native then return end self.native=true self:createChildren() end
function Base:addChild(c) c.parent=self c:instantiate() self.children[#self.children+1]=c end
function Base:addToUIManager() self:instantiate() self.added=true end
function Base:removeFromUIManager() self.added=false end
function Base:setVisible(v) self.visible=v end function Base:setEnable(v) self.enable=v end
function Base:close() self.visible=false end function Base:prerender() end function Base:update() end
function Base:titleBarHeight() return fh+1 end
function Base:getAbsoluteX() return self.x+(self.parent and self.parent:getAbsoluteX() or 0) end
function Base:getAbsoluteY() return self.y+(self.parent and self.parent:getAbsoluteY() or 0) end
function Base:drawText() end function Base:drawRect() end function Base:drawRectBorder() end
function Base:clear() self.items={} self.selected=0 end
function Base:setOnMouseDownFunction(target,fn) self.target=target self.onmousedown=fn end
function Base:addItem(text,item,tooltip)
    local row={text=text,item=item,tooltip=tooltip,index=#self.items+1,height=self.itemheight}
    self.items[#self.items+1]=row return row
end
ISCollapsableWindow=Base ISButton=Base ISScrollingListBox=Base
ISTextEntryBox=Base:derive('Entry')
function ISTextEntryBox:new(value,x,y,w,h) local o=Base.new(self,x,y,w,h) o.value=value return o end
function ISTextEntryBox:getText() return self.value end function ISTextEntryBox:setText(v) self.value=v end
function ISTextEntryBox:unfocus() end
ISComboBox=Base:derive('Combo')
function ISComboBox:new(...) local o=Base.new(self,...) o.options={} o.data={} o.selected=1 return o end
function ISComboBox:addOption(s) self.options[#self.options+1]=s end
function ISComboBox:addOptionWithData(s,d) self:addOption(s) self.data[#self.options]=d end
function ISComboBox:getOptionData(n) return self.data[n] end
function ISComboBox:clear() self.options={} self.data={} self.selected=1 end
function ISComboBox:hidePopup() self.hiddenPopup=true end
for _,n in ipairs({'ISCollapsableWindow','ISButton','ISComboBox','ISTextEntryBox','ISScrollingListBox'}) do package.loaded['ISUI/'..n]=true end
local actor={} local permitted=true local calls={} local serial=0
local entry={id='home',name='Settlement'}
local events={{id='event',name='Garden gathering',state='RUNNING',createdAt=9,endsAt=11,revision=3,quorum=2,organizerId='a',
    roster={a={joined=true,participationHours=.15},b={joined=true,participationHours=.1},c={withdrawn=true,reason='LATE_ARRIVAL'}}}}
local plans={{id='plan',args={name='Evening gathering'},enabled=true,count=4,lastIndex=0,firstAt=11,revision=2}}
local function copy(v) if type(v)~='table' then return v end local r={} for k,x in pairs(v) do r[k]=copy(x) end return r end
package.loaded['EmberRoutesProbe/ActivityService']={
    view=function() return copy(events) end,schedules=function() return copy(plans) end,
    issue=function() serial=serial+1 return 'request-'..serial end,
    start=function(a,args,token) calls[#calls+1]={kind='start',args=copy(args),token=token} return {id='new'} end,
    schedule=function(a,args,token,first,interval,count) calls[#calls+1]={kind='schedule',args=copy(args),first=first,interval=interval,count=count} return {id='new-plan'} end,
    cancel=function() calls[#calls+1]={kind='cancel'} return true end,
    cancelSchedule=function() calls[#calls+1]={kind='cancelSchedule'} return true end}
package.loaded['EmberRoutesProbe/SettlementZones']={activities=function() return {'SOCIAL','READING','SIT','SMOKE','FITNESS','STROLL','OBSERVE'} end,
    list=function() return {{id='zone',name='Garden',revision=7,enabled=true,area={x=0,y=0,w=8,h=7,z=0}}} end}
package.loaded['EmberRoutesProbe/MembershipService']={members=function() return {'a','b','c'} end,
    view=function() return {context='SETTLEMENT'} end}
package.loaded['EmberRoutesProbe/Driver']={bindId=function() return {} end}
package.loaded['EmberRoutesProbe/DisplayNames']={name=function(id) return id=='a' and 'Alexandra Long Resident Name' or id=='b' and 'Brianna' or 'Casey' end}
local Dialog=require 'EmberRoutesProbe/UI/ActivityDialog'
local function owner() return {actor=actor,entry=entry,fontHeight=fh,valid=function() return permitted end} end
local function open() return Dialog.open(owner()) end
local d=open()
check(d.mode=='LIST' and #d.scenes.items==2 and #d.details.items>=6,'scene/plan list and detached participant details render')
d:newDraft()
check(#d.roster.items==3 and #d.organizer.options==3,'specified roster initially selects settlement members')
d.roster.onmousedown(d.roster.target,{id='b'})
check(not d.selectedNpc.b and #d.organizer.options==2,'native list callback updates roster and organizer options')
d:applyDraft()
check(calls[#calls].kind=='start' and #calls[#calls].args.roster==2,'manual start submits only selected roster')
check(calls[#calls].args.rules.SOCIAL==2 and calls[#calls].args.rules.OBSERVE==1,'editor sends actual behavior rules')
d:newDraft() d:setMode('RULES') d.timeFields.delayMinutes:setText('15') d.timeFields.occurrences:setText('3') d:applyDraft()
check(calls[#calls].kind=='schedule' and calls[#calls].first==10.25 and calls[#calls].count==3,'timing inputs create one bounded plan')
d:selectScene(d.scenes.items[2].item) d:cancelSelected()
check(calls[#calls].kind=='cancelSchedule' and events[1].state=='RUNNING','schedule cancellation does not cancel current scene')
for _,size in ipairs({{800,600,20},{1280,720,28},{1920,1080,32},{3840,2160,32}}) do
    d:close() sw,sh,fh=size[1],size[2],size[3] d=open() d:newDraft()
    for _,mode in ipairs({'ROSTER','RULES','LIST'}) do
        d:setMode(mode)
        for _,w in ipairs(d.widgets) do
            local c=w.control
            if c.visible then
                check(c.x>=0 and c.y>=d:titleBarHeight() and c.x+c.width<=d.width+.01 and c.y+c.height<=d.height+.01,'visible control stays within dialog at scaled font')
                if c.doDrawItem then
                    local y=0
                    for _,row in ipairs(c.items) do y=c:doDrawItem(y,row,false) end
                    check(y>=0,'native list drawing handles scene, roster and participant detail rows')
                end
            end
        end
    end
end
permitted=false d:update()
check(d.disposed and not d.added and d.owner.activityDialog==nil,'authority loss closes window and detaches owner')
permitted=true
function ERSettlementPreview(tab,height,screenWidth,screenHeight)
    fh,sw,sh=height,screenWidth or 1280,screenHeight or 900
    local panel=open() panel.x=0 panel.y=0
    if tab=='activity-roster' then panel:newDraft()
    elseif tab=='activity-rules' then panel:newDraft() panel:setMode('RULES') end
    return panel
end
print('activity-dialog: '..checks..' PASS (native ISUI host substituted; no GPU/game run)')
