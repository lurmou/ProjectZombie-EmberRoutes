-- Player-owned UI draft. Business orders and request receipts remain PublicWork's authority.
local Public=require 'EmberRoutesProbe/PublicWork'
local Draft={}
local function copy(t) local r={} for k,v in pairs(t or {}) do r[k]=v end return r end
local function same(a,b)
    for k,v in pairs(a or {}) do if (b or {})[k]~=v then return false end end
    for k,v in pairs(b or {}) do if (a or {})[k]~=v then return false end end
    return true
end
function Draft.read(actor,scope)
    if not actor or not actor.getModData then return nil end
    local drafts=actor:getModData().EmberRoutesPublicOrderDrafts
    local d=drafts and drafts[scope]
    if type(d)~='table' or d.scope~=scope then return nil end
    return {scope=d.scope,recipe=d.recipe,quantity=d.quantity,surface=d.surface,
        preferences=copy(d.preferences),requestId=d.requestId,result=d.result,product=d.product}
end
function Draft.update(actor,scope,recipe,quantity,surface,preferences,product)
    assert(actor and actor.getModData,'Public order draft requires player ModData')
    local d=Draft.read(actor,scope)
    if not d or d.recipe~=recipe or d.quantity~=quantity or d.surface~=surface
        or not same(d.preferences,preferences) then
        d={scope=scope,recipe=recipe,quantity=quantity,surface=surface,
            preferences=copy(preferences),requestId=Public.requestId(),product=product}
    end
    local meta=actor:getModData()
    meta.EmberRoutesPublicOrderDrafts=meta.EmberRoutesPublicOrderDrafts or {}
    meta.EmberRoutesPublicOrderDrafts[scope]=d
    return d
end
function Draft.result(actor,scope,requestId,result)
    local drafts=actor:getModData().EmberRoutesPublicOrderDrafts
    local d=drafts and drafts[scope]
    if d and d.requestId==requestId then d.result=result end
end
return Draft
