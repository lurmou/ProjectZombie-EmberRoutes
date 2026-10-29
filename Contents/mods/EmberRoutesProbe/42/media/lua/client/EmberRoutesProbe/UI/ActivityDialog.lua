require 'ISUI/ISCollapsableWindow'
require 'ISUI/ISButton'
require 'ISUI/ISComboBox'
require 'ISUI/ISTextEntryBox'
require 'ISUI/ISScrollingListBox'
local Service=require 'EmberRoutesProbe/ActivityService'
local Zones=require 'EmberRoutesProbe/SettlementZones'
local Members=require 'EmberRoutesProbe/MembershipService'
local Driver=require 'EmberRoutesProbe/Driver'
local Names=require 'EmberRoutesProbe/DisplayNames'
local Layout=require 'EmberRoutesProbe/UI/Layout'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Text=require 'EmberRoutesProbe/UI/Text'
local Tooltip=require 'EmberRoutesProbe/UI/TooltipAnchor'
local Dialog=ISCollapsableWindow:derive('EmberRoutesActivityDialog')
local function t(key,...) return getText('IGUI_EmberRoutesProbe_Activity_'..key,...) end
local function reason(key)
    if not key then return '' end
    return getTextOrNull('IGUI_EmberRoutesProbe_Activity_'..key)
        or getTextOrNull('IGUI_EmberRoutesProbe_Leisure_'..key)
        or getTextOrNull('IGUI_EmberRoutesProbe_LifeZone_'..key)
        or getTextOrNull('IGUI_EmberRoutesProbe_Monitor_'..key) or t('blocked')
end
local function minutes(n) return tostring(math.floor((n or 0)*60+.5)) end
local function datum(combo) return combo:getOptionData(combo.selected) end
function Dialog.open(owner)
    if not owner:valid() then return end
    if owner.activityDialog then owner.activityDialog:close() end
    local h=owner.fontHeight local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    local w,height=math.min(sw*.94,h*62),math.min(sh*.94,h*43)
    local o=ISCollapsableWindow.new(Dialog,(sw-w)/2,(sh-height)/2,w,height)
    o.owner,o.actor,o.scope=owner,owner.actor,owner.entry.id o.fontHeight,o.pad=h,math.ceil(h*.6)
    o.title=t('title')..' - '..owner.entry.name o.resizable=false
    o.backgroundColor,o.borderColor=Theme.window,Theme.border
    o.selectedNpc,o.widgets,o.labels,o.names={},{},{},{}
    o:initialise() o:addToUIManager() owner.activityDialog=o return o
end
function Dialog:initialise() ISCollapsableWindow.initialise(self) end
function Dialog:button(r,label,callback,mode)
    local b=ISButton:new(r.x,r.y,r.width,math.min(r.height,self.fontHeight+self.pad),label,self,callback)
    b:initialise() Theme.button(b,false) self:addChild(b)
    if mode then self.widgets[#self.widgets+1]={control=b,mode=mode} end
    return b
end
function Dialog:list(r,mode,rowHeight,callback)
    local list=ISScrollingListBox:new(r.x,r.y,r.width,r.height)
    list:initialise() list.itemheight=rowHeight list.font=UIFont.Small list.backgroundColor=Theme.panel list.borderColor=Theme.border
    list.owner=self list.mode=mode list.doDrawItem=Dialog.drawRow
    if callback then list:setOnMouseDownFunction(self,callback) end
    Tooltip.attach(list,'updateTooltip')
    self:addChild(list) self.widgets[#self.widgets+1]={control=list,mode=mode}
    return list
end
function Dialog:field(r,key,value,mode,combo)
    local cols=assert(Layout.axis(r,{{grow=1},{grow=1}},{gap=self.pad/2}))
    self.labels[#self.labels+1]={mode=mode,text=t(key),bounds=cols[1]}
    local c=cols[2] local height=math.min(c.height,self.fontHeight+self.pad)
    local control=combo and ISComboBox:new(c.x,c.y,c.width,height,self,nil)
        or ISTextEntryBox:new(value or '',c.x,c.y,c.width,height)
    control:initialise() self:addChild(control)
    control.tooltip=t(key) Tooltip.attach(control,'prerender')
    self.widgets[#self.widgets+1]={control=control,mode=mode}
    return control
end
function Dialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local rows=assert(Layout.axis({x=0,y=self:titleBarHeight(),width=self.width,height=self.height-self:titleBarHeight()},
        {{basis=h+p},{grow=1},{basis=h*3},{basis=h+p}},{direction='column',padding=p,gap=p/2}))
    local top=assert(Layout.axis(rows[1],{{grow=1},{grow=1},{grow=1},{grow=1}},{gap=p/2}))
    self:button(top[1],t('list'),Dialog.showList)
    self:button(top[2],t('new'),Dialog.newDraft)
    self.rosterButton=self:button(top[3],t('roster'),function(s) s:setMode('ROSTER') end)
    self.rulesButton=self:button(top[4],t('rulesTiming'),function(s) s:setMode('RULES') end)
    local columns=assert(Layout.axis(rows[2],{{grow=1},{grow=1}},{gap=p}))
    self.scenes=self:list(columns[1],'LIST',h*3,Dialog.selectScene)
    self.details=self:list(columns[2],'LIST',h*2.5,nil)
    local left=assert(Layout.axis(columns[1],{{grow=1},{grow=1},{grow=1},{grow=1}}, {direction='column',gap=p}))
    self.nameField=self:field(left[1],'name',t('defaultName'),'ROSTER')
    self.zone=self:field(left[2],'zone',nil,'ROSTER',true)
    self.organizer=self:field(left[3],'organizer',nil,'ROSTER',true)
    self:button(left[4],t('refreshRoster'),Dialog.refreshRoster,'ROSTER')
    local right=assert(Layout.axis(columns[2],{{grow=1},{basis=h+p}},{direction='column',gap=p}))
    self.roster=self:list(right[1],'ROSTER',h*1.8,Dialog.toggleNpc)
    local all=assert(Layout.axis(right[2],{{grow=1},{grow=1}},{gap=p}))
    self:button(all[1],t('all'),function(s) for _,row in ipairs(s.roster.items) do s.selectedNpc[row.item.id]=true end s:organizers() end,'ROSTER')
    self:button(all[2],t('none'),function(s) s.selectedNpc={} s:organizers() end,'ROSTER')
    self.ruleFields={}
    local tracks={} for _=1,7 do tracks[#tracks+1]={grow=1} end
    local ruleRows=assert(Layout.axis(columns[1],tracks,{direction='column',gap=p/2}))
    for i,id in ipairs(Zones.activities()) do
        local c=self:field(ruleRows[i],id,nil,'RULES',true)
        for _,key in ipairs({'inherit','disabled','allowed','preferred'}) do c:addOption(t(key)) end
        c.selected=id=='SOCIAL' and 4 or id=='OBSERVE' and 3 or 1 self.ruleFields[id]=c
    end
    local fields={{'quorum','2'},{'durationMinutes','60'},{'gatherMinutes','10'},
        {'delayMinutes','0'},{'intervalHours','24'},{'occurrences','1'}}
    local timeTracks={} for _ in ipairs(fields) do timeTracks[#timeTracks+1]={grow=1} end
    local timeRows=assert(Layout.axis(columns[2],timeTracks,{direction='column',gap=p/2}))
    self.timeFields={}
    for i,field in ipairs(fields) do self.timeFields[field[1]]=self:field(timeRows[i],field[1],field[2],'RULES') end
    self.noticeBounds=rows[3]
    local actions=assert(Layout.axis(rows[4],{{grow=1},{grow=1}},{gap=p}))
    self.cancelButton=self:button(actions[1],t('cancelSelected'),Dialog.cancelSelected,'LIST')
    self.applyButton=self:button(actions[2],t('startOrSchedule'),Dialog.applyDraft,'EDITOR')
    self.closeButton2=self:button(actions[1],getText('UI_btn_close'),Dialog.close,'EDITOR')
    self.hasDraft=false self:setMode('LIST') self:refreshList()
end
function Dialog:setMode(mode)
    self.mode=mode
    for _,w in ipairs(self.widgets) do
        local visible=w.mode==mode or w.mode=='EDITOR' and mode~='LIST'
        w.control:setVisible(visible)
        if not visible and w.control.hidePopup then w.control:hidePopup() end
        if not visible and w.control.unfocus then w.control:unfocus() end
        if not visible then Tooltip.clear(w.control) end
    end
    self.rosterButton:setEnable(self.hasDraft) self.rulesButton:setEnable(self.hasDraft)
    self.notice=mode=='LIST' and t('listHint') or t('editorHint')
end
function Dialog.showList(self) self:setMode('LIST') self:refreshList() end
function Dialog:name(id)
    if not id then return t('noneSelected') end
    if not self.names[id] then
        local b=Driver.bindId(self.actor,id) self.names[id]=Names.name(id,b and b.handle) or t('resident')
    end
    return self.names[id]
end
function Dialog:refreshRoster()
    local previous=datum(self.zone)
    self.zone:clear()
    for _,zone in ipairs(Zones.list(self.scope) or {}) do
        if zone.enabled then
            self.zone:addOptionWithData(t('zoneOption',zone.name,zone.area.w,zone.area.h,zone.area.z),zone)
            if previous and previous.id==zone.id then self.zone.selected=#self.zone.options end
        end
    end
    self.roster:clear()
    for _,id in ipairs(Members.members(self.scope)) do
        local m=Members.view(id)
        if m and not m.pending and not m.retired and m.context=='SETTLEMENT' then
            self.roster:addItem(self:name(id),{id=id,name=self:name(id)},self:name(id))
        end
    end
    self:organizers()
end
function Dialog:organizers()
    local previous=datum(self.organizer) self.organizer:clear() local n=0
    for _,row in ipairs(self.roster.items) do
        if self.selectedNpc[row.item.id] then
            self.organizer:addOptionWithData(row.item.name,row.item.id) n=n+1
            if row.item.id==previous then self.organizer.selected=n end
        end
    end
    local q=tonumber(self.timeFields.quorum:getText())
    if n>0 and (not q or q>n) then self.timeFields.quorum:setText(tostring(math.min(2,n))) end
end
function Dialog:toggleNpc(row)
    self.selectedNpc[row.id]=not self.selectedNpc[row.id] self:organizers()
end
function Dialog:newDraft()
    self.hasDraft=true self.token=nil self.firstAt=nil self.selectedNpc={}
    self:refreshRoster()
    for _,row in ipairs(self.roster.items) do self.selectedNpc[row.item.id]=true end
    self:organizers() self:setMode('ROSTER')
end
function Dialog:refreshList()
    local old=self.selection and self.selection.id
    self.scenes:clear()
    local events,why=Service.view(self.actor,self.scope)
    if not events then self.notice=reason(why) return end
    table.sort(events,function(a,b) return a.createdAt==b.createdAt and a.id>b.id or a.createdAt>b.createdAt end)
    for _,e in ipairs(events) do self.scenes:addItem(e.name,{id=e.id,kind='SCENE',value=e},e.name) end
    local plans,invalid=Service.schedules(self.actor,self.scope)
    if not plans then self.notice=reason(invalid) end
    for _,s in ipairs(plans or {}) do self.scenes:addItem(s.args.name,{id=s.id,kind='PLAN',value=s},s.args.name) end
    local selected
    for i,row in ipairs(self.scenes.items) do if row.item.id==old then selected=row.item self.scenes.selected=i break end end
    if not selected and self.scenes.items[1] then selected=self.scenes.items[1].item self.scenes.selected=1 end
    self:selectScene(selected)
end
function Dialog:selectScene(row)
    self.selection=row self.details:clear()
    if not row then self.cancelButton:setEnable(false) return end
    local v=row.value
    local function line(label,value) self.details:addItem(label,{label=label,value=value},label..'\n'..tostring(value)) end
    if row.kind=='PLAN' then
        line(t('schedule'),v.args.name)
        line(t('state'),t(v.enabled and 'planned' or 'disabledPlan'))
        line(t('remaining'),tostring(math.max(0,v.count-v.lastIndex-1)))
        line(t('firstAt'),minutes(v.firstAt))
        line(t('reason'),reason(v.reason))
        self.cancelButton:setEnable(v.enabled)
    else
        line(t('state'),reason(v.state))
        if v.outcome then line(t('outcome'),reason(v.outcome)) end
        line(t('organizer'),self:name(v.organizerId))
        line(t('quorum'),tostring(v.quorum or 1))
        line(t('reason'),reason(v.reason))
        local ids={} for id in pairs(v.roster) do ids[#ids+1]=id end
        table.sort(ids,function(a,b) return self:name(a)<self:name(b) end)
        for _,id in ipairs(ids) do
            local m=v.roster[id]
            local status=m.settled and 'settled' or m.withdrawn and 'left' or m.joined and 'joined'
                or m.state=='ACCEPTED' and 'ready' or 'invited'
            line(self:name(id),t(status)..' · '..t('participation',minutes(m.participationHours))..(m.reason and ' · '..reason(m.reason) or ''))
        end
        self.cancelButton:setEnable(v.state=='GATHERING' or v.state=='RUNNING')
    end
end
function Dialog:cancelSelected()
    local row=self.selection if not row then return end
    local ok,why
    if row.kind=='PLAN' then ok,why=Service.cancelSchedule(self.actor,row.id,row.value.revision)
    else ok,why=Service.cancel(self.actor,row.id,row.value.revision) end
    self:refreshList() self.notice=ok and t('cancelRequested') or reason(why)
end
function Dialog:applyDraft()
    local zone=datum(self.zone) local organizer=datum(self.organizer)
    if not zone then self:setMode('ROSTER') self.notice=t('zoneRequired') return end
    local roster={} for _,row in ipairs(self.roster.items) do if self.selectedNpc[row.item.id] then roster[#roster+1]=row.item.id end end
    local rules={} for id,c in pairs(self.ruleFields) do if c.selected>1 then rules[id]=c.selected-2 end end
    local values={} for id,c in pairs(self.timeFields) do values[id]=tonumber(c:getText()) end
    if not values.durationMinutes or not values.gatherMinutes or not values.quorum or not values.delayMinutes
        or not values.intervalHours or not values.occurrences or values.delayMinutes<0 then self.notice=t('invalidNumbers') return end
    local args={name=self.nameField:getText(),settlementId=self.scope,zoneId=zone.id,zoneRevision=zone.revision,
        organizerId=organizer,roster=roster,rules=rules,quorum=values.quorum,
        durationHours=values.durationMinutes/60,gatherHours=values.gatherMinutes/60}
    local token,why=self.token
    if not token then token,why=Service.issue(self.actor,self.scope) self.token=token end
    if not token then self.notice=reason(why) return end
    local result,failed
    if values.delayMinutes>0 or values.occurrences>1 then
        if not self.firstAt then self.firstAt=getGameTime():getWorldAgeHours()+values.delayMinutes/60 end
        result,failed=Service.schedule(self.actor,args,token,self.firstAt,values.intervalHours,values.occurrences)
    else result,failed=Service.start(self.actor,args,token) end
    if not result then
        self.firstAt=nil
        if failed=='ACTIVITY_REQUEST_EXPIRED' then self.token=nil end
        self.notice=reason(failed) return
    end
    self.token=nil self.firstAt=nil self:setMode('LIST') self:refreshList() self.notice=t('created')
end
function Dialog.drawRow(list,y,item,alt)
    local o=list.owner local row=item.item local h=o.fontHeight local color=Theme.textColor
    if list.selected==item.index then
        local c=Theme.selected list:drawRect(0,y,list.width,item.height,c.a,c.r,c.g,c.b)
    end
    local label,value
    if list.mode=='ROSTER' then
        local size=math.max(8,h*.7) local yy=y+(item.height-size)/2
        list:drawRectBorder(6,yy,size,size,1,color.r,color.g,color.b)
        if o.selectedNpc[row.id] then list:drawRect(9,yy+3,size-6,size-6,1,Theme.accent.r,Theme.accent.g,Theme.accent.b) end
        label=row.name
    elseif list==o.scenes then
        label=row.value.name or row.value.args.name
        value=row.kind=='PLAN' and t(row.value.enabled and 'planned' or 'disabledPlan') or reason(row.value.state)
    else label=row.label value=row.value end
    local x=list.mode=='ROSTER' and h*1.8 or 6
    Theme.text(list,Text.wrapLimited(label or '',list.width-x-20,UIFont.Small,1)[1] or '',x,y+3,color)
    if value then Theme.text(list,Text.wrapLimited(value,list.width-26,UIFont.Small,1)[1] or '',6,y+h+5,Theme.muted) end
    return y+item.height
end
function Dialog:prerender()
    ISCollapsableWindow.prerender(self)
    for _,label in ipairs(self.labels) do
        if label.mode==self.mode then
            local r=label.bounds local lines=Text.wrapLimited(label.text,r.width,UIFont.Small,math.max(1,math.min(2,math.floor(r.height/self.fontHeight))))
            for i,line in ipairs(lines) do Theme.text(self,line,r.x,r.y+(i-1)*self.fontHeight,Theme.textColor) end
        end
    end
    local r=self.noticeBounds
    for i,line in ipairs(Text.wrapLimited(self.notice or '',r.width,UIFont.Small,3)) do Theme.text(self,line,r.x,r.y+(i-1)*self.fontHeight,Theme.muted) end
end
function Dialog:update()
    if ISCollapsableWindow.update then ISCollapsableWindow.update(self) end
    if not self.owner:valid() then self:close() return end
    local now=getTimestampMs()
    if self.mode=='LIST' and now>=(self.nextRefresh or 0) then self.nextRefresh=now+1000 self:refreshList() end
end
function Dialog:close()
    if self.disposed then return end self.disposed=true
    for _,w in ipairs(self.widgets) do
        if w.control.hidePopup then w.control:hidePopup() end
        Tooltip.clear(w.control)
    end
    ISCollapsableWindow.close(self) self:removeFromUIManager()
    if self.owner.activityDialog==self then self.owner.activityDialog=nil end
end
return Dialog
