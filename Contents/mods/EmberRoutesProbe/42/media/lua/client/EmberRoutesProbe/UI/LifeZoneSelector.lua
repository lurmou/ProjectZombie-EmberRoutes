-- Multi-rectangle zone CSG selector for work zones (lumber, corpse, forage, etc.) and life zones.
local Base=require 'EmberRoutesProbe/UI/SettlementSelector'
local Zones=require 'EmberRoutesProbe/SettlementZones'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Text=require 'EmberRoutesProbe/UI/Text'

local function text(key, ...) return getText('IGUI_EmberRoutesProbe_LifeZone_'..key, ...) end

---@class EmberRoutesLifeZoneSelector:EmberRoutesSettlementSelector
local Selector=Base:derive('EmberRoutesLifeZoneSelector')
local active

function Selector:new(actor,scope,zone,options)
    local o=Base.new(self,actor,nil,nil)
    o.scope=scope
    o.zone=zone
    o.lockedZ=zone and ((zone.areas and zone.areas[1] and zone.areas[1].z) or (zone.area and zone.area.z)) or math.floor(actor:getZ())
    o.previewZ=o.lockedZ
    o.world=Ledger.data()
    o.title=options and options.title or text(zone and 'redraw' or 'create')
    o.isWorkZone=options and options.isWorkZone
    o.onSaved=options and options.onSaved
    o.defaultName=options and options.defaultName
    o.hintLines=Text.wrap(text('selectionHint'),o.width-o.pad*2,UIFont.Small)

    -- Populate existing areas if editing an existing zone
    if zone then
        if zone.areas and #zone.areas > 0 then
            o.areas = Geometry.cloneAreas(zone.areas)
        elseif zone.area then
            o.areas = { Geometry.cloneArea(zone.area) }
        end
    else
        o.areas = {}
    end
    o.history = {}
    o.mode = "add"
    return o
end

function Selector:point()
    if math.floor(self.actor:getZ())~=self.lockedZ then return nil end
    local n=self.actor:getIndex()
    local x=math.floor(screenToIsoX(n,getMouseX(),getMouseY(),self.lockedZ))
    local y=math.floor(screenToIsoY(n,getMouseX(),getMouseY(),self.lockedZ))
    if getCell():getGridSquare(x,y,self.lockedZ) then return x,y end
end

function Selector:range(x,y)
    self.previewZ=self.lockedZ
    self.cursorX,self.cursorY=x,y
    if not self.anchor then return end
    local area=Geometry.rectangle(self.anchor.x,self.anchor.y,x,y)
    if area then
        area.z=self.lockedZ
        self.dragArea=area
        self:updateDragMessage()
    end
end

function Selector:updateSummaryMessage()
    local count=#self.areas
    local tiles=Geometry.totalTiles(self.areas)
    local modeHint=self.mode=="add" and text("hintAdd") or text("hintRemove")
    local summary=getText("IGUI_EmberRoutesProbe_Settlement_summary", count, tiles)
    self.store:setState({message=modeHint.."\n"..summary})
end

function Selector:updateDragMessage()
    if not self.dragArea then return end
    local count=#self.areas
    local tiles=Geometry.totalTiles(self.areas)
    local dragText
    if self.mode=="add" then
        dragText=getText("IGUI_EmberRoutesProbe_Settlement_dragAdd",self.dragArea.w,self.dragArea.h,self.dragArea.w*self.dragArea.h)
    else
        dragText=getText("IGUI_EmberRoutesProbe_Settlement_dragRemove",self.dragArea.w,self.dragArea.h)
    end
    local summary=getText("IGUI_EmberRoutesProbe_Settlement_summary",count,tiles)
    self.store:setState({message=dragText.." · "..summary})
end

function Selector:apply()
    if not self.areas or #self.areas==0 then
        self.store:setState({message=text('selectArea')})
        return
    end

    local rules={}
    for _,id in ipairs(Zones.activities()) do
        rules[id]=self.zone and self.zone.rules[id] or 1
    end

    local name=self.nameEntry and self.nameEntry:getText()
    if not name or name:match('^%s*$') then
        name=self.defaultName or text('defaultName')
    end

    local isWorkZone=(self.isWorkZone==true)
    local saved,why=Zones.save(self.actor,self.scope,self.zone and self.zone.id,self.zone and self.zone.revision,{
        name=name,
        areas=self.areas,
        enabled=not self.zone or self.zone.enabled,
        rules=rules,
        isWorkZone=isWorkZone,
        z=self.lockedZ
    })

    if saved then
        if self.onSaved then
            self.onSaved(saved)
        end
        self:close()
    else
        self.store:setState({message=text(why) or why})
    end
end

function Selector:update()
    if Base.update then Base.update(self) end
    if Ledger.data()~=self.world or not Ledger.view(self.actor,self.scope)
        or math.floor(self.actor:getZ())~=self.lockedZ then self:close() end
end

function Selector:close()
    if self.disposed then return end self.disposed=true
    Base.close(self) if active==self then active=nil end
end

function Selector.open(actor,scope,zone,options)
    if not Ledger.view(actor,scope) then return end
    local z = zone and ((zone.areas and zone.areas[1] and zone.areas[1].z) or (zone.area and zone.area.z))
    if z and z~=math.floor(actor:getZ()) then actor:Say(text('wrongFloor')) return end
    if active then active:close() end
    local panel=Selector:new(actor,scope,zone,options)
    panel:initialise()
    panel:instantiate()
    Base.claim(panel)
    if not zone and panel.nameEntry then
        local defName=options and options.defaultName or text('defaultName')
        panel.nameEntry:setText(defName)
    elseif zone and panel.nameEntry then
        panel.nameEntry:setText(zone.name)
    end
    if options and options.title then
        panel.title=options.title
    end
    panel.isWorkZone=options and options.isWorkZone
    panel.onSaved=options and options.onSaved
    panel.defaultName=options and options.defaultName

    panel:addToUIManager()
    active=panel
    if actor:getJoypadBind()~=-1 then setJoypadFocus(actor:getIndex(),panel) end
    return panel
end

return Selector
