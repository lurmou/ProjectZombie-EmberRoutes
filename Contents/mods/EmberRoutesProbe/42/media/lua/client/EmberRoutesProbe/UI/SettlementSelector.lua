require "ISUI/ISCollapsableWindow"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"
local Geometry=require "EmberRoutesProbe/SettlementGeometry"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Text=require "EmberRoutesProbe/UI/Text"
local Layout=require "EmberRoutesProbe/UI/Layout"
local State=require "EmberRoutesProbe/UI/State"
local Log=require "EmberRoutesProbe/Log"
local Theme=require "EmberRoutesProbe/UI/Theme"

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
---@field dragArea {x:number,y:number,w:number,h:number}?
---@field areas {x:number,y:number,w:number,h:number}[]
---@field history table[]
---@field mode "add"|"remove"
---@field hintLines string[]
---@field statusLines string[]
---@field store EmberRoutesUIStore
---@field nameEntry ISTextEntryBox
---@field buttonAdd ISButton
---@field buttonRemove ISButton
---@field buttonUndo ISButton
---@field buttonClear ISButton
---@field messageY number
---@field renderTick function?
---@field unsubscribe function?
EmberRoutesSettlementSelector=ISCollapsableWindow:derive("EmberRoutesSettlementSelector")
local active

function EmberRoutesSettlementSelector.claim(panel)
    if active and active~=panel then active:close() end
    active=panel
end

local function text(key,...)
    local fullKey="IGUI_EmberRoutesProbe_Settlement_"..key
    local args={...}
    if #args>0 then
        local str=getText(fullKey, ...)
        for i,v in ipairs(args) do
            str=str:gsub("%%"..i.."%$?%a?", tostring(v))
        end
        return str
    end
    return getText(fullKey)
end

---@param actor IsoPlayer
---@param entry EmberRoutesSettlement?
---@param saved function?
---@return EmberRoutesSettlementSelector
function EmberRoutesSettlementSelector:new(actor,entry,saved)
    local h=getTextManager():getFontHeight(UIFont.Small)
    local p=math.ceil(h*0.6)
    local w=math.min(getCore():getScreenWidth()*0.75,math.max(420,h*24))
    local hint=Text.wrap(text("selectionHint"),w-p*2,UIFont.Small)
    local height=math.min(getCore():getScreenHeight()*0.85,h*(#hint+11)+p*8)
    ---@type EmberRoutesSettlementSelector
    local o=ISCollapsableWindow.new(self,p,p,w,height)
    o.actor,o.entry,o.saved,o.fontHeight,o.pad=actor,entry,saved,h,p
    o.previewZ=math.floor(actor:getZ())
    o.cursorX=math.floor(actor:getX())
    o.cursorY=math.floor(actor:getY())
    o.title=text(entry and "edit" or "create")
    o.resizable=false
    o.backgroundColor={r=0.035,g=0.045,b=0.05,a=0.94}
    o.hintLines=hint
    o.statusLines={}
    o.mode="add"
    o.areas=entry and entry.areas and Geometry.cloneAreas(entry.areas) or {}
    o.history={}
    o.store=State.new({area=false,message=""})
    return o
end

function EmberRoutesSettlementSelector:initialise()
    ISCollapsableWindow.initialise(self)
    self.renderTick=function() self:renderWorldHighlights() end
    Events.OnRenderTick.Add(self.renderTick)
end

function EmberRoutesSettlementSelector:createChildren()
    ISCollapsableWindow.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local top=self:titleBarHeight()+p+h*#self.hintLines

    local slots=assert(Layout.axis({x=0,y=top,width=self.width,height=self.height-top},
        {{basis=h+p},{basis=h+p*1.2},{grow=1},{basis=h+p*2}},{direction="column",padding=p,gap=p}))

    self.nameEntry=ISTextEntryBox:new(self.entry and self.entry.name or text("defaultName").." "..(#Ledger.list()+1),
        slots[1].x,slots[1].y,slots[1].width,slots[1].height)
    self.nameEntry:initialise()
    self:addChild(self.nameEntry)

    -- Row 2: Mode toolbar (Add, Cut, Undo, Clear)
    local modeButtons=assert(Layout.axis(slots[2],{{grow=1},{grow=1},{grow=1},{grow=1}},{gap=p}))
    self.buttonAdd=ISButton:new(modeButtons[1].x,modeButtons[1].y,modeButtons[1].width,modeButtons[1].height,
        text("modeAdd"),self,function() self:setMode("add") end)
    self.buttonAdd:initialise()
    self:addChild(self.buttonAdd)

    self.buttonRemove=ISButton:new(modeButtons[2].x,modeButtons[2].y,modeButtons[2].width,modeButtons[2].height,
        text("modeRemove"),self,function() self:setMode("remove") end)
    self.buttonRemove:initialise()
    self:addChild(self.buttonRemove)

    self.buttonUndo=ISButton:new(modeButtons[3].x,modeButtons[3].y,modeButtons[3].width,modeButtons[3].height,
        text("modeUndo"),self,function() self:undo() end)
    self.buttonUndo:initialise()
    self:addChild(self.buttonUndo)

    self.buttonClear=ISButton:new(modeButtons[4].x,modeButtons[4].y,modeButtons[4].width,modeButtons[4].height,
        text("modeClear"),self,function() self:clearAreas() end)
    self.buttonClear:initialise()
    self:addChild(self.buttonClear)

    self:refreshModeButtons()

    self.messageY=slots[3].y

    -- Bottom row: Apply & Cancel
    local bottomButtons=assert(Layout.axis(slots[4],{{grow=1},{grow=1}},{gap=p}))
    self.buttonApply=ISButton:new(bottomButtons[1].x,bottomButtons[1].y,bottomButtons[1].width,bottomButtons[1].height,
        getText("UI_btn_apply"),self,function() self:apply() end)
    self.buttonApply:initialise()
    self:addChild(self.buttonApply)

    self.buttonCancel=ISButton:new(bottomButtons[2].x,bottomButtons[2].y,bottomButtons[2].width,bottomButtons[2].height,
        getText("UI_btn_cancel"),self,function() self:close() end)
    self.buttonCancel:initialise()
    self:addChild(self.buttonCancel)

    self.unsubscribe=self.store:subscribe(function(snapshot)
        self.area=snapshot.area
        self.statusLines=Text.wrap(snapshot.message,self.width-p*2,UIFont.Small)
        if #self.statusLines>3 then self.statusLines={self.statusLines[1],self.statusLines[2],self.statusLines[3].."..."} end
    end)
    self:setWantKeyEvents(true)
    self:updateSummaryMessage()
end

function EmberRoutesSettlementSelector:refreshModeButtons()
    if self.buttonAdd then
        if self.mode=="add" then
            self.buttonAdd.backgroundColor={r=0.12,g=0.38,b=0.22,a=1.0}
            self.buttonAdd.borderColor={r=0.3,g=0.85,b=0.45,a=1.0}
        else
            self.buttonAdd.backgroundColor={r=0.10,g=0.13,b=0.16,a=0.9}
            self.buttonAdd.borderColor={r=0.25,g=0.30,b=0.35,a=0.8}
        end
    end
    if self.buttonRemove then
        if self.mode=="remove" then
            self.buttonRemove.backgroundColor={r=0.42,g=0.15,b=0.15,a=1.0}
            self.buttonRemove.borderColor={r=0.95,g=0.35,b=0.35,a=1.0}
        else
            self.buttonRemove.backgroundColor={r=0.10,g=0.13,b=0.16,a=0.9}
            self.buttonRemove.borderColor={r=0.25,g=0.30,b=0.35,a=0.8}
        end
    end
    if self.buttonUndo then
        self.buttonUndo.enable=#self.history>0
    end
end

function EmberRoutesSettlementSelector:setMode(mode)
    self.mode=mode
    self:refreshModeButtons()
    self:updateSummaryMessage()
end

function EmberRoutesSettlementSelector:undo()
    if #self.history>0 then
        self.areas=table.remove(self.history)
        self.area=(self.areas and #self.areas>0) and self.areas[1] or false
        self:refreshModeButtons()
        self:updateSummaryMessage()
    end
end

function EmberRoutesSettlementSelector:clearAreas()
    if self.areas and #self.areas>0 then
        self.history[#self.history+1]=Geometry.cloneAreas(self.areas)
        self.areas={}
        self.area=false
        self:refreshModeButtons()
        self:updateSummaryMessage()
    end
end

function EmberRoutesSettlementSelector:updateSummaryMessage()
    local count=#self.areas
    local tiles=Geometry.totalTiles(self.areas)
    local modeHint=self.mode=="add" and text("hintAdd") or text("hintRemove")
    local summary=text("summary",count,tiles)
    local currentArea=(self.areas and #self.areas>0) and self.areas[1] or false
    self.store:setState({area=currentArea,message=modeHint.."\n"..summary})
end

function EmberRoutesSettlementSelector:updateDragMessage()
    if not self.dragArea then return end
    local count=#self.areas
    local tiles=Geometry.totalTiles(self.areas)
    local dragText
    if self.mode=="add" then
        dragText=text("dragAdd",self.dragArea.w,self.dragArea.h,self.dragArea.w*self.dragArea.h)
    else
        dragText=text("dragRemove",self.dragArea.w,self.dragArea.h)
    end
    local summary=text("summary",count,tiles)
    self.store:setState({message=dragText.." · "..summary})
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
    local area=Geometry.rectangle(self.anchor.x,self.anchor.y,x,y)
    if area then self.dragArea=area self:updateDragMessage() end
end

function EmberRoutesSettlementSelector:overPanel()
    local x,y=getMouseX(),getMouseY()
    local left,top=self:getAbsoluteX(),self:getAbsoluteY()
    return x>=left and y>=top and x<left+self.width and y<top+self.height
end

function EmberRoutesSettlementSelector:onMouseDownOutside()
    if self:overPanel() then return true end
    local x,y=self:point()
    if x then
        self.anchor={x=x,y=y}
        self.dragging=true
        self.dragArea=Geometry.rectangle(x,y,x,y)
        self:updateDragMessage()
    end
    return true
end

function EmberRoutesSettlementSelector:onMouseMoveOutside()
    if self.dragging and not self:overPanel() then
        local x,y=self:point()
        if x then self:range(x,y) end
    end
end

function EmberRoutesSettlementSelector:onMouseUpOutside()
    if self.dragging and self.dragArea then
        if #self.history>=10 then table.remove(self.history,1) end
        self.history[#self.history+1]=Geometry.cloneAreas(self.areas)
        if self.mode=="add" then
            self.areas=Geometry.addToList(self.areas,self.dragArea)
        else
            self.areas=Geometry.subtractFromList(self.areas,self.dragArea)
        end
        self.dragArea=nil
        self.area=(self.areas and #self.areas>0) and self.areas[1] or false
        self:refreshModeButtons()
    end
    self.dragging=false
    self.anchor=nil
    self:updateSummaryMessage()
    return true
end

function EmberRoutesSettlementSelector:apply()
    -- Child classes (e.g. LifeZoneSelector) might rely on self.area directly
    local targetAreas=self.areas
    if (not targetAreas or #targetAreas==0) and self.area then
        targetAreas={self.area}
    end
    if not targetAreas or #targetAreas==0 then
        self.store:setState({message=text("noAreas")})
        return
    end
    local ok,entry,code=pcall(Ledger.commit,self.actor,self.entry and self.entry.id,self.nameEntry:getText(),targetAreas)
    if not ok then Log.write("SETTLEMENT","COMMIT_ERROR "..tostring(entry)) code="ERROR" entry=nil end
    if entry then
        Log.write("SETTLEMENT","SAVED id="..entry.id.." revision="..entry.revision.." areas="..#entry.areas)
        self:close()
        if self.saved then self.saved(entry) end
    else
        self.store:setState({message=text(code)})
    end
end

-- World highlight rendering: driven exclusively by Events.OnRenderTick for 100% flicker-free rendering
function EmberRoutesSettlementSelector:renderWorldHighlights()
    if not self.actor or (self.actor.isDead and self.actor:isDead()) or (self.isVisible and not self:isVisible()) then return end
    local playerNum=self.actor:getIndex()
    local z=self.previewZ or math.floor(self.actor:getZ())

    -- 1. Render all confirmed areas (Warm Amber/Gold)
    if self.areas and #self.areas>0 then
        for _,r in ipairs(self.areas) do
            addAreaHighlightForPlayer(playerNum,r.x,r.y,r.x+r.w,r.y+r.h,z,0.95,0.78,0.20,0.35)
        end
    elseif self.area then
        addAreaHighlightForPlayer(playerNum,self.area.x,self.area.y,self.area.x+self.area.w,
            self.area.y+self.area.h,z,0.95,0.78,0.20,0.35)
    end

    -- 2. Render dragging preview
    if self.dragging and self.dragArea then
        local d=self.dragArea
        if self.mode=="add" then
            -- Emerald green for additions
            addAreaHighlightForPlayer(playerNum,d.x,d.y,d.x+d.w,d.y+d.h,z,0.20,0.85,0.35,0.45)
        else
            -- Rose red for cutouts / removals
            addAreaHighlightForPlayer(playerNum,d.x,d.y,d.x+d.w,d.y+d.h,z,0.95,0.22,0.22,0.50)
        end
    elseif not self.dragging and self.cursorX and self.cursorY then
        -- 3. Render hover square under cursor when idle
        local hx,hy=self:point()
        if hx and hy then
            self.cursorX,self.cursorY=hx,hy
            addAreaHighlightForPlayer(playerNum,hx,hy,hx+1,hy+1,z,0.90,0.95,1.0,0.30)
        end
    end
end

function EmberRoutesSettlementSelector:prerender()
    ISCollapsableWindow.prerender(self)
    if self.renderWorldHighlights then self:renderWorldHighlights() end
    local y=self:titleBarHeight()+self.pad
    for _,line in ipairs(self.hintLines) do
        self:drawText(line,self.pad,y,0.9,0.85,0.65,1,UIFont.Small)
        y=y+self.fontHeight
    end
    for i,line in ipairs(self.statusLines) do
        self:drawText(line,self.pad,self.messageY+(i-1)*self.fontHeight,0.9,0.87,0.75,1,UIFont.Small)
    end
end

function EmberRoutesSettlementSelector:onKeyPress(key)
    if key==Keyboard.KEY_ESCAPE then self:close()
    elseif key==Keyboard.KEY_RETURN then self:apply()
    elseif key==Keyboard.KEY_1 or key==Keyboard.KEY_A then self:setMode("add")
    elseif key==Keyboard.KEY_2 or key==Keyboard.KEY_R then self:setMode("remove")
    elseif key==Keyboard.KEY_Z then self:undo() end
end

function EmberRoutesSettlementSelector:isKeyConsumed(key)
    return key==Keyboard.KEY_ESCAPE or key==Keyboard.KEY_RETURN
        or key==Keyboard.KEY_1 or key==Keyboard.KEY_2
        or key==Keyboard.KEY_A or key==Keyboard.KEY_R or key==Keyboard.KEY_Z
end

function EmberRoutesSettlementSelector:onJoypadDown(button)
    if button==Joypad.BButton then self:close()
    elseif button==Joypad.XButton then self:apply()
    elseif button==Joypad.YButton then self:setMode(self.mode=="add" and "remove" or "add")
    elseif button==Joypad.AButton then
        if self.anchor then
            self:range(self.cursorX,self.cursorY)
            self:onMouseUpOutside()
        else
            self.anchor={x=self.cursorX,y=self.cursorY}
            self.dragging=true
            self.dragArea=Geometry.rectangle(self.cursorX,self.cursorY,self.cursorX,self.cursorY)
        end
    end
end

function EmberRoutesSettlementSelector:onJoypadDirUp() self:range(self.cursorX,self.cursorY-1) end
function EmberRoutesSettlementSelector:onJoypadDirDown() self:range(self.cursorX,self.cursorY+1) end
function EmberRoutesSettlementSelector:onJoypadDirLeft() self:range(self.cursorX-1,self.cursorY) end
function EmberRoutesSettlementSelector:onJoypadDirRight() self:range(self.cursorX+1,self.cursorY) end

function EmberRoutesSettlementSelector:close()
    if self.renderTick then
        Events.OnRenderTick.Remove(self.renderTick)
        self.renderTick=nil
    end
    if self.unsubscribe then self.unsubscribe() self.unsubscribe=nil end
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
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
    panel:initialise()
    panel:addToUIManager()
    active=panel
    if actor:getJoypadBind()~=-1 then setJoypadFocus(actor:getIndex(),panel) end
    return panel
end

return EmberRoutesSettlementSelector
