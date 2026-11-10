-- Central once-only registry for engine event subscriptions.
--
-- The engine appends every Events.X.Add call to a list and never checks
-- for an existing entry (zombie/Lua/Event$Add is a bare ArrayList.add),
-- so subscribing the same callback twice fires it twice. Every
-- subscribe-once site in the mod goes through this one table instead of
-- keeping a guard flag per call site.
--
-- Keys are stable strings, not function values: a re-executed file builds
-- fresh closures, so identity cannot tell the second registration from a
-- new one. The first registration wins; it is the one other modules hold
-- through require, so keeping it keeps the live table wired.
local once = {}
local M = {}

-- Subscribe fn to event once under key. Returns true when fn was just
-- added, false when key was already present or the arguments are unusable.
-- The same key on a different event is a different subscription.
function M.subscribeOnce(event, key, fn)
    if type(key) ~= "string" or type(fn) ~= "function" then return false end
    local et = type(event)
    if et ~= "table" and et ~= "userdata" then return false end
    if type(event.Add) ~= "function" then return false end
    local keys = once[event]
    if not keys then keys = {} once[event] = keys end
    if keys[key] then return false end
    keys[key] = true
    event.Add(fn)
    return true
end

-- Run fn once under key. Returns true when fn just ran, false when key
-- was already present or fn is not a function. Same registry as
-- subscribeOnce, for one-shot wiring that is not an engine subscription
-- (Boot's retirement handler on the shared even-paused dispatcher).
function M.runOnce(key, fn)
    if type(key) ~= "string" or type(fn) ~= "function" then return false end
    if once[key] then return false end
    once[key] = true
    fn()
    return true
end

return M
