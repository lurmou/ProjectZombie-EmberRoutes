-- Ordinary outdoor work uses the existing Job envelope, not a private ledger.
local Validate=require 'EmberRoutesProbe/Validate'
local R={}
local categories={cleaning=true,farming=true,lumberjack=true,forager=true}
function R.valid(j)
    if type(j)~='table' or j.providerType~='FIELD_WORK' or type(j.payload)~='table' then return false end
    local p=j.payload local t=p.target
    if p.format~=1 or not categories[p.category] or not Validate.stringId(p.offerKey)
        or not Validate.integer(p.sequence, 0)
        or type(p.claims)~='table' or #p.claims>128 or type(p.assets)~='table' or #p.assets>96
        or type(t)~='table' or not Validate.coord(t.x) or not Validate.coord(t.y) or not Validate.coord(t.z)
        or type(t.kind)~='string' or type(t.identity)~='string'
        or (p.phase~='WORK' and p.phase~='COLLECT' and p.phase~='DELIVER' and p.phase~='SETTLED') then return false end
    local seen={}
    for _,key in ipairs(p.claims) do if type(key)~='string' or seen[key] then return false end seen[key]=true end
    seen={}
    for _,a in ipairs(p.assets) do
        if not Validate.itemId(a.id) or seen[a.id] or type(a.fullType)~='string'
            or (a.custody~='GROUND' and a.custody~='HELD' and a.custody~='DELIVERED') then return false end
        if a.custody~='DELIVERED' and not (function()
            for _,key in ipairs(p.claims) do if key=='item:'..a.id then return true end end
        end)() then return false end
        seen[a.id]=true
    end
    local a=p.attempt
    if a and (type(a)~='table' or type(a.id)~='string' or type(a.kind)~='string'
        or (a.state~='PREPARED' and a.state~='APPLIED' and a.state~='ABORTED' and a.state~='UNKNOWN')) then return false end
    if j.state=='DONE' or j.state=='CANCELLED' then
        if p.phase~='SETTLED' or #p.claims>0 or p.holding or p.capacity then return false end
        for _,asset in ipairs(p.assets) do if asset.custody~='DELIVERED' then return false end end
    end
    return true
end
function R.asset(j,id) for _,a in ipairs(j.payload.assets) do if a.id==id then return a end end end
function R.addClaim(p,key)
    for _,k in ipairs(p.claims) do if k==key then return end end
    p.claims[#p.claims+1]=key
end
function R.dropClaim(p,key)
    for i=#p.claims,1,-1 do if p.claims[i]==key then table.remove(p.claims,i) end end
end
return R
