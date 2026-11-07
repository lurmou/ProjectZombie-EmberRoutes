--[[
    spring-driver-test.lua - EmberRoutes UI
    Unit tests for SpringDriver: zero-GC kinetic physics & spring dynamics.
]]

package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path

local checks = 0
local function check(value, message)
    assert(value, message or "Assertion failed")
    checks = checks + 1
end

local SpringDriver = require "EmberRoutesProbe/UI/SpringDriver"

-- ==============================================================================
-- Test 1: 1D Spring Lifecycle & Physics
-- ==============================================================================
do
    local spring = SpringDriver.create(100, { stiffness = 300, damping = 25, precision = 0.05 })
    check(spring.val == 100, "Initial value matches")
    check(spring.target == 100, "Initial target matches")
    check(spring.vel == 0, "Initial velocity is zero")
    check(spring.settled == true, "Initially settled")

    -- Snap
    SpringDriver.snap(spring, 200)
    check(spring.val == 200 and spring.target == 200 and spring.settled == true, "Snap immediately relocates value and settles")

    -- Move target to 400
    local target = 400
    local prevVal = spring.val
    local steps = 0

    -- Step physics with 60fps dt (0.016s)
    repeat
        steps = steps + 1
        local cur = SpringDriver.update(spring, target, 0.016)
        check(cur == spring.val, "Update returns current value")
        -- Should be moving towards target
        if steps < 10 then
            check(spring.val > prevVal, "Spring is accelerating towards target")
        end
        prevVal = spring.val
    until spring.settled or steps >= 120

    check(spring.settled == true, "Spring settled within reasonable frame count")
    check(math.abs(spring.val - target) <= 0.05, "Settled value is within precision tolerance of target")
    check(spring.val == target, "Settled snaps exactly to target")
    check(spring.vel == 0, "Velocity zeroed upon settling")

    -- Early exit optimization when settled
    local callsVal = SpringDriver.update(spring, target, 0.016)
    check(callsVal == target and spring.settled == true, "Settled state performs early exit")
end

-- ==============================================================================
-- Test 2: dt Clamping (Stall & Explosion Protection)
-- ==============================================================================
do
    local spring = SpringDriver.create(0, { stiffness = 400, damping = 20 })
    -- Simulate a 5-second massive freeze spike
    SpringDriver.update(spring, 100, 5.0)
    check(spring.val > 0 and spring.val < 150, "dt clamping prevents numeric explosion on extreme stalls")
end

-- ==============================================================================
-- Test 3: 2D Spring Vector (Shared Layout X & Width Tracking)
-- ==============================================================================
do
    local v2 = SpringDriver.create2D(10, 50, { stiffness = 280, damping = 26 })
    check(v2.a == 10 and v2.b == 50, "2D initial values match")
    check(v2.settled == true, "2D initially settled")

    SpringDriver.snap2D(v2, 20, 60)
    check(v2.a == 20 and v2.b == 60 and v2.settled == true, "2D snap works symmetrically")

    -- Target: X=120, W=80
    local steps = 0
    repeat
        steps = steps + 1
        local curA, curB = SpringDriver.update2D(v2, 120, 80, 0.016)
        check(curA == v2.a and curB == v2.b, "update2D returns both coordinates")
    until v2.settled or steps >= 150

    check(v2.settled == true, "2D settled")
    check(v2.a == 120 and v2.b == 80, "2D snapped exactly to targets")
    check(v2.velA == 0 and v2.velB == 0, "2D velocities zeroed")
end

-- ==============================================================================
-- Test 4: Smooth Mode (Exponential Decay / Critically Damped ease-out)
-- ==============================================================================
do
    local smooth = SpringDriver.create(0, { mode = "smooth", damping = 12, precision = 0.01 })
    check(smooth.mode == "smooth", "Mode set to smooth")

    local steps = 0
    repeat
        steps = steps + 1
        SpringDriver.update(smooth, 100, 0.016)
        check(smooth.val <= 100, "Smooth mode never overshoots target")
    until smooth.settled or steps >= 120

    check(smooth.settled == true, "Smooth mode settled")
    check(smooth.val == 100, "Smooth mode reached target")
end

-- ==============================================================================
-- Test 5: FilterChips Shared Layout Kinetic Indicator Integration
-- ==============================================================================
do
    UIFont = { Small = 1 }
    getTextManager = function()
        return {
            getFontHeight = function() return 18 end,
            MeasureStringX = function(self, font, str) return (#(str or "")) * 8 end
        }
    end
    ISPanel = {
        derive = function(self, name)
            local sub = {}
            for k, v in pairs(self) do sub[k] = v end
            sub.Type = name
            return sub
        end,
        new = function(self, x, y, w, h)
            local o = {}
            for k, v in pairs(self) do o[k] = v end
            o.x = x or 0
            o.y = y or 0
            o.width = w or 100
            o.height = h or 20
            return o
        end,
        initialise = function(self) end,
        prerender = function(self) end,
        render = function(self) end,
        drawRect = function(self) end,
        drawRectBorder = function(self) end,
        drawText = function(self) end,
        getMouseX = function(self) return 0 end,
        getMouseY = function(self) return 0 end
    }
    package.loaded["ISUI/ISPanel"] = ISPanel

    local FilterChips = require "EmberRoutesProbe/UI/FilterChips"
    local chips = FilterChips:new(0, 0, 400, 26)
    check(chips.indicator ~= nil, "FilterChips creates indicator spring state")
    check(chips.indicatorInitialized == false, "Indicator initially uninitialized")

    chips:setOptions({
        { id = "alpha", label = "Alpha Tab" },
        { id = "beta", label = "Beta Tab" },
        { id = "gamma", label = "Gamma Tab" }
    }, "alpha")

    check(#chips.chips == 3, "Created 3 chip bounds")
    local chip1 = chips.chips[1]
    local chip2 = chips.chips[2]
    local chip3 = chips.chips[3]
    check(chip2.x > chip1.x, "Chip 2 is to the right of Chip 1")

    -- First prerender should snap indicator to initial selection
    chips:prerender()
    check(chips.indicatorInitialized == true, "First prerender initializes indicator")
    check(chips.indicator.a == chip1.x, "Indicator snaps to initial chip X")
    check(chips.indicator.b == chip1.width, "Indicator snaps to initial chip width")
    check(chips.indicator.settled == true, "Indicator starts settled")

    -- Select Beta (gliding transition)
    chips:setSelected("beta")
    chips:prerender() -- 1st physics tick
    check(chips.indicator.settled == false, "Indicator becomes unsettled upon target transition")
    check(chips.indicator.a > chip1.x, "Indicator begins sliding towards Beta")

    -- Step until settled at Beta
    local steps = 0
    repeat
        steps = steps + 1
        chips:prerender()
    until chips.indicator.settled or steps >= 120

    check(chips.indicator.settled == true, "Indicator smoothly settles at target tab")
    check(chips.indicator.a == chip2.x, "Settled indicator X matches Beta tab")
    check(chips.indicator.b == chip2.width, "Settled indicator width matches Beta tab")

    -- Instant snap test
    chips:setSelected("gamma", true)
    check(chips.indicator.a == chip3.x, "Immediate setSelected snaps X instantly")
    check(chips.indicator.b == chip3.width, "Immediate setSelected snaps width instantly")
    check(chips.indicator.settled == true, "Indicator remains settled after instant snap")

    -- Underline variant
    chips.variant = "underline"
    chips:setSelected("alpha")
    chips:prerender()
    check(chips.indicator.settled == false, "Underline variant slides indicator correctly")
end

print("spring-driver-test: " .. checks .. " PASS")
return true
