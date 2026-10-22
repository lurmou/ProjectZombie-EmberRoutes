local Batch = dofile("Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Batch.lua")
local assertions = 0
local function check(value, message)
    assertions = assertions + 1
    assert(value, message)
end
local function step(name, response)
    local s = { name = name, starts = 0, polls = 0, cancels = 0 }
    function s.start() s.starts = s.starts + 1 end
    function s.poll() s.polls = s.polls + 1 return response, "evidence" end
    function s.cancel() s.cancels = s.cancels + 1 end
    return s
end
local function make(steps)
    return Batch.new(steps, function() end)
end
local a, b = step("first", "WAIT"), step("second", "PASSED")
local batch = make({ a, b })
batch:tick(0)
batch:tick(100)
check(a.starts == 1 and a.polls == 2, "one start despite repeated ticks")
check(b.starts == 0, "later effect cannot start before current completes")
a.poll = function() return "PASSED", "real effect verified" end
batch:tick(200)
check(#batch.records == 1 and batch.records[1].detail == "real effect verified", "preserve evidence")
batch:tick(201)
batch:tick(202)
check(batch.state == "PASSED" and #batch.records == 2, "all steps completed")
for i = 1, 10 do batch:tick(203 + i) end
check(a.starts == 1 and b.starts == 1, "terminal ticks cannot repeat settlement")
local failed, blocked = step("bad", "FAILED"), step("must not execute", "PASSED")
batch = make({ failed, blocked })
batch:tick(0)
batch:tick(1)
check(batch.state == "FAILED" and failed.cancels == 1, "failure stops current")
check(blocked.starts == 0, "fail fast without later side effects")
local waiting = step("stalled", "WAIT")
batch = make({ waiting, blocked })
batch:tick(0)
batch:tick(59999)
check(batch.state == "RUNNING", "timeout boundary not early")
batch:tick(60000)
batch:tick(60001)
check(batch.state == "FAILED" and waiting.cancels == 1, "bounded timeout exactly once")
check(batch.records[1].detail:find("TIMEOUT"), "timeout not successful completion")
waiting = step("interrupted", "WAIT")
batch = make({ waiting, blocked })
batch:tick(0)
batch:cancel("MOVEMENT")
batch:cancel("REMOVE")
batch:tick(1000)
check(batch.state == "CANCELLED" and waiting.cancels == 1, "repeated cancellation idempotent")
check(#batch.records == 0 and blocked.starts == 0, "cancellation never reports pass")
waiting = step("broken cancel", "WAIT")
waiting.cancel = function() error("injected native failure") end
batch = make({ waiting })
batch:tick(0)
check(not pcall(batch.cancel, batch, "STOP"), "cleanup error remains visible")
check(batch.state == "CANCELLED", "cleanup exception cannot leave runner active")
local broken = step("broken start", "WAIT")
broken.start = function() error("injected queue error") end
batch = make({ broken })
check(not pcall(batch.tick, batch, 0), "start failure visible to boundary")
batch:cancel("ERROR")
check(broken.cancels == 1, "partially started action remains owned for cleanup")
local rejected = step("refused approach", "PASSED")
rejected.start = function() return "FAILED", "INVALID_TILE" end
batch = make({ rejected, blocked })
check(pcall(batch.tick, batch, 0), "expected start rejection is a result, not an exception")
check(batch.state == "FAILED" and batch.reason == "INVALID_TILE" and batch.records[1].detail == "INVALID_TILE",
    "start rejection records original failure code")
batch:tick(1)
check(rejected.cancels == 1 and rejected.polls == 0 and blocked.starts == 0,
    "start rejection cleans up once without polling or executing later steps")
print("PASS " .. assertions .. " Lua batch policy assertions; native engine NOT simulated")
