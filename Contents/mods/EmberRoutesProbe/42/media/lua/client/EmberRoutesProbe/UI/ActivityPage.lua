require 'ISUI/ISPanel'
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
local Definitions=require 'EmberRoutesProbe/ActivityRegistry'
local Catalog=require 'EmberRoutesProbe/ActivityScenarioCatalog'
local Presentation=require 'EmberRoutesProbe/UI/ActivityPresentation'
local ScenarioCard=require 'EmberRoutesProbe/UI/ActivityScenarioCard'
local AtmosphereBoard=require 'EmberRoutesProbe/UI/ActivityAtmosphereBoard'

---@class EmberRoutesActivityPage:ISPanel
---@field owner EmberRoutesSettlementDashboard
---@field actor IsoPlayer
---@field scope string
---@field fontHeight number
---@field pad number
local Page=ISPanel:derive('EmberRoutesActivityPage')

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
local function definitionName(id)
    local def=Definitions.get(id or 'FREE_GATHERING')
    return def and (getTextOrNull(def.nameKey) or t('unnamedActivity')) or t('definitionUnavailable')
end

---@param owner EmberRoutesSettlementDashboard
---@param bounds table
---@return EmberRoutesActivityPage
function Page:new(owner,bounds)
    local o=ISPanel.new(self,bounds.x,bounds.y,bounds.width,bounds.height)
    o.owner,o.actor,o.scope=owner,owner.actor,owner.entry.id
    o.fontHeight,o.pad=owner.fontHeight,owner.pad
    o.background=false
    o.selectedNpc,o.widgets,o.labels,o.names={},{},{},{}
    o.hasDraft=false
    o.mode='LIST'
    return o
end

function Page:initialise() ISPanel.initialise(self) end

function Page:button(r,label,callback,mode)
    local b=ISButton:new(r.x,r.y,r.width,math.min(r.height,self.fontHeight+self.pad),label,self,callback)
    b:initialise() Theme.button(b,false) self:addChild(b)
    if mode then self.widgets[#self.widgets+1]={control=b,mode=mode} end
    return b
end

function Page:list(r,mode,rowHeight,callback)
    local list=ISScrollingListBox:new(r.x,r.y,r.width,r.height)
    list:initialise() list.itemheight=rowHeight list.font=UIFont.Small
    list.backgroundColor=Theme.panel list.borderColor=Theme.border
    list.owner=self list.mode=mode list.doDrawItem=Page.drawRow
    if callback then list:setOnMouseDownFunction(self,callback) end
    Tooltip.attach(list,'updateTooltip')
    self:addChild(list) self.widgets[#self.widgets+1]={control=list,mode=mode}
    return list
end

function Page:field(r,key,value,mode,combo)
    local cols=assert(Layout.axis(r,{{grow=1},{grow=1}},{gap=self.pad/2}))
    local bounds=cols[1]
    self.labels[#self.labels+1]={mode=mode,bounds=bounds,
        lines=Text.wrapLimited(t(key),bounds.width,UIFont.Small,math.max(1,math.min(2,math.floor(bounds.height/self.fontHeight))))}
    local c=cols[2] local height=math.min(c.height,self.fontHeight+self.pad)
    local control=combo and ISComboBox:new(c.x,c.y,c.width,height,self,Page.draftChanged)
        or ISTextEntryBox:new(value or '',c.x,c.y,c.width,height)
    control:initialise() self:addChild(control)
    if not combo then control.target=self control.onTextChangeFunction=Page.draftChanged end
    control.tooltip=t(key) Tooltip.attach(control,'prerender')
    self.widgets[#self.widgets+1]={control=control,mode=mode}
    return control
end

function Page:createChildren()
    ISPanel.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local rows=assert(Layout.axis({x=0,y=0,width=self.width,height=self.height},
        {{basis=h+p},{grow=1},{basis=h*2.5},{basis=h+p}},{direction='column',padding=p,gap=p/2}))

    -- Top Mode Bar
    local top=assert(Layout.axis(rows[1],{{grow=1},{grow=1},{grow=1},{grow=1}},{gap=p/2}))
    self.listButton=self:button(top[1],t('listShort'),Page.showList)
    self.newButton=self:button(top[2],t('newShort'),Page.newDraft)
    self.rosterButton=self:button(top[3],t('rosterShort'),function(s) s:setMode('ROSTER') end)
    self.rulesButton=self:button(top[4],t('rulesShort'),function(s) s:setMode('RULES') end)

    -- Middle Content Area
    local columns=assert(Layout.axis(rows[2],{{grow=1},{grow=1}},{gap=p}))
    self.scenes=self:list(columns[1],'LIST',h*3,Page.selectScene)
    self.details=self:list(columns[2],'LIST',h*2.5,nil)
    self.reviewList=self:list(rows[2],'REVIEW',h*3.5,nil)

    -- ROSTER mode controls
    local left=assert(Layout.axis(columns[1],{{grow=1},{grow=1},{grow=1},{grow=1},{grow=1}}, {direction='column',gap=p}))
    self.nameField=self:field(left[1],'name',t('defaultName'),'ROSTER')
    self.definition=self:field(left[2],'activityType',nil,'ROSTER',true)
    self.definition.onChange=Page.chooseDefinition
    self.zone=self:field(left[3],'zone',nil,'ROSTER',true)
    self.organizer=self:field(left[4],'organizer',nil,'ROSTER',true)
    self.speaker=self:field(left[5],'speaker',nil,'ROSTER',true)

    local right=assert(Layout.axis(columns[2],{{grow=1},{basis=h+p}},{direction='column',gap=p}))
    self.roster=self:list(right[1],'ROSTER',h*1.8,Page.toggleNpc)
    local all=assert(Layout.axis(right[2],{{grow=1},{grow=1},{grow=1},{grow=1.5}},{gap=p}))
    self:button(all[1],t('all'),function(s) for _,row in ipairs(s.roster.items) do s.selectedNpc[row.item.id]=true end s:organizers() end,'ROSTER')
    self:button(all[2],t('none'),function(s) s.selectedNpc={} s:organizers() end,'ROSTER')
    self:button(all[3],t('refreshShort'),Page.refreshRoster,'ROSTER')
    self.advancedDrawerBtn=self:button(all[4],t('advancedDrawer'),function(s) s:setMode('RULES') end,'ROSTER')

    -- RULES mode controls
    self.ruleFields={}
    local tracks={} for _=1,7 do tracks[#tracks+1]={grow=1} end
    local ruleRows=assert(Layout.axis(columns[1],tracks,{direction='column',gap=p/2}))
    for i,id in ipairs(Zones.activities()) do
        local c=self:field(ruleRows[i],id,nil,'RULES',true)
        for _,key in ipairs({'inherit','disabled','allowed','preferred'}) do c:addOption(t(key)) end
        c.selected=id=='SOCIAL' and 4 or id=='OBSERVE' and 3 or 1
        self.ruleFields[id]=c
    end

    local fields={{'quorum','2'},{'durationMinutes','60'},{'gatherMinutes','10'},
        {'delayMinutes','0'},{'intervalHours','24'},{'occurrences','1'}}
    local timeTracks={} for _ in ipairs(fields) do timeTracks[#timeTracks+1]={grow=1} end
    timeTracks[#timeTracks+1]={grow=1}
    local timeRows=assert(Layout.axis(columns[2],timeTracks,{direction='column',gap=p/2}))
    self.timeFields={}
    for i,field in ipairs(fields) do self.timeFields[field[1]]=self:field(timeRows[i],field[1],field[2],'RULES') end
    self.basicDrawerBtn=self:button(timeRows[#timeTracks],t('basicDrawer'),function(s) s:setMode('ROSTER') end,'RULES')

    -- Notice / Hint row
    self.noticeBounds=rows[3]

    -- Bottom Action Bar
    local actions=assert(Layout.axis(rows[4],{{grow=1},{grow=1},{grow=1}},{gap=p}))
    self.cancelButton=self:button(actions[1],t('cancelShort'),Page.cancelSelected,'LIST')
    self.editButton=self:button(actions[3],t('editSelected'),Page.editSelected,'LIST')

    self.backButton=self:button(actions[1],t('backToList'),Page.showList,'EDITOR')
    self.previewButton=self:button(actions[2],t('previewShort'),Page.reviewDraft,'EDITOR')
    self.applyButton=self:button(actions[3],t('submit'),Page.applyDraft,'EDITOR')

    self.hasDraft=false
    self:setMode('LIST')
    self:refreshList()
end

function Page:draftChanged()
    if self.loadingDraft then return end
    self.reviewKey=nil self.token=nil self.firstAt=nil self.reviewList:clear()
    if self.applyButton then self.applyButton:setEnable(true) end
    self.notice=t('reviewRequired')
end

function Page:setMode(mode)
    self.mode=mode
    for _,w in ipairs(self.widgets) do
        local visible=w.mode==mode or w.mode=='EDITOR' and mode~='LIST'
        w.control:setVisible(visible)
        if not visible and w.control.hidePopup then w.control:hidePopup() end
        if not visible and w.control.unfocus then w.control:unfocus() end
        if not visible then Tooltip.clear(w.control) end
    end
    self.rosterButton:setEnable(self.hasDraft)
    self.rulesButton:setEnable(self.hasDraft)
    Theme.styleButton(self.listButton,mode=='LIST',mode=='LIST')
    Theme.styleButton(self.rosterButton,mode=='ROSTER',mode=='ROSTER')
    Theme.styleButton(self.rulesButton,mode=='RULES',mode=='RULES')
    self.notice=mode=='LIST' and t('listHint') or self.editing and t(self.editing.kind=='SCENE' and 'sceneEditHint' or 'planEditHint') or t('editorHint')
end

function Page.showList(self)
    self:setMode('LIST')
    self:refreshList()
end

function Page:name(id)
    if not id then return t('noneSelected') end
    if not self.names[id] then
        local b=Driver.bindId(self.actor,id)
        self.names[id]=Names.name(id,b and b.handle) or t('resident')
    end
    return self.names[id]
end

function Page:refreshRoster()
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
        local previousMember=self.editing and self.editing.kind=='SCENE' and self.editing.value.roster[id]
        if m and not m.pending and not m.retired and m.context=='SETTLEMENT'
            and not (previousMember and previousMember.withdrawn and not previousMember.settled) then
            local badge=Presentation.statusBadge('READY')
            self.roster:addItem(self:name(id),{id=id,name=self:name(id),badge=badge},self:name(id))
        end
    end
    self:organizers()
    self:cacheRows(self.roster)
end

function Page:organizers()
    local previous=datum(self.organizer) self.organizer:clear() local n=0
    local speaker=datum(self.speaker) self.speaker:clear()
    for _,row in ipairs(self.roster.items) do
        if self.selectedNpc[row.item.id] then
            self.organizer:addOptionWithData(row.item.name,row.item.id) n=n+1
            self.speaker:addOptionWithData(row.item.name,row.item.id)
            if row.item.id==previous then self.organizer.selected=n end
            if row.item.id==speaker then self.speaker.selected=n end
        end
    end
    local q=tonumber(self.timeFields.quorum:getText())
    if n>0 and (not q or q>n) then self.timeFields.quorum:setText(tostring(math.min(2,n))) end
    self:draftChanged()
end

function Page:toggleNpc(row)
    self.selectedNpc[row.id]=not self.selectedNpc[row.id]
    self:organizers()
end

function Page:newDraft()
    self.hasDraft=true self.editing=nil self.token=nil self.firstAt=nil self.selectedNpc={} self.reviewKey=nil
    self:lockSceneFields(false)
    self:loadDefinitions('FREE_GATHERING') self:chooseDefinition()
    self:refreshRoster()
    for _,row in ipairs(self.roster.items) do self.selectedNpc[row.item.id]=true end
    self:organizers() self:setMode('ROSTER')
end

function Page:loadDefinitions(id,version)
    self.definition:clear() self.definition.selected=0
    for _,def in ipairs(Definitions.list()) do
        self.definition:addOptionWithData(definitionName(def.id),def)
        if def.id==id and (version==nil or version==def.definitionVersion) then self.definition.selected=#self.definition.options end
    end
end

function Page:chooseDefinition()
    local def=datum(self.definition) if not def then return end
    local scenario=Catalog.fromDefinition(def.id)
    self.currentScenario=scenario
    local allowed={} for _,id in ipairs(def.behaviors) do allowed[id]=true end
    for id,c in pairs(self.ruleFields) do
        c.selected=not allowed[id] and 2 or def.defaultRules[id]==nil and 1 or def.defaultRules[id]+2
        c:setEnabled(allowed[id]==true and not def.scriptProfile)
    end
    self.timeFields.quorum:setText(tostring(def.defaultQuorum))
    self.speaker:setEnabled(def.scriptProfile~=nil)
    self.timeFields.durationMinutes:setText(tostring(def.defaultDurationHours*60))
    self.timeFields.gatherMinutes:setText(tostring(def.defaultGatherHours*60))
    local tip=getTextOrNull(def.descriptionKey) or ''
    if scenario then
        local purpose=getTextOrNull(scenario.purposeKey) or ''
        local benefit=scenario.benefits and getTextOrNull(scenario.benefits.summaryKey) or ''
        if #purpose>0 then tip=tip..'\n'..t('purposeShort')..': '..purpose end
        if #benefit>0 then tip=tip..'\n'..t('expectedBenefitLabel')..': '..benefit end
    end
    self.definition.tooltip=tip..'\n'..t('definitionLimit',def.maxParticipants)
    self:draftChanged()
end

function Page:refreshList()
    local old=self.selection and self.selection.id
    local scroll=self.scenes:getYScroll()
    self.scenes:clear()
    local events,why=Service.view(self.actor,self.scope,true)
    if not events then self.notice=reason(why) return end
    table.sort(events,function(a,b) return a.createdAt==b.createdAt and a.id>b.id or a.createdAt>b.createdAt end)
    for _,e in ipairs(events) do self.scenes:addItem(e.name,{id=e.id,kind='SCENE',value=e},e.name) end
    local plans,invalid=Service.schedules(self.actor,self.scope)
    if not plans then self.notice=reason(invalid) end
    for _,s in ipairs(plans or {}) do self.scenes:addItem(s.args.name,{id=s.id,kind='PLAN',value=s},s.args.name) end
    self:cacheRows(self.scenes)
    local selected
    local oldKind=self.selection and self.selection.kind
    for i,row in ipairs(self.scenes.items) do if row.item.id==old and row.item.kind==oldKind then selected=row.item self.scenes.selected=i break end end
    if not selected and self.scenes.items[1] then selected=self.scenes.items[1].item self.scenes.selected=1 end
    self:selectScene(selected)
    self.scenes:setYScroll(scroll)
    self.sourceRevision=Service.revision(self.actor,self.scope)
end

function Page:selectScene(row)
    local keep=self.selection and row and self.selection.id==row.id and self.selection.kind==row.kind
    local scroll=keep and self.details:getYScroll() or 0
    self.selection=row self.details:clear()
    if not row then self.cancelButton:setEnable(false) self.editButton:setEnable(false) return end
    local v=row.value
    if row.kind=='SCENE' then
        local detail,why=Service.detail(self.actor,row.id)
        if not detail then self.cancelButton:setEnable(false) self.editButton:setEnable(false) self.notice=reason(why) return end
        v=detail row.value=detail
    end
    local function line(label,value) self.details:addItem(label,{label=label,value=value},label..'\n'..tostring(value)) end
    if row.kind=='PLAN' then
        line(t('schedule'),v.args.name)
        line(t('state'),t(v.enabled and 'planned' or 'disabledPlan'))
        line(t('remaining'),tostring(math.max(0,v.count-v.lastIndex-1)))
        line(t('firstAt'),minutes(v.firstAt))
        local remaining=math.max(0,v.count-v.lastIndex-1)
        local nextAt=v.firstAt+(v.lastIndex+1)*v.intervalHours
        line(t('nextOccurrence'),v.enabled and remaining>0 and minutes(math.max(0,nextAt-getGameTime():getWorldAgeHours())) or t('noMoreOccurrences'))
        line(t('intervalHours'),tostring(v.intervalHours))
        line(t('zone'),self:zoneName(v.args.zoneId))
        line(t('reason'),reason(v.reason))
        self.cancelButton:setEnable(v.enabled)
        self.editButton:setEnable(true)
    else
        local stripItem=self.details:addItem(v.name or '',{kind='ATMOSPHERE_STRIP',detail=v},v.name or '')
        stripItem.height=math.floor(self.fontHeight*4.2)

        line(t('activityType'),definitionName(v.definition))
        line(t('state'),Presentation.phaseText(v.state,v.stage))
        if v.outcome then line(t('outcome'),Presentation.outcomeText(v.outcome)) end
        if v.stage then
            if v.stage.supported then
                line(t('stage'),v.stage.format==2 and t('phase_'..v.stage.id) or v.stage.id=='free' and t('freePhase') or t('stageNumber',v.stage.index))
                line(t('stageState'),reason(v.stage.state))
                if v.stage.format==2 and v.stage.index==2 and not v.stage.sharedStart then line(t('state'),t('armingRoles')) end
                line(t('stageExits'),t('stageExitCount',v.stage.exitCount,v.stage.actorCount))
            else line(t('stage'),reason('ACTIVITY_STAGE_UNSUPPORTED')) end
        end
        line(t('organizer'),self:name(v.organizerId))
        if v.speakerId then line(t('speaker'),self:name(v.speakerId)) end
        local host=v.roster[v.organizerId]
        line(t('requiredRole'),t((not host or host.withdrawn) and 'requiredAbsent'
            or host.state=='ACCEPTED' and 'requiredReady' or 'requiredPending'))
        line(t('quorum'),tostring(v.quorum or 1))
        line(t('zone'),self:zoneName(v.zone.id))
        local hours=getGameTime():getWorldAgeHours()
        if v.state=='GATHERING' then line(t('gatherRemaining'),minutes(math.max(0,v.gatherDeadline-hours)))
        elseif v.state=='RUNNING' then line(t('durationRemaining'),minutes(math.max(0,(v.stage and v.stage.sharedEnd or v.endsAt)-hours))) end
        local c=v.counts
        if c then
            line(t('headcounts'),t('headcountValues',c.invited,c.arrived,c.joined,c.settled))
            if c.unknown>0 then line(t('resultCheck'),t('unknownCount',c.unknown)) end
        end
        line(t('reason'),reason(v.reason))
        local ids={} for id in pairs(v.roster) do ids[#ids+1]=id end
        table.sort(ids,function(a,b) return self:name(a)<self:name(b) end)
        for _,id in ipairs(ids) do
            local m=v.roster[id]
            local mState=m.settled and 'SETTLED' or m.withdrawn and 'REJECTED' or m.joined and 'READY'
                or m.state=='ACCEPTED' and 'ADMITTED' or m.attendanceState or 'WAIT'
            local badge=Presentation.statusBadge(mState,m.reason)
            local label=self:name(id)..(v.speakerId and ' · '..t(id==v.speakerId and 'speaker' or 'listener') or '')
            local statusDesc=badge.text..' · '..t('participation',minutes(m.participationHours))
            if badge.desc and #badge.desc>0 then statusDesc=statusDesc..' ('..badge.desc..')' end
            line(label,statusDesc)
            if m.relief then
                local r=m.relief
                local rDesc=Presentation.benefitText(v.definition,v.state,r)
                line('  '..t('relief_'..r.state),rDesc)
            end
        end
        self.cancelButton:setEnable(v.state=='GATHERING' or v.state=='RUNNING')
        self.editButton:setEnable(v.state=='GATHERING' and hours<v.gatherDeadline)
    end
    self.detailMinute=math.floor(getGameTime():getWorldAgeHours()*60)
    local _,_,version=Service.revision(self.actor,self.scope,row.kind=='SCENE' and row.id or nil)
    self.detailVersion=version
    self.details:setYScroll(scroll)
    self:cacheRows(self.details)
end

function Page:zoneName(id)
    for _,zone in ipairs(Zones.list(self.scope) or {}) do if zone.id==id then return zone.name end end
    return t('zoneUnavailable')
end

function Page:lockSceneFields(locked)
    self.definition:setEnabled(not locked)
    self.zone:setEnabled(not locked)
    local def=datum(self.definition) local allowed={}
    if def then for _,id in ipairs(def.behaviors) do allowed[id]=true end end
    for id,c in pairs(self.ruleFields) do c:setEnabled(not locked and allowed[id]==true) end
    for id,c in pairs(self.timeFields) do
        if id~='quorum' then c:setEditable(not locked) end
    end
end

function Page:editSelected()
    local row=self.selection if not row then return end
    local v=row.value
    if row.kind=='SCENE' and (v.state~='GATHERING' or getGameTime():getWorldAgeHours()>=v.gatherDeadline) then
        self.notice=reason('ACTIVITY_EDIT_CLOSED') return
    end
    self.loadingDraft=true self.hasDraft=true self.editing={id=row.id,kind=row.kind,revision=v.revision,value=v}
    self.token=nil self.firstAt=nil self.reviewKey=nil self.selectedNpc={}
    local args
    if row.kind=='PLAN' then args=v.args else
        local roster={} for id,m in pairs(v.roster) do if not m.withdrawn then roster[#roster+1]=id end end
        args={name=v.name,roster=roster,zoneId=v.zone.id,zoneRevision=v.zone.revision,rules=v.rules,
            definitionId=v.definition,definitionVersion=v.definitionVersion,
            organizerId=v.organizerId,speakerId=v.speakerId,quorum=v.quorum,durationHours=v.durationHours,gatherHours=v.gatherDeadline-v.createdAt}
    end
    self:loadDefinitions(args.definitionId or 'FREE_GATHERING',args.definitionVersion)
    self:chooseDefinition()
    self:refreshRoster()
    for _,id in pairs(args.roster) do self.selectedNpc[id]=true end
    self:organizers()
    for i in ipairs(self.zone.options) do
        local zone=self.zone:getOptionData(i) if zone and zone.id==args.zoneId then self.zone.selected=i end
    end
    for i in ipairs(self.organizer.options) do if self.organizer:getOptionData(i)==args.organizerId then self.organizer.selected=i end end
    for i in ipairs(self.speaker.options) do if self.speaker:getOptionData(i)==args.speakerId then self.speaker.selected=i end end
    self.nameField:setText(args.name)
    for id,c in pairs(self.ruleFields) do c.selected=args.rules[id]==nil and 1 or args.rules[id]+2 end
    self.timeFields.quorum:setText(tostring(args.quorum or math.min(2,#args.roster)))
    self.timeFields.durationMinutes:setText(string.format('%.6f',args.durationHours*60))
    self.timeFields.gatherMinutes:setText(string.format('%.6f',(args.gatherHours or math.min(args.durationHours,1/6))*60))
    local nextAt=row.kind=='PLAN' and v.firstAt+(v.lastIndex+1)*v.intervalHours or 0
    self.timeFields.delayMinutes:setText(row.kind=='PLAN' and string.format('%.6f',math.max(0,(nextAt-getGameTime():getWorldAgeHours())*60)) or '0')
    self.timeFields.intervalHours:setText(row.kind=='PLAN' and tostring(v.intervalHours) or '24')
    self.timeFields.occurrences:setText(row.kind=='PLAN' and tostring(math.max(1,v.count-v.lastIndex-1)) or '1')
    self.editZone={id=args.zoneId,revision=args.zoneRevision}
    self:lockSceneFields(row.kind=='SCENE') self.loadingDraft=false self:setMode('ROSTER')
end

function Page:cancelSelected()
    local row=self.selection if not row then return end
    local ok,why
    if row.kind=='PLAN' then ok,why=Service.cancelSchedule(self.actor,row.id,row.value.revision)
    else ok,why=Service.cancel(self.actor,row.id,row.value.revision) end
    self:refreshList() self.notice=ok and t('cancelRequested') or reason(why)
end

function Page:readDraft()
    local zone=datum(self.zone) local organizer=datum(self.organizer)
    local definition=datum(self.definition)
    if not definition then return nil,t('definitionUnavailable') end
    if not zone then return nil,t('zoneRequired') end
    local roster={} for _,row in ipairs(self.roster.items) do if self.selectedNpc[row.item.id] then roster[#roster+1]=row.item.id end end
    local rules={} for id,c in pairs(self.ruleFields) do if c.selected>1 then rules[id]=c.selected-2 end end
    local values={} for id,c in pairs(self.timeFields) do values[id]=tonumber(c:getText()) end
    for _,id in ipairs({'durationMinutes','gatherMinutes','quorum','delayMinutes','intervalHours','occurrences'}) do
        local value=values[id]
        if not value or value~=value or math.abs(value)>=100000000 then return nil,t('invalidNumbers') end
    end
    if values.durationMinutes<1 or values.durationMinutes>1440 or values.gatherMinutes<1 or values.gatherMinutes>1440
        or values.quorum<1 or values.quorum~=math.floor(values.quorum) or values.delayMinutes<0
        or values.occurrences<1 or values.occurrences>366 or values.occurrences~=math.floor(values.occurrences)
        or values.intervalHours<0 or values.occurrences>1 and values.intervalHours<1/60 then return nil,t('invalidNumbers') end
    if self.editing and self.editing.kind=='SCENE' then zone=self.editZone end
    local args={name=self.nameField:getText(),settlementId=self.scope,zoneId=zone.id,zoneRevision=zone.revision,
        definitionId=definition.id,definitionVersion=definition.definitionVersion,
        organizerId=organizer,roster=roster,rules=rules,quorum=values.quorum,
        durationHours=values.durationMinutes/60,gatherHours=values.gatherMinutes/60}
    if definition.scriptProfile then args.speakerId=datum(self.speaker) end
    if self.editing and self.editing.kind=='SCENE' then
        local original=self.editing.value
        args.durationHours=original.durationHours args.gatherHours=original.gatherDeadline-original.createdAt
    end
    local key=Definitions.commandKey(args)
    if not key then return nil,reason('ACTIVITY_DATA_INVALID') end
    key=key..'|time:'..values.delayMinutes..':'..values.intervalHours..':'..values.occurrences
    return {args=args,values=values,key=key,
        planned=self.editing and self.editing.kind=='PLAN' or values.delayMinutes>0 or values.occurrences>1}
end

function Page:reviewDraft()
    local draft,why=self:readDraft()
    self.reviewKey=nil self.reviewList:clear()
    if not draft then self.notice=why return end
    local review,failed=Service.review(self.actor,draft.args,draft.planned,self.editing and self.editing.kind=='SCENE' and self.editing.id)
    if not review then self.notice=reason(failed) return end
    local function line(label,value) self.reviewList:addItem(label,{label=label,value=value},label..'\n'..value) end
    line(t('activityType'),definitionName(draft.args.definitionId))
    line(t('preflight'),t('preflightCounts',review.ready,review.waiting,review.unknown))
    local ids={} for id in pairs(review.participants) do ids[#ids+1]=id end
    table.sort(ids,function(a,b) return self:name(a)<self:name(b) end)
    for _,id in ipairs(ids) do
        local p=review.participants[id]
        line(self:name(id),reason(p.state)..(p.reason and ' - '..reason(p.reason) or ''))
    end
    self:cacheRows(self.reviewList)
    self.reviewKey=review.ok~=false and draft.key or nil
    self.applyButton:setEnable(review.ok~=false)
    self:setMode('REVIEW')
    self.notice=review.ok==false and reason(review.reason) or t(draft.planned and 'planPreviewHint' or 'previewHint')
end

function Page:applyDraft()
    local draft,why=self:readDraft() if not draft then self.notice=why return end
    if self.reviewKey~=draft.key then self:reviewDraft() return end
    local args,values=draft.args,draft.values
    local token,why=self.token
    if not token then token,why=Service.issue(self.actor,self.scope) self.token=token end
    if not token then self.notice=reason(why) return end
    local result,failed
    if self.editing and self.editing.kind=='SCENE' then
        result,failed=Service.update(self.actor,self.editing.id,self.editing.revision,args,token)
    elseif draft.planned then
        if not self.firstAt then self.firstAt=getGameTime():getWorldAgeHours()+values.delayMinutes/60 end
        if self.editing then
            result,failed=Service.updateSchedule(self.actor,self.editing.id,self.editing.revision,args,token,self.firstAt,values.intervalHours,values.occurrences)
        else result,failed=Service.schedule(self.actor,args,token,self.firstAt,values.intervalHours,values.occurrences) end
    else result,failed=Service.start(self.actor,args,token) end
    if not result then
        self.firstAt=nil self.reviewKey=nil
        if failed=='ACTIVITY_REQUEST_EXPIRED' then self.token=nil end
        self.notice=reason(failed) return
    end
    local edited=self.editing~=nil
    self.token=nil self.firstAt=nil self.reviewKey=nil self.editing=nil self.hasDraft=false
    self:setMode('LIST') self:refreshList()
    self.notice=result.outcome and result.outcome~='COMPLETED' and reason(result.reason) or t(edited and 'updated' or 'created')
end

function Page:cacheRows(list)
    for _,item in ipairs(list.items) do
        local row=item.item local label,value
        if list.mode=='ROSTER' then
            label=row.name
        elseif list==self.scenes then
            label=row.value.name or row.value.args.name
            value=row.kind=='PLAN' and t(row.value.enabled and 'planned' or 'disabledPlan') or Presentation.phaseText(row.value.state,row.value.stage)
        elseif row.kind=='ATMOSPHERE_STRIP' then
            label='' value=nil
        elseif row.kind=='RESIDENT_CARD' then
            label=row.name value=nil
        else
            label=row.label value=row.value
        end
        local x=list.mode=='ROSTER' and self.fontHeight*1.8 or 6
        item.drawLabel=Text.wrapLimited(label or '',list.width-x-20,UIFont.Small,1)[1] or ''
        item.drawValues=value and Text.wrapLimited(value,list.width-26,UIFont.Small,list==self.reviewList and 2 or 1) or {}
    end
end

function Page.drawRow(list,y,item,alt)
    local o=list.owner local row=item.item local h=o.fontHeight local color=Theme.textColor
    local scroll=list:getYScroll()
    if y+scroll+item.height<0 or y+scroll>=list.height then return y+item.height end
    if list.selected==item.index then
        local c=Theme.selected list:drawRect(0,y,list.width,item.height,c.a,c.r,c.g,c.b)
    end
    if row and row.kind=='ATMOSPHERE_STRIP' then
        AtmosphereBoard.drawStrip(list,4,y+2,list.width-8,item.height-4,row.detail)
        return y+item.height
    end
    if row and row.kind=='RESIDENT_CARD' then
        AtmosphereBoard.drawResidentCard(list,4,y+2,list.width-8,item.height-4,row.name,row.role,row.member,row.isSpeaker,row.isOrganizer)
        return y+item.height
    end
    if list.mode=='ROSTER' then
        local size=math.max(8,h*.7) local yy=y+(item.height-size)/2
        list:drawRectBorder(6,yy,size,size,1,color.r,color.g,color.b)
        if o.selectedNpc[row.id] then list:drawRect(9,yy+3,size-6,size-6,1,Theme.accent.r,Theme.accent.g,Theme.accent.b) end
        if row.badge then
            local badgeText=row.badge.text or ''
            local bw=(getTextManager and getTextManager():MeasureStringX(UIFont.Small,badgeText) or (#badgeText*8))+8
            local bx=list.width-bw-10
            local by=y+(item.height-h)/2
            list:drawRect(bx,by,bw,h,0.9,0.12,0.16,0.20)
            list:drawRectBorder(bx,by,bw,h,1,0.35,0.75,0.45)
            Theme.text(list,badgeText,bx+4,by,Theme.accent)
        end
    end
    Theme.text(list,item.drawLabel or '',list.mode=='ROSTER' and h*1.8 or 6,y+3,color)
    for i,line in ipairs(item.drawValues or {}) do Theme.text(list,line,6,y+h+5+(i-1)*h,Theme.muted) end
    return y+item.height
end

function Page:prerender()
    ISPanel.prerender(self)
    for _,label in ipairs(self.labels) do
        if label.mode==self.mode then
            local r=label.bounds
            for i,line in ipairs(label.lines) do Theme.text(self,line,r.x,r.y+(i-1)*self.fontHeight,Theme.textColor) end
        end
    end
    local r=self.noticeBounds
    if self.notice~=self.preparedNotice then
        self.preparedNotice=self.notice self.noticeLines=Text.wrapLimited(self.notice or '',r.width,UIFont.Small,3)
    end
    for i,line in ipairs(self.noticeLines or {}) do Theme.text(self,line,r.x,r.y+(i-1)*self.fontHeight,Theme.muted) end
end

function Page:update()
    if ISPanel.update then ISPanel.update(self) end
    if not self.owner:valid() then return end
    local now=getTimestampMs()
    if self.mode=='LIST' and now>=(self.nextRefresh or 0) then
        self.nextRefresh=now+1000
        local revision,why,version=Service.revision(self.actor,self.scope,self.selection and self.selection.kind=='SCENE' and self.selection.id or nil)
        if revision==nil then self.notice=reason(why)
        elseif revision~=self.sourceRevision then self:refreshList()
        elseif self.selection and (self.detailVersion~=version or self.detailMinute~=math.floor(getGameTime():getWorldAgeHours()*60)) then self:selectScene(self.selection) end
    end
end

function Page:activate()
    self:setVisible(true)
    self:refreshList()
end

function Page:deactivate()
    self:setVisible(false)
    for _,w in ipairs(self.widgets) do
        if w.control.hidePopup then w.control:hidePopup() end
        if w.control.unfocus then w.control:unfocus() end
        Tooltip.clear(w.control)
    end
end

function Page:dispose()
    if self.disposed then return end
    self.disposed=true
    self:deactivate()
end

return Page
