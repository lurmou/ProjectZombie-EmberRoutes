-- Haul-loop driver (tests/navharness/haul-loop-driver.lua).
--
-- Reusable headless driver for the REAL HaulAgent.lua under lua5.4:
-- installs the stub set, then runs the simulated decide loop -- tick
-- every 100ms (HaulAgent.tick cadence), resume attempt every 500ms
-- (PublicWork decide cadence) while the agent is idle -- and records a
-- full event trace plus a per-walk table.
--
-- Usage (see haul-loop-scenarios.lua):
--   local driver = require('haul-loop-driver')
--   local report = driver.run(spec, { durationMs = 60000 })
--   -- report.walks: { { tStart=, tEnd=, endpoint=, outcome=, walkMs= }, ... }
--   -- report.events: { { t=, kind=, detail= }, ... }  (MOVE/PAUSE/RESUME)
--   -- report.counts: pauses, resumesStarted, resumesGated
local Stubs = require('haul-loop-stubs')

local M = {}

function M.run(spec, opts)
    opts = opts or {}
    local durationMs = opts.durationMs or 60000
    local decideMs = opts.decideMs or 500
    local tickMs = opts.tickMs or 100
    local maxPauses = opts.maxPauses or 999

    local ctx = Stubs.install(spec)
    local record = ctx.record
    local logEvent = ctx.logEvent
    local agent = require('EmberRoutesProbe/Hauling/HaulAgent').new('npc')

    -- Wrap pause so every pause/resume transition lands in the trace
    -- with the record state at that moment.
    local realPause = agent.pause
    agent.pause = function(reason, owned)
        logEvent('PAUSE', 'reason=' .. tostring(reason) .. ' state=' .. tostring(record.state))
        return realPause(reason, owned)
    end

    local pauses, resumesStarted, resumesGated = 0, 0, 0
    local function countPauses()
        local c = 0
        for _, e in ipairs(ctx.events) do
            if e.kind == 'PAUSE' then c = c + 1 end
        end
        return c
    end

    local r = agent.resume(ctx.actor)
    logEvent('RESUME', tostring(r))
    if r == 'STARTED' then resumesStarted = resumesStarted + 1
    elseif r == 'ROUTING_WAIT' then resumesGated = resumesGated + 1 end

    local nextDecide = ctx.now + decideMs
    local deadline = ctx.now + durationMs
    while ctx.now < deadline and pauses < maxPauses do
        ctx.now = ctx.now + tickMs
        agent.tick()
        if not agent.busy() and ctx.now >= nextDecide then
            nextDecide = ctx.now + decideMs
            local res = agent.resume(ctx.actor)
            local backoff = ''
            if record.pathBackoff then
                for id, untilMs in pairs(record.pathBackoff) do
                    backoff = backoff .. ' ' .. id .. '->' .. tostring(untilMs)
                end
            end
            logEvent('RESUME', tostring(res) .. backoff)
            if res == 'STARTED' then resumesStarted = resumesStarted + 1
            elseif res == 'ROUTING_WAIT' then resumesGated = resumesGated + 1 end
        end
        pauses = countPauses()
    end

    -- Settle phase: drain any in-flight step (a resume issued on the
    -- last decide tick would otherwise leave the agent RUNNING at the
    -- deadline purely by alignment). No new resumes here -- only ticks,
    -- so the final state is deterministic, not deadline luck.
    local settleEnd = ctx.now + 2000
    while ctx.now < settleEnd and agent.busy() do
        ctx.now = ctx.now + tickMs
        agent.tick()
        pauses = countPauses()
    end

    local walks = {}
    for _, m in ipairs(ctx.moves) do
        if m.tEnd then
            walks[#walks + 1] = {
                tStart = m.tStart, tEnd = m.tEnd, endpoint = m.endpoint,
                outcome = m.outcome, walkMs = m.tEnd - m.tStart,
            }
        end
    end

    return {
        ctx = ctx, record = record, walks = walks, events = ctx.events,
        logLines = ctx.logLines,
        counts = { pauses = pauses, resumesStarted = resumesStarted,
                   resumesGated = resumesGated },
        finalState = record.state, finalReason = record.reason,
        pathBackoff = record.pathBackoff,
    }
end

-- One-line-per-walk summary for stdout; the full event trace goes to a
-- file via writeTrace.
function M.walkTable(report)
    local lines = {}
    for i, w in ipairs(report.walks) do
        lines[#lines + 1] = string.format(
            '  walk #%d t=%d..%dms endpoint=%s outcome=%s walkMs=%d',
            i, w.tStart, w.tEnd, w.endpoint, w.outcome, w.walkMs)
    end
    if #lines == 0 then lines[1] = '  (no walks)' end
    return table.concat(lines, '\n')
end

function M.writeTrace(report, path)
    local f = assert(io.open(path, 'w'))
    for _, e in ipairs(report.events) do
        f:write(string.format('t=%dms %s %s\n', e.t, e.kind, e.detail))
    end
    for _, l in ipairs(report.logLines) do
        f:write(string.format('t=%dms LOG %s %s\n', l.t, l.tag, l.msg))
    end
    f:write(string.format(
        'SUMMARY pauses=%d resumesStarted=%d resumesGated=%d finalState=%s finalReason=%s\n',
        report.counts.pauses, report.counts.resumesStarted, report.counts.resumesGated,
        tostring(report.finalState), tostring(report.finalReason)))
    f:close()
end

return M
