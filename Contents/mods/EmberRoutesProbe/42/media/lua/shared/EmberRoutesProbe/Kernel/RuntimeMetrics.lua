-- Explicit Debug sampling only. Constant storage; no per-tick logging.
-- Fixed histogram buckets; p95/p99 are conservative bucket upper bounds.
-- Calls/totals/max remain exact. No per-call sample list or copy at END.
local Log=require 'EmberRoutesProbe/Kernel/Log'
local TickConfig=require 'EmberRoutesProbe/Kernel/TickConfig'
local M={}
local sample,last
local epoch=0
-- Last slow-handler log per domain, on the diagnostic clock (ms). Cleared
-- by reset() with the sample so a new world starts with a fresh log budget.
local lastSlowLog={}
local function clock() return EmberRoutesProbeJava.diagnosticTimeNanos()/1000000 end
-- NPC count at log time, from the same bridge call the domains already use
-- (workerCount); 0 when the bridge is absent so a stubbed clock can still
-- name the domain instead of failing the log line.
local function npcCount()
    local bridge=EmberRoutesProbeJava
    if bridge and type(bridge.workerCount)=='function' then
        local n=bridge.workerCount()
        if type(n)=='number' then return n end
    end
    return 0
end
-- Names one slow domain tick in the log (Viewpoint/Smooth Frames pilot):
-- the sampling table alone is never read mid-game, so a domain at or above
-- TickConfig.slowHandlerMs gets one structured line -- domain, cost, NPC
-- count -- in the same RUNTIME_PERF category and key=value shape as the
-- sampling END summary. Repeats from the same domain inside
-- TickConfig.slowHandlerLogCooldownMs are dropped. nowMs is the end
-- timestamp on the same clock that measured elapsedMs, so callers pass the
-- timestamp they already have and no extra clock read is needed. Returns
-- true when a line was written.
function M.reportSlow(name,elapsedMs,nowMs)
    if type(elapsedMs)~='number' or elapsedMs<TickConfig.slowHandlerMs then return false end
    local lastAt=lastSlowLog[name]
    if lastAt and type(nowMs)=='number' and nowMs-lastAt<TickConfig.slowHandlerLogCooldownMs then return false end
    lastSlowLog[name]=nowMs
    Log.event('RUNTIME_PERF','SLOW_HANDLER',{domain=name,ms=string.format('%.3f',elapsedMs),npcs=npcCount()})
    return true
end
function M.active() return sample~=nil end
function M.now() return clock() end
-- Sampling sessions are epoch-numbered so callers can cache per-session
-- structures (e.g. resolved service tables) and rebuild on each new sample.
function M.epoch() return epoch end
local function bucket(ms)
    if ms<=5 then return math.ceil(ms*40) end
    if ms<=50 then return 200+math.ceil((ms-5)*4) end
    if ms<=500 then return 380+math.ceil((ms-50)/2.5) end
    if ms<=5000 then return 560+math.ceil((ms-500)/25) end
    return 741
end
local function upper(key,maximum)
    if key<=200 then return key/40 end
    if key<=380 then return 5+(key-200)/4 end
    if key<=560 then return 50+(key-380)*2.5 end
    if key<=740 then return 500+(key-560)*25 end
    return maximum
end
local function addElapsed(name,elapsed)
    local row=sample.rows[name]
    if not row then row={calls=0,total=0,max=0,hist={},peakWindow=0} sample.rows[name]=row end
    row.calls=row.calls+1 row.total=row.total+elapsed
    if elapsed>row.max then row.max=elapsed end
    local hist=row.hist local key=bucket(elapsed)
    hist[key]=(hist[key] or 0)+1
    -- Per-bucket worst-second attribution rides the global 1s window rollover;
    -- no extra clock calls per measure.
    local frame=sample.frame
    frame[name]=(frame[name] or 0)+elapsed
end
function M.start()
    if not EmberRoutesProbeJava or not EmberRoutesProbeJava.diagnosticTimeNanos then return false end
    local now=clock()
    sample={started=now,deadline=now+20000,ticks=0,total=0,max=0,rows={},frame={},
        windowAt=now,windowMs=0,peakWindow=0}
    epoch=epoch+1
    Log.write('RUNTIME_PERF','START duration=20s units=ms wall-inclusive percentiles=bucket-upper-bounds')
    return true
end
function M.measure(name,fn)
    local started=clock()
    fn()
    local elapsed=clock()-started
    addElapsed(name,elapsed)
    -- Same naming as the unmeasured Boot dispatch below: a slow domain is
    -- named in the log the moment it happens, not only in the END summary.
    M.reportSlow(name,elapsed,started+elapsed)
end
-- Span variant for wrappers that must keep the wrapped function's return value.
function M.measureSpan(name,started)
    addElapsed(name,clock()-started)
end
local function percentiles(row)
    local keys={} for key in pairs(row.hist) do keys[#keys+1]=key end table.sort(keys)
    local count,p95,p99=0,nil,nil
    for _,key in ipairs(keys) do
        count=count+row.hist[key]
        if not p95 and count>=math.ceil(row.calls*0.95) then p95=upper(key,row.max) end
        if not p99 and count>=math.ceil(row.calls*0.99) then p99=upper(key,row.max) break end
    end
    return p95 or 0,p99 or 0
end
function M.finishTick(started)
    local now=clock() local s=sample
    local elapsed=now-started
    s.ticks=s.ticks+1 s.total=s.total+elapsed s.max=math.max(s.max,elapsed)
    s.windowMs=s.windowMs+elapsed
    if now-s.windowAt>=1000 or now>=s.deadline then
        s.peakWindow=math.max(s.peakWindow,s.windowMs)
        for name,ms in pairs(s.frame) do
            local row=s.rows[name]
            if row and ms>row.peakWindow then row.peakWindow=ms end
        end
        s.frame={}
        s.windowAt=now s.windowMs=0
    end
    if now<s.deadline then return end
    s.seconds=(now-s.started)/1000 last=s sample=nil
    Log.write('RUNTIME_PERF',string.format('END seconds=%.2f ticks=%d Boot_ms_per_second=%.3f max_tick_ms=%.3f peak_tick_window_ms=%.3f',s.seconds,s.ticks,s.total/s.seconds,s.max,s.peakWindow))
    local names={} for name in pairs(s.rows) do names[#names+1]=name end table.sort(names)
    for _,name in ipairs(names) do
        local r=s.rows[name]
        local p95,p99=percentiles(r)
        Log.write('RUNTIME_PERF',string.format('%s calls=%d ms_per_second=%.3f p95_ms=%.3f p99_ms=%.3f max_ms=%.3f peak_win_ms=%.3f',
            name,r.calls,r.total/s.seconds,p95,p99,r.max,r.peakWindow or 0))
    end
end
function M.result() return last end
function M.reset() sample,last=nil,nil lastSlowLog={} epoch=epoch+1 end
return M
