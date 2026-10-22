local Geometry={MAX_SIDE=128}
local function coordinate(n)
    return type(n)=="number" and n==n and math.abs(n)<=10000000 and n==math.floor(n)
end
function Geometry.rectangle(x1,y1,x2,y2)
    if not coordinate(x1) or not coordinate(y1) or not coordinate(x2) or not coordinate(y2) then return nil,"INVALID_BOUNDS" end
    local r={x=math.min(x1,x2),y=math.min(y1,y2),w=math.abs(x2-x1)+1,h=math.abs(y2-y1)+1}
    if r.w>Geometry.MAX_SIDE or r.h>Geometry.MAX_SIDE then return nil,"AREA_LIMIT" end
    return r
end
function Geometry.valid(r)
    return type(r)=="table" and coordinate(r.x) and coordinate(r.y) and coordinate(r.w) and coordinate(r.h)
        and r.w>=1 and r.h>=1 and r.w<=Geometry.MAX_SIDE and r.h<=Geometry.MAX_SIDE
end
function Geometry.contains(r,x,y)
    return x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h
end
function Geometry.inside(settlement,x,y)
    for _,r in ipairs(settlement.areas) do if Geometry.contains(r,x,y) then return true end end
    return false
end
function Geometry.overlap(a,b,gap)
    gap=gap or 0
    return a.x<b.x+b.w+gap and a.x+a.w+gap>b.x and a.y<b.y+b.h+gap and a.y+a.h+gap>b.y
end
return Geometry
