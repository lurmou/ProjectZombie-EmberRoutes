local Policy = dofile("Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FollowPolicy.lua")
local count = 0
local function check(value, message) count = count + 1 assert(value, message) end
local function sample(x, lx, z, lz, motion)
    return { x = x, y = 0, z = z or 0, leaderX = lx, leaderY = 0, leaderZ = lz or 0, motion = motion or "IDLE" }
end
local policy = Policy.new()
local s = sample(0, 5)
local intent, point = policy:tick(s, 0)
check(intent == "MOVE" and point.x == 5 and point.z == 0, "follow requests leader position")
policy:accepted(s, 0)
check(policy:tick(s, 100) == "WAIT", "decision throttled")
s.motion = "MOVING"
check(policy:tick(s, 500) == "WAIT", "same target does not restart native path")
s.leaderX = 6
check(policy:tick(s, 1000) == "WAIT", "minor target jitter does not replan")
s.leaderX = 7
check(policy:tick(s, 1500) == "MOVE", "large target change can replan after cooldown")
policy:accepted(s, 1500)
s.x = 6
check(policy:tick(s, 2000) == "STOP", "near leader stops existing movement")
s.motion, s.x = "STOPPED", 4.5
check(policy:tick(s, 2500) == "WAIT", "hysteresis avoids restarting inside three tiles")
s.x = 3
check(policy:tick(s, 3000) == "MOVE", "restart after leaving outer radius")
policy = Policy.new()
intent, point = policy:tick(sample(0, 0, 0, 1), 0)
check(intent == "MOVE" and point.z == 1, "same XY downstairs must follow upstairs")
intent, point = Policy.new():tick(sample(0, 0, 0, 0.5), 0)
check(intent == "MOVE" and point.z == 0, "stair target requests integral floor")
check(Policy.new():tick(sample(0, 16.01), 0) == "BLOCK", "out of bounded range blocks")
check(Policy.new():tick(sample(0, 16), 0) == "MOVE", "range boundary accepted")
for _, invalid in ipairs({ math.huge, -math.huge, 0/0 }) do
    check(Policy.new():tick(sample(0, invalid), 0) == "BLOCK", "invalid coordinate rejected")
end
check(Policy.new():tick(nil, 0) == "BLOCK", "missing actor/carrier blocks")
check(Policy.new():tick(sample(0, 5, 0, 0, "MOVING"), 0) == "BLOCK", "does not steal unowned movement")
policy = Policy.new()
s = sample(0, 6)
for i = 1, 3 do
    local time = (i - 1) * 3000
    s.motion = "IDLE"
    check(policy:tick(s, time) == "MOVE", "bounded retry can issue request")
    policy:accepted(s, time)
    s.motion = "FAILED"
    local outcome = policy:tick(s, time + 500)
    check(outcome == (i == 3 and "BLOCK" or "WAIT"), "third consecutive native failure stops retries")
    if i < 3 then check(policy:tick(s, time + 1000) == "WAIT", "native failure has backoff") end
end
policy = Policy.new()
check(not policy:rejected(0), "first refused request has retry budget")
check(not policy:rejected(1500), "second refusal still bounded")
check(policy:rejected(3000), "third refusal exhausts budget")
policy = Policy.new()
policy.failures = 2
s = sample(0, 1)
check(policy:tick(s, 0) == "WAIT" and policy.failures == 0, "actual proximity clears consecutive failure count")
print("PASS " .. count .. " follow policy assertions; native engine NOT simulated")
