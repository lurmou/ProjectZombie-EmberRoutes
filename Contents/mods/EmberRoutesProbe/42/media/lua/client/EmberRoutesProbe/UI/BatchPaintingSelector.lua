require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISContextMenu"
local Geometry=require "EmberRoutesProbe/SettlementGeometry"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Batch=require "EmberRoutesProbe/BatchStoragePainting"
local Filter=require "EmberRoutesProbe/StorageFilter"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Text=require "EmberRoutesProbe/UI/Text"

---@class EmberRoutesBatchPaintingSelector:ISCollapsableWindow
---@field actor IsoPlayer
---@field settlement table
---@field fontHeight number
---@field pad number
---@field previewZ number
---@field cursorX number
---@field cursorY number
---@field anchor {x:number,y:number}?
---@field dragging boolean?
---@field dragArea {x:number,y:number,w:number,h:number}?
---@field selectedContainers table[]
---@field renderTick function?
---@field btnApply ISButton
---@field btnCancel ISButton
EmberRoutesBatchPaintingSelector=ISCollapsableWindow:derive("EmberRoutesBatchPaintingSelector")
local active

function EmberRoutesBatchPaintingSelector.open(actor,settlement)
    if active then active:close() end
    local selector=EmberRoutesBatchPaintingSelector:new(actor,settlement)
    selector:initialise()
    selector:addToUIManager()
    active=selector
    return selector
end

local function text(key,...)
    local str=getText("IGUI_EmberRoutesProbe_BatchPaint_"..key)
    local args={...}
    if #args>0 then
        for i,v in ipairs(args) do
            str=str:gsub("%%"..i,tostring(v))
        end
    end
    return str
end

function EmberRoutesBatchPaintingSelector:new(actor,settlement)
    local h=getTextManager():getFontHeight(UIFont.Small)
    local p=math.ceil(h*0.6)
    local w=math.min(getCore():getScreenWidth()*0.6,math.max(380,h*22))
    local height=h*8+p*6
    local sw=getCore():getScreenWidth()
    ---@type EmberRoutesBatchPaintingSelector
    local o=ISCollapsableWindow.new(self,sw-w-p*2,p*3,w,height)
    o.actor=actor
    o.settlement=settlement
    o.fontHeight=h
    o.pad=p
    o.previewZ=math.floor(actor:getZ())
    o.cursorX=math.floor(actor:getX())
    o.cursorY=math.floor(actor:getY())
    o.title=text("title")
    o.resizable=false
    o.backgroundColor={r=0.035,g=0.045,b=0.05,a=0.94}
    o.selectedContainers={}
    o.statusMessage=text("dragHint")
    return o
end

function EmberRoutesBatchPaintingSelector:initialise()
    ISCollapsableWindow.initialise(self)
    self.renderTick=function() self:renderWorldHighlights() end
    Events.OnRenderTick.Add(self.renderTick)
end

function EmberRoutesBatchPaintingSelector:createChildren()
    ISCollapsableWindow.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local btnW=math.floor((self.width-p*3)/2)
    local btnY=self.height-h-p*2

    self.btnApply=ISButton:new(p,btnY,btnW,h+p*0.8,text("applyBtn"),self,EmberRoutesBatchPaintingSelector.openPresetMenu)
    self.btnApply:initialise()
    Theme.button(self.btnApply,true)
    self.btnApply.enable=false
    self:addChild(self.btnApply)

    self.btnCancel=ISButton:new(p*2+btnW,btnY,btnW,h+p*0.8,text("cancelBtn"),self,EmberRoutesBatchPaintingSelector.close)
    self.btnCancel:initialise()
    Theme.button(self.btnCancel,false)
    self:addChild(self.btnCancel)
end

function EmberRoutesBatchPaintingSelector:point()
    local n=self.actor:getIndex()
    self.previewZ=math.floor(self.actor:getZ())
    local x=math.floor(screenToIsoX(n,getMouseX(),getMouseY(),self.previewZ))
    local y=math.floor(screenToIsoY(n,getMouseX(),getMouseY(),self.previewZ))
    if getCell():getGridSquare(x,y,self.previewZ) then return x,y end
end

function EmberRoutesBatchPaintingSelector:overPanel()
    local x,y=getMouseX(),getMouseY()
    local left,top=self:getAbsoluteX(),self:getAbsoluteY()
    return x>=left and y>=top and x<left+self.width and y<top+self.height
end

function EmberRoutesBatchPaintingSelector:onMouseDownOutside()
    if self:overPanel() then return true end
    local x,y=self:point()
    if x then
        self.anchor={x=x,y=y}
        self.dragging=true
        self.dragArea=Geometry.rectangle(x,y,x,y)
        self:updateSelection()
    end
    return true
end

function EmberRoutesBatchPaintingSelector:onMouseMoveOutside()
    if self.dragging and not self:overPanel() then
        local x,y=self:point()
        if x and self.anchor then
            self.cursorX,self.cursorY=x,y
            local area=Geometry.rectangle(self.anchor.x,self.anchor.y,x,y)
            if area then
                self.dragArea=area
                self:updateSelection()
            end
        end
    end
end

function EmberRoutesBatchPaintingSelector:onMouseUpOutside()
    if self.dragging and self.dragArea then
        self.dragging=false
        self:updateSelection()
        if #self.selectedContainers>0 then
            self:openPresetMenu()
        end
    end
end

function EmberRoutesBatchPaintingSelector:updateSelection()
    if not self.dragArea then
        self.selectedContainers={}
        self.statusMessage=text("dragHint")
        if self.btnApply then self.btnApply.enable=false end
        return
    end

    self.selectedContainers=Batch.scanArea(self.dragArea,self.previewZ)
    local count=#self.selectedContainers
    if count>0 then
        self.statusMessage=text("selectedCount",count,self.previewZ)
        if self.btnApply then self.btnApply.enable=true end
    else
        self.statusMessage=text("noneFound",self.previewZ)
        if self.btnApply then self.btnApply.enable=false end
    end
end

function EmberRoutesBatchPaintingSelector:openPresetMenu()
    if #self.selectedContainers==0 then return end
    local playerNum=self.actor:getPlayerNum()
    local menu=ISContextMenu.get(playerNum,getMouseX(),getMouseY())
    if not menu then return end

    local function applyPreset(presetId,presetName)
        local result=Batch.apply(self.selectedContainers,presetId,self.actor)
        self.actor:Say(text("appliedSuccess",tostring(result.updated),presetName))
        self:close()
    end

    menu:addOption("🤖 "..text("preset_auto"),self,function() applyPreset("auto",text("preset_auto")) end)
    menu:addOption("🍱 "..getText("IGUI_EmberRoutesProbe_Filter_food"),self,function() applyPreset("food",getText("IGUI_EmberRoutesProbe_Filter_food")) end)
    menu:addOption("💊 "..getText("IGUI_EmberRoutesProbe_Filter_medical"),self,function() applyPreset("medical",getText("IGUI_EmberRoutesProbe_Filter_medical")) end)
    menu:addOption("🔫 "..getText("IGUI_EmberRoutesProbe_Filter_weapons"),self,function() applyPreset("weapons",getText("IGUI_EmberRoutesProbe_Filter_weapons")) end)
    menu:addOption("👕 "..getText("IGUI_EmberRoutesProbe_Filter_apparel"),self,function() applyPreset("apparel",getText("IGUI_EmberRoutesProbe_Filter_apparel")) end)
    menu:addOption("📚 "..getText("IGUI_EmberRoutesProbe_Filter_literature"),self,function() applyPreset("literature",getText("IGUI_EmberRoutesProbe_Filter_literature")) end)
    menu:addOption("🛠️ "..getText("IGUI_EmberRoutesProbe_Filter_tools"),self,function() applyPreset("tools",getText("IGUI_EmberRoutesProbe_Filter_tools")) end)
    menu:addOption("🧱 "..getText("IGUI_EmberRoutesProbe_Filter_materials"),self,function() applyPreset("materials",getText("IGUI_EmberRoutesProbe_Filter_materials")) end)
    menu:addOption("💎 "..getText("IGUI_EmberRoutesProbe_Filter_trade"),self,function() applyPreset("trade",getText("IGUI_EmberRoutesProbe_Filter_trade")) end)
    menu:addOption("♻️ "..getText("IGUI_EmberRoutesProbe_Filter_scrap"),self,function() applyPreset("scrap",getText("IGUI_EmberRoutesProbe_Filter_scrap")) end)

    local kitsOpt=menu:addOption("🎣 "..getText("IGUI_EmberRoutesProbe_Filter_kits"))
    local subKits=ISContextMenu:getNew(menu)
    menu:addSubMenu(kitsOpt,subKits)
    for _,kitId in ipairs({"kit.fishing","kit.farming","kit.tailoring","kit.mechanic"}) do
        subKits:addOption(getText("IGUI_EmberRoutesProbe_Filter_"..kitId),self,function()
            applyPreset(kitId,getText("IGUI_EmberRoutesProbe_Filter_"..kitId))
        end)
    end
end

function EmberRoutesBatchPaintingSelector:renderWorldHighlights()
    if not self:getIsVisible() or not self.actor then return end
    local playerNum=self.actor:getPlayerNum()
    local z=self.previewZ or 0

    if self.dragArea then
        local d=self.dragArea
        local r,g,b,a=0.20,0.82,0.88,0.40
        if #self.selectedContainers>0 then
            r,g,b,a=0.25,0.92,0.45,0.45
        end
        addAreaHighlightForPlayer(playerNum,d.x,d.y,d.x+d.w,d.y+d.h,z,r,g,b,a)
    elseif self.cursorX and self.cursorY then
        local hx,hy=self:point()
        if hx and hy then
            self.cursorX,self.cursorY=hx,hy
            addAreaHighlightForPlayer(playerNum,hx,hy,hx+1,hy+1,z,0.85,0.92,1.0,0.30)
        end
    end
end

function EmberRoutesBatchPaintingSelector:prerender()
    ISCollapsableWindow.prerender(self)
    local h,p=self.fontHeight,self.pad
    local y=self:titleBarHeight()+p
    self:drawText(text("hintLine1"),p,y,0.9,0.88,0.72,1,UIFont.Small)
    y=y+h
    self:drawText(text("hintLine2"),p,y,0.8,0.8,0.8,1,UIFont.Small)
    y=y+h+p*0.5
    local col=Theme.accent
    if #self.selectedContainers>0 then col={r=0.3,g=0.95,b=0.45,a=1} end
    self:drawText(self.statusMessage,p,y,col.r or 0.8,col.g or 0.8,col.b or 0.8,1,UIFont.Small)
end

function EmberRoutesBatchPaintingSelector:onKeyPress(key)
    if key==Keyboard.KEY_ESCAPE then self:close()
    elseif key==Keyboard.KEY_RETURN and #self.selectedContainers>0 then self:openPresetMenu() end
end

function EmberRoutesBatchPaintingSelector:isKeyConsumed(key)
    return key==Keyboard.KEY_ESCAPE or key==Keyboard.KEY_RETURN
end

function EmberRoutesBatchPaintingSelector:close()
    if self.renderTick then
        Events.OnRenderTick.Remove(self.renderTick)
        self.renderTick=nil
    end
    if active==self then active=nil end
    self:setVisible(false)
    self:removeFromUIManager()
end

return EmberRoutesBatchPaintingSelector