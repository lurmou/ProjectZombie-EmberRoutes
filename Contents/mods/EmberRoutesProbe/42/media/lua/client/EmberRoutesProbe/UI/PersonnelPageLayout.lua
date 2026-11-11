-- PersonnelPageLayout.lua - EmberRoutes UI
-- Page construction and layout: createChildren (filters, buttons, matrix
-- list with priority-cell rendering and mouse handling, declarative spec),
-- layout-alias sync, priority-header layout and resize. Attached to
-- EmberRoutesPersonnelPage by PersonnelPage.lua (mixin pattern: this module
-- receives the class table, so there is no circular require back to the
-- page module). Moved verbatim from PersonnelPage.lua; behaviour unchanged.

require 'ISUI/ISPanel'
require 'ISUI/ISButton'
local C = require 'EmberRoutesProbe/UI/PersonnelPageConstants'
local Cached = require 'EmberRoutesProbe/UI/CachedList'
local Theme = require 'EmberRoutesProbe/UI/Theme'
local Tooltip = require 'EmberRoutesProbe/UI/TooltipManager'
local Text = require 'EmberRoutesProbe/UI/Text'
local Public = require 'EmberRoutesProbe/Work/PublicWork'
local LayoutHost = require 'EmberRoutesProbe/UI/LayoutHost'
local UI = require 'EmberRoutesProbe/UI/UI'
local FilterChips = require 'EmberRoutesProbe/UI/FilterChips'

local function attach(Page)
function Page:createChildren()
    ISPanel.createChildren(self)
    local h,p=self.fontHeight,self.pad

    self.pageHost=LayoutHost:new(0,0,self.width,self.height,{direction='column'})
    self.pageHost:initialise()
    self:addChild(self.pageHost)

    self.workFilters=FilterChips:new(0,0,0,h+p,function(key)
        self.workFilter=key self.store:setState({revision=self.store.value.revision+1})
    end)
    local options={}
    for _,key in ipairs({'all','working','idle','blocked'}) do options[#options+1]={id=key,label=getText('IGUI_EmberRoutesProbe_Distributed_'..key)} end
    self.workFilters:setOptions(options,self.workFilter)

    self.refreshButton=ISButton:new(0,0,0,h+p,getText('IGUI_EmberRoutesProbe_Monitor_refresh'),self,function()
        self:refresh()
    end)
    self.refreshButton:initialise()
    Theme.button(self.refreshButton)
    self.refreshButton.onclick=function()
        local sel=self.store.value.selected
        if sel then require('EmberRoutesProbe/Settlement/PersonnelService').invalidate(sel.id) end
        self:refresh()
    end

    self.dossierButton=ISButton:new(0,0,0,h+p,C.text('viewDossier'),self,function() self:toggleDossierDrawer() end)
    self.dossierButton:initialise()
    Theme.button(self.dossierButton)

    self.info=require('EmberRoutesProbe/UI/InfoList').new(self,self.infoBounds)

    self.workCommands={}
    for _,key in ipairs({'stop','resume','return','stopBody'}) do
        local button=ISButton:new(0,0,0,0,getText('IGUI_EmberRoutesProbe_Distributed_'..key),self,function()
            if not self.active or not self.activationScope or not self.activationScope:isCurrent() then return end
            local result=require('EmberRoutesProbe/Work/WorkCommandAdapter').command(self.actor,self.entry.id,self.currentWork and self.currentWork.row,key)
            self.store:setState({notice=require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)})
            self:refresh()
        end)
        button:initialise()
        Theme.button(button)
        button:setVisible(false)
        self.workCommands[key]=button
    end

    self.workCategories=Public.categories()
    self.matrixNameRatio=#self.workCategories>4 and .22 or .4
    self.priorityHeaders={}
    local colTracks={{grow=self.matrixNameRatio*100}}
    for _ in ipairs(self.workCategories) do colTracks[#colTracks+1]={grow=(1-self.matrixNameRatio)*100/#self.workCategories} end
    self.colTracks=colTracks

    for i,category in ipairs(self.workCategories) do
        local key=category
        local button=ISButton:new(0,0,0,0,C.pubText(key),self,function() self:batchCycle(key) end)
        button:initialise()
        Theme.button(button)
        local fullTitle=C.pubText(key)
        button.title=''
        button.tooltip=fullTitle..'\n'..C.text('priorityHint')
        local originalRender=button.render
        button.render=function(btn)
            if originalRender then originalRender(btn) end
            local lines=btn.lines or {}
            local widths=btn.widths or {}
            for line,label in ipairs(lines) do
                local tw=widths[line] or 0
                Theme.text(btn,label,(btn.width-tw)/2,(btn.height-#lines*h)/2+(line-1)*h,Theme.textColor)
            end
        end
        Tooltip.register(button,{method='prerender',owner=self})
        self:addChild(button)
        self.priorityHeaders[#self.priorityHeaders+1]=button
    end

    local listStyle={
        emptyColor=Theme.muted,
        prepare=function(list,value)
            local cells={}
            for _,key in ipairs(self.workCategories) do
                local n=value.priorities and value.priorities[key] or 3
                local label=n==0 and '-' or tostring(n)
                cells[#cells+1]={value=n,label=label,width=getTextManager():MeasureStringX(UIFont.Small,label)}
            end
            local nameColW=(self.colHeaders and self.colHeaders[1]) and self.colHeaders[1].width or 100
            return {
                height=math.floor(h*2.2),
                work=Text.wrapLimited(value.workLine or '',list.width-p*2,UIFont.Small,1)[1] or '',
                name=Text.wrapLimited(value.name,nameColW-p*2,UIFont.Small,1)[1] or '',
                cells=cells
            }
        end,
        draw=function(list,y,entry)
            local item=entry.item.value local rowH=entry.height
            if y+list:getYScroll()+rowH<0 or y+list:getYScroll()>=list.height then return y+rowH end
            if list.selected==entry.index then
                Theme.rect(list,0,y,list.width,rowH,Theme.selected)
                Theme.rect(list,0,y,list.width,rowH,Theme.selectedBorder or Theme.border,true)
            elseif list.mouseoverselected==entry.index then Theme.rect(list,0,y,list.width,rowH,Theme.hover) end
            local dot=item.busy and Theme.gold or Theme.accent
            Theme.rect(list,p/2,y+rowH/2-3,6,6,dot)
            Theme.text(list,entry.item.visual.name,p+8,y,Theme.textColor)
            Theme.text(list,entry.item.visual.work,p/2,y+rowH-h,Theme.muted)
            local mx=list:getMouseX()
            for i,cell in ipairs(entry.item.visual.cells) do
                local r=self.colHeaders and self.colHeaders[i+1]
                if r then
                    local x=r.x-self.headerBounds.x+p/4 local w=r.width-p/2
                    local style=C.PRIORITY_COLORS[cell.value] or C.PRIORITY_COLORS[3]
                    local hovered=list.mouseoverselected==entry.index and mx>=x and mx<=x+w
                    Theme.rect(list,x,y,w,rowH-h,style.bg) Theme.rect(list,x,y,w,rowH-h,hovered and Theme.accent or style.border,true)
                    Theme.text(list,cell.label,x+(w-cell.width)/2,y+(rowH-h*2)/2,style.text)
                end
            end
            return y+rowH
        end
    }

    self.matrixList=Cached.create(self,self.matrixListBounds,function(_,row)
        self.store:setState({selected=row})
    end,listStyle)
    Theme.list(self.matrixList)
    self.matrixList.itemheight=math.floor(h*2.2)
    self.matrixList.emberEmptyState={
        icon='person',
        iconSize=36,
        title=C.text('noWorkers'),
        hint=C.text('emptyFilterHint'),
        action=C.text('resetFilters'),
        onAction=function()
            self.workFilter='all'
            self.workFilters:setSelected('all')
            self.store:setState({revision=self.store.value.revision+1})
            self:refresh()
        end
    }
    self:addChild(self.matrixList)

    local function categoryAt(list,x)
        if not self.colHeaders or not self.headerBounds then return end
        for i,key in ipairs(self.workCategories) do
            local r=self.colHeaders[i+1]
            if r then
                local left=r.x-self.headerBounds.x+p/4
                if x>=left and x<=left+r.width-p/2 then return key end
            end
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
            list.tooltip=C.text('cellTooltip',w.name or '',C.pubText(key),C.pubText('priority_'..val))
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

    local spec=UI.Column({padding=p,gap=p/2,align="stretch"},{
        UI.Item(
            UI.Row({gap=p,align="stretch"},{
                UI.Item(self.workFilters,{grow=1,bind=self.topInfoBounds}),
                UI.Item(self.refreshButton,{basis=h*6})
            }),
            {grow=0,basis=h+p}
        ),
        UI.Item(
            UI.Row({gap=p,align="stretch"},{
                UI.Item(
                    UI.Column({gap=p/4,align="stretch"},{
                        UI.Item(self.headerBounds,{
                            key="matrixHeader",
                            basis=h*2+p/2,
                            bind=self.headerBounds,
                            margin={right=16}
                        }),
                        UI.Item(self.matrixListBounds,{
                            key="matrixList",
                            grow=1,
                            bind=self.matrixListBounds
                        })
                    }),
                    {key="matrixPane",grow=74,bind=self.matrixBounds}
                ),
                UI.Item(
                    UI.Column({gap=p/2,align="stretch"},{
                        UI.Item(self.dossierButton,{basis=h+p}),
                        UI.Item(self.infoBounds,{key="info",grow=1,bind=self.infoBounds}),
                        UI.Grid({columns=2,gap=p/2,height=(h+p)*2+p/2,grow=0,when=function() return self:hasWorkCommands() end},
                            self.workCommands.stop,
                            self.workCommands.resume,
                            self.workCommands['return'],
                            self.workCommands.stopBody
                        )
                    }),
                    {key="detailsPane",grow=26,bind=self.detailsBounds}
                )
            }),
            {grow=1}
        ),
        UI.Item(self.bottomNoticeBounds,{
            key="bottomNotice",
            basis=h,
            bind=self.bottomNoticeBounds
        })
    })

    local handles,err=self.pageHost:build(spec)
    assert(handles,err)
    self.layoutHandles=handles
end

function Page:syncLayoutAliases()
    local p=self.pad
    if self.matrixList and self.matrixListBounds then
        self.matrixList:setX(self.matrixListBounds.x)
        self.matrixList:setY(self.matrixListBounds.y)
        self.matrixList:setWidth(self.matrixListBounds.width)
        self.matrixList:setHeight(self.matrixListBounds.height)
        if self.matrixList.vscroll then
            self.matrixList.vscroll:setX(self.matrixListBounds.width-16)
            self.matrixList.vscroll:setHeight(self.matrixListBounds.height)
        end
        self.matrixList.emberEmptyState={
        icon='person',
        iconSize=36,
        title=C.text('noWorkers'),
        hint=C.text('emptyFilterHint'),
        action=C.text('resetFilters'),
        onAction=function()
            self.workFilter='all'
            self.workFilters:setSelected('all')
            self.store:setState({revision=self.store.value.revision+1})
            self:refresh()
        end
    }
    end
    if self.info and self.info.list and self.infoBounds then
        self.info.list:setX(self.infoBounds.x)
        self.info.list:setY(self.infoBounds.y)
        self.info.list:setWidth(self.infoBounds.width)
        self.info.list:setHeight(self.infoBounds.height)
        if self.info.list.vscroll then
            self.info.list.vscroll:setX(self.infoBounds.width-16)
            self.info.list.vscroll:setHeight(self.infoBounds.height)
        end
    end
    self:syncHeaderLayout()
    self:syncCommandVisibility()
end

function Page:syncHeaderLayout()
    if not self.headerBounds or not self.colTracks or self.headerBounds.width<=0 then return end
    local h,p=self.fontHeight,self.pad
    self.colHeaders=assert(Layout.axis(self.headerBounds,self.colTracks,{gap=p/3}))
    for i,category in ipairs(self.workCategories) do
        local button=self.priorityHeaders and self.priorityHeaders[i]
        local bounds=self.colHeaders and self.colHeaders[i+1]
        if button and bounds then
            button:setX(bounds.x)
            button:setY(bounds.y)
            button:setWidth(bounds.width)
            button:setHeight(bounds.height)
            local fullTitle=C.pubText(category)
            local lines=Text.wrapLimited(fullTitle,math.max(1,bounds.width-p/2),UIFont.Small,2)
            button.lines=lines
            local widths={}
            for lineIdx,label in ipairs(lines) do
                widths[lineIdx]=getTextManager():MeasureStringX(UIFont.Small,label)
            end
            button.widths=widths
        end
    end
end

function Page:onResize()
    if ISPanel.onResize then ISPanel.onResize(self) end
    if self.pageHost then
        self.pageHost:setWidth(self.width)
        self.pageHost:setHeight(self.height)
        if self.pageHost:isActivationValid() then
            self.pageHost:resolveLayout()
            self:syncLayoutAliases()
        end
    end
end

end

return attach
