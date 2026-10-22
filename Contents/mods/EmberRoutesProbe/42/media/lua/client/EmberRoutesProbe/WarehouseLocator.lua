local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Geometry=require "EmberRoutesProbe/SettlementGeometry"
local Locator={}
local methods={}
local active
methods.__index=methods
function Locator.new(actor,id)
    return setmetatable({actor=actor,id=id,root=Ledger.data(),cell=getCell()},methods)
end
function methods:clear()
    if self.callback then Events.OnRenderTick.Remove(self.callback) self.callback=nil end
    self.endpoint=nil self.position=nil
    if active==self then active=nil end
end
function methods:validate(sourceId)
    if self.root~=Ledger.data() or self.cell~=getCell() then return nil,"WORLD_CHANGED" end
    local entry,reason=Ledger.view(self.actor,self.id)
    if not entry then return nil,reason end
    local position,code=Registry.describe(sourceId)
    if not position then return nil,code end
    if not Geometry.inside(entry,position.x,position.y) then return nil,"SOURCE_OUTSIDE" end
    local endpoint,why=Registry.resolve(sourceId,"take","local-world")
    if not endpoint then return nil,why end
    return endpoint,position
end
function methods:render()
    local saved,p=self.endpoint,self.position
    if not saved or not p then return end
    local now=getTimestampMs()
    if now>=self.expires or now<self.started or self.cell~=getCell() then self:clear() return end
    if now>=self.nextCheck then
        local endpoint,position=self:validate(saved.id)
        if not endpoint or type(position)~="table" or endpoint.object~=saved.object or endpoint.container~=saved.container
                or position.x~=p.x or position.y~=p.y or position.z~=p.z then
            self:clear() return
        end
        self.nextCheck=now+500
    end
    addAreaHighlightForPlayer(self.actor:getIndex(),p.x,p.y,p.x+1,p.y+1,p.z,0.85,0.72,0.3,0.65)
end
function methods:locate(sourceId)
    if active and active~=self then active:clear() end
    self:clear()
    if type(_G.getTimestampMs)~="function" or type(_G.addAreaHighlightForPlayer)~="function"
            or not Events.OnRenderTick then return nil,"LOCATOR_UNAVAILABLE" end
    local endpoint,position=self:validate(sourceId)
    if not endpoint or type(position)~="table" then
        return nil,type(position)=="string" and position or "LOCATOR_UNAVAILABLE"
    end
    self.endpoint,self.position=endpoint,position
    active=self
    self.started=getTimestampMs() self.expires=self.started+5000 self.nextCheck=self.started+500
    self.callback=function() self:render() end
    Events.OnRenderTick.Add(self.callback)
    return {x=position.x,y=position.y,z=position.z},"SOURCE_MARKED"
end
return Locator
