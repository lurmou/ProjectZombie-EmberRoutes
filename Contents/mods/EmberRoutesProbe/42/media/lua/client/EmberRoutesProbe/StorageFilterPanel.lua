local Tooltip=require "EmberRoutesProbe/UI/TooltipAnchor"
local Gate=require "EmberRoutesProbe/RuntimeGate"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Filter=require "EmberRoutesProbe/StorageFilter"
local Editor=require "EmberRoutesProbe/FilterEditor"
local Log=require "EmberRoutesProbe/Log"
local Flow=require "EmberRoutesProbe/UI/Text"
local Layout=require "EmberRoutesProbe/UI/Layout"
local State=require "EmberRoutesProbe/UI/State"
local Rows=require "EmberRoutesProbe/UI/FilterList"
local Configuration=require "EmberRoutesProbe/ContainerConfiguration"
local ConfigControls=require "EmberRoutesProbe/UI/ContainerConfigControls"
local Theme=require "EmberRoutesProbe/UI/Theme"

---@class EmberRoutesFilterList: ISScrollingListBox
---@field owner EmberRoutesStorageFilterPanel
---@class EmberRoutesStorageFilterPanel: ISCollapsableWindow
---@field actor IsoPlayer
---@field object IsoObject
---@field fontHeight number
---@field pad number
---@field rowHeight number
---@field statusY number
---@field store EmberRoutesUIStore
---@field container ItemContainer
---@field unsubscribe function?
---@field model {draft:table,descriptions:table[],collapsed:table,status:string}
---@field hintLines string[]
---@field statusCaption string
---@field statusLines string[]
---@field tickTexture Texture?
---@field list EmberRoutesFilterList
---@field buttons ISButton[]
---@field registered boolean
---@field configControls EmberRoutesContainerConfigControls
EmberRoutesStorageFilterPanel=ISCollapsableWindow:derive("EmberRoutesStorageFilterPanel")
local opened=setmetatable({},{__mode="v"})
local nativeKeys={apply="UI_btn_apply",cancel="UI_btn_cancel"}
local function text(key) return getText(nativeKeys[key] or ("IGUI_EmberRoutesProbe_Filter_"..key)) end

---@param actor IsoPlayer
---@param object IsoObject
---@param container ItemContainer?
function EmberRoutesStorageFilterPanel:new(actor,object,container,initial)
    container=container or object:getContainer()
    local fontHeight=getTextManager():getFontHeight(UIFont.Small)
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    local width=math.min(sw*0.9,fontHeight*44)
    local height=math.min(sh*0.82,fontHeight*35)
    ---@type EmberRoutesStorageFilterPanel
    local o=ISCollapsableWindow.new(self,(sw-width)/2,(sh-height)/2,width,height)
    o.actor,o.object,o.fontHeight,o.pad=actor,object,fontHeight,math.ceil(fontHeight*0.6)
    o.container=container
    o.title=text("title").." - "..(getTextOrNull("IGUI_ContainerTitle_"..container:getType()) or container:getType())
    o.resizable=false
    o.backgroundColor,o.borderColor=Theme.window,Theme.border
    local descriptions,seen={},{}
    local items=container:getItems()
    for i=0,math.min(items:size(),2000)-1 do
        local item=items:get(i)
        local id=item:getFullType()
        if not seen[id] and #descriptions<128 then
            local descriptor=Filter.describe(item)
            descriptor.node=Filter.classify(descriptor,item)
            descriptions[#descriptions+1]=descriptor seen[id]=true
        end
    end
    table.sort(descriptions,function(a,b) return a.fullType<b.fullType end)
    o.model=Editor.new(Registry.filter(object,container),descriptions)
    -- Default collapse root groups that have children for clean UI
    o.model.collapsed={}
    for _,id in ipairs(Filter.order) do
        local node=Filter.nodes[id]
        if node and not node.parent and node.hasChildren then
            o.model.collapsed[id]=true
        end
    end
    if initial then
        local draft
        if type(initial)=="string" then draft=Configuration.preset(o.model.draft,initial)
        else draft=Configuration.replace(o.model.draft,initial) end
        if draft then o.model.draft=draft end
    end
    o.registered=Registry.metadata(object,container)~=nil
    o.store=State.new({model=o.model,status="",statusError=false,role=Registry.logistics({object=object,container=container})})
    o.statusCaption=""
    o.statusLines={}
    o.tickTexture=getTexture("media/ui/inventoryPanes/Tickbox_Tick.png")
    o.hintLines=Flow.wrapLimited(text("configHint"),width-o.pad*2,UIFont.Small,2)
    return o
end

function EmberRoutesStorageFilterPanel:initialise()
    ISCollapsableWindow.initialise(self)
end

function EmberRoutesStorageFilterPanel:createChildren()
    ISCollapsableWindow.createChildren(self)
    local p,h=self.pad,self.fontHeight
    self.rowHeight=h*2+p
    local top=self:titleBarHeight()+p+h*(#self.hintLines+1)
    local footer=h+p*2
    local regions=assert(Layout.axis({x=0,y=top,width=self.width,height=self.height-top-p},
        {{basis=h*3},{basis=h+p},{grow=1},{basis=h*3},{basis=footer}}, {direction="column",padding=p,gap=p/2}))
    self.configControls=ConfigControls.new(self,regions[2],regions[1])
    self.list=Rows.create(self,regions[3])
    self.list:setOnMouseDownFunction(self,EmberRoutesStorageFilterPanel.toggle)
    self.list:setOverrideAButtonFunction(self,EmberRoutesStorageFilterPanel.toggle)
    self:addChild(self.list)
    local buttons={ {"all",EmberRoutesStorageFilterPanel.all}, {"none",EmberRoutesStorageFilterPanel.none}, {"apply",EmberRoutesStorageFilterPanel.apply}, {"cancel",EmberRoutesStorageFilterPanel.close} }
    self.buttons={}
    local slots=assert(Layout.axis(regions[5],{{grow=1},{grow=1},{grow=1},{grow=1}},{gap=p}))
    for i,definition in ipairs(buttons) do
        local slot=slots[i]
        local button=ISButton:new(slot.x,slot.y,slot.width,slot.height,text(definition[1]),self,definition[2])
        button:initialise() Theme.button(button,definition[1]=="apply") self:addChild(button)
        self.buttons[i]=button
    end
    self.statusY=regions[4].y
    self.unsubscribe=self.store:subscribe(function(snapshot,changed)
        self.model=snapshot.model
        if changed.model then self:refreshRows() end
        self.configControls:refresh()
        local warning=self.configControls.warning
        local caption=snapshot.status=="" and warning or (snapshot.statusError and (snapshot.status.."\n"..warning) or (warning.."\n"..snapshot.status))
        self.statusLines=Flow.wrapLimited(caption,self.width-self.pad*2,UIFont.Small,3)
    end)
    self:refreshRows()
    self.configControls:refresh()
    self.statusLines=Flow.wrapLimited(self.configControls.warning,self.width-self.pad*2,UIFont.Small,3)

    -- Keyboard navigation: Space toggles allow/deny; Left/Right toggles collapse/expand
    self.list.onKeyPress=function(list,key)
        if key==Keyboard.KEY_UP then
            list.selected=math.max(1,list.selected-1) list:ensureVisible(list.selected)
        elseif key==Keyboard.KEY_DOWN then
            list.selected=math.min(#list.items,list.selected+1) list:ensureVisible(list.selected)
        elseif key==Keyboard.KEY_SPACE then
            local entry=list.items[list.selected]
            if entry then EmberRoutesStorageFilterPanel.toggle(self,entry.item) end
        elseif key==Keyboard.KEY_RIGHT then
            local entry=list.items[list.selected]
            if entry and entry.item and entry.item.hasChildren and entry.item.collapsed then
                self:toggleCollapse(entry.item)
            end
        elseif key==Keyboard.KEY_LEFT then
            local entry=list.items[list.selected]
            if entry and entry.item and entry.item.hasChildren and not entry.item.collapsed then
                self:toggleCollapse(entry.item)
            end
        elseif key==Keyboard.KEY_RETURN then self:apply()
        elseif key==Keyboard.KEY_ESCAPE then self:close() end
    end
    self.list.isKeyConsumed=function(_,key)
        return key==Keyboard.KEY_UP or key==Keyboard.KEY_DOWN or key==Keyboard.KEY_SPACE
            or key==Keyboard.KEY_RETURN or key==Keyboard.KEY_ESCAPE
            or key==Keyboard.KEY_LEFT or key==Keyboard.KEY_RIGHT
    end
    self.list.onJoypadDown=function(list,button,joypadData)
        if button==Joypad.AButton then local entry=list.items[list.selected] if entry then self:toggle(entry.item) end
        elseif button==Joypad.XButton then self:apply()
        elseif button==Joypad.BButton then self:close()
        else ISScrollingListBox.onJoypadDown(list,button,joypadData) end
    end
    self.list.onJoypadDirUp=function(list) list.selected=math.max(1,list.selected-1) list:ensureVisible(list.selected) end
    self.list.onJoypadDirDown=function(list) list.selected=math.min(#list.items,list.selected+1) list:ensureVisible(list.selected) end
    self.list.onJoypadDirRight=function(list)
        local entry=list.items[list.selected]
        if entry and entry.item and entry.item.hasChildren and entry.item.collapsed then
            self:toggleCollapse(entry.item)
        end
    end
    self.list.onJoypadDirLeft=function(list)
        local entry=list.items[list.selected]
        if entry and entry.item and entry.item.hasChildren and not entry.item.collapsed then
            self:toggleCollapse(entry.item)
        end
    end
end

function EmberRoutesStorageFilterPanel:refreshRows() Rows.refresh(self) end

function EmberRoutesStorageFilterPanel:edit(change)
    local model=Editor.new(self.model.draft,self.model.descriptions)
    model.collapsed=self.model.collapsed or {}
    change(model)
    self.store:setState({model=model,status="",statusError=false})
end

function EmberRoutesStorageFilterPanel:toggle(row)
    self:edit(function(model) Editor.toggle(model,row) end)
end

function EmberRoutesStorageFilterPanel:toggleCollapse(row)
    if not row or not row.hasChildren or not row.id then return end
    self:edit(function(model)
        Editor.toggleCollapse(model,row.id)
    end)
end

function EmberRoutesStorageFilterPanel:all() self:edit(function(model) Editor.all(model,true) end) end
function EmberRoutesStorageFilterPanel:none() self:edit(function(model) Editor.all(model,false) end) end

function EmberRoutesStorageFilterPanel:apply()
    local ok,result=pcall(Registry.configure,self.actor,self.object,self.model.draft,self.container,self.store.value.role)
    if not ok then Log.write("STORAGE_FILTER","APPLY_ERROR "..tostring(result)) result="ERROR" end
    local tag=Registry.metadata(self.object,self.container)
    local square=self.object and self.object.getSquare and self.object:getSquare()
    Log.write("STORAGE_FILTER","APPLY "..result
        .." id="..tostring(tag and tag.id or "unknown")
        .." role="..tostring(tag and tag.logisticsRole or self.store.value.role or "?")
        ..(square and " at="..square:getX()..","..square:getY()..","..square:getZ() or ""))
    if result=="FILTER_CONFIGURED" then self:close()
    else
        local key="IGUI_EmberRoutesProbe_WorkCode_"..result
        local message=getText(key)
        self.statusCaption=text("failed")..(message==key and result or message)
        self.store:setState({status=self.statusCaption,statusError=true})
    end
end

function EmberRoutesStorageFilterPanel:prerender()
    ISCollapsableWindow.prerender(self)
    local y=self:titleBarHeight()+self.pad
    for _,line in ipairs(self.hintLines) do
        self:drawText(line,self.pad,y,0.9,0.85,0.65,1,UIFont.Small) y=y+self.fontHeight
    end
    self.configControls:draw()
    local color=self.store.value.statusError and Theme.status.ERROR or Theme.muted
    for index,line in ipairs(self.statusLines) do
        self:drawText(line,self.pad,self.statusY+(index-1)*self.fontHeight,color.r,color.g,color.b,color.a,UIFont.Small)
    end
end

function EmberRoutesStorageFilterPanel:close()
    Tooltip.clear(self.list)
    if self.configControls then self.configControls:close() end
    if self.unsubscribe then self.unsubscribe() self.unsubscribe=nil end
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if self.actor and self.actor:getJoypadBind()~=-1 then
        ---@diagnostic disable-next-line: deprecated
        setJoypadFocus(self.actor:getPlayerNum(),nil)
    end
end

---@param container ItemContainer?
function EmberRoutesStorageFilterPanel.open(actor,object,container,initial)
    if not Gate.canExecute(actor) or not actor then return end
    if not object then return end
    container=container or object:getContainer()
    if Registry.containerIndex(object,container)==nil then return end
    local previous=opened[actor:getPlayerNum()]
    if previous then previous:close() end
    local panel=EmberRoutesStorageFilterPanel:new(actor,object,container,initial)
    panel:initialise()
    panel:addToUIManager()
    opened[actor:getPlayerNum()]=panel
    if actor:getJoypadBind()~=-1 then setJoypadFocus(actor:getPlayerNum(),panel.list) end
    return panel
end

return EmberRoutesStorageFilterPanel
