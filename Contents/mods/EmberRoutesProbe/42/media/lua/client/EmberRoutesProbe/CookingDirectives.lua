-- Read-only settlement directives. Existing duties retain their cleanup authority.
local Policy=require 'EmberRoutesProbe/JobPolicyService'
local Spatial=require 'EmberRoutesProbe/FieldSpatial'
local D={}
function D.kitchen(scope,object)
    local p=Policy.get(scope,'cooking')
    if not p.kitchenZoneId or p.kitchenZoneId=='' then return true end
    local entry=require('EmberRoutesProbe/SettlementLedger').get(scope)
    local sq=object and object:getSquare()
    return entry and sq and Spatial.inside(entry,p.kitchenZoneId,sq:getX(),sq:getY(),sq:getZ()) or false
end
function D.less(scope)
    local strategy=Policy.get(scope,'cooking').spoilageStrategy or 'EXPIRE_SOON_FIRST'
    local function remaining(item)
        if not instanceof(item,'Food') then return math.huge end
        local off=item:getOffAgeMax()
        if not off or off<=0 or off>=1000000000 then return math.huge end
        return math.max(0,off-item:getAge())
    end
    return function(a,b)
        if strategy~='ANY_SAFE' then
            local x,y=remaining(a.item),remaining(b.item)
            if x~=y then
                if strategy=='FRESH_FIRST' then return x>y end
                return x<y
            end
        end
        return a.item:getID()<b.item:getID()
    end
end
return D
