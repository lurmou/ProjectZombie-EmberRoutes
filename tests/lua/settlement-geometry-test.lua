package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local n=0
local function check(value,why) n=n+1 assert(value,why) end
local Geometry=require "EmberRoutesProbe/SettlementGeometry"

-- 1. Test basic rectangle & totalTiles
local r1 = assert(Geometry.rectangle(0, 0, 9, 9))
check(r1.x == 0 and r1.y == 0 and r1.w == 10 and r1.h == 10, "10x10 rect created")
check(Geometry.totalTiles({r1}) == 100, "totalTiles is 100")

-- 2. Test Geometry.subtract
-- Cutout hole in the center (from 2,2 to 5,5 -> w=4, h=4 -> 16 tiles)
local cutCenter = assert(Geometry.rectangle(2, 2, 5, 5))
local subParts = Geometry.subtract(r1, cutCenter)
check(#subParts == 4, "center cutout produces 4 slices")
check(Geometry.totalTiles(subParts) == 84, "center cutout leaves 84 tiles")

-- 3. Test subtraction completely covering
local bigCut = assert(Geometry.rectangle(-5, -5, 15, 15))
local emptyParts = Geometry.subtract(r1, bigCut)
check(#emptyParts == 0, "complete cover leaves 0 slices")

-- 4. Test subtraction with no overlap
local disjointCut = assert(Geometry.rectangle(20, 20, 25, 25))
local noOpParts = Geometry.subtract(r1, disjointCut)
check(#noOpParts == 1 and noOpParts[1].w == 10 and noOpParts[1].h == 10, "disjoint cutout leaves rect unchanged")

-- 5. Test subtraction from a list of areas
-- Area A: (0,0, 10x10), Area B: (20,0, 10x10)
local areas = { {x=0, y=0, w=10, h=10}, {x=20, y=0, w=10, h=10} }
check(Geometry.totalTiles(areas) == 200, "two disjoint 10x10 areas = 200 tiles")
-- Cut spanning across x=5..25, y=0..10
local cutSpan = {x=5, y=0, w=20, h=10}
local remaining = Geometry.subtractFromList(areas, cutSpan)
-- Area A lost right 5 cols (x=5..10), remaining x=0..5 (w=5, h=10) = 50 tiles
-- Area B lost left 5 cols (x=20..25), remaining x=25..30 (w=5, h=10) = 50 tiles
check(Geometry.totalTiles(remaining) == 100, "subtractFromList removed 100 tiles from both areas")
check(#remaining == 2, "2 remaining disjoint rects")

-- 6. Test Geometry.addToList (disjoint union & compaction)
local list = {}
list = Geometry.addToList(list, {x=0, y=0, w=10, h=10})
check(Geometry.totalTiles(list) == 100 and #list == 1, "added first rect")
-- Add overlapping rect (x=5, y=0, w=10, h=10) -> total x=0..15, w=15, h=10
list = Geometry.addToList(list, {x=5, y=0, w=10, h=10})
check(Geometry.totalTiles(list) == 150, "overlapping addition does not double count")
check(#list == 1 and list[1].w == 15 and list[1].h == 10, "adjacent overlapping rects compacted into 1")

-- 7. Test L-shape irregular territory
local lShape = {}
lShape = Geometry.addToList(lShape, {x=0, y=0, w=10, h=20})
lShape = Geometry.addToList(lShape, {x=10, y=0, w=10, h=10})
check(Geometry.totalTiles(lShape) == 300, "L-shape has 300 tiles")
check(#lShape == 2, "L-shape cleanly represented by 2 rectangles")
check(Geometry.inside({areas=lShape}, 5, 15), "inside lower leg of L-shape")
check(Geometry.inside({areas=lShape}, 15, 5), "inside arm of L-shape")
check(not Geometry.inside({areas=lShape}, 15, 15), "outside corner of L-shape")

-- 8. Test removing part of L-shape
lShape = Geometry.subtractFromList(lShape, {x=0, y=10, w=10, h=10})
check(Geometry.totalTiles(lShape) == 200, "cutout removed 100 tiles from L-shape")
check(not Geometry.inside({areas=lShape}, 5, 15), "no longer inside cut region")

local upper={x=0,y=0,w=10,h=10,z=2}
check(Geometry.cloneArea(upper).z==2,'single-zone clone retains floor')
local cut=Geometry.subtractFromList({upper},{x=2,y=2,w=4,h=4,z=2})
for _,part in ipairs(cut) do check(part.z==2,'CSG slice retains floor') end
local floors=Geometry.addToList({upper},{x=0,y=0,w=10,h=10,z=3})
check(#floors==2 and Geometry.totalTiles(floors)==200,'different floors never merge or erase')
check(not Geometry.inside({},0,0),'invalid territory grants no coordinates')
print("PASS " .. n .. " settlement geometry irregular and boolean checks")
