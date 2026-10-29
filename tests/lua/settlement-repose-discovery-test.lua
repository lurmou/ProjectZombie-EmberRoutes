local f=dofile('tests/lua/repose-sites-test.lua')
local Index=require 'EmberRoutesProbe/SettlementFacilities'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Sites=f.sites local checks=0
local function tick() f.advance(require('EmberRoutesProbe/TickConfig').facilitiesMs) Index.tick(64) end
local function check(value,label) checks=checks+1 assert(value,label) end
local foreign={id='other',revision=1,areas={{x=200,y=0,w=8,h=8}}}
f.entry.areas={{x=0,y=0,w=96,h=16}} f.entry.revision=1
package.loaded['EmberRoutesProbe/SettlementLedger'].at=function(x,y)
    if Geometry.inside(f.entry,x,y) then return {f.entry} end
    if Geometry.inside(foreign,x,y) then return {foreign} end return {}
end
local oldA,oldB=f.furniture:getSquare(),f.other:getSquare()
oldA.rows={} oldB.rows={}
local farA,farB=f.square(80,0,2),f.square(81,0,2)
f.furniture.square=farA f.other.square=farB farA.rows={f.furniture} farB.rows={f.other}
f.chunk.low=-2 f.chunk.high=2
local reads=0 local original=f.cell.getGridSquare
f.cell.getGridSquare=function(self,x,y,z) reads=reads+1 return original(self,x,y,z) end
local function discover(id)
    local request=Sites.new(f.actor,f.npc,id,'SLEEP')
    for _=1,1000 do
        tick()
        local candidate,done,reason=request:step(8)
        if done then return candidate,reason end
    end
    error('bounded settlement discovery did not converge')
end
local candidate=assert(discover('a'))
check(candidate.object==f.furniture or candidate.object==f.other,'whole-settlement search discovers a bed 80 tiles away on floor 2')
local proof=assert(Sites.prepare(candidate,f.actor,f.npc,'a','SLEEP'))
check(proof.parts[1].z==2,'preparation no longer imposes NPC floor or distance admission limits')
local before=reads local another=Sites.new(f.actor,f.npc,'b','SLEEP')
local shared,done=another:step(16)
check(done and shared and reads-before<40,'second NPC selects from shared observations rather than rescanning the territory')
local function single(x,y,z)
    local square=f.square(x,y,z) local object={mod={},square=square,flags={[IsoFlagType.bed]=true}}
    function object:getSquare() return self.square end function object:getModData() return self.mod end
    function object:getProperties()
        return {get=function(_,key) if key=='BedType' then return 'goodBed' end end,
            has=function(_,flag) return self.flags[flag]==true end}
    end
    function object:getSprite() return {} end function object:hasSpriteGrid() return false end
    function object:isFurnitureOccupied() return self.occupied==true end
    square.rows={object} return object
end
local near=single(2,1,0) Index.invalidate(2,1)
local originalX,originalZ=f.actor.getX,f.actor.getZ
f.actor.getX=function() return 80.5 end f.actor.getZ=function() return 2 end
local revision=Sites.view(f.actor,f.furniture).revision
assert(Sites.configure(f.actor,f.furniture,revision,'ASSIGNED','a')=='SITE_POLICY_SAVED')
f.actor.getX,f.actor.getZ=originalX,originalZ
for _=1,40 do tick() end
check(assert(discover('a')).object~=near,'own assigned distant bed ranks ahead of a nearby public bed')
check(assert(discover('b')).object==near,'another NPC cannot borrow an assigned bed and can select the public alternative')
local outside=single(200,0,0)
check(not Sites.prepare({object=outside,revision=0,settlementId='s'},f.actor,f.npc,'a','SLEEP')
    and not outside.mod.EmberRoutesRepose,'foreign-settlement bed is rejected before assigning any furniture identity')
-- Only the basement bed is available now.
f.actor.getX=function() return 80.5 end f.actor.getZ=function() return 2 end
revision=Sites.view(f.actor,f.furniture).revision
assert(Sites.configure(f.actor,f.furniture,revision,'DISABLED')=='SITE_POLICY_SAVED')
f.actor.getX,f.actor.getZ=originalX,originalZ
near.occupied=true
local basement=single(50,4,-2) Index.invalidate(50,4)
local lower=assert(discover('a'))
check(lower.object==basement and Sites.prepare(lower,f.actor,f.npc,'a','SLEEP'),
    'loaded negative floors come from the chunk range and remain selectable from ground level')
local loaded=true
f.cell.getChunkForGridSquare=function(_,x,y)
    if not loaded and math.floor(x/8)==6 and math.floor(y/8)==0 then return nil end return f.chunk
end
f.cell.getGridSquare=function(self,x,y,z)
    reads=reads+1
    if not loaded and math.floor(x/8)==6 and math.floor(y/8)==0 then return nil end
    return original(self,x,y,z)
end
loaded=false Index.invalidate(50,4)
local waiting=Sites.new(f.actor,f.npc,'a','SLEEP') local reason
local remainedPending=true
for _=1,30 do
    tick()
    local c,complete,why=waiting:step(8) reason=why
    remainedPending=remainedPending and not c and not complete
end
check(remainedPending,'unloaded territory cannot be reported as an empty complete bed search')
check(reason=='SITE_UNLOADED','unloaded target keeps a specific observation reason')
loaded=true Index.invalidate(50,4)
check(assert(discover('a')).object==basement,'load invalidation reactivates an existing bed without changing its identity')
local oldRow=Index.watch(f.entry,function() return nil,0 end)
f.entry.revision=2 f.entry.areas={{x=0,y=0,w=8,h=8},{x=0,y=0,w=8,h=8}}
f.chunk.low=0 f.chunk.high=0
local revised=Index.watch(f.entry,function() return nil,0 end)
check(revised~=oldRow and #revised.slots==0,'settlement revision discards derived observations from removed areas')
before=reads Index.advance(revised,1000)
check(reads-before==64,'overlapping areas visit their shared chunk once per observation sweep')
check(not Index.pending(revised),'complete loaded sweep can distinguish no usable observation from missing world data')
for _=1,11 do f.advance() end
before=reads Index.tick(64)
check(reads==before,'unused settlement observations stop consuming the background scan budget')
local first
for i=1,33 do
    local row=Index.watch({id='cache-'..i,revision=1,areas={{x=0,y=0,w=1,h=1}}},function() return nil,0 end)
    if i==1 then first=row end
    f.advance()
end
check(Index.watch({id='cache-1',revision=1,areas={{x=0,y=0,w=1,h=1}}},function() return nil,0 end)~=first,
    'derived cache is bounded even after settlements are repeatedly replaced')
print('PASS '..checks..' settlement-wide/shared/multilevel/loading discovery checks; world and paths mocked')
