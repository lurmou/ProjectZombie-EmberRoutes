require "ISUI/ISPanel"
require "ISUI/ISButton"
local Dropdown=require "EmberRoutesProbe/UI/Dropdown"
local SearchInput=require "EmberRoutesProbe/UI/SearchInput"
local Service=require "EmberRoutesProbe/Crafting/CraftingService"
local Layout=require "EmberRoutesProbe/UI/Layout"
local State=require "EmberRoutesProbe/UI/State"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Text=require "EmberRoutesProbe/UI/Text"
local Tooltip=require "EmberRoutesProbe/UI/TooltipManager"
local Lifecycle=require "EmberRoutesProbe/UI/PageLifecycle"
local Grid=require "EmberRoutesProbe/UI/RecipeGrid"
local Draft=require "EmberRoutesProbe/UI/CraftingDraft"
local Words=require "EmberRoutesProbe/Crafting/CraftingText"
local text=Words.get
---@class EmberRoutesCraftingBrowser:ISPanel
---@field owner EmberRoutesSettlementDashboard
---@field shell table
---@field actor IsoPlayer
---@field entry table
---@field fontHeight number
---@field pad number
---@field store table
---@field grid any
---@field draft table
---@field search ISTextEntryBox
---@field category EmberRoutesDropdown
---@field unsupported ISButton
---@field previous ISButton
---@field next ISButton
---@field refreshButton ISButton
---@field paging table
---@field columns table
---@field recipe table?
---@field active boolean?
---@field syncing boolean?
---@field cancelCatalog function?
---@field cancelPreview function?
---@field previewKey string?
---@field statusLines table
---@field disposed boolean?
---@field focusedList any
---@field catalogGeneration number?
---@field previewGeneration number?
---@field defaultSurface string?
---@field activation table?
EmberRoutesCraftingBrowser=ISPanel:derive("EmberRoutesCraftingBrowser")
---@param shell EmberRoutesCraftingPage
---@param bounds {x:number,y:number,width:number,height:number}
---@return EmberRoutesCraftingBrowser
function EmberRoutesCraftingBrowser:new(shell,bounds)
    ---@type EmberRoutesCraftingBrowser
    local o=ISPanel.new(self,bounds.x,bounds.y,bounds.width,bounds.height)
    o.shell=shell o.owner=shell.owner o.actor=shell.actor o.entry=shell.entry o.fontHeight=shell.fontHeight o.pad=shell.pad
    o.background=false
    o.store=State.new({snapshot={workers={},surfaces={}},catalog={rows={},categories={},page=1,pages=1,loading=true},
        search="",category=false,unsupported=false,page=1,recipeId=false,surface=false,quantity=1,
        preview={state="CHECKING",conditions={},counts={}},notice=""})
    return o
end
function EmberRoutesCraftingBrowser:initialise() ISPanel.initialise(self) end
function EmberRoutesCraftingBrowser:createChildren()
    ISPanel.createChildren(self) local h,p=self.fontHeight,self.pad
    self.columns=assert(Layout.axis({x=0,y=0,width=self.width,height=self.height},{{grow=4},{grow=5}},{padding=p,gap=p}))
    local left=self.columns[1]
    local regions=assert(Layout.axis(left,{{basis=h+p},{basis=h+p},{grow=1},{basis=h+p},{basis=h}},{direction="column",gap=p/2}))
    self.search=SearchInput:new(regions[1].x,regions[1].y,regions[1].width,regions[1].height,text("searchRecipes"),self,function()
        self:change({search=string.sub(self.search:getText(),1,160),page=1})
    end)
    self:addChild(self.search)
    local controls=assert(Layout.axis(regions[2],{{grow=2},{grow=1}},{gap=p/2}))
    local r=controls[1]
    self.category=Dropdown:new(r.x,r.y,r.width,r.height,self,function(target,selectedCat)
        if not target.syncing then target:change({category=selectedCat or false,page=1}) end
    end)
    self.category:initialise() self.category:setOptions({{id=false,label=text("allCategories")}},false) self:addChild(self.category)
    r=controls[2]
    self.unsupported=ISButton:new(r.x,r.y,r.width,r.height,text("supportedOnly"),self,function() self:change({unsupported=not self.store.value.unsupported,page=1}) end)
    self.unsupported:initialise() Theme.button(self.unsupported) self:addChild(self.unsupported)
    self.grid=Grid.new(self,regions[3],function(row) self:change({recipeId=row.id}) end)
    local maxRefresh=math.floor(regions[4].width*0.35)
    local refreshWidth=math.min(maxRefresh,getTextManager():MeasureStringX(UIFont.Small,text("button_refresh"))+p*2)
    local pages=assert(Layout.axis(regions[4],{{grow=1},{grow=2},{basis=refreshWidth},{grow=1}},{gap=p/2})) self.paging=pages[2]
    local function button(bounds,title,delta)
        local b=ISButton:new(bounds.x,bounds.y,bounds.width,bounds.height,title,self,function() self:turn(delta) end)
        b:initialise() Theme.button(b) self:addChild(b) return b
    end
    self.previous=button(pages[1],"<",-1) self.next=button(pages[4],">",1)
    local r=pages[3]
    self.refreshButton=ISButton:new(r.x,r.y,r.width,r.height,text("button_refresh"),self,function()
        self.previewKey=nil self:change({notice=Words.reason("REFRESHED")}) self:repaint()
    end)
    self.refreshButton:initialise() Theme.button(self.refreshButton) self:addChild(self.refreshButton)
    self.statusLines={bounds=regions[5],lines={}}
    self.draft=Draft.new(self,self.columns[2])
end

function EmberRoutesCraftingBrowser:onResize()
    if ISPanel.onResize then ISPanel.onResize(self) end
    local h, p = self.fontHeight, self.pad
    self.columns = Layout.axis({x = 0, y = 0, width = self.width, height = self.height}, {{grow = 4}, {grow = 5}}, {padding = p, gap = p})
    if not self.columns then return end
    local left = self.columns[1]
    local regions = Layout.axis(left, {{basis = h + p}, {basis = h + p}, {grow = 1}, {basis = h + p}, {basis = h}}, {direction = "column", gap = p / 2})
    if not regions then return end

    if self.search then
        self.search:setX(regions[1].x)
        self.search:setY(regions[1].y)
        self.search:setWidth(regions[1].width)
        self.search:setHeight(regions[1].height)
    end

    local controls = Layout.axis(regions[2], {{grow = 2}, {grow = 1}}, {gap = p / 2})
    if controls then
        if self.category then
            self.category:setX(controls[1].x)
            self.category:setY(controls[1].y)
            self.category:setWidth(controls[1].width)
            self.category:setHeight(controls[1].height)
        end
        if self.unsupported then
            self.unsupported:setX(controls[2].x)
            self.unsupported:setY(controls[2].y)
            self.unsupported:setWidth(controls[2].width)
            self.unsupported:setHeight(controls[2].height)
        end
    end

    if self.grid then
        self.grid:setX(regions[3].x)
        self.grid:setY(regions[3].y)
        self.grid:setWidth(regions[3].width)
        self.grid:setHeight(regions[3].height)
        if self.grid.onResize then self.grid:onResize() end
    end

    local maxRefresh = math.floor(regions[4].width * 0.35)
    local refreshWidth = math.min(maxRefresh, (getTextManager() and getTextManager():MeasureStringX(UIFont.Small, text("button_refresh")) or 60) + p * 2)
    local pages = Layout.axis(regions[4], {{grow = 1}, {grow = 2}, {basis = refreshWidth}, {grow = 1}}, {gap = p / 2})
    if pages then
        self.paging = pages[2]
        if self.previous then
            self.previous:setX(pages[1].x)
            self.previous:setY(pages[1].y)
            self.previous:setWidth(pages[1].width)
            self.previous:setHeight(pages[1].height)
        end
        if self.next then
            self.next:setX(pages[4].x)
            self.next:setY(pages[4].y)
            self.next:setWidth(pages[4].width)
            self.next:setHeight(pages[4].height)
        end
        if self.refreshButton then
            self.refreshButton:setX(pages[3].x)
            self.refreshButton:setY(pages[3].y)
            self.refreshButton:setWidth(pages[3].width)
            self.refreshButton:setHeight(pages[3].height)
        end
    end

    if self.statusLines then
        self.statusLines.bounds = regions[5]
    end

    if self.draft then
        if self.draft.setBounds then
            self.draft:setBounds(self.columns[2])
        elseif self.draft.onResize then
            self.draft:onResize(self.columns[2])
        end
    end
end
function EmberRoutesCraftingBrowser:applyArgs(args)
    self.filterProduct=args.filterProduct
    self.recipe=nil self.previewKey=nil
    self.store:setState({recipeId=false,page=1,search='',preview={state='CHECKING',conditions={},counts={}}})
    if self.active then self:watchCatalog() end
end
function EmberRoutesCraftingBrowser:change(patch) self.store:setState(patch) end
function EmberRoutesCraftingBrowser:repaint() self:project(self.store.value,{preview=true}) end
function EmberRoutesCraftingBrowser:watchCatalog()
    if self.cancelCatalog then self.cancelCatalog() end
    self.catalogGeneration=(self.catalogGeneration or 0)+1
    local generation=self.catalogGeneration local token=self.activation local v=self.store.value
    self.cancelCatalog=Service.watchCatalog(self.actor,self.entry.id,
        {search=v.search,category=v.category or nil,unsupported=v.unsupported,page=v.page,size=self.grid.capacity,productType=self.filterProduct},function(catalog)
            if not self.active or self.activation~=token or self.catalogGeneration~=generation then return end
            if catalog.reason=="WORLD_RESET" then self.owner:close() return end
            self.store:setState({catalog=catalog})
        end)
end
function EmberRoutesCraftingBrowser:activate()
    local mounted=Lifecycle.mount(self,function(callback) return Service.watch(self.actor,self.entry.id,callback) end,
        function(snapshot)
            if snapshot.reason=="WORLD_RESET" then self.owner:close() return end
            self.store:setState({snapshot=snapshot})
        end)
    if mounted and self.active then
        self.store:setState({snapshot=Service.status(self.actor,self.entry.id)}) self:watchCatalog() self:repaint()
    end
end
function EmberRoutesCraftingBrowser:deactivate()
    Lifecycle.unmount(self)
    if self.cancelCatalog then self.cancelCatalog() self.cancelCatalog=nil end
    if self.cancelPreview then self.cancelPreview() self.cancelPreview=nil end
    self.previewKey=nil self.search:unfocus() self.category:hidePopup() self.draft:hide()
    for _,control in ipairs({self.search,self.category,self.unsupported,self.previous,self.next,self.refreshButton}) do Tooltip.clear(control) end
end
function EmberRoutesCraftingBrowser:dispose() self.disposed=true self:deactivate() end
function EmberRoutesCraftingBrowser:close() self.owner:close() end
function EmberRoutesCraftingBrowser:focusContent()
    self.focusedList=self.grid
    if self.actor:getJoypadBind()~=-1 then setJoypadFocus(self.actor:getIndex(),self.grid) end
end
function EmberRoutesCraftingBrowser:focusList(list) self.focusedList=list end
function EmberRoutesCraftingBrowser:isListFocused(list)
    return self.active and self.focusedList==list and not self.search:isFocused() and not self.draft.quantity:isFocused()
end
function EmberRoutesCraftingBrowser:onListActivate(list)
    if list==self.draft.list then
        local entry=list.items[list.selected] if entry then self.draft:activate(entry.item.value) end
    end
end
function EmberRoutesCraftingBrowser:onListKey(key,list)
    if key==Keyboard.KEY_RETURN then self:onListActivate(list)
    elseif key==Keyboard.KEY_TAB then self:focusContent() end
end
function EmberRoutesCraftingBrowser:focusDraft()
    if self.actor:getJoypadBind()~=-1 then setJoypadFocus(self.actor:getIndex(),self.draft.quantity) end
end
function EmberRoutesCraftingBrowser:turn(delta)
    self:change({page=math.max(1,math.min(self.store.value.catalog.pages,self.store.value.page+delta))})
end
function EmberRoutesCraftingBrowser:project(value,changes)
    if not self.active then return end
    if changes.notice then self.statusLines.lines=Text.wrapLimited(value.notice,self.statusLines.bounds.width,UIFont.Small,1) end
    if changes.search or changes.category or changes.unsupported or changes.page then self:watchCatalog() end
    if changes.catalog then
        local catalog=value.catalog
        self.pagingText=catalog.page.." / "..catalog.pages.."  ("..(catalog.total or 0)..")"
        self.pagingWidth=getTextManager():MeasureStringX(UIFont.Small,self.pagingText)
        self.grid:setRows(catalog.rows,value.recipeId)
        self.grid.empty=self.filterProduct and not catalog.loading and catalog.total==0 and getText("IGUI_EmberRoutesProbe_Distributed_noRecipe") or text(catalog.loading and "catalogLoading" or "catalogEmpty")
        local catOptions={{id=false,label=text("allCategories")}}
        for _,category in ipairs(catalog.categories) do
            table.insert(catOptions,{id=category,label=getTextOrNull("IGUI_CraftCategory_"..category) or category})
        end
        self.syncing=true
        self.category:setOptions(catOptions,value.category or false)
        self.syncing=false
        self.syncing=false
        Theme.enable(self.previous,catalog.page>1) Theme.enable(self.next,catalog.page<catalog.pages)
        self.unsupported:setTitle(text(value.unsupported and "includingUnsupported" or "supportedOnly"))
        self.statusLines.lines=Text.wrapLimited(value.notice~="" and value.notice or (catalog.loading and text("catalogLoading") or ""),self.statusLines.bounds.width,UIFont.Small,1)
        if not self.filterProduct and not value.recipeId and catalog.rows[1] then self:change({recipeId=catalog.rows[1].id}) return end
        if not (changes.recipeId or changes.snapshot or changes.quantity or changes.surface or changes.preview) then return end
    end
    if changes.recipeId then
        self.recipe=value.recipeId and Service.describe(value.recipeId) or nil self.draft.expanded={}
        self.grid:setRows(value.catalog.rows,value.recipeId)
    end
    if changes.snapshot then
        if value.snapshot.surfaceId and value.snapshot.surfaceId~=self.defaultSurface then
            self.defaultSurface=value.snapshot.surfaceId
        end
    end
    local key=tostring(value.recipeId)..":"..tostring(value.quantity)..":"..tostring(self.recipe and self.recipe.surface and value.surface or false)
    if self.previewKey~=key and value.recipeId then
        self.previewKey=key
        self.previewGeneration=(self.previewGeneration or 0)+1 local generation=self.previewGeneration
        if self.cancelPreview then self.cancelPreview() end
        local token=self.activation
        self:change({preview={state="CHECKING",conditions={},counts={}}})
        self.cancelPreview=Service.preview(self.actor,self.entry.id,nil,value.recipeId,value.quantity,value.surface or nil,function(result)
            if self.active and self.activation==token and self.previewKey==key and self.previewGeneration==generation then self:change({preview=result}) end
        end)
        return
    end
    self.draft:set(self.recipe,value.preview,value.snapshot,value)
end
function EmberRoutesCraftingBrowser:command(command,recipeId,surfaceId)
    local v=self.store.value
    local Words=require "EmberRoutesProbe/UI/OrderMonitorCards"
    local result=Service.command(self.actor,self.entry.id,v.npcId,command,surfaceId or v.surface,recipeId or v.recipeId,v.quantity)
    self:change({notice=Words.reason(result),snapshot=Service.status(self.actor,self.entry.id)})
    if command=="run" and result=="STARTED" then
        if self.shell and self.shell.returnContext then self.shell:returnWarehouse() elseif self.shell and self.shell.selectView then self.shell:selectView("orders") end
    end
end
function EmberRoutesCraftingBrowser:warehouse(fullType)
    self.owner:selectTab("warehouse")
    local page=self.owner.pages.warehouse
    if page and page.search then page.search:setText(fullType) end -- Query also matches fullType.
end
function EmberRoutesCraftingBrowser:prerender()
    ISPanel.prerender(self) if not self.active then return end
    self.draft:draw()
    local r=self.paging local c=self.store.value.catalog
    local pagingText=self.pagingText or ''
    local tw=self.pagingWidth or 0
    local tx=r.x+math.max(0,math.floor((r.width-tw)/2))
    local ty=r.y+math.floor((r.height-self.fontHeight)/2)
    Theme.text(self,pagingText,tx,ty,Theme.muted)
    local status=self.statusLines for i,line in ipairs(status.lines) do Theme.text(self,line,status.bounds.x,status.bounds.y+(i-1)*self.fontHeight,Theme.muted) end
end
return EmberRoutesCraftingBrowser
