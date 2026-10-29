-- Single OnTickEvenPaused entry for the whole mod. Profiling wrappers and
-- One engine entry; pacing reduces handler work, not engine callback count.
-- Wall time avoids making read throughput depend on rendering FPS or speed.
local Config=require 'EmberRoutesProbe/TickConfig'
local Performance=require 'EmberRoutesProbe/RuntimeMetrics'
local M={handlers={}}
local installed,fireCount,lastAt
local function runHandlers()
    for _,fn in ipairs(M.handlers) do fn() end
end
local function dispatch()
    if getTimestampMs then
        local now=getTimestampMs()
        if lastAt and now>=lastAt and now-lastAt<Config.readMs then return end
        lastAt=now
    else
        -- Minimal hosts without the game clock retain the old bounded cadence.
        fireCount=(fireCount or 0)+1
        if fireCount%3~=1 then return end
    end
    -- Retirement and other even-paused work run on a separate engine entry
    -- from Probe.tick, so without this wrapper their cost is invisible to the
    -- runtime sampler. Wrap only while a sampling session is active so there
    -- is zero overhead in normal play.
    if Performance.active() then
        Performance.measure('Retirement', runHandlers)
    else
        runHandlers()
    end
end
function M.add(fn)
    M.handlers[#M.handlers+1]=fn
    if not installed and Events and Events.OnTickEvenPaused then
        Events.OnTickEvenPaused.Add(dispatch) installed=true
    end
    return fn
end
return M
