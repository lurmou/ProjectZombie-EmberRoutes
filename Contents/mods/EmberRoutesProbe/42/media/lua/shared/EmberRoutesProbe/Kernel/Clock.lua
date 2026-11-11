-- Unified clock entry point. Every production read of game or wall time
-- goes through here so the two clocks are never confused:
--
-- * Clock.nowMs() -- engine monotonic millisecond clock
--   (Project Zomboid getTimestampMs): deadlines, cooldowns, throttles,
--   elapsed measurement, animation phase, status timestamps. Falls back
--   to wall-clock milliseconds (os.time() * 1000) where the engine clock
--   is absent (plain-Lua tests, headless hosts), exactly as the old
--   inline `getTimestampMs and getTimestampMs() or (os.time() * 1000)`
--   guards did. Unit and origin are unchanged: milliseconds.
-- * Clock.wallSeconds() -- wall-clock seconds (os.time): calendar /
--   display uses only. Never substitute it for nowMs or vice versa.
-- * Clock.hasEngineClock() -- whether the engine clock is present.
--   Only for call sites whose no-engine branch is deliberately different
--   (e.g. skipping a dedup suppression), never as a general guard.
--
-- The engine function is looked up fresh on every call, never captured
-- at require time, so test stubs that reassign the global mid-test keep
-- working exactly as they did with direct getTimestampMs() calls.
local Clock = {}

function Clock.hasEngineClock()
    return type(_G.getTimestampMs) == "function"
end

function Clock.nowMs()
    local f = _G.getTimestampMs
    if type(f) == "function" then return f() end
    return os.time() * 1000
end

function Clock.wallSeconds()
    return os.time()
end

return Clock
