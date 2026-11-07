-- Shared native crafting-surface proximity guard.
local Rules=require "EmberRoutesProbe/Hauling/HaulRules"
local Adapter={}
function Adapter.atBench(character,object)
    local square=object and object:getSquare()
    local current=character and character:getCurrentSquare()
    local cell=getCell()
    return square and current and cell and cell:getGridSquare(square:getX(),square:getY(),square:getZ())==square
        and square:getObjects():contains(object) and current:canReachTo(square)
        and Rules.near(character:getX(),character:getY(),character:getZ(),square:getX()+0.5,square:getY()+0.5,square:getZ())
end
return Adapter
