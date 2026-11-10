local Ledger=require "EmberRoutesProbe/Settlement/SettlementLedger"
local Templates=require "EmberRoutesProbe/Kernel/ModDataTemplates"
local Store={}
function Store.data()
    local root=ModData.getOrCreate("EmberRoutes/Logistics/v1")
    -- A non-empty table without a version, or a wrong version, is refused
    -- with an explicit code; the stored table is left untouched. The old
    -- unconditional stamp is gone: it labelled any table as current.
    local ok,why=Templates.open(root,Templates.templates.logistics,'LOGISTICS_FORMAT_UNSUPPORTED')
    if not ok then error(why) end
    if type(root.entries)~='table' or type(root.workers)~='table' then error('LOGISTICS_FORMAT_UNSUPPORTED') end
    return root
end
function Store.get(id)
    local root=Store.data() local entry=root.entries[id]
    if not entry then entry=Templates.fresh('logisticsEntry') root.entries[id]=entry end
    -- Missing entry fields take the template values; wrong-typed fields are
    -- still refused below.
    Templates.fill(entry,Templates.templates.logisticsEntry)
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
