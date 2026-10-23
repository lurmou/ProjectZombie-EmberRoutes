-- Pure ordinary-work ordering. Urgent/personal arbitration is outside this
-- selector and may never be outweighed by distance or waiting time.
local Selector={}
function Selector.choose(candidates,priorities)
    local best,bestPriority
    for _,c in ipairs(candidates) do
        local p=priorities[c.category]
        if p and p>=1 and p<=4 and c.allowed==true then
            local score=c.score or 0
            if not best or p<bestPriority or p==bestPriority and
                (score>(best.score or 0) or score==(best.score or 0) and c.key<best.key) then
                best,bestPriority=c,p
            end
        end
    end
    return best
end
return Selector
