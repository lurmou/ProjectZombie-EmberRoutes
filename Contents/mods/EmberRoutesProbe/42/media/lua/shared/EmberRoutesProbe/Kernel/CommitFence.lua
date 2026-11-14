-- Session-local response to an ambiguous authoritative write. This is not
-- saved evidence and cannot make a partially committed world safe by itself.
local F={}
local world,reason
function F.enter(root)
    if root~=world then world,reason=root,nil end
end
function F.block(root,why)
    if world~=root then world=root end
    reason=reason or tostring(why or 'COMMIT_EFFECT_UNKNOWN')
end
function F.status() return reason end
return F
