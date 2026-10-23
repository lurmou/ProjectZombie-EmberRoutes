require 'ISUI/ISPanel'
require 'ISUI/ISButton'
local Layout=require 'EmberRoutesProbe/UI/Layout'
local State=require 'EmberRoutesProbe/UI/State'
local Cached=require 'EmberRoutesProbe/UI/CachedList'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Lifecycle=require 'EmberRoutesProbe/UI/PageLifecycle'
local Tooltip=require 'EmberRoutesProbe/UI/TooltipAnchor'
local Text=require 'EmberRoutesProbe/UI/Text'
local Public=require 'EmberRoutesProbe/PublicWork'
local Crafting=require 'EmberRoutesProbe/CraftingService'

local function text(key,...) return getText('IGUI_EmberRoutesProbe_Personnel_'..key,...) end
local function pubText(key,...) return getText('IGUI_EmberRoutesProbe_Public_'..key,...) end

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

---@param owner EmberRoutesSettlementDashboard
---@param bounds table
---@return EmberRoutesPersonnelPage
function EmberRoutesPersonnelPage:new(owner,bounds)
    local o=ISPanel.new(self,bounds.x,bounds.y,bounds.width,bounds.height)
    o.owner=owner
    o.actor,o.entry=owner.actor,owner.entry
    o.fontHeight,o.pad=owner.fontHeight,owner.pad
    o.background=false
    o.store=State.new({workers={},selected=nil,notice='',revision=0})
    o.store:subscribe(function(value)
        if o.active and not o.disposed then o:project(value) end
    end)
    return o
end

function EmberRoutesPersonnelPage:initialise() ISPanel.initialise(self) end

function EmberRoutesPersonnelPage:createChildren()
    ISPanel.createChildren(self)
    local h,p=self.fontHeight,self.pad

    local regions=assert(Layout.axis({x=0,y=0,width=self.width,height=self.height},
        {{basis=h*2+p},{grow=1},{basis=h+p}},
        {direction='column',padding=p,gap=p/2}))

    local top=assert(Layout.axis(regions[1],{{grow=1},{basis=h*6}},{gap=p}))
    self.topInfoBounds=top[1]

    self.refreshButton=ISButton:new(top[2].x,top[2].y,top[2].width,top[2].height,getText('IGUI_EmberRoutesProbe_Settlement_refresh'),self,function()
        self:refresh()
    end)
    self.refreshButton:initialise()
    Theme.button(self.refreshButton,true)
    self:addChild(self.refreshButton)

    local mainCols=assert(Layout.axis(regions[2],{{grow=65},{grow=35}},{gap=p}))
    self.matrixBounds=mainCols[1]
    self.detailsBounds=mainCols[2]

    local matrixParts=assert(Layout.axis(self.matrixBounds,{{basis=h+p/2},{grow=1}},{direction='column',gap=p/4}))
    self.headerBounds=matrixParts[1]

    local colTracks={{grow=40},{grow=30},{grow=30}}
    self.colHeaders=assert(Layout.axis(self.headerBounds,colTracks,{gap=p/3}))

    self.craftingHeaderBtn=ISButton:new(self.colHeaders[2].x,self.colHeaders[2].y,self.colHeaders[2].width,self.colHeaders[2].height,text('crafting'),self,function()
        self:batchCycle('crafting')
    end)
    self.craftingHeaderBtn:initialise()
    Theme.button(self.craftingHeaderBtn)
    self.craftingHeaderBtn.tooltip=text('priorityHint')
    Tooltip.attach(self.craftingHeaderBtn,'prerender')
    self:addChild(self.craftingHeaderBtn)

    self.haulingHeaderBtn=ISButton:new(self.colHeaders[3].x,self.colHeaders[3].y,self.colHeaders[3].width,self.colHeaders[3].height,text('hauling'),self,function()
        self:batchCycle('hauling')
    end)
    self.haulingHeaderBtn:initialise()
    Theme.button(self.haulingHeaderBtn)
    self.haulingHeaderBtn.tooltip=text('priorityHint')
    Tooltip.attach(self.haulingHeaderBtn,'prerender')
    self:addChild(self.haulingHeaderBtn)

    local listBounds=matrixParts[2]
    local listStyle={
        emptyColor=Theme.muted,
        prepare=function(list,value)
            return {height=math.floor(h*2.2)}
        end,
        draw=function(list,y,entry)
            local item=entry.item.value
            local rowH=entry.height
            if y+list:getYScroll()+rowH<0 or y+list:getYScroll()>=list.height then return y+rowH end

            if list.selected==entry.index then
                Theme.rect(list,0,y,list.width,rowH,Theme.selected)
            elseif list.mouseoverselected==entry.index then
                Theme.rect(list,0,y,list.width,rowH,Theme.hover)
            end

            -- Worker name column
            local nameW=list.width*0.40
            local statusDotColor=item.busy and {r=1.0,g=0.75,b=0.25,a=1.0} or {r=0.35,g=0.88,b=0.60,a=1.0}
            Theme.rect(list,p/2,y+rowH/2-3,6,6,statusDotColor)
            local nameText=Text.wrapLimited(item.name,nameW-p*2,UIFont.Small,1)[1] or item.name
            Theme.text(list,nameText,p+8,y+(rowH-h)/2,Theme.textColor)

            -- Priority cell 1: Crafting
            local c1X=nameW+p/4
            local c1W=list.width*0.30-p/2
            local c1Val=item.priorities and item.priorities.crafting or 3
            local c1Style=PRIORITY_COLORS[c1Val] or PRIORITY_COLORS[3]
            Theme.rect(list,c1X,y+2,c1W,rowH-4,c1Style.bg)
            Theme.rect(list,c1X,y+2,c1W,rowH-4,c1Style.border,true)
            local c1Text=pubText('priority_'..c1Val)
            local c1StrW=getTextManager():MeasureStringX(UIFont.Small,c1Text)
            Theme.text(list,c1Text,c1X+(c1W-c1StrW)/2,y+(rowH-h)/2,c1Style.text)

            -- Priority cell 2: Hauling
            local c2X=nameW+list.width*0.30+p/4
            local c2W=list.width*0.30-p/2
            local c2Val=item.priorities and item.priorities.hauling or 3
            local c2Style=PRIORITY_COLORS[c2Val] or PRIORITY_COLORS[3]
            Theme.rect(list,c2X,y+2,c2W,rowH-4,c2Style.bg)
            Theme.rect(list,c2X,y+2,c2W,rowH-4,c2Style.border,true)
            local c2Text=pubText('priority_'..c2Val)
            local c2StrW=getTextManager():MeasureStringX(UIFont.Small,c2Text)
            Theme.text(list,c2Text,c2X+(c2W-c2StrW)/2,y+(rowH-h)/2,c2Style.text)

            return y+rowH
        end
    }

    self.matrixList=Cached.create(self,listBounds,function(_,row)
        self.store:setState({selected=row})
    end,listStyle)
    Theme.list(self.matrixList)
    self.matrixList.itemheight=math.floor(h*2.2)
    self.matrixList.emberEmptyLines=Text.wrap(text('noWorkers'),listBounds.width-p*2,UIFont.Small)
    self:addChild(self.matrixList)

    -- Override matrixList onMouseDown to support direct cell clicking
    local origMouseDown=self.matrixList.onMouseDown
    self.matrixList.onMouseDown=function(list,x,y)
        local rowIdx=list:rowAt(x,y)
        if rowIdx>0 and rowIdx<=#list.items then
            local entry=list.items[rowIdx]
            local worker=entry and entry.item and entry.item.value
            if worker then
                local w=list.width
                local nameW=w*0.40
                local colW=w*0.30
                if x>nameW and x<=nameW+colW then
                    self:cycleWorkerPriority(worker,'crafting')
                    return true
                elseif x>nameW+colW then
                    self:cycleWorkerPriority(worker,'hauling')
                    return true
                end
            end
        end
        if origMouseDown then return origMouseDown(list,x,y) end
        return true
    end

    self.bottomNoticeBounds=regions[3]
end

function EmberRoutesPersonnelPage:cycleWorkerPriority(worker,category)
    local cur=worker.priorities and worker.priorities[category] or 3
    local nextVal=(cur+1)%5
    Public.setPriority(self.actor,self.entry.id,worker.id,category,nextVal)
    self:refresh()
end

function EmberRoutesPersonnelPage:batchCycle(category)
    local workers=self.store.value.workers or {}
    if #workers==0 then return end
    local first=workers[1]
    local cur=first.priorities and first.priorities[category] or 3
    local nextVal=(cur+1)%5
    for _,w in ipairs(workers) do
        Public.setPriority(self.actor,self.entry.id,w.id,category,nextVal)
    end
    self.store:setState({notice=text('batchNotice',text(category))})
    self:refresh()
end

function EmberRoutesPersonnelPage:activate()
    self.active=true
    self:refresh()
end

function EmberRoutesPersonnelPage:deactivate()
    self.active=false
    Tooltip.clear(self.craftingHeaderBtn)
    Tooltip.clear(self.haulingHeaderBtn)
end

function EmberRoutesPersonnelPage:dispose()
    self.disposed=true
    self:deactivate()
end

function EmberRoutesPersonnelPage:refresh()
    if not self.active or self.disposed then return end
    local status=Crafting.status(self.actor,self.entry.id)
    local rawWorkers=status.workers or {}
    local enriched={}
    for _,w in ipairs(rawWorkers) do
        local p=Public.priorities(w.id)
        enriched[#enriched+1]={
            id=w.id,
            name=w.name,
            busy=w.busy or false,
            order=w.order,
            priorities=p
        }
    end
    local selected=self.store.value.selected
    if selected then
        local found=false
        for _,w in ipairs(enriched) do
            if w.id==selected.id then selected=w found=true break end
        end
        if not found then selected=enriched[1] or nil end
    else
        selected=enriched[1] or nil
    end
    self.store:setState({workers=enriched,selected=selected,revision=self.store.value.revision+1})
    self:project(self.store.value)
end

function EmberRoutesPersonnelPage:project(value)
    if not self.active or self.disposed then return end
    local rows=value.workers or {}
    local signature=function(w)
        local p=w.priorities or {}
        return w.id..'|'..w.name..'|'..(w.busy and '1' or '0')..'|'..(p.crafting or 0)..'|'..(p.hauling or 0)
    end
    Cached.reconcile(self.matrixList,rows,signature,function(w) return w.id end,true)
end

function EmberRoutesPersonnelPage:prerender()
    ISPanel.prerender(self)
    local h,p=self.fontHeight,self.pad

    -- Top Info
    Theme.text(self,text('title'),self.topInfoBounds.x,self.topInfoBounds.y,Theme.gold)
    Theme.text(self,text('priorityHint'),self.topInfoBounds.x,self.topInfoBounds.y+h,Theme.muted)

    -- Column 1 header (Worker Name)
    Theme.text(self,text('worker'),self.colHeaders[1].x+p/2,self.colHeaders[1].y+(self.colHeaders[1].height-h)/2,Theme.accent)

    -- Right Details Card
    local r=self.detailsBounds
    Theme.rect(self,r.x,r.y,r.width,r.height,Theme.panel)
    Theme.rect(self,r.x,r.y,r.width,r.height,Theme.border,true)

    local cardY=r.y+p
    Theme.text(self,text('workerDetails'),r.x+p,cardY,Theme.gold)
    cardY=cardY+h+p/2
    Theme.rect(self,r.x+p,cardY,r.width-p*2,1,Theme.border)
    cardY=cardY+p/2

    local sel=self.store.value.selected
    if sel then
        Theme.text(self,sel.name,r.x+p,cardY,Theme.textColor)
        cardY=cardY+h+p/4
        Theme.text(self,'ID: '..string.sub(sel.id,1,12)..'...',r.x+p,cardY,Theme.muted)
        cardY=cardY+h+p/2

        local statusStr=sel.busy and text('statusBusy') or text('statusIdle')
        local statusCol=sel.busy and {r=1.0,g=0.75,b=0.25,a=1.0} or {r=0.35,g=0.88,b=0.60,a=1.0}
        Theme.text(self,statusStr,r.x+p,cardY,statusCol)
        cardY=cardY+h+p/4

        Theme.text(self,text('healthNormal'),r.x+p,cardY,Theme.muted)
        cardY=cardY+h+p/2

        local jobStr=sel.order and sel.order.jobId and text('activeJob',sel.order.jobId) or text('activeJob',text('none'))
        for _,line in ipairs(Text.wrap(jobStr,r.width-p*2,UIFont.Small)) do
            Theme.text(self,line,r.x+p,cardY,Theme.textColor)
            cardY=cardY+h
        end
    else
        Theme.text(self,text('noWorkers'),r.x+p,cardY,Theme.muted)
    end

    -- Bottom notice
    local notice=self.store.value.notice or ''
    if notice~='' then
        Theme.text(self,notice,self.bottomNoticeBounds.x,self.bottomNoticeBounds.y,Theme.accent)
    end
end

function EmberRoutesPersonnelPage:focusContent()
    if self.actor:getJoypadBind()~=-1 then setJoypadFocus(self.actor:getIndex(),self.matrixList) end
end

return EmberRoutesPersonnelPage
