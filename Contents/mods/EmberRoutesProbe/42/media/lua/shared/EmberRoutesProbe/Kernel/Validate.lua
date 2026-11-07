-- Pure orthogonal validation primitives for durable records and schemas.
-- Shared between client and server, zero allocations on primitive checks.
local Validate={}

Validate.MAX_COORD = 10000000
Validate.MAX_SAFE_INT = 9007199254740991
Validate.MAX_STRING_ID_LEN = 256

function Validate.finite(v, min, max)
    if type(v)~='number' or v~=v or math.abs(v)==math.huge then return false end
    if min~=nil and v<min then return false end
    if max~=nil and v>max then return false end
    return true
end

function Validate.integer(v, min, max)
    if not Validate.finite(v, min, max) then return false end
    return v==math.floor(v)
end

function Validate.stringId(v, maxLen)
    if type(v)~='string' or #v==0 or #v>(maxLen or Validate.MAX_STRING_ID_LEN) then return false end
    return true
end

function Validate.itemId(v)
    return Validate.integer(v, 0, Validate.MAX_SAFE_INT)
end

function Validate.coord(v)
    return Validate.integer(v, -Validate.MAX_COORD, Validate.MAX_COORD)
end

function Validate.dense(t, limit)
    if type(t)~='table' or #t>(limit or 1024) then return false end
    local count=0
    for k in pairs(t) do
        if not Validate.integer(k, 1, #t) then return false end
        count=count+1
    end
    return count==#t
end

return Validate
