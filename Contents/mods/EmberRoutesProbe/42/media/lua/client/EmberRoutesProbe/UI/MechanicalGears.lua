--[[
    MechanicalGears.lua - EmberRoutes UI
    Mechanism 6: Interlocking Counter-Rotating Gear Mechanism & Transmission Drive.
    
    Architectural Compliance:
      - Real Asset Loading: Pre-loads vanilla textures (Button_Gear.png / gears.png) with
        guaranteed fallback to stylized vector cogwheel geometry if textures are unready.
      - Counter-Rotating Kinematics: Driven gear rotates at exact gear ratio:
          omega2 = -omega1 * (R1 / R2)
      - Dynamic Load Speed: Rotational velocity smoothly scales with production activity;
        decelerates smoothly to a stop when work is idle.
      - Safe Native Draw: Uses ISUIElement:DrawTextureAngle with javaObject verification.
      - Zero-GC: Immutable color scalars, zero table allocations in render/prerender.
]]

local Theme = require 'EmberRoutesProbe/UI/Theme'

local MechanicalGears = {}

-- Pre-cached vanilla gear textures
local TEX_PRIMARY_GEAR = nil
local TEX_SECONDARY_GEAR = nil

-- Each texture is requested once. A missing texture must not turn into a
-- getTexture call on every draw frame.
local primaryTried,secondaryTried=false,false
local function ensureTextures()
    if not primaryTried and not TEX_PRIMARY_GEAR then
        primaryTried=true
        if type(getTexture)=="function" then
            TEX_PRIMARY_GEAR = getTexture("media/ui/inventoryPanes/Button_Gear.png")
        end
    end
    if not secondaryTried and not TEX_SECONDARY_GEAR then
        secondaryTried=true
        if type(getTexture)=="function" then
            TEX_SECONDARY_GEAR = getTexture("media/ui/gears.png")
        end
    end
end

-- Pre-allocated immutable palette (Zero GC)
local COLOR_GEAR_BASE   = {r = 0.35, g = 0.42, b = 0.50, a = 0.85}
local COLOR_GEAR_HUB    = {r = 0.18, g = 0.22, b = 0.28, a = 0.95}
local COLOR_GEAR_BORDER = {r = 0.55, g = 0.65, b = 0.75, a = 0.90}

---Creates a gear transmission state container.
---@param r1 number? Driver gear radius (default 24px)
---@param r2 number? Driven gear radius (default 14px)
---@return table
function MechanicalGears.createState(r1, r2)
    local radius1 = r1 or 24
    local radius2 = r2 or 14
    return {
        r1 = radius1,
        r2 = radius2,
        ratio = radius1 / radius2,
        angle = 0.0,
        currentSpeed = 0.0,
        targetSpeed = 0.0
    }
end

---Updates rotational kinematics step.
---@param state table
---@param isActive boolean Whether machinery/work is actively running
---@param loadFactor number? Workload multiplier (0.0 to 2.0, default 1.0)
function MechanicalGears.update(state, isActive, loadFactor)
    if not state then return end
    local mult = loadFactor or 1.0
    state.targetSpeed = isActive and (2.2 * mult) or 0.0

    local dt = UIManager.getMillisSinceLastRender() / 1000.0
    if dt > 0.1 then dt = 0.1 end
    if dt <= 0 then dt = 0.016 end

    -- Smooth acceleration / deceleration
    local diff = state.targetSpeed - state.currentSpeed
    state.currentSpeed = state.currentSpeed + diff * (1.0 - math.exp(-6.0 * dt))

    -- Integrate angle
    state.angle = (state.angle + state.currentSpeed) % 360.0
end

---Draws a vector cogwheel with a real circular silhouette, radial teeth and an
---axle bore. Fallback for when vanilla gear textures are unavailable.
---Scanline disc is computed from scalar math only: no table allocation in draw.
local function drawVectorGear(owner, cx, cy, radius, angle, numTeeth)
    local rad = math.rad(angle)
    local r = math.max(3, math.floor(radius))
    local toothW = math.max(2, math.floor(r * 0.30))
    local toothH = math.max(2, math.floor(r * 0.30))

    -- Teeth first: the disc overlaps their inner halves so they read as a rim.
    for i = 0, (numTeeth - 1) do
        local a = rad + (i * (math.pi * 2 / numTeeth))
        local tx = cx + math.floor(math.cos(a) * r) - math.floor(toothW / 2)
        local ty = cy + math.floor(math.sin(a) * r) - math.floor(toothH / 2)
        Theme.rect(owner, tx, ty, toothW, toothH, COLOR_GEAR_BORDER)
    end

    -- Circular body, one 1px scanline per row (never a solid square).
    for dy = -r, r do
        local half = math.floor(math.sqrt(math.max(0, r * r - dy * dy)))
        Theme.rect(owner, cx - half, cy + dy, half * 2 + 1, 1, COLOR_GEAR_BASE)
    end

    -- Bright outer rim: only the 1px ring where the disc is wider than r-1.
    for dy = -r, r do
        local outer = math.floor(math.sqrt(math.max(0, r * r - dy * dy)))
        local inner = math.floor(math.sqrt(math.max(0, (r - 1) * (r - 1) - dy * dy)))
        if outer > inner then
            Theme.rect(owner, cx - outer, cy + dy, 1, 1, COLOR_GEAR_BORDER)
            Theme.rect(owner, cx + outer, cy + dy, 1, 1, COLOR_GEAR_BORDER)
        end
    end

    -- Axle bore with a visible hub ring, matching the vanilla Button_Gear look.
    local hubR = math.max(1, math.floor(r * 0.32))
    local hubD = hubR * 2 + 1
    Theme.rect(owner, cx - hubR, cy - hubR, hubD, hubD, COLOR_GEAR_HUB)
    Theme.rect(owner, cx - hubR, cy - hubR, hubD, hubD, COLOR_GEAR_BORDER, true)
end

---Draws interlocking two-gear transmission drive.
---@param owner ISPanel
---@param cx number Driver gear center X
---@param cy number Driver gear center Y
---@param state table
---@param opts table?
function MechanicalGears.draw(owner, cx, cy, state, opts)
    opts = opts or {}
    ensureTextures()

    local r1 = state and state.r1 or 24
    local r2 = state and state.r2 or 14
    local ratio = state and state.ratio or (r1 / r2)
    local a1 = state and state.angle or 0.0
    -- Driven gear counter-rotates in reverse direction:
    local a2 = (-a1 * ratio) % 360.0
    -- A slim status strip has no room for two interlocking gears: at compact
    -- radii they overlap into a pixel blob, so show only the driver gear.
    local compact = (r1 <= 14)

    -- Calculate driven gear center offset (interlocking teeth overlap by 4px)
    local dist = r1 + r2 - 4
    local offsetAngle = opts.drivenAngle or (-math.pi / 4) -- upper-right offset by default
    local c2x = cx + math.floor(math.cos(offsetAngle) * dist)
    local c2y = cy + math.floor(math.sin(offsetAngle) * dist)

    local canDrawAngle = (owner.DrawTextureAngle ~= nil) and (owner.javaObject ~= nil)
    local canDrawScaled = (owner.drawTextureScaledAspect ~= nil)

    -- 1. Draw Driver Gear (Primary).
    -- A slim 28px strip cannot host the vanilla gear at native (~30px) size:
    -- it covers the title. Scale it into the reserved 2*r1+2 slot instead and
    -- let the load factor drive its opacity (idle = dim, running = bright).
    if compact and canDrawScaled and TEX_PRIMARY_GEAR and not opts.vector then
        local size = r1 * 2 + 2
        local speed = state and state.currentSpeed or 0.0
        local alpha = 0.55 + 0.45 * math.min(1.0, speed / 2.2)
        owner:drawTextureScaledAspect(TEX_PRIMARY_GEAR, cx - r1 - 1, cy - r1 - 1,
            size, size, 1.0, 1.0, 1.0, alpha)
    elseif canDrawAngle and TEX_PRIMARY_GEAR and not opts.vector then
        owner:DrawTextureAngle(TEX_PRIMARY_GEAR, cx, cy, a1)
    else
        drawVectorGear(owner, cx, cy, r1, a1, 8)
    end

    -- 2. Draw Driven Gear (Secondary, Counter-rotating) -- full-size only.
    if not compact then
        if canDrawAngle and TEX_SECONDARY_GEAR and not opts.vector then
            owner:DrawTextureAngle(TEX_SECONDARY_GEAR, c2x, c2y, a2)
        else
            drawVectorGear(owner, c2x, c2y, r2, a2, 6)
        end
    end
end

return MechanicalGears
