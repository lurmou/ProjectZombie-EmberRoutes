--[[
    SpringDriver.lua - EmberRoutes UI
    Mechanism: Headless Zero-GC Spring Dynamics & Kinetic Smoothing Engine.
    
    Inspired by Motion.dev physics (stiffness, damping, mass) and EasyUI micro-interactions.
    Designed specifically for Project Zomboid v42 Java/LWJGL environment:
      - 100% Zero-GC in render/prerender: operates entirely on pre-allocated scalar fields.
      - Dual-mode support: Physical 2nd-order damped spring & Exponential Critically Damped decay.
      - Auto-settle bypass: ceases mathematical evaluations once equilibrium is reached.
      - Clamp safety: bounds time delta against engine frame drops to eliminate numerical oscillation.
]]

local SpringDriver = {}

---Creates a 1D scalar spring state.
---@param initialVal number? Initial scalar value (default 0.0)
---@param opts table? Configuration options:
---   - stiffness: number (default 280.0, controls speed/snappiness)
---   - damping: number (default 26.0, controls friction/overshoot)
---   - precision: number (default 0.1, threshold to snap and settle)
---   - mode: "spring"|"smooth" (default "spring")
---@return table
function SpringDriver.create(initialVal, opts)
    opts = opts or {}
    local v = initialVal or 0.0
    return {
        val = v,
        target = v,
        vel = 0.0,
        stiffness = opts.stiffness or 280.0,
        damping = opts.damping or 26.0,
        precision = opts.precision or 0.1,
        settled = true,
        mode = opts.mode or "spring"
    }
end

---Creates a 2D scalar spring state (e.g. for X & Width, or X & Y tracking).
---Pre-allocating a 2D container cuts property lookups in half compared to two separate tables.
---@param initA number? Initial A value (e.g. position X)
---@param initB number? Initial B value (e.g. width)
---@param opts table? Configuration options
---@return table
function SpringDriver.create2D(initA, initB, opts)
    opts = opts or {}
    local a = initA or 0.0
    local b = initB or 0.0
    return {
        a = a,
        targetA = a,
        velA = 0.0,
        b = b,
        targetB = b,
        velB = 0.0,
        stiffness = opts.stiffness or 280.0,
        damping = opts.damping or 26.0,
        precision = opts.precision or 0.1,
        settled = true,
        mode = opts.mode or "spring"
    }
end

---Steps a 1D spring towards target value.
---@param state table The pre-allocated spring state
---@param target number Target value to pursue
---@param dt number Time delta in seconds (typically UIManager.getMillisSinceLastRender() / 1000.0)
---@return number currentVal
function SpringDriver.update(state, target, dt)
    if not state then return target end
    state.target = target

    -- Early exit if already at rest at destination
    if state.settled and state.val == target and state.vel == 0.0 then
        return state.val
    end
    state.settled = false

    -- Clamping dt to [0.001, 0.050] eliminates explosion during background alt-tab or game stalls
    local step = dt
    if not step or step <= 0.0 then step = 0.016 end
    if step > 0.05 then step = 0.05 end

    if state.mode == "smooth" then
        local diff = target - state.val
        if math.abs(diff) < state.precision then
            state.val = target
            state.vel = 0.0
            state.settled = true
            return state.val
        end
        state.settled = false
        state.val = state.val + diff * (1.0 - math.exp(-state.damping * step))
        return state.val
    end

    -- Semi-implicit Euler integration for 2nd order mass-spring-damper system
    local diff = state.val - target
    local accel = -state.stiffness * diff - state.damping * state.vel

    state.vel = state.vel + accel * step
    state.val = state.val + state.vel * step

    if math.abs(state.val - target) < state.precision and math.abs(state.vel) < state.precision then
        state.val = target
        state.vel = 0.0
        state.settled = true
    else
        state.settled = false
    end

    return state.val
end

---Steps a 2D spring state towards target values. Zero table allocations.
---@param state table The pre-allocated 2D spring state
---@param targetA number Target value for A
---@param targetB number Target value for B
---@param dt number Time delta in seconds
---@return number curA, number curB
function SpringDriver.update2D(state, targetA, targetB, dt)
    if not state then return targetA, targetB end
    state.targetA = targetA
    state.targetB = targetB

    if state.settled and state.a == targetA and state.b == targetB and state.velA == 0.0 and state.velB == 0.0 then
        return state.a, state.b
    end
    state.settled = false

    local step = dt
    if not step or step <= 0.0 then step = 0.016 end
    if step > 0.05 then step = 0.05 end

    local diffA = state.a - targetA
    local diffB = state.b - targetB
    local accelA = -state.stiffness * diffA - state.damping * state.velA
    local accelB = -state.stiffness * diffB - state.damping * state.velB

    state.velA = state.velA + accelA * step
    state.a = state.a + state.velA * step

    state.velB = state.velB + accelB * step
    state.b = state.b + state.velB * step

    local settledA = math.abs(state.a - targetA) < state.precision and math.abs(state.velA) < state.precision
    local settledB = math.abs(state.b - targetB) < state.precision and math.abs(state.velB) < state.precision

    if settledA then
        state.a = targetA
        state.velA = 0.0
    end
    if settledB then
        state.b = targetB
        state.velB = 0.0
    end

    state.settled = settledA and settledB
    return state.a, state.b
end

---Immediately snaps 1D spring to value without animation.
---@param state table
---@param val number
function SpringDriver.snap(state, val)
    if not state then return end
    state.val = val
    state.target = val
    state.vel = 0.0
    state.settled = true
end

---Immediately snaps 2D spring to values without animation.
---@param state table
---@param a number
---@param b number
function SpringDriver.snap2D(state, a, b)
    if not state then return end
    state.a = a
    state.targetA = a
    state.velA = 0.0
    state.b = b
    state.targetB = b
    state.velB = 0.0
    state.settled = true
end

return SpringDriver
