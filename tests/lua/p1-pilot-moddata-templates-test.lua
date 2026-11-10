-- P1 pilot 10/15: ModData default templates + version key (Minecraft
-- data-driven tables, localized). Every persisted table carries format=1
-- (the table version key, starting at 1, same caliber as pilot 6's
-- schemaVersion) and a default template. A table with the current version
-- and a missing field takes the template value on read; a wrong version, or
-- a non-empty table without one, is refused with an explicit code and the
-- stored table is left untouched. Run from the repo root:
-- lua tests/lua/p1-pilot-moddata-templates-test.lua
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;" .. package.path
DebugLog = { log = function() end }
function getText(key) return key end
function getRandomUUID() return 'uuid-test' end
local n = 0
local function check(v, s) n = n + 1 assert(v, s) end
local function copy(t)
    if type(t) ~= 'table' then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = copy(v) end
    return r
end
local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- (1) Helper: version gate + fill, no silent relabel.
local Templates = require 'EmberRoutesProbe/Kernel/ModDataTemplates'
check(Templates.SCHEMA_VERSION == 1, 'ModDataTemplates SCHEMA_VERSION is 1')
check(Templates.checkVersion({}, 'X'), 'empty table passes the version gate (new table)')
check(not Templates.checkVersion({ a = 1 }, 'X'), 'non-empty table without a version fails the gate')
check(Templates.checkVersion({ format = 1 }, 'X'), 'format 1 passes the gate')
check(not Templates.checkVersion({ format = 2 }, 'X'), 'format 2 fails the gate')
check(not Templates.checkVersion('x', 'X'), 'non-table fails the gate')
local stamped = {}
check(Templates.open(stamped, Templates.templates.work, 'X') and stamped.format == 1
    and type(stamped.containers) == 'table', 'empty table is stamped and filled on open')
local filled = { format = 1 }
check(Templates.open(filled, Templates.templates.work, 'X') and type(filled.containers) == 'table'
    and type(filled.craftSurfaces) == 'table', 'missing fields on a versioned table take template values')
local kept = { format = 1, containers = { c = 1 } }
check(Templates.open(kept, Templates.templates.work, 'X') and kept.containers.c == 1,
    'present fields are never overwritten by the template')
local wrong, before = { format = 2, containers = {} }, nil
before = copy(wrong)
local ok, code = Templates.open(wrong, Templates.templates.work, 'WORK_FORMAT_UNSUPPORTED')
check(not ok and code == 'WORK_FORMAT_UNSUPPORTED' and same(wrong, before),
    'wrong version is refused with a code and the stored table is untouched')
local unversioned = { containers = { c = 1 } }
before = copy(unversioned)
ok, code = Templates.open(unversioned, Templates.templates.work, 'WORK_FORMAT_UNSUPPORTED')
check(not ok and code == 'WORK_FORMAT_UNSUPPORTED' and same(unversioned, before),
    'non-empty table without a version is refused and untouched')
local freshA, freshB = Templates.fresh('work'), Templates.fresh('work')
check(freshA ~= freshB and freshA.containers ~= freshB.containers, 'fresh templates are independent copies')
freshA.containers.x = 1
check(freshB.containers.x == nil, 'filling one table never writes another template copy')

-- (2) Work root + container tags, through the real Registry load entry.
local worlds = {}
ModData = { getOrCreate = function(key)
    if not worlds[key] then worlds[key] = {} end
    return worlds[key]
end }
EmberRoutesProbeJava = {}
local Registry = require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
worlds['EmberRoutes/Work/v1'] = {}
local root = Registry.data()
check(root.format == 1 and type(root.containers) == 'table' and type(root.craftSurfaces) == 'table'
    and root.taskJobs == nil, 'empty Work root initializes from the template; no job ledger is published')
worlds['EmberRoutes/Work/v1'] = { format = 1 }
root = Registry.data()
check(type(root.containers) == 'table' and type(root.craftSurfaces) == 'table',
    'Work root with the current version but missing maps takes the template maps')
worlds['EmberRoutes/Work/v1'] = { format = 2, containers = {} }
before = copy(worlds['EmberRoutes/Work/v1'])
local okRoot, whyRoot = pcall(Registry.data)
check(not okRoot and tostring(whyRoot):find('WORK_FORMAT_UNSUPPORTED', 1, true)
    and same(worlds['EmberRoutes/Work/v1'], before), 'Work root format 2 is refused and untouched')
worlds['EmberRoutes/Work/v1'] = { containers = { c = 1 } }
before = copy(worlds['EmberRoutes/Work/v1'])
okRoot, whyRoot = pcall(Registry.data)
check(not okRoot and tostring(whyRoot):find('WORK_FORMAT_UNSUPPORTED', 1, true)
    and same(worlds['EmberRoutes/Work/v1'], before), 'non-empty Work root without a version is refused and untouched')
local md = { EmberRoutesContainer = { id = 't1', scopeId = 'local-world' } }
local container = {}
local object = { getContainer = function() return container end, getModData = function() return md end }
local tag = Registry.metadata(object, container)
check(tag and tag.format == 1 and tag.id == 't1', 'unversioned container tag takes the template version on read')
md.EmberRoutesContainer = { format = 2, id = 't2', scopeId = 'local-world' }
check(Registry.metadata(object, container) == nil, 'wrong-version container tag is not recognized')
check(md.EmberRoutesContainer.id == 't2', 'rejected tag record stays in ModData, untouched')

-- (3) Settlements root: missing revision/entries fill; wrong version refuses.
local Ledger = require 'EmberRoutesProbe/Settlement/SettlementLedger'
worlds['EmberRoutes/Settlements/v1'] = {}
local ledger = Ledger.data()
check(ledger.format == 1 and type(ledger.entries) == 'table' and ledger.revision == 0
    and type(ledger.factionId) == 'string', 'empty Settlements root initializes from the template')
worlds['EmberRoutes/Settlements/v1'] = { format = 1, entries = {} }
ledger = Ledger.data()
check(ledger.revision == 0, 'Settlements root with the current version but no revision takes 0')
worlds['EmberRoutes/Settlements/v1'] = { format = 2 }
before = copy(worlds['EmberRoutes/Settlements/v1'])
okRoot, whyRoot = pcall(Ledger.data)
check(not okRoot and tostring(whyRoot):find('SETTLEMENT_FORMAT_UNSUPPORTED', 1, true)
    and same(worlds['EmberRoutes/Settlements/v1'], before), 'Settlements root format 2 is refused and untouched')
worlds['EmberRoutes/Settlements/v1'] = { entries = { e = 1 } }
okRoot, whyRoot = pcall(Ledger.data)
check(not okRoot and tostring(whyRoot):find('SETTLEMENT_FORMAT_UNSUPPORTED', 1, true),
    'non-empty Settlements root without a version is refused, not silently stamped')

-- (4) Logistics root + per-entry defaults.
local Logistics = require 'EmberRoutesProbe/Logistics/LogisticsStore'
worlds['EmberRoutes/Logistics/v1'] = {}
local logRoot = Logistics.data()
check(logRoot.format == 1 and type(logRoot.entries) == 'table' and type(logRoot.workers) == 'table',
    'empty Logistics root initializes from the template')
worlds['EmberRoutes/Logistics/v1'] = { format = 1 }
logRoot = Logistics.data()
check(type(logRoot.entries) == 'table' and type(logRoot.workers) == 'table',
    'Logistics root with the current version but missing maps takes the template maps')
worlds['EmberRoutes/Logistics/v1'] = { format = 1, entries = { s = {} } }
local entry = Logistics.get('s')
check(entry.intake == true and entry.tidy == true and entry.revision == 0
    and type(entry.workers) == 'table', 'logistics entry with missing fields takes the entry template')
worlds['EmberRoutes/Logistics/v1'] = { format = 1, entries = { s = { intake = 'yes' } } }
okRoot, whyRoot = pcall(Logistics.get, 's')
check(not okRoot and tostring(whyRoot):find('LOGISTICS_RECORD_INVALID', 1, true),
    'wrong-typed logistics entry field is still refused, not filled over')
worlds['EmberRoutes/Logistics/v1'] = { format = 9 }
before = copy(worlds['EmberRoutes/Logistics/v1'])
okRoot, whyRoot = pcall(Logistics.data)
check(not okRoot and tostring(whyRoot):find('LOGISTICS_FORMAT_UNSUPPORTED', 1, true)
    and same(worlds['EmberRoutes/Logistics/v1'], before), 'Logistics root format 9 is refused and untouched')

-- (5) CustomKits: the old silent relabel is gone; wrong version refuses.
local Kits = require 'EmberRoutesProbe/Crafting/CustomKits'
worlds['EmberRoutes/CustomKits/v1'] = { format = 2, kits = {} }
before = copy(worlds['EmberRoutes/CustomKits/v1'])
okRoot, whyRoot = pcall(Kits.data)
check(not okRoot and tostring(whyRoot):find('CUSTOM_KITS_FORMAT_UNSUPPORTED', 1, true)
    and same(worlds['EmberRoutes/CustomKits/v1'], before),
    'CustomKits format 2 is refused and untouched, never silently relabelled as 1')
worlds['EmberRoutes/CustomKits/v1'] = { format = 1 }
local kits = Kits.data()
check(type(kits.kits) == 'table', 'CustomKits with the current version but no kits map takes the template map')
worlds['EmberRoutes/CustomKits/v1'] = {}
kits = Kits.data()
check(kits.format == 1 and type(kits.kits) == 'table', 'empty CustomKits root initializes from the template')

-- (6) StockStore sub-document: missing rules/revision fill; wrong version refuses.
worlds['EmberRoutes/Work/v1'] = { format = 1, containers = {}, taskJobs = { format = 1, byId = {} } }
local Stock = require 'EmberRoutesProbe/Warehouse/StockStore'
local stock = Stock.data()
check(stock.format == 1 and stock.revision == 0 and type(stock.rules) == 'table',
    'missing maintainStock is created from the template')
worlds['EmberRoutes/Work/v1'].maintainStock = { format = 1 }
stock = Stock.data()
check(stock.revision == 0 and type(stock.rules) == 'table',
    'maintainStock with the current version but missing fields takes the template values')
worlds['EmberRoutes/Work/v1'].maintainStock = { format = 2, rules = {} }
okRoot, whyRoot = pcall(Stock.data)
check(not okRoot and tostring(whyRoot):find('STOCK_STORE_CORRUPTED', 1, true),
    'maintainStock format 2 is refused with an explicit code')

-- (7) JobStore taskJobs: missing byId fills at read without touching the
-- stored carrier; wrong version refuses; check() stays read-only.
local Jobs = require 'EmberRoutesProbe/Kernel/JobStore'
check(Jobs.check({ taskJobs = { format = 1 } }), 'taskJobs with the current version but no byId reads as empty')
local raw = { taskJobs = { format = 1 } }
check(Jobs.check(raw) and raw.taskJobs.byId == nil, 'JobStore check never writes the missing byId back')
check(Jobs.check({ taskJobs = {} }), 'empty taskJobs table reads as a fresh ledger')
local badJobs, badWhy = Jobs.check({ taskJobs = { format = 99, byId = {} } })
check(not badJobs and badWhy == 'JOB_FORMAT_UNSUPPORTED', 'taskJobs format 99 is refused with a code')
badJobs, badWhy = Jobs.check({ taskJobs = { format = 1, byId = 5 } })
check(not badJobs and badWhy == 'JOB_FORMAT_UNSUPPORTED', 'wrong-typed taskJobs byId is refused')
local jobRoot = { nextClaimSeq = 0 }
local api = assert(Jobs.open(jobRoot))
check(api:create({ id = 'current', npcId = 'a', providerType = 'TEST', scopeId = 'world', revision = 1,
    state = 'PREPARING', effects = 'KNOWN', obligations = {}, payload = { proof = true } }),
    'job creation still works on a ledger opened from the template')
check(jobRoot.taskJobs.format == 1 and jobRoot.taskJobs.byId.current ~= nil,
    'opened ledger publishes the versioned carrier')

-- (8) LaborStore: root labor fields + custody document, through the real
-- Store.data() restore path.
local laborRoot = { format = 1, containers = {}, taskJobs = { format = 1, byId = {} } }
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry'] =
    { data = function() return laborRoot end, id = function() return 'custody-1' end }
package.loaded['EmberRoutesProbe/Work/LaborSignals'] = { changed = function() end, watch = function() end }
package.loaded['EmberRoutesProbe/Kernel/Log'] = { write = function() end }
package.loaded['EmberRoutesProbe/Kernel/Boot'] =
    { controlledExecution = true, ready = true, enabled = true, runtimeReady = true }
local Labor = require 'EmberRoutesProbe/Work/LaborStore'
Labor.data()
check(type(laborRoot.quarantineResources) == 'table'
    and laborRoot.nextClaimSeq == 1, 'Work root labor fields take the template values on load')
check(laborRoot.quarantineAudit == nil, 'no audit structure is created by a load alone')
check(laborRoot.toolCustody and laborRoot.toolCustody.format == 1
    and type(laborRoot.toolCustody.byId) == 'table' and type(laborRoot.toolCustody.byNpc) == 'table'
    and type(laborRoot.toolCustody.byItem) == 'table',
    'missing toolCustody is created from the template with its version key')
laborRoot = { format = 1, containers = {}, taskJobs = { format = 1, byId = {} },
    toolCustody = { format = 1, byId = {} } }
Labor.data()
check(type(laborRoot.toolCustody.byNpc) == 'table' and type(laborRoot.toolCustody.byItem) == 'table',
    'toolCustody lookup caches are filled from the template when missing')
laborRoot = { format = 1, containers = {}, taskJobs = { format = 1, byId = {} },
    toolCustody = { byId = {} } }
before = copy(laborRoot.toolCustody)
okRoot, whyRoot = pcall(Labor.data)
check(not okRoot and tostring(whyRoot):find('TOOL_CUSTODY_FORMAT_UNSUPPORTED', 1, true)
    and same(laborRoot.toolCustody, before),
    'non-empty toolCustody without a version is refused, not silently replaced')

-- (9) Public order drafts: unversioned drafts are not read; new ones carry
-- the version key.
package.loaded['EmberRoutesProbe/Work/PublicWork'] = { requestId = function() return 'req-test-1' end }
local Draft = require 'EmberRoutesProbe/Work/PublicOrderDraft'
local actorMd = {}
local actor = { getModData = function() return actorMd end }
actorMd.EmberRoutesPublicOrderDrafts = { s = { scope = 's', recipe = 'Base.Plank', quantity = 2 } }
check(Draft.read(actor, 's') == nil, 'draft without a version key is not read')
actorMd.EmberRoutesPublicOrderDrafts = { s = { format = 2, scope = 's', recipe = 'Base.Plank', quantity = 2 } }
check(Draft.read(actor, 's') == nil, 'draft with a wrong version is not read')
local written = Draft.update(actor, 's', 'Base.Plank', 2, nil, {})
check(written.format == 1 and written.requestId == 'req-test-1', 'new drafts are written with the version key')
local reread = Draft.read(actor, 's')
check(reread and reread.scope == 's' and reread.recipe == 'Base.Plank'
    and type(reread.preferences) == 'table',
    'draft read returns a detached copy with template preferences')
check(actorMd.EmberRoutesPublicOrderDrafts.s.format == 1, 'stored draft keeps its version key')

-- (10) Persistence samples: the marker carries the version key now.
local function sampleList()
    local out = {}
    function out:size() return #self end
    function out:get(i) return self[i + 1] end
    function out:getItemByIndex(i) return self[i + 1] end
    return out
end
local nextId = 1
local sampleContainer
sampleContainer = function()
    local c = { items = sampleList() }
    function c:getItems() return self.items end
    function c:AddItem(kind)
        nextId = nextId + 1
        local item = { id = nextId, data = {}, condition = 3, name = kind, container = self }
        function item:getID() return self.id end
        function item:getModData() return self.data end
        function item:getCondition() return self.condition end
        function item:getConditionMax() return 3 end
        function item:setCondition(value) self.condition = value end
        function item:setName(value) self.name = value end
        function item:getDisplayName() return self.name end
        function item:setCustomName(value) self.customName = value end
        function item:getName() return self.name end
        function item:getContainer() return self.container end
        if kind == 'Base.Bag_Schoolbag' then
            item.bag = sampleContainer()
            function item:getInventory() return self.bag end
        elseif kind == 'Base.WaterBottle' then
            item.fluid = { amount = 1 }
            function item.fluid:getAmount() return self.amount end
            function item:getFluidContainer() return self.fluid end
        end
        self.items[#self.items + 1] = item
        return item
    end
    function c:Remove(item)
        for i, value in ipairs(self.items) do
            if value == item then table.remove(self.items, i) item.container = nil return end
        end
    end
    return c
end
local npc = { data = {}, root = sampleContainer(), worn = sampleList(), attached = sampleList() }
function npc:getInventory() return self.root end
function npc:getModData() return self.data end
function npc:getPrimaryHandItem() return self.primary end
function npc:setPrimaryHandItem(item) self.primary = item end
function npc:getSecondaryHandItem() return self.secondary end
function npc:setSecondaryHandItem(item) self.secondary = item end
function npc:getWornItems() return self.worn end
function npc:getAttachedItems() return self.attached end
npc.damage = { health = 100 }
function npc.damage:getOverallBodyHealth() return self.health end
function npc.damage:RestoreToFullHealth() self.health = 100 end
function npc:getBodyDamage() return self.damage end
local Samples = require 'EmberRoutesProbe/Runtime/PersistenceSamples'
check(Samples.prepare(npc, 'npc-1') == 'SAMPLE_PREPARED', 'sample preparation still works')
local marker = npc.data.EmberRoutesPersistenceSample
check(marker.format == 1, 'new persistence samples carry the version key')
marker.format = nil
check(Samples.check(npc, 'npc-1') == 'SAMPLE_MARKER_INVALID', 'sample without a version is refused as invalid')
marker.format = 2
check(Samples.check(npc, 'npc-1') == 'SAMPLE_MARKER_INVALID', 'sample with a wrong version is refused as invalid')
marker.format = 1
check(Samples.check(npc, 'npc-1') == 'SAMPLE_PASSED', 'sample with the current version verifies unchanged')

print('PASS ' .. n .. ' ModData template + version-key checks; real PZ disk save NOT RUN')
