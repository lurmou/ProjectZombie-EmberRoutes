local Geometry={MAX_SIDE=128,MAX_AREAS=32}
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
    if type(settlement)~='table' or type(settlement.areas)~='table' then return false end
    for _,r in ipairs(settlement.areas) do if Geometry.valid(r) and Geometry.contains(r,x,y) then return true end end
    return false
end
-- Optional floor belongs to work/life zones; settlement territory remains 2D.
function Geometry.cloneArea(r)
    if not Geometry.valid(r) or r.z~=nil and not coordinate(r.z) then return nil end
    return {x=r.x,y=r.y,w=r.w,h=r.h,z=r.z}
end
function Geometry.overlap(a,b,gap)
    gap=gap or 0
    return a.x<b.x+b.w+gap and a.x+a.w+gap>b.x and a.y<b.y+b.h+gap and a.y+a.h+gap>b.y
end
function Geometry.cloneAreas(areas)
    local copy={}
    if areas then
        for _,r in ipairs(areas) do
            local area=Geometry.cloneArea(r)
            if area then copy[#copy+1]=area end
        end
    end
    return copy
end
function Geometry.totalTiles(areas)
    if not areas then return 0 end
    local count=0
    for _,r in ipairs(areas) do
        if Geometry.valid(r) then count=count+(r.w*r.h) end
    end
    return count
end
---@param A {x:number,y:number,w:number,h:number}
---@param B {x:number,y:number,w:number,h:number}
---@return {x:number,y:number,w:number,h:number}[]
function Geometry.subtract(A,B)
    if not Geometry.valid(A) then return {} end
    if not Geometry.valid(B) or A.z~=nil and B.z~=nil and A.z~=B.z then return {Geometry.cloneArea(A)} end
    local Ax1,Ay1,Ax2,Ay2=A.x,A.y,A.x+A.w,A.y+A.h
    local Bx1,By1,Bx2,By2=B.x,B.y,B.x+B.w,B.y+B.h
    local Ix1=math.max(Ax1,Bx1)
    local Iy1=math.max(Ay1,By1)
    local Ix2=math.min(Ax2,Bx2)
    local Iy2=math.min(Ay2,By2)
    if Ix1>=Ix2 or Iy1>=Iy2 then return {Geometry.cloneArea(A)} end
    local result={}
    if Iy1>Ay1 then result[#result+1]={x=Ax1,y=Ay1,w=Ax2-Ax1,h=Iy1-Ay1} end
    if Ay2>Iy2 then result[#result+1]={x=Ax1,y=Iy2,w=Ax2-Ax1,h=Ay2-Iy2} end
    if Ix1>Ax1 then result[#result+1]={x=Ax1,y=Iy1,w=Ix1-Ax1,h=Iy2-Iy1} end
    if Ax2>Ix2 then result[#result+1]={x=Ix2,y=Iy1,w=Ax2-Ix2,h=Iy2-Iy1} end
    for _,part in ipairs(result) do part.z=A.z end
    return result
end
---@param areas {x:number,y:number,w:number,h:number}[]
---@return {x:number,y:number,w:number,h:number}[]
function Geometry.compact(areas)
    if not areas or #areas<=1 then return Geometry.cloneAreas(areas or {}) end
    local list=Geometry.cloneAreas(areas)
    local merged=true
    while merged do
        merged=false
        local len=#list
        for i=1,len-1 do
            local a=list[i]
            if a then
                for j=i+1,len do
                    local b=list[j]
                    if b and a.z==b.z then
                        if a.x==b.x and a.w==b.w and (a.y+a.h==b.y or b.y+b.h==a.y) and (a.h+b.h<=Geometry.MAX_SIDE) then
                            list[i]={x=a.x,y=math.min(a.y,b.y),w=a.w,h=a.h+b.h,z=a.z}
                            table.remove(list,j)
                            merged=true
                            break
                        elseif a.y==b.y and a.h==b.h and (a.x+a.w==b.x or b.x+b.w==a.x) and (a.w+b.w<=Geometry.MAX_SIDE) then
                            list[i]={x=math.min(a.x,b.x),y=a.y,w=a.w+b.w,h=a.h,z=a.z}
                            table.remove(list,j)
                            merged=true
                            break
                        end
                    end
                end
                if merged then break end
            end
        end
    end
    return list
end
---@param areas {x:number,y:number,w:number,h:number}[]
---@param cutRect {x:number,y:number,w:number,h:number}
---@return {x:number,y:number,w:number,h:number}[]
function Geometry.subtractFromList(areas,cutRect)
    if not areas or #areas==0 then return {} end
    if not Geometry.valid(cutRect) then return Geometry.cloneAreas(areas) end
    local result={}
    for _,rect in ipairs(areas) do
        local parts=Geometry.subtract(rect,cutRect)
        for _,part in ipairs(parts) do result[#result+1]=part end
    end
    return Geometry.compact(result)
end
---@param areas {x:number,y:number,w:number,h:number}[]
---@param newRect {x:number,y:number,w:number,h:number}
---@return {x:number,y:number,w:number,h:number}[]
function Geometry.addToList(areas,newRect)
    if not Geometry.valid(newRect) then return Geometry.cloneAreas(areas or {}) end
    local result=Geometry.cloneAreas(areas or {})
    local additions={Geometry.cloneArea(newRect)}
    for _,existing in ipairs(result) do
        local nextAdditions={}
        for _,piece in ipairs(additions) do
            local parts=Geometry.subtract(piece,existing)
            for _,part in ipairs(parts) do nextAdditions[#nextAdditions+1]=part end
        end
        additions=nextAdditions
        if #additions==0 then break end
    end
    for _,piece in ipairs(additions) do result[#result+1]=piece end
    return Geometry.compact(result)
end
return Geometry
