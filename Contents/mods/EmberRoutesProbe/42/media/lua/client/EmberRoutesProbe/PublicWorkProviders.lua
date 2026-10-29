-- Internal registry for public ordinary-work providers.
-- Each provider contributes discovery, claim execution, reconcile, and optional
-- idle/clean routines for a distinct workCategory (e.g. 'crafting', 'hauling', 'cooking').
local Registry={}
local defs={}
local order={}

function Registry.register(def)
    if type(def)~='table' or type(def.category)~='string' or #def.category<1 or #def.category>32
        or (def.defaultPriority~=nil and (type(def.defaultPriority)~='number' or def.defaultPriority<0 or def.defaultPriority>4)) then
        return false,'PROVIDER_INVALID'
    end
    if not defs[def.category] then
        order[#order+1]=def.category
    end
    defs[def.category]=def
    return true
end

function Registry.get(category)
    return defs[category]
end

function Registry.has(category)
    return defs[category]~=nil
end

function Registry.categories()
    local copy={}
    for i,cat in ipairs(order) do copy[i]=cat end
    return copy
end

function Registry.all()
    local list={}
    for _,cat in ipairs(order) do list[#list+1]=defs[cat] end
    return list
end

function Registry.reset()
    defs={}
    order={}
end

return Registry
