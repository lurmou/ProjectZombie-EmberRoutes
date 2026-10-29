local f=dofile('tests/lua/repose-sites-test.lua')
local Index=require 'EmberRoutesProbe/SettlementFacilities'
local Stations=require 'EmberRoutesProbe/CraftStations'
local Config=require 'EmberRoutesProbe/TickConfig'
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
ComponentType={CraftBench='CraftBench'}
local recipe={}
local bench={getRecipes=function() return f.list({recipe}) end}
local square=f.square(2,2,0)
local object={}
function object:getSquare() return square end function object:getModData() return {} end
function object:getComponent(kind) return kind=='CraftBench' and bench end
function object:getSprite() return {} end
function object:getProperties() return {get=function() end} end
function object:getUsingPlayer() return nil end
square.rows={object}
local request=Stations.search(f.entry,{recipe=recipe})
Index.invalidate(2,2)
local candidate
for _=1,160 do
    f.advance(Config.facilitiesMs) Index.tick(64)
    candidate=request:step(16)
    if candidate then break end
end
check(candidate and candidate.object==object and candidate.bench==bench,
    'shared bounded facility scan discovers CraftBench from its actual recipe list')
check(candidate.id==nil,'read-only discovery does not assign a furniture identity')
local other=Stations.search(f.entry,{recipe={}})
for _=1,160 do
    f.advance(Config.facilitiesMs) Index.tick(64)
    local mismatch=other:step(16)
    check(not mismatch,'another recipe cannot use a bench merely by furniture type')
    if not Index.pending(Index.watch(f.entry,Index.describe)) then break end
end
print('PASS '..checks..' shared craft-station index checks; engine objects mocked')
