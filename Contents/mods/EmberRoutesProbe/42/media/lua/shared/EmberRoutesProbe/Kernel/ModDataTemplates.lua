-- Default templates and version gates for persisted tables.
-- Every persisted table carries format=1 (the table version key, starting at
-- 1, same caliber as the schemaVersion gates on code-loaded data tables) and
-- a default template. A load entry opens its table through this module: a
-- table with the current version and a missing field gets the template value;
-- a table with a wrong version, or a non-empty table with no version, is
-- refused with an explicit code and the stored table is left untouched.
-- Named sub-documents with their own load entry carry their own version key;
-- bare index maps (containers, craftSurfaces, quarantine maps, byId/byNpc
-- lookup maps) inherit their parent document's version and are filled by
-- that document's template. Required record contents are still validated by
-- the owning module after the open; this module only versions and fills.
local T={SCHEMA_VERSION=1}
local function copy(value)
    if type(value)~='table' then return value end
    local result={}
    for key,item in pairs(value) do result[key]=copy(item) end
    return result
end
T.templates={
    -- Work root fields owned by the Registry load entry.
    -- Work root has its own format: v2 requires the independent obligation ledger.
    work={format=2,containers={},craftSurfaces={}},
    -- Work root fields owned by LaborStore (applied there, not by Registry).
    -- quarantineAudit is deliberately absent: it is created lazily by the
    -- first successful unquarantine, so a failed release writes no audit
    -- structure at all.
    workLabor={quarantineResources={},nextClaimSeq=1},
    settlements={format=1,entries={},revision=0},
    logistics={format=1,entries={},workers={}},
    logisticsEntry={intake=true,tidy=true,revision=0,workers={}},
    customKits={format=1,kits={}},
    taskJobs={format=1,byId={}},
    maintainStock={format=1,revision=0,rules={}},
    jobPolicies={format=1,revision=0,byScope={}},
    publicWork={format=1,sequence=0,orders={},priorities={},rules={},requests={}},
    deliveryOrders={format=1,orders={}},
    communityActivities={format=1,revision=0,events={}},
    publicLifeZones={format=1,revision=0,byId={}},
    careCommandEpochs={format=1,byNpc={}},
    companionIntents={format=1,byNpc={}},
    containerTag={format=1},
}
function T.fresh(name)
    local template=T.templates[name]
    assert(type(template)=='table','MODDATA_TEMPLATE_MISSING')
    return copy(template)
end
function T.empty(value)
    if type(value)~='table' then return false end
    for _ in pairs(value) do return false end
    return true
end
-- Fill every nil field from the template (deep copy, so two opened tables
-- never share one default table). Present fields, even wrong-typed ones, are
-- left for the owning module's validation.
function T.fill(target,template)
    for key,value in pairs(template) do
        if target[key]==nil then target[key]=copy(value) end
    end
    return target
end
-- Version-only gate. No write: a refused table is returned untouched, so a
-- caller can still assert the stored table kept its shape and identity.
function T.checkVersion(value,code)
    if type(value)~='table' then return false,code end
    if value.format==nil then
        if T.empty(value) then return true end
        return false,code
    end
    if value.format~=T.SCHEMA_VERSION then return false,code end
    return true
end
-- Gate + fill. An empty table is a new table: stamp the version and fill.
-- A non-empty table without a version, or a wrong version, is refused.
function T.open(value,template,code)
    local ok,why=T.checkVersion(value,code)
    if not ok then return false,why end
    if value.format==nil then value.format=T.SCHEMA_VERSION end
    T.fill(value,template)
    return true
end
return T
