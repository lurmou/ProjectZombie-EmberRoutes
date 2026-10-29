-- Reuse the established native world drag selector; commit only a child zone.
local Base=require 'EmberRoutesProbe/UI/SettlementSelector'
local Zones=require 'EmberRoutesProbe/SettlementZones'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Text=require 'EmberRoutesProbe/UI/Text'
local function text(key) return getText('IGUI_EmberRoutesProbe_LifeZone_'..key) end
local Selector=Base:derive('EmberRoutesLifeZoneSelector')
local active
function Selector:new(actor,scope,zone)
    local o=Base.new(self,actor,zone,nil)
    o.scope,o.zone,o.lockedZ,o.world=scope,zone,math.floor(actor:getZ()),Ledger.data()
    if zone then o.lockedZ=zone.area.z end
    o.previewZ=o.lockedZ o.title=text(zone and 'redraw' or 'create')
    o.hintLines=Text.wrap(text('selectionHint'),o.width-o.pad*2,UIFont.Small)
    return o
end
function Selector:point()
    if math.floor(self.actor:getZ())~=self.lockedZ then return nil end
    return Base.point(self)
end
function Selector:range(x,y)
    self.cursorX,self.cursorY=x,y self.previewZ=self.lockedZ
    if not self.anchor then return end
    local area=Geometry.rectangle(self.anchor.x,self.anchor.y,x,y)
    if area then area.z=self.lockedZ end
    local message=area and getText('IGUI_EmberRoutesProbe_LifeZone_range',area.w,area.h,self.lockedZ) or text('ZONE_DATA_INVALID')
    self.store:setState({area=area or false,message=message})
end
function Selector:apply()
    local area=self.area or self.zone and self.zone.area
    if not area then self.store:setState({message=text('selectArea')}) return end
    local rules={}
    for _,id in ipairs(Zones.activities()) do rules[id]=self.zone and self.zone.rules[id] or 1 end
    local saved,why=Zones.save(self.actor,self.scope,self.zone and self.zone.id,self.zone and self.zone.revision,
        {name=self.nameEntry:getText(),area=area,enabled=not self.zone or self.zone.enabled,rules=rules})
    if saved then self:close() else self.store:setState({message=text(why)}) end
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
function Selector.open(actor,scope,zone)
    if not Ledger.view(actor,scope) then return end
    if zone and zone.area.z~=math.floor(actor:getZ()) then actor:Say(text('wrongFloor')) return end
    if active then active:close() end
    local panel=Selector:new(actor,scope,zone)
    panel:initialise()
    Base.claim(panel)
    if zone then panel.store:setState({area=zone.area,message=getText('IGUI_EmberRoutesProbe_LifeZone_range',zone.area.w,zone.area.h,zone.area.z)}) end
    if not zone then panel.nameEntry:setText(text('defaultName')) end
    panel:addToUIManager() active=panel
    if actor:getJoypadBind()~=-1 then setJoypadFocus(actor:getIndex(),panel) end
    return panel
end
return Selector
