-- Pure geometry: prepare the entire tree before publishing any leaf rectangle.
local Solver = {}
local EPSILON = 0.0001
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function prepare(node, x, y, width, height, visible)
    node._visible = visible
    if not visible then
        for i = 1, #node.items do
            local item = node.items[i]
            item._visible = false
            item._x, item._y, item._width, item._height = 0, 0, 0, 0
            if item.child then prepare(item.child, 0, 0, 0, 0, false) end
        end
        return true
    end
    local row = node.direction == "row"
    local p = node.padding
    local ps, pe, cs, ce = p.top, p.bottom, p.left, p.right
    local main, cross = height, width
    if row then ps, pe, cs, ce = p.left, p.right, p.top, p.bottom; main, cross = width, height end
    local count, fixed, grow, last, growScale = 0, 0, 0, 0, 0
    for i = 1, #node.items do
        local item = node.items[i]
        if item.visible then
            local m = item.margin
            local ms, me, mcs, mce = m.top, m.bottom, m.left, m.right
            if row then ms, me, mcs, mce = m.left, m.right, m.top, m.bottom end
            count = count + 1
            fixed = fixed + item.resolvedBasis + ms + me
            -- Sum scaled weights so finite individual grows cannot overflow the total.
            if item.grow > 0 then
                if item.grow > growScale then
                    grow = grow * (growScale / item.grow) + 1
                    growScale = item.grow
                else grow = grow + item.grow / growScale end
                last = i
            end
            local available = cross - cs - ce - mcs - mce
            if available < -EPSILON then return nil, "INSUFFICIENT_SPACE" end
            if (item.alignSelf or node.align) ~= "stretch" and item.resolvedCrossBasis > available + EPSILON then
                return nil, "INSUFFICIENT_SPACE"
            end
        end
    end
    local free = main - ps - pe - math.max(0, count - 1) * node.gap - fixed
    if free < -EPSILON or cross - cs - ce < -EPSILON then return nil, "INSUFFICIENT_SPACE" end
    if free < 0 then free = 0 end
    local cursor, gap, allocated = ps, node.gap, 0
    if grow == 0 then
        if node.justify == "center" then cursor = cursor + math.max(0, free / 2)
        elseif node.justify == "end" then cursor = cursor + math.max(0, free)
        elseif node.justify == "space-between" and count > 1 then gap = gap + math.max(0, free) / (count - 1) end
    end
    for i = 1, #node.items do
        local item = node.items[i]
        item._visible = item.visible
        if item.visible then
            local m = item.margin
            local ms, me, mcs, mce = m.top, m.bottom, m.left, m.right
            if row then ms, me, mcs, mce = m.left, m.right, m.top, m.bottom end
            local allocation = 0
            if item.grow > 0 then
                if i == last then allocation = free - allocated
                else allocation = free * ((item.grow / growScale) / grow) end
                allocated = allocated + allocation
            end
            local size = math.max(0, item.resolvedBasis + allocation)
            local available = cross - cs - ce - mcs - mce
            local crossSize, offset = item.resolvedCrossBasis, cs + mcs
            local align = item.alignSelf or node.align
            if align == "stretch" then crossSize = math.max(0, available)
            elseif align == "center" then offset = offset + math.max(0, (available - crossSize) / 2)
            elseif align == "end" then offset = offset + math.max(0, available - crossSize) end
            cursor = cursor + ms
            if row then item._x, item._y, item._width, item._height = x + cursor, y + offset, size, crossSize
            else item._x, item._y, item._width, item._height = x + offset, y + cursor, crossSize, size end
            if item.child then
                local ok, err = prepare(item.child, item._x, item._y, item._width, item._height, true)
                if not ok then return nil, err end
            end
            cursor = cursor + size + me + gap
        else
            item._visible = false
            item._x, item._y, item._width, item._height = 0, 0, 0, 0
            if item.child then prepare(item.child, 0, 0, 0, 0, false) end
        end
    end
    return true
end
local function publish(node, pool)
    for i = 1, #node.items do
        local item = node.items[i]
        if item.child then publish(item.child, pool)
        else
            local slot = pool[item.slotIndex]
            slot.visible = item._visible
            if item._visible then
                slot.x, slot.y, slot.width, slot.height = item._x, item._y, item._width, item._height
            else
                slot.x, slot.y, slot.width, slot.height = 0, 0, 0, 0
            end
        end
    end
    node.dirty = false
end
local function invalidate(node)
    node.dirty = true
    for i = 1, #node.items do
        local child = node.items[i].child
        if child then invalidate(child) end
    end
end
function Solver.solve(root, bounds)
    assert(root and not root.disposed and root.root == root, "EXPECTED_LIVE_LAYOUT_ROOT")
    if type(bounds) ~= "table" or not finite(bounds.width) or not finite(bounds.height)
        or bounds.width <= 0 or bounds.height <= 0 then
        invalidate(root)
        return nil, "INVALID_BOUNDS"
    end
    local ok, err = prepare(root, 0, 0, bounds.width, bounds.height, true)
    if not ok then invalidate(root); return nil, err end
    publish(root, root._rectPool)
    root._rootLocked = true
    return root._rectPool
end
return Solver
