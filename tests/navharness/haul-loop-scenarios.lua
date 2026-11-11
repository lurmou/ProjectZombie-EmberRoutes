-- Haul-loop scenarios (tests/navharness/haul-loop-scenarios.lua).
--
-- Runs the REAL HaulAgent.lua headless under lua5.4 (see
-- haul-loop-stubs.lua for the bridge model: Spike4-B, MOVING 1.9s then
-- PATH_ENDED on every attempt) and checks the walk-stop loop against the
-- acceptance baselines recorded in the feasibility spike:
--   TAKE leg: walk ~2s, stop 15s (resume gate checks r.pathBackoff[r.source])
--   PUT  leg: task state flickers STARTED/PAUSED every 500ms, NPC barely
--             moves, walks again only once per 15s (resume gate never sees
--             the PUT destination backoff).
--
-- The KEY new scenario is S3 (multi-line manifest, PUT leg): it tests the
-- "multi-endpoint rotation" hypothesis -- that each failure backs off a
-- DIFFERENT endpoint, so the job keeps finding a fresh target and the NPC
-- walks a bit every few seconds. S4 is the TAKE-leg control: same
-- multi-endpoint manifest, but the TAKE leg pins on the first UNCOLLECTED
-- line's source, so rotation is expected NOT to happen there.
--
-- Run: tests/navharness/run-haul-loop.sh
-- Exit 0 = all scenarios pass; non-zero = an assertion failed.
-- Full event traces land in tests/navharness/haul-loop-trace-s<N>.txt.
local driver = require('haul-loop-driver')

local checks = 0
local function check(v, m)
    checks = checks + 1
    assert(v, m)
end

local function walkGaps(walks)
    local gaps = {}
    for i = 2, #walks do gaps[#gaps + 1] = walks[i].tStart - walks[i - 1].tStart end
    return gaps
end

local function walkEndpoints(walks)
    local eps = {}
    for _, w in ipairs(walks) do eps[#eps + 1] = w.endpoint end
    return table.concat(eps, ',')
end

local function header(name)
    print(string.rep('=', 70))
    print(name)
    print(string.rep('=', 70))
end

local TRACE_DIR = (os.getenv('NAV_HARNESS_DIR') or 'tests/navharness') .. '/'

-- S1: TAKE leg, single line (acceptance baseline).
header('S1 take-single: 1 UNCOLLECTED line, source=source')
local s1 = driver.run({
    lines = { { itemId = 1, custodyState = 'UNCOLLECTED', sourceId = 'source', destinationId = 'dest' } },
    sources = { 'source' }, destinations = { 'dest' },
    recordSource = 'source', recordDestination = 'dest',
}, { durationMs = 40000 })
print(driver.walkTable(s1))
print(string.format('pauses=%d resumesStarted=%d resumesGated=%d final=%s/%s',
    s1.counts.pauses, s1.counts.resumesStarted, s1.counts.resumesGated,
    tostring(s1.finalState), tostring(s1.finalReason)))
driver.writeTrace(s1, TRACE_DIR .. 'haul-loop-trace-s1.txt')
check(#s1.walks >= 2, 'S1: at least two walks in 40s')
for _, w in ipairs(s1.walks) do
    check(w.endpoint == 'source', 'S1: every walk targets source, got ' .. w.endpoint)
end
local g1 = walkGaps(s1.walks)
check(g1[1] >= 16000 and g1[1] <= 18000,
    'S1: walk-start gap ~17s (2s walk + 15s backoff), got ' .. tostring(g1[1]))
check(s1.counts.resumesGated >= 10, 'S1: resume gate blocks most 500ms retries')
check(s1.finalState == 'PAUSED' and s1.finalReason == 'ROUTING_WAIT', 'S1: ends PAUSED/ROUTING_WAIT')
print('S1 PASS: TAKE leg reproduced -- walk ~2s, stop 15s')

-- S2: PUT leg, single line (acceptance baseline).
header('S2 put-single: 1 CARRIED line, dest=dest')
local s2 = driver.run({
    lines = { { itemId = 1, custodyState = 'CARRIED', sourceId = 'source', destinationId = 'dest' } },
    sources = { 'source' }, destinations = { 'dest' },
    recordSource = 'source', recordDestination = 'dest',
}, { durationMs = 40000 })
print(driver.walkTable(s2))
print(string.format('pauses=%d resumesStarted=%d resumesGated=%d final=%s/%s',
    s2.counts.pauses, s2.counts.resumesStarted, s2.counts.resumesGated,
    tostring(s2.finalState), tostring(s2.finalReason)))
driver.writeTrace(s2, TRACE_DIR .. 'haul-loop-trace-s2.txt')
check(#s2.walks >= 2, 'S2: at least two walks in 40s')
for _, w in ipairs(s2.walks) do
    check(w.endpoint == 'dest', 'S2: every walk targets dest, got ' .. w.endpoint)
end
local g2 = walkGaps(s2.walks)
check(g2[1] >= 16000 and g2[1] <= 18000,
    'S2: walk-start gap ~17s, got ' .. tostring(g2[1]))
check(s2.counts.resumesGated == 0,
    'S2: resume gate NEVER blocks the PUT leg (it only checks r.source)')
check(s2.counts.pauses >= 5, 'S2: flicker -- many pauses with no walk between them')
check(s2.finalState == 'PAUSED' and s2.finalReason == 'ROUTING_WAIT', 'S2: ends PAUSED/ROUTING_WAIT')
print('S2 PASS: PUT leg reproduced -- STARTED/PAUSED flicker every 500ms, walk once per ~15s')

-- S3 (KEY): PUT leg, multi-line manifest, one destination per line.
-- Hypothesis: each PUT failure backs off a DIFFERENT destination, so the
-- next resume finds a fresh target and the NPC walks again within ~2s --
-- a burst of walks every few seconds, then a quiet flicker period once
-- every destination is backed off, repeating when the first backoff
-- expires. That burst is the "moves a bit every few seconds" rhythm.
header('S3 put-multi (KEY): 3 CARRIED lines -> destA/destB/destC')
local s3 = driver.run({
    lines = {
        { itemId = 1, custodyState = 'CARRIED', sourceId = 'sourceA', destinationId = 'destA' },
        { itemId = 2, custodyState = 'CARRIED', sourceId = 'sourceB', destinationId = 'destB' },
        { itemId = 3, custodyState = 'CARRIED', sourceId = 'sourceC', destinationId = 'destC' },
    },
    sources = { 'sourceA', 'sourceB', 'sourceC' },
    destinations = { 'destA', 'destB', 'destC' },
    recordSource = 'sourceA', recordDestination = 'destA',
}, { durationMs = 60000 })
print(driver.walkTable(s3))
print(string.format('pauses=%d resumesStarted=%d resumesGated=%d final=%s/%s',
    s3.counts.pauses, s3.counts.resumesStarted, s3.counts.resumesGated,
    tostring(s3.finalState), tostring(s3.finalReason)))
driver.writeTrace(s3, TRACE_DIR .. 'haul-loop-trace-s3.txt')
local g3 = walkGaps(s3.walks)
check(#s3.walks >= 4, 'S3: at least 4 walks in 60s (rotation burst + repeat cycle)')
check(s3.walks[1].endpoint == 'destA' and s3.walks[2].endpoint == 'destB'
    and s3.walks[3].endpoint == 'destC',
    'S3: first three walks rotate destA -> destB -> destC, got ' .. walkEndpoints(s3.walks))
check(g3[1] >= 1500 and g3[1] <= 3000 and g3[2] >= 1500 and g3[2] <= 3000,
    'S3: rotation burst -- walks ~2s apart, got gaps ' .. tostring(g3[1]) .. '/' .. tostring(g3[2]))
check(g3[3] >= 9000,
    'S3: quiet flicker period after all destinations backed off, gap ' .. tostring(g3[3]) .. 'ms')
check(s3.walks[4].endpoint == 'destA',
    'S3: second cycle restarts at destA once its 15s backoff expires, got ' .. s3.walks[4].endpoint)
check(s3.counts.resumesGated == 0, 'S3: resume gate never blocks (PUT backoffs are invisible to it)')
print('S3 VERDICT: ROTATION CONFIRMED on the PUT leg -- walks to destA, destB, destC')
print('  ~2s apart, then ~11s of 500ms STARTED/PAUSED flicker with no walking,')
print('  repeating when the first backoff expires. This IS the "moves a bit')
print('  every few seconds" rhythm, and it can only happen on the PUT leg.')

-- S4 (control): TAKE leg, multi-line manifest, one source per line.
-- The TAKE leg pins on nextSource() = the FIRST uncollected line's source,
-- and the resume gate keys on r.source, so no rotation is possible here:
-- every walk must target sourceA and gaps must stay ~17s.
header('S4 take-multi (control): 3 UNCOLLECTED lines -> sourceA/sourceB/sourceC')
local s4 = driver.run({
    lines = {
        { itemId = 1, custodyState = 'UNCOLLECTED', sourceId = 'sourceA', destinationId = 'destA' },
        { itemId = 2, custodyState = 'UNCOLLECTED', sourceId = 'sourceB', destinationId = 'destB' },
        { itemId = 3, custodyState = 'UNCOLLECTED', sourceId = 'sourceC', destinationId = 'destC' },
    },
    sources = { 'sourceA', 'sourceB', 'sourceC' },
    destinations = { 'destA', 'destB', 'destC' },
    recordSource = 'sourceA', recordDestination = 'destA',
}, { durationMs = 40000 })
print(driver.walkTable(s4))
print(string.format('pauses=%d resumesStarted=%d resumesGated=%d final=%s/%s',
    s4.counts.pauses, s4.counts.resumesStarted, s4.counts.resumesGated,
    tostring(s4.finalState), tostring(s4.finalReason)))
driver.writeTrace(s4, TRACE_DIR .. 'haul-loop-trace-s4.txt')
check(#s4.walks >= 2, 'S4: at least two walks in 40s')
for _, w in ipairs(s4.walks) do
    check(w.endpoint == 'sourceA', 'S4: every walk targets sourceA (first uncollected line), got ' .. w.endpoint)
end
local g4 = walkGaps(s4.walks)
check(g4[1] >= 16000 and g4[1] <= 18000,
    'S4: walk-start gap stays ~17s, got ' .. tostring(g4[1]))
check(s4.counts.resumesGated >= 10, 'S4: resume gate blocks retries on r.source')
print('S4 VERDICT: ROTATION FALSIFIED on the TAKE leg -- the job pins on the')
print('  first UNCOLLECTED line\'s source (sourceA); sourceB/sourceC are never')
print('  attempted while line 1 is uncollected, so no "every few seconds" walk')
print('  can come from the TAKE leg.')

print(string.rep('=', 70))
print(string.format('HAUL-LOOP PASS: %d checks, 4 scenarios', checks))
print('Conclusion: multi-endpoint rotation is REAL but PUT-leg-only. The')
print('in-game "moves a bit every few seconds" is explained if the NPC was')
print('carrying cargo with per-line destinations; it is NOT explained if the')
print('NPC was still collecting (TAKE leg pins on one source, 2s walk / 15s stop).')
