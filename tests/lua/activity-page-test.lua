local checks=0
local function check(v,m) assert(v,m) checks=checks+1 end
local fh,sw,sh=20,1280,900
UIFont={Small=1}
Keyboard={KEY_ESCAPE=1,KEY_PRIOR=2,KEY_NEXT=3}
getCore=function() return {getScreenWidth=function() return sw end,getScreenHeight=function() return sh end} end
getTextManager=function() return {getFontHeight=function() return fh end,MeasureStringX=function(_,font,s) return #s*fh*.45 end} end
getTextOrNull=function(key) return ERTestTranslations and ERTestTranslations[key] end
getText=function(key,...)
    local s=getTextOrNull(key) or key
    for i,v in ipairs({...}) do s=s:gsub('%%'..i,function() return tostring(v) end) end return s
end
getTimestampMs=function() return 10000 end
getGameTime=function() return {getWorldAgeHours=function() return 10 end} end
getCell=function() return {getGridSquare=function() end} end

local Base={}
function Base:derive(name) local c={Type=name} c.__index=c return setmetatable(c,{__index=self}) end
function Base:new(x,y,w,h,title,target,callback)
    return setmetatable({x=x,y=y,width=w,height=h,title=title,target=target,onclick=callback,items={},selected=0,children={}},{__index=self})
end
function Base:initialise() self.children=self.children or {} end
function Base:createChildren() end
function Base:instantiate() if self.native then return end self.native=true self:createChildren() end
function Base:addChild(c) c.parent=self c:instantiate() self.children[#self.children+1]=c end
function Base:addToUIManager() self:instantiate() self.added=true end
function Base:removeFromUIManager() self.added=false end
function Base:setVisible(v) self.visible=v end
function Base:setEnable(v) self.enable=v end
function Base:setEnabled(v) self.enabled=v end
function Base:setEditable(v) self.editable=v end
function Base:getYScroll() return self.scroll or 0 end
function Base:setYScroll(v) self.scroll=v end
function Base:close() self.visible=false end
function Base:prerender() end
function Base:update() end
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
function Base:setWantKeyEvents(v) end

ISCollapsableWindow=Base:derive('ISCollapsableWindow')
ISPanel=Base:derive('ISPanel')
ISButton=Base:derive('ISButton')
ISScrollingListBox=Base:derive('ISScrollingListBox')
ISTextEntryBox=Base:derive('Entry')
function ISTextEntryBox:new(value,x,y,w,h) local o=Base.new(self,x,y,w,h) o.value=value return o end
function ISTextEntryBox:getText() return self.value end
function ISTextEntryBox:setText(v) self.value=v end
function ISTextEntryBox:setPlaceholderText(v) end
function ISTextEntryBox:unfocus() end

ISComboBox=Base:derive('Combo')
function ISComboBox:new(...) local o=Base.new(self,...) o.options={} o.data={} o.selected=1 return o end
function ISComboBox:addOption(s) self.options[#self.options+1]=s end
function ISComboBox:addOptionWithData(s,d) self:addOption(s) self.data[#self.options]=d end
function ISComboBox:getOptionData(n) return self.data[n] end
function ISComboBox:clear() self.options={} self.data={} self.selected=1 end
function ISComboBox:hidePopup() self.hiddenPopup=true end

ISModalDialog=Base:derive('ISModalDialog')
for _,n in ipairs({'ISCollapsableWindow','ISPanel','ISButton','ISComboBox','ISTextEntryBox','ISScrollingListBox','ISModalDialog'}) do
    package.loaded['ISUI/ISModalDialog']=ISModalDialog
    package.loaded['ISUI/'..n]=true
end

local actor={getIndex=function() return 0 end,getPlayerNum=function() return 0 end,getJoypadBind=function() return -1 end}
getSpecificPlayer=function(i) return actor end
local permitted=true
local calls={}
local serial=0
local entry={id='home',name='Test Settlement'}
local events={{id='event',name='Garden gathering',state='RUNNING',createdAt=9,endsAt=11,revision=3,quorum=2,organizerId='a',
    stage={supported=true,id='free',index=1,state='RUNNING',actorCount=2,exitCount=0},
    zone={id='zone',revision=7},durationHours=1,gatherDeadline=9.1,rules={SOCIAL=2,OBSERVE=1},
    roster={a={joined=true,participationHours=.15},b={joined=true,participationHours=.1},c={withdrawn=true,reason='LATE_ARRIVAL'}}}}
local plans={{id='plan',args={name='Evening gathering',roster={'a','b'},zoneId='zone',zoneRevision=7,
    organizerId='a',rules={OBSERVE=1,SOCIAL=2},quorum=2,durationHours=1,gatherHours=.1},
    enabled=true,count=4,lastIndex=0,firstAt=11,intervalHours=24,revision=2}}

local function copy(v) if type(v)~='table' then return v end local r={} for k,x in pairs(v) do r[k]=copy(x) end return r end

package.loaded['EmberRoutesProbe/ActivityService']={
    view=function() return copy(events) end,schedules=function() return copy(plans) end,
    revision=function() return 1 end,detail=function() return copy(events[1]) end,
    review=function(actor,args)
        local people={} for _,id in ipairs(args.roster) do people[id]={state='READY'} end
        return {ready=#args.roster,waiting=0,unknown=0,participants=people}
    end,
    issue=function() serial=serial+1 return 'request-'..serial end,
    start=function(a,args,token) calls[#calls+1]={kind='start',args=copy(args),token=token} return {id='new'} end,
    schedule=function(a,args,token,first,interval,count) calls[#calls+1]={kind='schedule',args=copy(args),first=first,interval=interval,count=count} return {id='new-plan'} end,
    update=function() calls[#calls+1]={kind='update'} return {id='event'} end,
    updateSchedule=function() calls[#calls+1]={kind='updateSchedule'} return {id='plan'} end,
    cancel=function() calls[#calls+1]={kind='cancel'} return true end,
    cancelSchedule=function() calls[#calls+1]={kind='cancelSchedule'} return true end
}
package.loaded['EmberRoutesProbe/SettlementZones']={
    activities=function() return {'SOCIAL','READING','SIT','SMOKE','FITNESS','STROLL','OBSERVE'} end,
    list=function() return {{id='zone',name='Garden',revision=7,enabled=true,area={x=0,y=0,w=8,h=7,z=0}}} end
}
package.loaded['EmberRoutesProbe/MembershipService']={
    members=function() return {'a','b','c'} end,
    view=function() return {context='SETTLEMENT'} end
}
package.loaded['EmberRoutesProbe/Driver']={bindId=function() return {} end}
package.loaded['EmberRoutesProbe/DisplayNames']={
    name=function(id) return id=='a' and 'Alexandra' or id=='b' and 'Brianna' or 'Casey' end
}
local worldData={}
package.loaded['EmberRoutesProbe/SettlementLedger']={
    authorized=function() return permitted end,
    data=function() return worldData end,
    view=function(_,id) return id==entry.id and entry or nil end
}
package.loaded['EmberRoutesProbe/WarehouseIndex']={
    watch=function(_,fn) return function() end end,
    query=function() return {} end,
    revision=function() return 1 end,
    snapshot=function() return {state='READY',rows={},counts={items=0}} end,
}
package.loaded['EmberRoutesProbe/WarehouseMetrics']={
    begin=function() return 0 end,
    finish=function() end
}

local Registry=require 'EmberRoutesProbe/UI/PageRegistry'
local def=Registry.get('activities')
check(def~=nil and def.isTab==true and def.module=='ActivityPage','PageRegistry registers activities as a first-class tab')
check(def.order==38,'activities tab is correctly ordered between policies and defense')

local Dashboard=require 'EmberRoutesProbe/SettlementDashboard'
local panel,reason=Dashboard.open(actor,entry.id,'activities')
if not panel then print('open failed with reason:',reason) else print('opened panel with activeTab:',panel.activeTab) end
check(panel~=nil and panel.activeTab=='activities','SettlementDashboard can open directly to activities tab')
check(panel.activityButton==nil,'activityButton has been fully removed from SettlementDashboard title/footer')

local tabBtn=panel.tabButtons['activities']
check(tabBtn~=nil,'activities tab button is present in navigation bar')

local page=panel.pages['activities']
check(page~=nil and page.mode=='LIST','ActivityPage is instantiated and defaults to LIST mode')
check(#page.scenes.items==2 and #page.details.items>=6,'scenes and schedule details correctly populate in ActivityPage')
check(page.details.items[1].item.kind=='ATMOSPHERE_STRIP','atmosphere strip is prepended to activity details')

-- Test mode switching, scenario integration and drawer toggle inside ActivityPage
page:newDraft()
check(page.mode=='ROSTER' and page.hasDraft==true,'newDraft enters ROSTER mode with draft active')
check(page.currentScenario~=nil and page.currentScenario.id=='free_gathering','currentScenario is initialized from scenario catalog')
check(#page.roster.items==3 and #page.organizer.options==3,'roster and organizers populate from settlement membership')
check(page.roster.items[1].item.badge~=nil,'roster items carry live status badges')
check(page.advancedDrawerBtn~=nil and page.basicDrawerBtn~=nil,'advanced drawer toggle buttons are present')

-- Drawer toggle interactions
page.advancedDrawerBtn.onclick(page)
check(page.mode=='RULES' and page.timeFields.quorum~=nil,'clicking advancedDrawerBtn opens RULES drawer')
page.basicDrawerBtn.onclick(page)
check(page.mode=='ROSTER','clicking basicDrawerBtn folds back to ROSTER basic setup')

page:setMode('RULES')
check(page.mode=='RULES' and page.timeFields.quorum~=nil,'RULES mode displays rule options and timing inputs')

-- Verify rendering of atmosphere strip and resident badges without crashing
local stripItem=page.details.items[1]
page.drawRow(page.details,0,stripItem)
local rosterRow=page.roster.items[1]
page.drawRow(page.roster,0,rosterRow)

page:reviewDraft()
check(page.mode=='REVIEW' and #page.reviewList.items>0,'reviewDraft performs preflight attendance review')

page:applyDraft()
check(calls[#calls].kind=='start','applyDraft submits activity creation')
check(page.mode=='LIST','successful submission returns to LIST mode')

-- Test tab switching: deactivate and reactivate
panel:selectTab('defense')
check(panel.activeTab=='defense' and page.visible==false,'switching away deactivates ActivityPage')
panel:selectTab('activities')
check(panel.activeTab=='activities' and page.visible==true,'switching back reactivates ActivityPage')

-- Test backward-compatibility ActivityDialog.open redirecting to activities tab
local Dialog=require 'EmberRoutesProbe/UI/ActivityDialog'
panel:selectTab('defense')
local redirectedPage=Dialog.open(panel)
check(panel.activeTab=='activities' and redirectedPage==page,'ActivityDialog.open seamlessly redirects to activities tab')

-- Clean up
panel:close()
check(panel.disposed==true,'panel closes cleanly')

print('activity-page-test: '..checks..' PASS')
