local assertions = 0
local function check(v, m)
    assertions = assertions + 1
    assert(v, m or ("Assertion failed: #" .. tostring(assertions)))
end

-- Mock PZ environment
local currentTime = 1000
function getTimestampMs() return currentTime end
function getText(key) return "[" .. tostring(key) .. "]" end

local seed = 12345
function ZombRand(n)
    if not n or n <= 1 then return 0 end
    seed = (seed * 1103515245 + 12345) % 2147483648
    return math.floor(seed % n)
end

local player = { x = 0, y = 0, z = 0, dead = false, sneaking = false }
function player:getX() return self.x end
function player:getY() return self.y end
function player:getZ() return self.z end
function player:isDead() return self.dead end
function player:isSneaking() return self.sneaking end

function getSpecificPlayer(idx)
    if idx == 0 then return player end
    return nil
end

local actor = { x = 5, y = 5, z = 0, dead = false, asleep = false, lastSay = nil, sayCount = 0 }
function actor:getX() return self.x end
function actor:getY() return self.y end
function actor:getZ() return self.z end
function actor:isDead() return self.dead end
function actor:isAsleep() return self.asleep end
function actor:Say(line, r, g, b, font, dist, tag)
    self.lastSay = { line = line, r = r, g = g, b = b, font = font, dist = dist, tag = tag }
    self.sayCount = self.sayCount + 1
end

local Catalog = require "EmberRoutesProbe/Chatter/ChatterCatalog"
local Service = require "EmberRoutesProbe/Chatter/ChatterService"

-- Test 1: Catalog basic lookup and colors
local line, r, g, b, font, urgent = Catalog.get("HEALTH_BLEEDING")
check(line ~= nil and line ~= "", "Catalog returns bleeding bark")
check(r == 1.0 and g == 0.25 and b == 0.25, "Bleeding bark has crisis red color")
check(urgent == true, "Bleeding bark is urgent")

local lineCmd, rCmd, gCmd, bCmd = Catalog.get("CMD_FOLLOW")
check(lineCmd ~= nil and lineCmd ~= "", "Catalog returns follow bark")
check(rCmd == 0.30 and gCmd == 1.00 and bCmd == 0.50, "Command bark has order green color")

-- Test 2: Combinatorial randomness and high entropy
local uniqueBleed = {}
for i = 1, 40 do
    local generated = Catalog.get("HEALTH_BLEEDING")
    uniqueBleed[generated] = true
end
local distinctCount = 0
for _ in pairs(uniqueBleed) do distinctCount = distinctCount + 1 end
check(distinctCount >= 4, "Slot-based assembly generates diverse barks for bleeding (distinct: " .. tostring(distinctCount) .. ")")

local uniqueFollow = {}
for i = 1, 40 do
    local genFollow = Catalog.get("CMD_FOLLOW")
    uniqueFollow[genFollow] = true
end
local distinctFollow = 0
for _ in pairs(uniqueFollow) do distinctFollow = distinctFollow + 1 end
check(distinctFollow >= 4, "Slot-based assembly generates diverse barks for follow (distinct: " .. tostring(distinctFollow) .. ")")

Translator = { getLanguage = function() return { name = function() return "EN" end } end }
local enLine = Catalog.get("CMD_FOLLOW")
check(enLine:find(" ") ~= nil, "English mode assembles parts with space separators")
Translator = nil

-- Test 3: Standard speech within distance
currentTime = 1000
actor.sayCount = 0
local spoke = Service.speak(actor, "CMD_FOLLOW")
check(spoke == true, "Actor speaks CMD_FOLLOW within 30 tiles")
check(actor.sayCount == 1, "Actor:Say called once")
check(actor.lastSay.dist == 30.0, "Standard bark distance is 30.0 (native Say radius)")

-- Test 4: Regular cooldown (8s)
currentTime = 2000 -- only 1s passed
local spokeAgain = Service.speak(actor, "CMD_FOLLOW")
check(spokeAgain == false, "Actor cannot speak again during 8s cooldown")
check(actor.sayCount == 1, "Actor:Say count unchanged")

-- Test 5: Urgent bypasses regular cooldown
local spokeUrgent = Service.speak(actor, "HEALTH_BLEEDING")
check(spokeUrgent == true, "Urgent bark bypasses regular cooldown")
check(actor.sayCount == 2, "Actor:Say called for urgent bark")
check(actor.lastSay.r == 1.0 and actor.lastSay.g == 0.25, "Urgent bark has red color")

-- Test 6: Urgent anti-spam (4s throttle per urgent event)
currentTime = 3000 -- only 1s passed since urgent
local spokeUrgentSpam = Service.speak(actor, "HEALTH_BLEEDING")
check(spokeUrgentSpam == false, "Same urgent bark throttled within 4s")

-- Test 7: Distance guard (> 30 tiles, native Say radius)
currentTime = 20000 -- reset cooldowns
actor.x = 25 -- distSq = 25*25 + 5*5 = 650 < 900: inside the 30-tile hearing gate
local spokeNear = Service.speak(actor, "CMD_FOLLOW")
check(spokeNear == true, "Actor at 25 tiles still speaks within 30-tile gate")
currentTime = 30000 -- reset cooldown after the pin above
actor.x = 35 -- distSq = 35*35 + 5*5 = 1250 > 900
local spokeFar = Service.speak(actor, "CMD_FOLLOW")
check(spokeFar == false, "Actor beyond 30 tiles stays quiet")
actor.x = 5 -- restore position

-- Test 8: Floor guard (different Z)
actor.z = 1
player.z = 0
local spokeFloor = Service.speak(actor, "CMD_FOLLOW")
check(spokeFloor == false, "Actor on different floor stays quiet")
actor.z = 0 -- restore

-- Test 9: Sleep silence
actor.asleep = true
local spokeAsleep = Service.speak(actor, "HEALTH_BLEEDING")
check(spokeAsleep == false, "Asleep actor stays quiet even for bleeding")
actor.asleep = false

-- Test 10: Stealth etiquette (player sneaking)
player.sneaking = true
currentTime = 30000
local spokeSneakCasual = Service.speak(actor, "CMD_FOLLOW")
check(spokeSneakCasual == false, "Casual chatter suppressed when player sneaks")

local spokeSneakUrgent = Service.speak(actor, "HEALTH_BLEEDING")
check(spokeSneakUrgent == true, "Urgent chatter allowed during sneak")
check(actor.lastSay.dist == 10.0, "Urgent chatter during sneak drops to 10.0 whisper distance (native SayWhisper radius)")
player.sneaking = false

-- Test 11: onActionResult
currentTime = 40000
actor.sayCount = 0
local resInjured = Service.onActionResult(actor, "INJURED")
check(resInjured == true, "onActionResult handles INJURED")
check(actor.sayCount == 1, "Actor:Say triggered for INJURED")

-- Contract change (P0): STORAGE_FULL / NO_TOOL have no production producer,
-- so onActionResult now rejects unknown result codes instead of speaking.
local resUnknown = Service.onActionResult(actor, "STORAGE_FULL")
check(resUnknown == false, "Result code with no production contract is rejected")
currentTime = 50000
check(Service.onActionResult(actor, "STORAGE_FULL") == false, "Rejection is stable after cooldown")

-- Test 12: observeHealth edge detection
currentTime = 60000
actor.sayCount = 0
Service.observeHealth(actor, { bleeding = false, deep = false })
check(actor.sayCount == 0, "No bark for healthy state")

-- Rising edge on bleeding
currentTime = 61000
Service.observeHealth(actor, { bleeding = true, deep = false })
check(actor.sayCount == 1, "Rising edge on bleeding triggers bark")

-- Ongoing bleeding (same state) stays quiet
currentTime = 66000
Service.observeHealth(actor, { bleeding = true, deep = false })
check(actor.sayCount == 1, "Continuous bleeding does not repeatedly bark")

-- Rising edge on deep wound
currentTime = 71000
Service.observeHealth(actor, { bleeding = true, deep = true })
check(actor.sayCount == 2, "Rising edge on deep wound triggers bark")

-- Test 13: Purge
Service.purge(actor)
local inspect = Service._inspect(actor)
check(inspect.cooldown == nil and inspect.urgentCooldown == nil and inspect.edge == nil, "Purge clears all actor cache")

print("PASS " .. tostring(assertions) .. " chatter service checks; native host mocked")
