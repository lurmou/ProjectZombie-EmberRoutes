local Policy = {}
Policy.__index = Policy

function Policy.new()
    return setmetatable({ nextSample = 0, lastRequest = -10000, retryAt = 0, failures = 0, awaiting = false }, Policy)
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Policy:accepted(sample, time)
    self.awaiting = true
    self.lastRequest = time
    self.target = { x = sample.leaderX, y = sample.leaderY, z = sample.leaderZ }
end

function Policy:rejected(time)
    self.awaiting = false
    self.failures = self.failures + 1
    self.retryAt = time + 1500
    return self.failures >= 3
end

function Policy:tick(s, time)
    if time < self.nextSample then return "WAIT", "THROTTLED" end
    self.nextSample = time + 500
    if not s then return "BLOCK", "LEADER_OR_CARRIER_UNAVAILABLE" end
    for _, key in ipairs({ "x", "y", "z", "leaderX", "leaderY", "leaderZ" }) do
        if not finite(s[key]) then return "BLOCK", "INVALID_POSITION" end
    end
    local dx, dy, dz = s.x - s.leaderX, s.y - s.leaderY, s.z - s.leaderZ
    local distance2 = dx * dx + dy * dy + dz * dz
    if distance2 > 256 then return "BLOCK", "LEADER_TOO_FAR" end
    local sameFloor = math.floor(s.z + 0.001) == math.floor(s.leaderZ + 0.001) and math.abs(dz) <= 0.2
    if sameFloor and distance2 <= 4 then
        self.awaiting, self.failures = false, 0
        return s.motion == "MOVING" and "STOP" or "WAIT", "NEAR_LEADER"
    end
    if self.awaiting and s.motion ~= "MOVING" then
        self.awaiting = false
        if s.motion == "REACHED" then self.failures = 0
        elseif self:rejected(time) then return "BLOCK", "PATH_FAILURE_LIMIT"
        end
    end
    if s.motion == "MOVING" then
        local target = self.target
        if not target then return "BLOCK", "UNOWNED_MOVEMENT" end
        local tx, ty, tz = target.x - s.leaderX, target.y - s.leaderY, target.z - s.leaderZ
        if tx * tx + ty * ty + tz * tz < 2.25 then return "WAIT", "PATH_IN_PROGRESS" end
    elseif sameFloor and distance2 <= 9 then return "WAIT", "WITHIN_START_RADIUS" end
    if time < self.retryAt or time - self.lastRequest < 1000 then return "WAIT", "REQUEST_COOLDOWN" end
    return "MOVE", { x = s.leaderX, y = s.leaderY, z = math.floor(s.leaderZ + 0.001) }
end

return Policy
