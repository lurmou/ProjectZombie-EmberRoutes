-- Contract test for PublicWorkProviders.register():
-- 1. discover and claim must be functions.
-- 2. Optional hooks, when present, must also be functions.
-- 3. Temporary removal of claim triggers failure (P1 acceptance check).
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;" .. package.path

local Registry = require 'EmberRoutesProbe/Work/PublicWorkProviders'

local function ok(v, msg) assert(v, msg) end
local function noop() end

-- ---- valid base def ----
-- Registration is loud: defaultPriority and retained are both required.
local valid = { category = 'test_valid', defaultPriority = 3, discover = noop, claim = noop, retained = noop }

local pass, err = Registry.register(valid)
ok(pass == true, 'valid provider must register: ' .. tostring(err))

-- ---- missing defaultPriority ----
Registry.reset()
local no_priority = { category = 'test_noprio', discover = noop, claim = noop, retained = noop }
pass, err = Registry.register(no_priority)
ok(pass == false, 'missing defaultPriority must fail')
ok(err == 'PROVIDER_MISSING_PRIORITY', 'error code PROVIDER_MISSING_PRIORITY, got: ' .. tostring(err))

-- ---- defaultPriority out of range ----
Registry.reset()
local bad_priority = { category = 'test_badprio', defaultPriority = 5, discover = noop, claim = noop, retained = noop }
pass, err = Registry.register(bad_priority)
ok(pass == false, 'out-of-range defaultPriority must fail')
ok(err == 'PROVIDER_INVALID', 'error code PROVIDER_INVALID, got: ' .. tostring(err))

-- ---- defaultPriority must be an integer tier (decide() buckets tiers 1-4) ----
Registry.reset()
local frac_priority = { category = 'test_fracprio', defaultPriority = 2.5, discover = noop, claim = noop, retained = noop }
pass, err = Registry.register(frac_priority)
ok(pass == false, 'fractional defaultPriority must fail')
ok(err == 'PROVIDER_INVALID', 'error code PROVIDER_INVALID, got: ' .. tostring(err))

-- ---- missing retained: loud at registration, never silently skipped ----
Registry.reset()
local no_retained = { category = 'test_noretained', defaultPriority = 3, discover = noop, claim = noop }
pass, err = Registry.register(no_retained)
ok(pass == false, 'missing retained must fail')
ok(err == 'PROVIDER_MISSING_RETAINED', 'error code PROVIDER_MISSING_RETAINED, got: ' .. tostring(err))

-- ---- retained is not a function ----
Registry.reset()
local bad_retained = { category = 'test_badretained', defaultPriority = 3, discover = noop, claim = noop, retained = true }
pass, err = Registry.register(bad_retained)
ok(pass == false, 'non-function retained must fail')
ok(err == 'PROVIDER_HOOK_NOT_FUNCTION:retained', 'error code must name retained, got: ' .. tostring(err))

-- ---- missing discover ----
Registry.reset()
local no_discover = { category = 'test_nodiscover', defaultPriority = 3, claim = noop, retained = noop }
pass, err = Registry.register(no_discover)
ok(pass == false, 'missing discover must fail')
ok(err == 'PROVIDER_MISSING_DISCOVER', 'error code PROVIDER_MISSING_DISCOVER, got: ' .. tostring(err))

-- ---- missing claim ----
Registry.reset()
local no_claim = { category = 'test_noclaim', defaultPriority = 3, discover = noop, retained = noop }
pass, err = Registry.register(no_claim)
ok(pass == false, 'missing claim must fail')
ok(err == 'PROVIDER_MISSING_CLAIM', 'error code PROVIDER_MISSING_CLAIM, got: ' .. tostring(err))

-- ---- discover is not a function ----
Registry.reset()
local bad_discover = { category = 'test_baddis', defaultPriority = 3, discover = 'string', claim = noop, retained = noop }
pass, err = Registry.register(bad_discover)
ok(pass == false, 'non-function discover must fail')

-- ---- claim is not a function ----
Registry.reset()
local bad_claim = { category = 'test_badclaim', defaultPriority = 3, discover = noop, claim = 42, retained = noop }
pass, err = Registry.register(bad_claim)
ok(pass == false, 'non-function claim must fail')

-- ---- optional hook present and correct ----
Registry.reset()
local with_hooks = { category = 'test_hooks', defaultPriority = 3, discover = noop, claim = noop, retained = noop, reconcile = noop, advance = noop }
pass, err = Registry.register(with_hooks)
ok(pass == true, 'valid optional hooks must register: ' .. tostring(err))

-- ---- optional hook present but wrong type ----
Registry.reset()
local bad_hook = { category = 'test_badhook', defaultPriority = 3, discover = noop, claim = noop, retained = noop, reconcile = 'not_a_function' }
pass, err = Registry.register(bad_hook)
ok(pass == false, 'non-function optional hook must fail')
ok(err and err:find('PROVIDER_HOOK_NOT_FUNCTION'), 'error code must name hook, got: ' .. tostring(err))

-- ---- acceptance: temporarily remove claim, re-register must fail ----
Registry.reset()
local removable = { category = 'test_removable', defaultPriority = 3, discover = noop, claim = noop, retained = noop }
pass = Registry.register(removable)
ok(pass == true, 'setup: initial register ok')
-- Simulate contract violation: register same category without claim
local broken = { category = 'test_removable', defaultPriority = 3, discover = noop, retained = noop }
pass, err = Registry.register(broken)
ok(pass == false, 're-register without claim must fail')
ok(err == 'PROVIDER_MISSING_CLAIM', 'must reject missing claim on re-register')

-- ---- acceptance: temporarily remove retained, re-register must fail ----
Registry.reset()
pass = Registry.register(removable)
ok(pass == true, 'setup: initial register ok')
local brokenRetained = { category = 'test_removable', defaultPriority = 3, discover = noop, claim = noop }
pass, err = Registry.register(brokenRetained)
ok(pass == false, 're-register without retained must fail')
ok(err == 'PROVIDER_MISSING_RETAINED', 'must reject missing retained on re-register, got: ' .. tostring(err))

Registry.reset()

-- ---- explicit priority order: fan-out follows defaultPriority, then category ----
local orderA = { category = 'order_tool', defaultPriority = 4, discover = noop, claim = noop, retained = noop }
local orderB = { category = 'order_clean', defaultPriority = 2, discover = noop, claim = noop, retained = noop }
local orderC = { category = 'order_craft', defaultPriority = 3, discover = noop, claim = noop, retained = noop }
local orderD = { category = 'order_cook', defaultPriority = 3, discover = noop, claim = noop, retained = noop }
ok(Registry.register(orderA) and Registry.register(orderB) and Registry.register(orderC)
    and Registry.register(orderD), 'setup: out-of-order registration ok')
local fanout = {}
for _, p in ipairs(Registry.all()) do fanout[#fanout + 1] = p.category end
ok(table.concat(fanout, ',') == 'order_clean,order_cook,order_craft,order_tool',
    'fan-out order follows explicit defaultPriority then category, got: ' .. table.concat(fanout, ','))
local cats = Registry.categories()
ok(table.concat(cats, ',') == 'order_tool,order_clean,order_craft,order_cook',
    'categories() stays registration order for UI and saved sets, got: ' .. table.concat(cats, ','))
-- Re-register with a changed priority re-sorts the fan-out.
ok(Registry.register({ category = 'order_tool', defaultPriority = 1, discover = noop, claim = noop, retained = noop }),
    'setup: re-register with new priority ok')
fanout = {}
for _, p in ipairs(Registry.all()) do fanout[#fanout + 1] = p.category end
ok(table.concat(fanout, ',') == 'order_tool,order_clean,order_cook,order_craft',
    're-register re-sorts the fan-out, got: ' .. table.concat(fanout, ','))
-- pendingScore takes the highest score, not the first positive in
-- registration order.
Registry.reset()
local lowFirst = { category = 'score_low', defaultPriority = 2, discover = noop, claim = noop, retained = noop,
    pendingScore = function() return 5 end }
local highSecond = { category = 'score_high', defaultPriority = 3, discover = noop, claim = noop, retained = noop,
    pendingScore = function() return 9 end }
ok(Registry.register(lowFirst) and Registry.register(highSecond), 'setup: scorers register')
ok(Registry.pendingScore('npc1') == 9, 'pendingScore takes the highest score, got: ' .. tostring(Registry.pendingScore('npc1')))

Registry.reset()

-- ---- P4 kernel hooks and the priorityRequired declaration ----
for _, hook in ipairs({ 'retained', 'command', 'orderCommanded', 'retireUnclaimed', 'orderRetired', 'reset' }) do
    Registry.reset()
    pass, err = Registry.register({ category = 'test_p4', defaultPriority = 3, discover = noop, claim = noop, retained = noop, [hook] = true })
    ok(pass == false and err == 'PROVIDER_HOOK_NOT_FUNCTION:' .. hook, 'non-function ' .. hook .. ' must fail, got: ' .. tostring(err))
end
Registry.reset()
pass, err = Registry.register({ category = 'test_p4', defaultPriority = 3, discover = noop, claim = noop, retained = noop, priorityRequired = 'yes' })
ok(pass == false and err == 'PROVIDER_INVALID', 'non-boolean priorityRequired must fail, got: ' .. tostring(err))
Registry.reset()

-- ---- claim failure contract (P2): release only on a rollback declaration ----
local Directory = require 'EmberRoutesProbe/Kernel/TaskDirectory'
local jobs = {}

-- Builds the Job, then refuses without undoing it or declaring a rollback.
local leaky = { category = 'test_leaky', discover = noop,
    claim = function(selected, npcId, jobId) jobs[jobId] = { npcId = npcId, state = 'PREPARING' } return 'COMMIT_FAILED' end }
-- Refuses and declares that it left nothing behind.
local clean = { category = 'test_clean', discover = noop,
    claim = function() return 'TARGET_CHANGED', Registry.CLAIM_ROLLED_BACK end }

local dir = Directory.new()
ok(dir:upsert('offer:a', 1, 'test_leaky', 's'), 'setup: offer a')
ok(dir:claim('offer:a', 1, 'npc1', 'job1'), 'setup: claim a')
local result, declaration = leaky.claim({ key = 'offer:a' }, 'npc1', 'job1', { directory = dir })
local retained = Registry.settleFailedClaim(dir, 'offer:a', 'job1', declaration)
ok(result == 'COMMIT_FAILED' and jobs.job1, 'setup: leaky claim created a Job and refused')
ok(retained == 'CLAIM_ROLLBACK_UNDECLARED', 'undeclared failure is diagnosed, got: ' .. tostring(retained))
local again, why = dir:claim('offer:a', 1, 'npc2', 'job2')
ok(again == false and why == 'OFFER_ALLOCATED', 'undeclared failure keeps the offer allocated to its Job')
ok(dir:upsert('offer:a', 1, 'test_leaky', 's').jobId == 'job1', 'rediscovery sees the retained allocation')

ok(dir:upsert('offer:b', 1, 'test_clean', 's'), 'setup: offer b')
ok(dir:claim('offer:b', 1, 'npc1', 'job3'), 'setup: claim b')
result, declaration = clean.claim({ key = 'offer:b' }, 'npc1', 'job3', { directory = dir })
retained = Registry.settleFailedClaim(dir, 'offer:b', 'job3', declaration)
ok(retained == nil, 'declared rollback releases the offer, got: ' .. tostring(retained))
ok(dir:upsert('offer:b', 1, 'test_clean', 's').jobId == nil, 'released offer is free again')
ok(dir:claim('offer:b', 1, 'npc2', 'job4'), 'released offer can be claimed by another worker')

-- A declaration cannot release another Job's allocation.
retained = Registry.settleFailedClaim(dir, 'offer:b', 'job3', Registry.CLAIM_ROLLED_BACK)
ok(retained == 'OFFER_CHANGED', 'stale declaration keeps the new allocation, got: ' .. tostring(retained))
ok(dir:upsert('offer:b', 1, 'test_clean', 's').jobId == 'job4', 'new allocation untouched')

-- ---- lazy provider shells forward the declaration (and/or would drop it) ----
local fieldReady = false
package.loaded['EmberRoutesProbe/Kernel/RuntimeGate'] = { hasFieldOperations = function() return fieldReady end }
local serviceResult, serviceDeclaration = 'NPC_BUSY', Registry.CLAIM_ROLLED_BACK
package.loaded['EmberRoutesProbe/Field/CleaningService'] = {
    claim = function() return serviceResult, serviceDeclaration end }
local Cleaning = require 'EmberRoutesProbe/Field/CleaningProvider'
result, declaration = Cleaning.claim({}, 'npc1', 'job5', {})
ok(result == 'CLEANING_UNAVAILABLE' and declaration == Registry.CLAIM_ROLLED_BACK, 'unavailable shell declares rollback')
fieldReady = true
result, declaration = Cleaning.claim({}, 'npc1', 'job5', {})
ok(result == 'NPC_BUSY' and declaration == Registry.CLAIM_ROLLED_BACK, 'shell forwards the service declaration')
serviceResult, serviceDeclaration = 'TASK_WRITE_FAILURE', nil
result, declaration = Cleaning.claim({}, 'npc1', 'job5', {})
ok(result == 'TASK_WRITE_FAILURE' and declaration == nil, 'shell does not invent a declaration')
serviceResult = 'QUEUED'
ok(Cleaning.claim({}, 'npc1', 'job5', {}) == 'QUEUED', 'shell forwards success')
package.loaded['EmberRoutesProbe/Kernel/RuntimeGate'] = nil
package.loaded['EmberRoutesProbe/Field/CleaningService'] = nil
package.loaded['EmberRoutesProbe/Field/CleaningProvider'] = nil

-- ---- field and cooking claims: TASK_WRITE_FAILURE is never declared ----
-- Real FieldWork/CookingService claim code over minimal host stubs, with the
-- real LaborJobCommit classifier on the stub store. A write failure keeps the
-- offer unless its evidence is exactly a JobStore.create refusal (which the
-- kernel returns before the write, after releasing the new token); a failed
-- restore keeps it too; other refusals before the write declare rollback.
local Commit = require 'EmberRoutesProbe/Work/LaborJobCommit'
local createCases = {
    { 'TASK_WRITE_FAILURE', 'CRAFT_SCOPE_RECONCILE_REQUIRED', 'ROLLED_BACK' }, -- scope fence refusal
    { 'TASK_WRITE_FAILURE', 'JOB_LIMIT', 'ROLLED_BACK' },
    { 'TASK_WRITE_FAILURE', 'CAS_REACHED_RELOAD_FROM_SAVE:CALLBACK_OR_KERNEL_THROW:boom', nil }, -- throw after write
    { 'TASK_WRITE_FAILURE', 'CAS_REACHED_RELOAD_FROM_SAVE:CRAFT_SCOPE_RECONCILE_REQUIRED', nil },
    { 'TASK_WRITE_FAILURE', nil, nil },
    { 'TASK_WRITE_FAILURE', '', nil },
    { 'TASK_WRITE_FAILURE', 'INVALID_KERNEL_RESULT', nil },
    { 'TASK_WRITE_FAILURE', 'java.lang.Error: JOB_LIMIT', nil },
    { 'ROLLBACK_FAILURE', 'RECONCILE_REQUIRED:PARTIAL_RESTORE:CRAFT_SCOPE_RECONCILE_REQUIRED', nil },
    { 'ROLLBACK_FAILURE', 'CRAFT_SCOPE_RECONCILE_REQUIRED', nil },
}
local stubbed = {}
local function stub(name, t) stubbed[#stubbed + 1] = 'EmberRoutesProbe/' .. name package.loaded['EmberRoutesProbe/' .. name] = t return t end
local released, writeResult, writeEvidence = {}, nil, nil
local npc = { isDead = function() return false end, isOnFire = function() return false end,
    getSurroundingAttackingZombies = function() return 0 end }
stub('Runtime/TaskJobs', { current = function() return { visitNpc = noop, get = noop, peek = noop } end })
stub('Work/LaborStore', { resourceOwner = noop, releaseCustody = function(id) released[#released + 1] = id end,
    createClaimedJob = function() return false, writeResult, writeEvidence end,
    createEffectsUnknown = Commit.createEffectsUnknown })
local worldRoot = {}
stub('Warehouse/ContainerRegistry', { data = function() return worldRoot end })
stub('Runtime/TaskRuntime', { current = function() return { accepting = function() return true end,
    owns = function() return false end } end })
stub('Runtime/Driver', { bindId = function(_, id) return { id = id, handle = npc } end, valid = function() return true end })
stub('Kernel/Boot', {}) stub('Work/LaborSignals', { changed = noop })
stub('Field/FieldContext', {}) stub('Field/FieldSession', {})
stub('Field/FieldWork', nil)
local FieldWork = require 'EmberRoutesProbe/Field/FieldWork'
local field = FieldWork.provider({ category = 'test_field', discover = noop,
    claim = function() return { createdCustodies = { 'custody1' } }, { 'tile:1' } end })
local fieldCases = { { 'CLAIM_FAILURE', nil, 'ROLLED_BACK' }, { 'KERNEL_UNAVAILABLE', nil, 'ROLLED_BACK' } }
for _, case in ipairs(createCases) do fieldCases[#fieldCases + 1] = case end
for _, case in ipairs(fieldCases) do
    released, writeResult, writeEvidence = {}, case[1], case[2]
    local label = case[1] .. '/' .. tostring(case[2])
    result, declaration = field.claim({ key = 'field:1' }, 'npc1', 'jobF', { actor = {}, entry = { id = 's' } })
    ok(result == case[1] and declaration == case[3], 'field ' .. label .. ' declaration, got: ' .. tostring(declaration))
    ok(#released == 1 and released[1] == 'custody1', 'field undoes its custodies before refusing ' .. label)
end
-- Acceptance: while a settlement's scope fence refuses new Jobs, a refused
-- field claim frees its offer for the next decision instead of holding it.
local fenceDir = Directory.new()
ok(fenceDir:upsert('field:fenced', 1, 'test_field', 's') and fenceDir:claim('field:fenced', 1, 'npc1', 'jobF1'), 'setup: fenced offer claimed')
writeResult, writeEvidence = 'TASK_WRITE_FAILURE', 'CRAFT_SCOPE_RECONCILE_REQUIRED'
result, declaration = field.claim({ key = 'field:fenced' }, 'npc1', 'jobF1', { actor = {}, entry = { id = 's' } })
ok(Registry.settleFailedClaim(fenceDir, 'field:fenced', 'jobF1', declaration) == nil, 'fence refusal releases the field offer')
ok(fenceDir:upsert('field:fenced', 1, 'test_field', 's').jobId == nil and fenceDir:claim('field:fenced', 1, 'npc2', 'jobF2'),
    'released field offer can be claimed again')

-- Cooking: discover + advance make one AUTO plan ready; the claim then fails
-- at the supply reservation (which wraps createClaimedJob) with the given code.
local now = 1000
function getTimestampMs() return now end
function getGameTime() return { getWorldAgeHours = function() return 1 end } end
EmberRoutesProbeJava = { carrierActive = true }
local entry = { id = 's', revision = 1 }
local selection = { minimum = 1, estimated = 1, recipe = { getOriginalname = function() return 'Soup' end } }
local reserveResult, reserveEvidence
stub('Cooking/CookingRecord', { new = function(id) return { id = id, payload = {} } end })
stub('Cooking/CookingPolicy', { epsilon = 1e-6, batch = function() return { target = 1 } end })
stub('Cooking/CookingSupplyService', { observe = function() return { demand = { active = true, gap = 1 } } end,
    reserve = function() return false, reserveResult, reserveEvidence end })
stub('Integration/CookingMenu', { fit = function(s) return s end, new = function() return {
    step = function() return true end, result = function() return selection end } end })
stub('Cooking/CookingEvolved', { prepare = function(job) return job end })
stub('Cooking/CookingProfiles', { accept = noop })
stub('Settlement/MembershipService', { entry = function() return entry end })
stub('SelfCare/NeedsObserver', { sample = function() return { safe = true } end })
stub('SelfCare/SelfCare', { blocksWork = function() return false end })
stub('Work/Work', { busy = function() return false end, hasCargo = function() return false end, registerExecutor = noop })
stub('Cooking/CookingOrders', { first = noop })
stub('Runtime/PlanningWake', { capture = function() return {} end, changed = function() return false end })
stub('Cooking/CookingCargo', { coldGate = function() return { run = function() return 'Success' end } end })
stub('Work/OrderQuery', { priorities = function() return { cooking = 1 } end })
stub('Work/JobPolicyService', { get = function() return {} end })
stub('Cooking/CookingService', nil) stub('Cooking/CookingProvider', nil)
local Cooking = require 'EmberRoutesProbe/Cooking/CookingProvider'
local selected = { key = 'cooking:s', scopeId = 's' }
local function cookClaim(code, evidence, jobId, directory)
    now = now + 100
    reserveResult, reserveEvidence = code, evidence
    Cooking.discover({ npcId = 'cook1', entry = entry, now = now })
    Cooking.advance({ actor = {}, now = now })
    return Cooking.claim(selected, 'cook1', jobId or 'jobC', { actor = {}, now = now, directory = directory or {} })
end
local cookCases = { { 'COOKING_QUOTA_CHANGED', nil, 'ROLLED_BACK' } }
for _, case in ipairs(createCases) do cookCases[#cookCases + 1] = case end
for _, case in ipairs(cookCases) do
    result, declaration = cookClaim(case[1], case[2])
    ok(result == case[1] and declaration == case[3], 'cooking ' .. case[1] .. '/' .. tostring(case[2]) .. ' declaration, got: '
        .. tostring(result) .. '/' .. tostring(declaration))
end
-- Acceptance: the settlement-wide auto-cooking offer is freed under the fence.
ok(fenceDir:upsert('cooking:s', 1, 'cooking', 's') and fenceDir:claim('cooking:s', 1, 'cook1', 'jobC1'), 'setup: cooking offer claimed')
result, declaration = cookClaim('TASK_WRITE_FAILURE', 'CRAFT_SCOPE_RECONCILE_REQUIRED', 'jobC1', fenceDir)
ok(Registry.settleFailedClaim(fenceDir, 'cooking:s', 'jobC1', declaration) == nil, 'fence refusal releases the cooking offer')
ok(fenceDir:upsert('cooking:s', 1, 'cooking', 's').jobId == nil and fenceDir:claim('cooking:s', 1, 'cook2', 'jobC2'),
    'released cooking offer can be claimed again')
result, declaration = Cooking.claim(selected, 'cook1', 'jobC', { actor = {}, now = now, directory = {} })
ok(result == 'COOKING_CANDIDATE_CHANGED' and declaration == 'ROLLED_BACK', 'cooking refusal without a plan declares rollback')
-- The real CookingSupplyService.reserve hands the store evidence through.
worldRoot.npcMembership = { format = 1, byNpc = {} }
stub('Cooking/CookingPolicy', { finite = function(v) return type(v) == 'number' end, population = function() return 1 end,
    demand = function() return { active = true, gap = 1 } end })
stub('Cooking/CookingRecord', { valid = function() return true end, copy = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end })
stub('Cooking/CookingBudget', { open = function() return { view = function() return { stamp = 'st' } end,
    reserve = function() return false, 'TASK_WRITE_FAILURE', 'CRAFT_SCOPE_RECONCILE_REQUIRED' end } end })
stub('Cooking/MealSupplyIndex', { new = function() return { step = function() return true end,
    result = function() return { complete = true, ready = 0, scopeId = 's' } end } end })
stub('Work/LaborStore', { claimsVersion = function() return 'owner', 1 end })
stub('Cooking/CookingSupplyService', nil)
local Supply = require 'EmberRoutesProbe/Cooking/CookingSupplyService'
local supplyEntry = { id = 's', factionId = 'f' }
local snapshot = Supply.observe(supplyEntry, now, 1, { scan = 64 })
ok(snapshot, 'setup: supply snapshot observed')
local reserved, why, evidence = Supply.reserve(supplyEntry, { scopeId = 's' }, snapshot, 1, now, 1)
ok(reserved == false and why == 'TASK_WRITE_FAILURE' and evidence == 'CRAFT_SCOPE_RECONCILE_REQUIRED',
    'supply reservation returns the store evidence, got: ' .. tostring(why) .. '/' .. tostring(evidence))
for _, name in ipairs(stubbed) do package.loaded[name] = nil end
EmberRoutesProbeJava = nil

print('PASS: provider-contract-test')
