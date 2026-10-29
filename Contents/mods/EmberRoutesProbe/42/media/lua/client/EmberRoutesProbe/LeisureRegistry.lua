-- Internal registry for idle activity definitions. Deliberately NOT a public
-- modding API: the def shape stabilizes with the 4.5 activity system, then the
-- public registerActivity surface gets its own design pass.
-- def: { id (unique, 1..32 chars), budget ('paths'|'scan'),
--        seek = function(env) -> candidate|nil, done, reason }
-- env:  actor, binding, id, npc, offer, entry, s, hours, point, budget,
--       cooling, now, state (def-private bucket on the offer).
-- Return protocol: candidate contributes to the bounded pool; done==false
-- Optional lifecycle and pure review(env) support continuity. Reviews must
-- never reserve, invite, consume, or move. Unknown lifecycle defaults to finite.
-- policyAtTarget is for transport-only discovery: seek must validate destination
-- policy itself; ordinary activity permissions are not applied to transit origin.
-- retains discovery state for the next decision without vetoing other activities.
-- Reserved SOCIAL is the continuity exception; nil,true has no candidate.
local Registry={}
local defs,order={},{}
function Registry.define(def)
    if type(def)~='table' or type(def.id)~='string' or #def.id<1 or #def.id>32
        or (def.budget~='paths' and def.budget~='scan')
        or type(def.seek)~='function' or defs[def.id] then return false,'DEF_INVALID' end
    defs[def.id]=def order[#order+1]=def
    return true
end
function Registry.all() return order end
function Registry.get(id) return defs[id] end
return Registry
