-- Scoped regression: installed ISTickBox constructor + real page, fake native host.
local count=0
local function check(value,message) assert(value,message) count=count+1 end
local Base={}
function Base:derive() local t={} t.__index=t setmetatable(t,{__index=self}) return t end
function Base:new(x,y,w,h) local o=setmetatable({x=x,y=y,width=w,height=h,children={},items={},selected=0},{__index=self}) return o end
function Base:initialise() if self.createChildren then self:createChildren() end end
function Base:createChildren() end
function Base:addChild(c) c.parent=self self.children[#self.children+1]=c end
function Base:titleBarHeight() return 24 end
function Base:addToUIManager() end function Base:removeFromUIManager() self.removed=true end
function Base:close() self.closed=true end function Base:update() end function Base:prerender() end
function Base:setHeight(h) self.height=h end function Base:getWidth() return self.width end function Base:setWidth(w) self.width=w end
function Base:setEnable(v) self.enable=v end function Base:setTitle(v) self.title=v end
function Base:setWantKeyEvents() end function Base:setOnMouseDownFunction() end function Base:setOverrideAButtonFunction() end
function Base:getYScroll() return 0 end function Base:setYScroll() end function Base:setScrollHeight() end function Base:ensureVisible() end
function Base:drawText() end function Base:drawRect() end function Base:drawRectBorder() end
function Base:addItem(label,item,tooltip)
    local row={text=label,item=item,tooltip=tooltip,height=self.itemheight,index=#self.items+1}
    self.items[#self.items+1]=row return row
end
ISCollapsableWindow=Base ISScrollingListBox=Base ISButton=Base ISPanel=Base
for _,id in ipairs({"ISCollapsableWindow","ISScrollingListBox","ISButton","ISPanel"}) do package.loaded["ISUI/"..id]=true end
UIFont={Small=1} Keyboard={KEY_UP=1,KEY_DOWN=2,KEY_ESCAPE=3} Joypad={BButton=1,XButton=2,YButton=3}
local h,sw,sh=20,1920,1080
function getTextManager() return {getFontHeight=function() return h end,MeasureStringX=function(_,_,s) return #s*h/2 end} end
function getCore() return {getScreenWidth=function() return sw end,getScreenHeight=function() return sh end} end
function getTexture() return {} end
function getTextOrNull(key)
    local labels={intakeShort="入库分拣",tidyShort="错放整理",workerDetails="任务详情",noTask="暂无工单",WORKING="正在搬运",SCANNING="正在查找路线"}
    local id=key:match("IGUI_EmberRoutesProbe_Logistics_(.*)")
    return labels[id] or (ERTestTranslations and ERTestTranslations[key])
end
function getText(key) return getTextOrNull(key) or key end
dofile("D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/client/ISUI/ISTickBox.lua")
package.loaded["ISUI/ISTickBox"]=true
local releases,stops=0,0
local worker={id="worker",reason="SCANNING",state="IDLE",taskId="",producer="",delivered=0,total=0,source="",destination=""}
local snapshot={reason="SCANNING",running=true,intake=true,tidy=true,workers={worker}}
local root={} local entry={id="settlement",name="据点"}
package.loaded["EmberRoutesProbe/SettlementLedger"]={data=function() return root end,view=function() return entry end}
package.loaded["EmberRoutesProbe/LogisticsService"]={status=function() return snapshot end,watch=function() return function() releases=releases+1 end end,stop=function() stops=stops+1 end}
local command
package.loaded["EmberRoutesProbe/LogisticsMenu"]={command=function(_,mode) command=mode return "MODE_CONFIGURED" end}
package.loaded["EmberRoutesProbe/Driver"]={bindId=function() return {handle={getFullName=function() return "Joni Epps" end}} end}
package.loaded["EmberRoutesProbe/ContainerRegistry"]={describe=function() return nil end}
package.loaded["EmberRoutesProbe/UI/TooltipAnchor"]={attach=function() end,clear=function() end,dismissOwner=function() end,unregisterOwner=function() end,clearOwner=function() end}
local actor={getJoypadBind=function() return -1 end,getIndex=function() return 0 end}
local Page=require "EmberRoutesProbe/UI/LogisticsPage"
for _,r in ipairs({{1920,1080,20},{1280,720,28},{2560,1440,24}}) do
    sw,sh,h=r[1],r[2],r[3]
    local owner={actor=actor,entry=entry,valid=function() return true end}
    local panel=Page:new(owner,{x=0,y=0,width=math.min(sw*0.86,h*54),height=math.min(sh*0.82,h*29)})
    function owner:close() panel:dispose() panel.removed=true end
    panel:initialise() panel:activate()
    check(panel.modes[1].boxSize==h and panel.modes[2].boxSize==h,"native tick size follows font, not whole mode region")
    check(panel.modes[1].y+h<panel.workerList.y and panel.modes[2].x>panel.modes[1].x,"both native mode boxes remain visible above worker list")
    check(panel.workerList.height>h*2 and panel.buttons.retry.y>=panel.workerList.y+panel.workerList.height,"worker actions do not overlap the list")
    local visual=panel.workerList.items[1].item.visual
    check(not visual.progress and not panel.workerList.items[1].tooltip,"idle row has neither fake 0/0 progress nor redundant tooltip")
    local first=panel.workerList.items[1]
    panel:project(panel.store.value,{snapshot=true})
    check(panel.workerList.items[1]==first,"unchanged status reuses the native worker entry")
    worker.taskId="task" worker.total=5 worker.delivered=2 worker.reason="WORKING"
    panel:project(panel.store.value,{snapshot=true})
    check(panel.details.bar and panel.details.list.items[1].height>0,"active work uses a prepared progress bar inside scrollable details")
    worker.producer="LOGISTICS" worker.sourceMode="INTAKE" worker.phase="COLLECT" worker.state="RUNNING"
    worker.lastCompleted={id="previous-batch",delivered=6,total=6,sourceMode="TIDY"}
    panel:project(panel.store.value,{snapshot=true})
    local previousRow=panel.workerList.items[1].item.value
    local before=panel.workerList.items[1].item.visual.status
    local summary=false
    for _,line in ipairs(panel.details.lines) do if string.find(line.text,"6/6",1,true) then summary=true end end
    check(summary,"current batch retains the previous completion after replacement")
    worker.phase="DELIVER"
    panel:project(panel.store.value,{snapshot=true})
    check(panel.workerList.items[1].item.value~=previousRow and panel.workerList.items[1].item.visual.status~=before,
        "phase changes invalidate cached rows even without changing delivery count or task ID")
    local old=panel.workerList.items[1].item.value
    worker.lastCompleted={id="another-batch",delivered=4,total=4,sourceMode="INTAKE"}
    panel:project(panel.store.value,{snapshot=true})
    check(panel.workerList.items[1].item.value~=old,"a new completed summary refreshes the selected card")
    worker.sourceMode="TIDY" panel:project(panel.store.value,{snapshot=true})
    check(panel.workerList.items[1].item.value.sourceMode=="TIDY","tidy and intake keep distinct task identities")
    worker.taskId="" worker.total=0 worker.delivered=0 worker.reason="SCANNING"
    worker.state="IDLE" worker.producer="" worker.phase=nil worker.sourceMode=nil worker.lastCompleted=nil
    local before=releases panel:close() panel:close()
    check(releases==before+1 and stops==0 and panel.removed,"closing is idempotent and keeps service running")
end
print("PASS "..count.." scoped logistics page/native tick/lifecycle checks; game renderer NOT RUN")
