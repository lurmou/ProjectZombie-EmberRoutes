-- Serializable furniture identity; independent of world handles or UI.
local Record={}
local function id(v) return type(v)=='string' and #v>0 and #v<=256 end
function Record.valid(p)
    if type(p)~='table' or not id(p.id) or not id(p.partId)
        or type(p.revision)~='number' or p.revision<1 or p.revision>1e12 or p.revision~=math.floor(p.revision)
        or type(p.parts)~='table' or #p.parts<1 or #p.parts>16
        or p.key~=nil and type(p.key)~='string' then return false end
    local seen,target={},false
    for _,part in ipairs(p.parts) do
        if type(part)~='table' or not id(part.id) or seen[part.id] then return false end
        seen[part.id]=true target=target or part.id==p.partId
        for _,axis in ipairs({'x','y','z'}) do
            local v=part[axis]
            if type(v)~='number' or v~=v or math.abs(v)>10000000 or v~=math.floor(v) then return false end
        end
    end
    return target
end
return Record
