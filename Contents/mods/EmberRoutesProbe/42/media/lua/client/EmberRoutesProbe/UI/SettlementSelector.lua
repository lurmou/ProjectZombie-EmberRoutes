require "ISUI/ISCollapsableWindow"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"
local Geometry=require "EmberRoutesProbe/SettlementGeometry"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Text=require "EmberRoutesProbe/UI/Text"
local Layout=require "EmberRoutesProbe/UI/Layout"
local State=require "EmberRoutesProbe/UI/State"
local Log=require "EmberRoutesProbe/Log"
---@class EmberRoutesSettlementSelector:ISCollapsableWindow
---@field actor IsoPlayer
---@field entry EmberRoutesSettlement?
---@field saved function?
---@field fontHeight number
---@field pad number
---@field previewZ number
---@field cursorX number
---@field cursorY number
---@field anchor {x:number,y:number}?
---@field dragging boolean?
---@field area table|false|nil
---@field hintLines string[]
---@field statusLines string[]
---@field store EmberRoutesUIStore
---@field nameEntry ISTextEntryBox
---@field messageY number
---@field unsubscribe function?
EmberRoutesSettlementSelector=ISCollapsableWindow:derive("EmberRoutesSettlementSelector")
local active
-- Child selectors share the existing world-input owner instead of registering
-- competing outside-mouse handlers alongside the settlement editor.
function EmberRoutesSettlementSelector.claim(panel)
    if active and active~=panel then active:close() end
    active=panel
end
local function text(key) return getText("IGUI_EmberRoutesProbe_Settlement_"..key) end
---@param actor IsoPlayer
---@param entry EmberRoutesSettlement?
---@param saved function?
---@return EmberRoutesSettlementSelector
function EmberRoutesSettlementSelector:new(actor,entry,saved)
    local h=getTextManager():getFontHeight(UIFont.Small)
    local p=math.ceil(h*0.6)
    local w=math.min(getCore():getScreenWidth()*0.75,h*34)
    local hint=Text.wrap(text("selectionHint"),w-p*2,UIFont.Small)
    local height=math.min(getCore():getScreenHeight()*0.8,h*(#hint+9)+p*7)
    ---@type EmberRoutesSettlementSelector
    local o=ISCollapsableWindow.new(self,p,p,w,height)
    o.actor,o.entry,o.saved,o.fontHeight,o.pad=actor,entry,saved,h,p
    o.previewZ=math.floor(actor:getZ()) o.cursorX=math.floor(actor:getX()) o.cursorY=math.floor(actor:getY())
    o.title=text(entry and "edit" or "create") o.resizable=false
    o.backgroundColor={r=0.035,g=0.045,b=0.05,a=0.94}
    o.hintLines=hint o.statusLines={}
    o.store=State.new({area=false,message=""})
    return o
end
function EmberRoutesSettlementSelector:initialise() ISCollapsableWindow.initialise(self) end
function EmberRoutesSettlementSelector:createChildren()
    ISCollapsableWindow.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local top=self:titleBarHeight()+p+h*#self.hintLines
    local slots=assert(Layout.axis({x=0,y=top,width=self.width,height=self.height-top},
        {{basis=h+p},{grow=1},{basis=h+p*2}},{direction="column",padding=p,gap=p}))
    self.nameEntry=ISTextEntryBox:new(self.entry and self.entry.name or text("defaultName").." "..(#Ledger.list()+1),
        slots[1].x,slots[1].y,slots[1].width,slots[1].height)
    self.nameEntry:initialise() self:addChild(self.nameEntry)
    self.messageY=slots[2].y
    local buttons=assert(Layout.axis(slots[3],{{grow=1},{grow=1}},{gap=p}))
    for i,definition in ipairs({{"UI_btn_apply",EmberRoutesSettlementSelector.apply},{"UI_btn_cancel",EmberRoutesSettlementSelector.close}}) do
        local r=buttons[i]
        local button=ISButton:new(r.x,r.y,r.width,r.height,getText(definition[1]),self,definition[2])
        button:initialise() self:addChild(button)
    end
    self.unsubscribe=self.store:subscribe(function(snapshot)
        self.area=snapshot.area
        self.statusLines=Text.wrap(snapshot.message,self.width-p*2,UIFont.Small)
        if #self.statusLines>3 then self.statusLines={self.statusLines[1],self.statusLines[2],self.statusLines[3].."..."} end
    end)
    self:setWantKeyEvents(true)
end
function EmberRoutesSettlementSelector:point()
    local n=self.actor:getIndex()
    self.previewZ=math.floor(self.actor:getZ())
    local x=math.floor(screenToIsoX(n,getMouseX(),getMouseY(),self.previewZ))
    local y=math.floor(screenToIsoY(n,getMouseX(),getMouseY(),self.previewZ))
    if getCell():getGridSquare(x,y,self.previewZ) then return x,y end
end
function EmberRoutesSettlementSelector:range(x,y)
    self.previewZ=math.floor(self.actor:getZ())
    self.cursorX,self.cursorY=x,y
    if not self.anchor then return end
    local area,reason=Geometry.rectangle(self.anchor.x,self.anchor.y,x,y)
    local message=area and (text("range")..area.x..","..area.y.." / "..area.w.." x "..area.h.." / "..text("allFloors")) or text(reason)
    self.store:setState({area=area or false,message=message})
end
-- Native outside callbacks can reach a parent while its Java text entry handles input.
function EmberRoutesSettlementSelector:overPanel()
    local x,y=getMouseX(),getMouseY()
    local left,top=self:getAbsoluteX(),self:getAbsoluteY()
    return x>=left and y>=top and x<left+self.width and y<top+self.height
end
function EmberRoutesSettlementSelector:onMouseDownOutside()
    if self:overPanel() then return true end
    local x,y=self:point()
    if x then self.anchor={x=x,y=y} self.dragging=true self:range(x,y) end
    return true
end
function EmberRoutesSettlementSelector:onMouseMoveOutside()
    if self.dragging and not self:overPanel() then local x,y=self:point() if x then self:range(x,y) end end
end
function EmberRoutesSettlementSelector:onMouseUpOutside() self.dragging=false self.anchor=nil return true end
function EmberRoutesSettlementSelector:apply()
    local ok,entry,code=pcall(Ledger.commit,self.actor,self.entry and self.entry.id,self.nameEntry:getText(),self.area or nil)
    if not ok then Log.write("SETTLEMENT","COMMIT_ERROR "..tostring(entry)) code="ERROR" entry=nil end
    if entry then
        Log.write("SETTLEMENT","SAVED id="..entry.id.." revision="..entry.revision)
        self:close() if self.saved then self.saved(entry) end
    else self.store:setState({message=text(code)}) end
end
function EmberRoutesSettlementSelector:prerender()
    ISCollapsableWindow.prerender(self)
    local y=self:titleBarHeight()+self.pad
    for _,line in ipairs(self.hintLines) do self:drawText(line,self.pad,y,0.9,0.85,0.65,1,UIFont.Small) y=y+self.fontHeight end
    for i,line in ipairs(self.statusLines) do self:drawText(line,self.pad,self.messageY+(i-1)*self.fontHeight,0.9,0.87,0.75,1,UIFont.Small) end
    if self.area then
        addAreaHighlightForPlayer(self.actor:getIndex(),self.area.x,self.area.y,self.area.x+self.area.w,
            self.area.y+self.area.h,self.previewZ,0.3,0.75,0.55,0.55)
    else
        addAreaHighlightForPlayer(self.actor:getIndex(),self.cursorX,self.cursorY,self.cursorX+1,self.cursorY+1,
            self.previewZ,0.3,0.75,0.55,0.55)
    end
end
function EmberRoutesSettlementSelector:onKeyPress(key)
    if key==Keyboard.KEY_ESCAPE then self:close() elseif key==Keyboard.KEY_RETURN then self:apply() end
end
function EmberRoutesSettlementSelector:isKeyConsumed(key) return key==Keyboard.KEY_ESCAPE or key==Keyboard.KEY_RETURN end
function EmberRoutesSettlementSelector:onJoypadDown(button)
    if button==Joypad.BButton then self:close()
    elseif button==Joypad.XButton then self:apply()
    elseif button==Joypad.AButton then
        if self.anchor then self:range(self.cursorX,self.cursorY) self.anchor=nil
        else self.anchor={x=self.cursorX,y=self.cursorY} self:range(self.cursorX,self.cursorY) end
    end
end
function EmberRoutesSettlementSelector:onJoypadDirUp() self:range(self.cursorX,self.cursorY-1) end
function EmberRoutesSettlementSelector:onJoypadDirDown() self:range(self.cursorX,self.cursorY+1) end
function EmberRoutesSettlementSelector:onJoypadDirLeft() self:range(self.cursorX-1,self.cursorY) end
function EmberRoutesSettlementSelector:onJoypadDirRight() self:range(self.cursorX+1,self.cursorY) end
function EmberRoutesSettlementSelector:close()
    if self.unsubscribe then self.unsubscribe() self.unsubscribe=nil end
    ISCollapsableWindow.close(self) self:removeFromUIManager()
    if self.actor:getJoypadBind()~=-1 then
        ---@diagnostic disable-next-line: deprecated
        setJoypadFocus(self.actor:getIndex(),nil)
    end
    if active==self then active=nil end
end
function EmberRoutesSettlementSelector.open(actor,entry,saved)
    if not Ledger.authorized(actor) then return end
    if active then active:close() end
    local panel=EmberRoutesSettlementSelector:new(actor,entry,saved)
    panel:initialise() panel:addToUIManager() active=panel
    if actor:getJoypadBind()~=-1 then setJoypadFocus(actor:getIndex(),panel) end
    return panel
end
return EmberRoutesSettlementSelector
