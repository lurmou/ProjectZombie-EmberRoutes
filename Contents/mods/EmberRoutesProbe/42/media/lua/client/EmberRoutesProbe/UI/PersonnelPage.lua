require 'ISUI/ISPanel'
require 'ISUI/ISButton'
require 'ISUI/ISContextMenu'
local Layout=require 'EmberRoutesProbe/UI/Layout'
local State=require 'EmberRoutesProbe/UI/State'
local Cached=require 'EmberRoutesProbe/UI/CachedList'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Lifecycle=require 'EmberRoutesProbe/UI/PageLifecycle'
local Tooltip=require 'EmberRoutesProbe/UI/TooltipManager'
local Text=require 'EmberRoutesProbe/UI/Text'
local Public=require 'EmberRoutesProbe/Work/PublicWork'
local Crafting=require 'EmberRoutesProbe/Crafting/CraftingService'
local DossierDrawer=require 'EmberRoutesProbe/UI/PersonnelDossierDrawer'

local function text(key,...) return getText('IGUI_EmberRoutesProbe_Personnel_'..key,...) end
local function pubText(key,...) return getText('IGUI_EmberRoutesProbe_Public_'..key,...) end
local function tr(key,fallback) local v=getTextOrNull(key) return v or fallback or key end

local PRIORITY_COLORS={
    [0]={bg={r=0.18,g=0.20,b=0.22,a=0.8},border={r=0.35,g=0.35,b=0.40,a=0.9},text={r=0.50,g=0.55,b=0.60,a=1.0}},
    [1]={bg={r=0.35,g=0.28,b=0.10,a=0.9},border={r=1.00,g=0.78,b=0.25,a=1.0},text={r=1.00,g=0.85,b=0.30,a=1.0}},
    [2]={bg={r=0.12,g=0.28,b=0.20,a=0.9},border={r=0.35,g=0.88,b=0.60,a=1.0},text={r=0.40,g=0.92,b=0.65,a=1.0}},
    [3]={bg={r=0.10,g=0.22,b=0.32,a=0.9},border={r=0.25,g=0.75,b=1.00,a=0.9},text={r=0.35,g=0.80,b=1.00,a=1.0}},
    [4]={bg={r=0.14,g=0.16,b=0.20,a=0.8},border={r=0.40,g=0.48,b=0.55,a=0.8},text={r=0.60,g=0.68,b=0.75,a=1.0}}
}

---@class EmberRoutesPersonnelPage:ISPanel
---@field owner EmberRoutesSettlementDashboard
---@field actor IsoPlayer
---@field entry table
---@field fontHeight number
---@field pad number
---@field store table
---@field matrixList EmberRoutesCachedList
---@field active boolean?
---@field disposed boolean?
EmberRoutesPersonnelPage=ISPanel:derive('EmberRoutesPersonnelPage')
function EmberRoutesPersonnelPage.floorLabel(z)
    local floor=math.floor(z+0.5)
    return floor==0 and getText('IGUI_EmberRoutesProbe_Settlement_floorGround')
        or ((floor+1)..getText('IGUI_EmberRoutesProbe_Settlement_floorLevel'))
end

---@param owner EmberRoutesSettlementDashboard
---@param bounds table
---@return EmberRoutesPersonnelPage
function EmberRoutesPersonnelPage:new(owner,bounds)
    local o=ISPanel.new(self,bounds.x,bounds.y,bounds.width,bounds.height)
    o.owner=owner
    o.actor,o.entry=owner.actor,owner.entry
    o.fontHeight,o.pad=owner.fontHeight,owner.pad
    o.background=false o.workFilter='all' o.overview={byNpc={}}
    o.bottomNoticeBounds={x=0,y=bounds.height-o.fontHeight,width=bounds.width,height=o.fontHeight}
    o.store=State.new({workers={},selected=nil,notice='',revision=0})
    return o
end

function EmberRoutesPersonnelPage:initialise() ISPanel.initialise(self) end

function EmberRoutesPersonnelPage:createChildren()
    ISPanel.createChildren(self)
    local h,p=self.fontHeight,self.pad

    local regions=assert(Layout.axis({x=0,y=0,width=self.width,height=self.height},
        {{basis=h+p},{grow=1},{basis=h}},
        {direction='column',padding=p,gap=p/2}))

    local top=assert(Layout.axis(regions[1],{{grow=1},{basis=h*6}},{gap=p}))
    self.topInfoBounds=top[1]
    self.workFilters=require('EmberRoutesProbe/UI/FilterChips'):new(top[1].x,top[1].y,top[1].width,top[1].height,function(key)
        self.workFilter=key self.store:setState({revision=self.store.value.revision+1})
    end)
    local options={}
    for _,key in ipairs({'all','working','idle','blocked'}) do options[#options+1]={id=key,label=getText('IGUI_EmberRoutesProbe_Distributed_'..key)} end
    self.workFilters:setOptions(options,self.workFilter) self:addChild(self.workFilters)

    self.refreshButton=ISButton:new(top[2].x,top[2].y,top[2].width,top[2].height,getText('IGUI_EmberRoutesProbe_Monitor_refresh'),self,function()
        self:refresh()
    end)
    self.refreshButton:initialise()
    Theme.button(self.refreshButton)
    self.refreshButton.onclick=function()
        local sel=self.store.value.selected
        if sel then require('EmberRoutesProbe/Settlement/PersonnelService').invalidate(sel.id) end
        self:refresh()
    end
    self:addChild(self.refreshButton)

    local mainCols=assert(Layout.axis(regions[2],{{grow=74},{grow=26}},{gap=p}))
    self.matrixBounds=mainCols[1]
    self.detailsBounds=mainCols[2]

    local rightParts=assert(Layout.axis(self.detailsBounds,{{basis=h+p},{grow=1},{basis=(h+p)*2+p/2}},{direction='column',gap=p/2}))
    self.infoBounds=rightParts[2]
    self.dossierButton=ISButton:new(rightParts[1].x,rightParts[1].y,rightParts[1].width,rightParts[1].height,
        text('viewDossier'),self,function() self:toggleDossierDrawer() end)
    self.dossierButton:initialise() Theme.button(self.dossierButton) self:addChild(self.dossierButton)
    self.info=require('EmberRoutesProbe/UI/InfoList').new(self,self.infoBounds)
    self.workCommands={}
    local actionRows=assert(Layout.axis(rightParts[3],{{grow=1},{grow=1}},{direction='column',gap=p/2}))
    local commands={}
    for _,row in ipairs(actionRows) do
        for _,b in ipairs(assert(Layout.axis(row,{{grow=1},{grow=1}},{gap=p/2}))) do commands[#commands+1]=b end
    end
    for i,key in ipairs({'stop','resume','return','stopBody'}) do
        local b=commands[i]
        local button=ISButton:new(b.x,b.y,b.width,b.height,getText('IGUI_EmberRoutesProbe_Distributed_'..key),self,function()
            if not self.active or not self.activationScope:isCurrent() then return end
            local result=require('EmberRoutesProbe/Work/WorkCommandAdapter').command(self.actor,self.entry.id,self.currentWork and self.currentWork.row,key)
            self.store:setState({notice=require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)}) self:refresh()
        end)
        button:initialise() Theme.button(button) button:setVisible(false) self:addChild(button) self.workCommands[key]=button
    end

    local matrixParts=assert(Layout.axis(self.matrixBounds,{{basis=h*2+p/2},{grow=1}},{direction='column',gap=p/4}))
    self.headerBounds=matrixParts[1]
    self.headerBounds.width=math.max(1,self.headerBounds.width-16)

    self.workCategories=Public.categories()
    self.matrixNameRatio=#self.workCategories>4 and .22 or .4
    self.priorityHeaders={}
    local colTracks={{grow=self.matrixNameRatio*100}}
    for _ in ipairs(self.workCategories) do colTracks[#colTracks+1]={grow=(1-self.matrixNameRatio)*100/#self.workCategories} end
    self.colHeaders=assert(Layout.axis(self.headerBounds,colTracks,{gap=p/3}))
    for i,category in ipairs(self.workCategories) do
        local key=category local bounds=self.colHeaders[i+1]
        local button=ISButton:new(bounds.x,bounds.y,bounds.width,bounds.height,pubText(key),self,function() self:batchCycle(key) end)
        button:initialise() Theme.button(button) button.tooltip=text('priorityHint')
        local fullTitle=pubText(key)
        local lines=Text.wrapLimited(fullTitle,bounds.width-p/2,UIFont.Small,2)
        button.title='' button.tooltip=fullTitle..'\n'..text('priorityHint')
        local widths={} for i,label in ipairs(lines) do widths[i]=getTextManager():MeasureStringX(UIFont.Small,label) end
        local originalRender=button.render
        button.render=function(btn)
            if originalRender then originalRender(btn) end
            for line,label in ipairs(lines) do
                local tw=widths[line]
                Theme.text(btn,label,(btn.width-tw)/2,(btn.height-#lines*h)/2+(line-1)*h,Theme.textColor)
            end
        end
        Tooltip.register(button,{method='prerender',owner=self}) self:addChild(button) self.priorityHeaders[#self.priorityHeaders+1]=button
    end
    local listBounds=matrixParts[2]
    local listStyle={emptyColor=Theme.muted,
        prepare=function(list,value)
            local cells={}
            for _,key in ipairs(self.workCategories) do
                local n=value.priorities[key] or 3 local label=n==0 and '-' or tostring(n)
                cells[#cells+1]={value=n,label=label,width=getTextManager():MeasureStringX(UIFont.Small,label)}
            end
            return {height=math.floor(h*2.2),work=Text.wrapLimited(value.workLine or '',list.width-p*2,UIFont.Small,1)[1] or '',name=Text.wrapLimited(value.name,self.colHeaders[1].width-p*2,UIFont.Small,1)[1] or '',cells=cells}
        end,
        draw=function(list,y,entry)
            local item=entry.item.value local rowH=entry.height
            if y+list:getYScroll()+rowH<0 or y+list:getYScroll()>=list.height then return y+rowH end
            if list.selected==entry.index then Theme.rect(list,0,y,list.width,rowH,Theme.selected)
            elseif list.mouseoverselected==entry.index then Theme.rect(list,0,y,list.width,rowH,Theme.hover) end
            local dot=item.busy and Theme.gold or Theme.accent
            Theme.rect(list,p/2,y+rowH/2-3,6,6,dot)
            Theme.text(list,entry.item.visual.name,p+8,y,Theme.textColor)
            Theme.text(list,entry.item.visual.work,p/2,y+rowH-h,Theme.muted)
            local mx=list:getMouseX()
            for i,cell in ipairs(entry.item.visual.cells) do
                local r=self.colHeaders[i+1]
                local x=r.x-self.headerBounds.x+p/4 local w=r.width-p/2
                local style=PRIORITY_COLORS[cell.value] or PRIORITY_COLORS[3]
                local hovered=list.mouseoverselected==entry.index and mx>=x and mx<=x+w
                Theme.rect(list,x,y,w,rowH-h,style.bg) Theme.rect(list,x,y,w,rowH-h,hovered and Theme.accent or style.border,true)
                Theme.text(list,cell.label,x+(w-cell.width)/2,y+(rowH-h*2)/2,style.text)
            end
            return y+rowH
        end}

    self.matrixList=Cached.create(self,listBounds,function(_,row)
        self.store:setState({selected=row})
    end,listStyle)
    Theme.list(self.matrixList)
    self.matrixList.itemheight=math.floor(h*2.2)
    self.matrixList.emberEmptyLines=Text.wrap(text('noWorkers'),listBounds.width-p*2,UIFont.Small)
    self:addChild(self.matrixList)

    local function categoryAt(list,x)
        for i,key in ipairs(self.workCategories) do
            local r=self.colHeaders[i+1] local left=r.x-self.headerBounds.x+p/4
            if x>=left and x<=left+r.width-p/2 then return key end
        end
    end
    local origMouseDown=self.matrixList.onMouseDown
    self.matrixList.onMouseDown=function(list,x,y)
        local row=list.items[list:rowAt(x,y)] local key=categoryAt(list,x)
        if row and key then self:cycleWorkerPriority(row.item.value,key) return true end
        return origMouseDown and origMouseDown(list,x,y) or true
    end
    local origMouseMove=self.matrixList.onMouseMove
    self.matrixList.onMouseMove=function(list,dx,dy)
        local row=list.items[list:rowAt(list:getMouseX(),list:getMouseY())]
        local key=categoryAt(list,list:getMouseX())
        if row and key then
            local w=row.item.value
            local val=(w.priorities and w.priorities[key]) or 3
            list.tooltip=text('cellTooltip',w.name or '',pubText(key),pubText('priority_'..val))
        else
            list.tooltip=nil
        end
        if list.tooltipUI then list.tooltipUI.name=nil list.tooltipUI.description=list.tooltip end
        return origMouseMove and origMouseMove(list,dx,dy) or false
    end
    self.matrixList.onRightMouseDown=function(list,x,y)
        local row=list.items[list:rowAt(x,y)] local key=categoryAt(list,x)
        if row and key then self:cycleWorkerPriority(row.item.value,key,-1) return true end
        if row then self.store:setState({selected=row.item.value}) self:onListActivate() return true end
        return false
    end
    -- Wheel scrolls the roster; priority changes require an explicit left/right click.

    self.bottomNoticeBounds=regions[3]
end

function EmberRoutesPersonnelPage:setWorkerPriority(worker,category,value)
    local values={}
    for _,key in ipairs(self.workCategories) do
        values[key]=(worker.priorities and worker.priorities[key]) or 3
    end
    values[category]=value
    local rev=(worker.priorities and worker.priorities.revision) or 0
    return Public.setPriorities(self.actor,self.entry.id,worker.id,values,rev)
end
function EmberRoutesPersonnelPage:cycleWorkerPriority(worker,category,delta)
    if not self.active or not self.owner:valid() then return end
    self.store:setState({selected=worker})
    local result=self:setWorkerPriority(worker,category,((worker.priorities[category] or 3)+(delta or 1))%5)
    self.store:setState({notice=require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)})
    self:refresh()
end
function EmberRoutesPersonnelPage:batchCycle(category)
    if not self.active or not self.activationScope or not self.activationScope:isCurrent() then return end
    local menu=ISContextMenu.get(self.actor:getIndex(),self.colHeaders[2].x+self:getAbsoluteX(),self.headerBounds.y+self:getAbsoluteY())
    self.activationScope:own(menu,function(m) m:hideSelfAndChildren2() end)
    for value=0,4 do
        menu:addOption(text('setAll',pubText(category),pubText('priority_'..value)),self,function()
            if not self.active or self.disposed or not self.owner:valid() then return end
            local ok,failed=0,{}
            for _,worker in ipairs(self.store.value.workers or {}) do
                local result=self:setWorkerPriority(worker,category,value)
                if result=='PRIORITY_SAVED' then ok=ok+1 else
                    failed[#failed+1]=worker.name..': '..require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)
                end
            end
            self.store:setState({notice=text('batchResult',ok,#failed)..(#failed>0 and (' | '..table.concat(failed,'; ')) or '')})
            self:refresh()
        end)
    end
end

function EmberRoutesPersonnelPage:resolveContext(context)
    if not context.npcId then return nil,"CONTEXT_UNSUPPORTED" end
    for _,worker in ipairs(Crafting.status(self.actor,self.entry.id).workers or {}) do
        if worker.id==context.npcId then return worker.id end
    end
    return nil,"TARGET_NOT_FOUND"
end

function EmberRoutesPersonnelPage:applyContext(context)
    if not self.active then return false end
    for _,worker in ipairs(self.store.value.workers or {}) do
        if worker.id==context.npcId then
            self.store:setState({selected=worker})
            for i,entry in ipairs(self.matrixList.items) do
                if entry.item.value.id==worker.id then self.matrixList.selected=i self.matrixList:ensureVisible(i) break end
            end
            return true
        end
    end
    return false
end

function EmberRoutesPersonnelPage:activate()
    local mounted=Lifecycle.mount(self,function(callback)
        if Crafting.watch then
            return require('EmberRoutesProbe/Work/WorkOverviewService').watch(self.actor,self.entry.id,callback)
        end
        return function() end
    end,function(snapshot)
        if snapshot and snapshot.reason=="WORLD_RESET" then self.owner:close() return end
        self:refresh()
    end)
    if mounted and self.active then
        self:refresh()
    end
end

function EmberRoutesPersonnelPage:deactivate()
    Lifecycle.unmount(self)
    self.batchResults=nil self.memberMenu=nil
    Tooltip.dismissOwner(self)
    if self.dossierDrawer then self.dossierDrawer:close() end
    if self.detailNpc then require('EmberRoutesProbe/Settlement/PersonnelService').release(self.detailNpc) self.detailNpc=nil end
end

function EmberRoutesPersonnelPage:dispose()
    self.disposed=true
    if self.dossierDrawer then self.dossierDrawer:dispose() self.dossierDrawer=nil end
    self:deactivate()
    Tooltip.unregisterOwner(self)
end

function EmberRoutesPersonnelPage:refresh()
    if not self.active or self.disposed then return end
    local status=Crafting.status(self.actor,self.entry.id)
    local rawWorkers=status.workers or {}
    local enriched=require('EmberRoutesProbe/Settlement/PersonnelService').enrichWorkers(self.actor,self.entry.id,rawWorkers)
    self.overview=require('EmberRoutesProbe/Work/WorkOverviewService').status(self.actor,self.entry.id)
    for _,w in ipairs(enriched) do
        local work=self.overview.byNpc[w.id]
        local state=work and work.state or 'idle'
        local title=work and work.title or ''
        if not work then
            local idle=require('EmberRoutesProbe/Leisure/LeisureService').status(w.id)
            title=idle and idle.reason and (getTextOrNull('IGUI_EmberRoutesProbe_Leisure_'..idle.reason) or '') or ''
        end
        w.workLine=title..' | '..getText('IGUI_EmberRoutesProbe_Distributed_'..state)
    end
    local selected=self.store.value.selected
    if selected then
        local found=false
        for _,w in ipairs(enriched) do
            if w.id==selected.id then selected=w found=true break end
        end
        if not found then selected=false end
    elseif not self.selectionInitialized then
        selected=enriched[1] or false
    end
    self.selectionInitialized=true
    local batchLines=require('EmberRoutesProbe/Integration/MembershipMenu').batchLines(self.batchResults)
    self.store:setState({workers=enriched,selected=selected,batchLines=batchLines,revision=self.store.value.revision+1})
end

function EmberRoutesPersonnelPage:project(value)
    if not self.active or self.disposed or not self.matrixList or not self.info then return end
    local rows={}
    for _,w in ipairs(value.workers or {}) do
        if require('EmberRoutesProbe/Work/WorkOverviewPresenter').visible(self.overview.byNpc[w.id],self.workFilter) then rows[#rows+1]=w end
    end
    local noticeW=self.bottomNoticeBounds and self.bottomNoticeBounds.width or (self.width or 400)
    self.noticeLine=Text.wrapLimited(value.notice or '',noticeW,UIFont.Small,1)[1] or ''
    local sel=value.selected
    local Personnel=require 'EmberRoutesProbe/Settlement/PersonnelService'
    if self.detailNpc~=(sel and sel.id) then
        Personnel.release(self.detailNpc) self.detailNpc=sel and sel.id self.knowledgePage=1
    end

    -- 2. Prepare Colonist Inspector detail items for self.info
    local detail={}
    if sel then
        local work=self.overview.byNpc[sel.id]
        detail[#detail+1]={text=sel.name,color=Theme.accent}
        if work then
            for _,line in ipairs(require('EmberRoutesProbe/UI/OrderMonitorCards').detailRows(work.row,false)) do detail[#detail+1]=line end
        else
            detail[#detail+1]={text=sel.workLine or '',color=Theme.muted}
        end
        self.currentWork=work
        local caps=require('EmberRoutesProbe/Work/WorkCommandAdapter').capabilities(work and work.row)
        for key,button in pairs(self.workCommands or {}) do button:setVisible(caps[key]==true) end
        if sel.isBleeding or sel.isInfected or sel.hasInjury then
            detail[#detail+1]={text=getText('IGUI_EmberRoutesProbe_Layout_injury'),color=Theme.status.ERROR}
        end

    else
        self.currentWork=nil
        for _,button in pairs(self.workCommands or {}) do button:setVisible(false) end
        detail[#detail+1]={text=text('noWorkers'),color=Theme.muted}
    end
    if sel then
        local extra=require('EmberRoutesProbe/UI/PersonnelPresentation').rows(Personnel.details(self.actor,self.entry.id,sel.id),self.detailMode,self.knowledgePage)
        if self.detailMode=='skills' or self.detailMode=='knowledge' then detail={} end
        for _,row in ipairs(extra) do detail[#detail+1]=row end
    end
    for _,line in ipairs(value.batchLines or {}) do detail[#detail+1]=line end
    self.info:set(detail)
    if self.dossierDrawer and self.dossierDrawerOpen then
        self.dossierDrawer:setWorker(sel)
    end

    -- 3. Reconcile matrix list
    local signature=function(w)
        local p=w.priorities or {}
        local prioParts={}
        for _,cat in ipairs(self.workCategories) do
            prioParts[#prioParts+1]=cat..'='..(p[cat] or 0)
        end
        return (w.workLine or '')..'|'..w.id..'|'..w.name..'|'..(w.busy and '1' or '0')..'|'..(p.revision or 0)..'|'..table.concat(prioParts,',')
    end
    Cached.reconcile(self.matrixList,rows,signature,function(w) return w.id end,true)
end

function EmberRoutesPersonnelPage:prerender()
    ISPanel.prerender(self)
    local h,p=self.fontHeight,self.pad

    -- Top Info


    -- Column 1 header (Worker Name)
    Theme.text(self,text('worker'),self.colHeaders[1].x+p/2,self.colHeaders[1].y+(self.colHeaders[1].height-h)/2,Theme.accent)

    -- Bottom notice
    local notice=self.store.value.notice or ''
    if notice~='' and self.bottomNoticeBounds then
        Theme.text(self,self.noticeLine or '',self.bottomNoticeBounds.x,self.bottomNoticeBounds.y,Theme.accent)
    end
end

function EmberRoutesPersonnelPage:update()
    ISPanel.update(self)
    if not self.active or self.disposed then return end
    local now=getTimestampMs()
    if not self.nextSyncCheck or now>self.nextSyncCheck then
        self.nextSyncCheck=now+5000
        self:refresh()
    end
end

function EmberRoutesPersonnelPage:onListFocus(_,direction)
    self.editCategory=direction<0 and 'crafting' or 'hauling'
    self.store:setState({notice=text('editHint',text(self.editCategory))})
end
function EmberRoutesPersonnelPage:toggleDossierDrawer(forceState)
    local newState=(forceState~=nil) and forceState or not self.dossierDrawerOpen
    self.dossierDrawerOpen=newState
    local sel=self.store.value.selected
    if newState and sel then
        local dash=self.owner
        local w=math.min(380,math.max(320,math.floor(dash.width*0.35)))
        local x,y,drawerW,drawerH=Layout.dockDrawer(dash,w,8)
        if not self.dossierDrawer then
            self.dossierDrawer=DossierDrawer:new(self,x,y,drawerW,drawerH)
            self.dossierDrawer:addToUIManager()
        else
            self.dossierDrawer:setX(x)
            self.dossierDrawer:setY(y)
            self.dossierDrawer:setWidth(drawerW)
            self.dossierDrawer:setHeight(drawerH)
            if not self.dossierDrawer:isVisible() then
                self.dossierDrawer:addToUIManager()
            end
        end
        self.dossierDrawer:setVisible(true)
        self.dossierDrawer:bringToTop()
        self.dossierDrawer:setWorker(sel)
    else
        if self.dossierDrawer then
            self.dossierDrawer:close()
        end
    end
end

function EmberRoutesPersonnelPage:onListKey(key)
    if key==Keyboard.KEY_RETURN then self:onListActivate()
    elseif key==Keyboard.KEY_LEFT or key==Keyboard.KEY_RIGHT then self:onListFocus(nil,key==Keyboard.KEY_LEFT and -1 or 1) end
end
function EmberRoutesPersonnelPage:onListActivate()
    local worker=self.store.value.selected if not worker then return end
    local category=self.editCategory or 'crafting'
    if not self.active or not self.activationScope or not self.activationScope:isCurrent() then return end
    if self.memberMenu then self.memberMenu:release() self.memberMenu=nil end
    local menu=ISContextMenu.get(self.actor:getIndex(),self:getAbsoluteX(),self:getAbsoluteY())
    self.memberMenu=self.activationScope:own(menu,function(value) value:hideSelfAndChildren2() end)
    local activation=self.activation
    local function guard() return self.active and not self.disposed and self.activation==activation and self.owner:valid() end
    local members=require 'EmberRoutesProbe/Integration/MembershipMenu'
    members.posting(self.actor,menu,worker.id,guard)
    members.batch(self.actor,menu,self.entry.id,self.store.value.workers,guard,function(results)
        if not guard() then return end
        self.batchResults=results self:refresh()
    end)
    for value=0,4 do menu:addOption(text(category)..': '..pubText('priority_'..value),self,function()
        if not guard() then return end
        local result=self:setWorkerPriority(worker,category,value)
        self.store:setState({notice=require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)}) self:refresh()
    end) end
end
function EmberRoutesPersonnelPage:close() if self.dossierDrawer then self.dossierDrawer:close() end self.owner:close() end
function EmberRoutesPersonnelPage:focusContent()
    if self.actor:getJoypadBind()~=-1 then setJoypadFocus(self.actor:getIndex(),self.matrixList) end
end

return EmberRoutesPersonnelPage
