-- Container-level invalidation only. Event callbacks never plan or dispatch.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Membership=require 'EmberRoutesProbe/SettlementMembership'
local Wake={}
local world,containers,scopes,unknown=nil,{},{},0
local revision=0
-- Cheap notification generation for the existing dispatcher. This is only a
-- wake hint; capture/changed still fence each request's exact dependencies.
function Wake.revision() return revision end
local function load()
    local root=Registry.data()
    if root~=world then world,containers,scopes,unknown=root,{},{},0 revision=revision+1 end
end
function Wake.capture(entry)
    load()
    local count=0 for _ in pairs(containers) do count=count+1 end
    if count>512 then containers={} unknown=unknown+1 end
    local token={world=world,scope=entry.id,scopeRevision=scopes[entry.id] or 0,unknown=unknown,ids={}}
    for _,id in ipairs(Membership.query(entry) or {}) do
        containers[id]=containers[id] or 0 token.ids[id]=containers[id]
    end
    return token
end
function Wake.changed(token)
    load()
    if token.world~=world or token.unknown~=unknown or token.scopeRevision~=(scopes[token.scope] or 0) then return true end
    for id,revision in pairs(token.ids) do if revision~=(containers[id] or 0) then return true end end
    return false
end
local function changed(id)
    load()
    if not id then unknown=unknown+1 revision=revision+1
    -- Keep only dependencies currently observed by planning, not arbitrary events.
    elseif containers[id]~=nil then containers[id]=containers[id]+1 revision=revision+1 end
end
if Registry.listeners then Registry.listeners[#Registry.listeners+1]=changed end
if Registry.inventoryListeners then Registry.inventoryListeners[#Registry.inventoryListeners+1]=changed end
if Ledger.listeners then Ledger.listeners[#Ledger.listeners+1]=function(id)
    load() scopes[id]=(scopes[id] or 0)+1 revision=revision+1
end end
if Events and Events.OnContainerUpdate then Events.OnContainerUpdate.Add(function(object)
    local ids=Registry.affected(object)
    if not ids then changed(nil) else for _,id in ipairs(ids) do changed(id) end end
end) end
return Wake
