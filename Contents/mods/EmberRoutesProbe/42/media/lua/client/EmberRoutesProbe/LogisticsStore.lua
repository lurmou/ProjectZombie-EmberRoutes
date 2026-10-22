local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Store={}
function Store.data()
    local root=ModData.getOrCreate("EmberRoutes/Logistics/v1")
    if root.format and root.format~=1 then error("LOGISTICS_FORMAT_UNSUPPORTED") end
    root.format=1 root.entries=root.entries or {} root.workers=root.workers or {}
    return root
end
function Store.get(id)
    local root=Store.data() local entry=root.entries[id]
    if not entry then entry={intake=true,tidy=true,revision=0,workers={}} root.entries[id]=entry end
    if type(entry.intake)~="boolean" or type(entry.tidy)~="boolean" or type(entry.workers)~="table"
        or type(entry.revision)~="number" then error("LOGISTICS_RECORD_INVALID") end
    return entry
end
function Store.mode(actor,id,mode)
    local settlement,reason=Ledger.view(actor,id)
    if not settlement then return nil,reason end
    if mode~="intake" and mode~="tidy" then return nil,"INVALID_MODE" end
    local entry=Store.get(id) entry[mode]=not entry[mode] entry.revision=entry.revision+1
    return entry
end
function Store.view(id)
    local entry=Store.get(id) local copy={intake=entry.intake,tidy=entry.tidy,revision=entry.revision,workers={}}
    for npcId in pairs(entry.workers) do copy.workers[#copy.workers+1]=npcId end
    table.sort(copy.workers) return copy
end
function Store.worker(actor,id,npcId,enabled)
    local settlement,reason=Ledger.view(actor,id)
    if not settlement then return nil,reason end
    if type(npcId)~="string" or npcId=="" or type(enabled)~="boolean" then return nil,"INVALID_WORKER" end
    local root=Store.data() local entry=Store.get(id)
    local previous=root.workers[npcId]
    if previous and previous~=id then return nil,"WORKER_OTHER_SETTLEMENT" end
    entry.workers[npcId]=enabled or nil root.workers[npcId]=enabled and id or nil entry.revision=entry.revision+1
    return entry
end
return Store
