-- Construction owns topology and pool allocation; solving only overwrites scalars.
local Solver = require "EmberRoutesProbe/UI/LayoutSolver"
local Node = {}
Node.__index = Node
local function number(value)
    assert(type(value) == "number" and value == value and value >= 0 and value < math.huge, "INVALID_LAYOUT_NUMBER")
    return value
end
local function edges(out, value)
    if type(value) == "table" then
        local top, right = number(value.top or 0), number(value.right or 0)
        local bottom, left = number(value.bottom or 0), number(value.left or 0)
        local changed=out.top~=top or out.right~=right or out.bottom~=bottom or out.left~=left
        out.top, out.right, out.bottom, out.left = top, right, bottom, left
        return changed
    else
        local n = number(value or 0)
        local changed=out.top~=n or out.right~=n or out.bottom~=n or out.left~=n
        out.top, out.right, out.bottom, out.left = n, n, n, n
        return changed
    end
end
local function alignment(value)
    assert(value == "stretch" or value == "start" or value == "center" or value == "end", "INVALID_ALIGN")
    return value
end
local function justify(value)
    assert(value == "start" or value == "center" or value == "end" or value == "space-between", "INVALID_JUSTIFY")
    return value
end
local function bindRoot(node, root)
    local oldPool = node._rectPool
    node.root = root
    node._rectPool = root._rectPool
    for i = 1, #node.items do
        local item = node.items[i]
        if item.child then
            bindRoot(item.child, root)
        else
            oldPool[item.slotIndex].visible = false
            item.slotIndex = #root._rectPool + 1
            root._rectPool[item.slotIndex] = { x = 0, y = 0, width = 0, height = 0, visible = false }
        end
    end
end
function Node.new(props)
    props = props or {}
    local self = setmetatable({ items = {}, padding = {}, _rectPool = {}, dirty = true,
        parent = false, parentItem = false, disposed = false, _visible = false,
        revision = 0, _rootLocked = false, _rootClaimed = false }, Node)
    self.root = self
    self.direction = props.direction or "column"
    assert(self.direction == "row" or self.direction == "column", "INVALID_DIRECTION")
    self.gap = number(props.gap or 0)
    self.align = alignment(props.align or "stretch")
    self.justify = justify(props.justify or "start")
    edges(self.padding, props.padding)
    return self
end
-- A native host claims its independent root before publishing any geometry.
function Node:claimRoot()
    assert(not self.disposed and self.root==self and not self._rootClaimed, "LAYOUT_ROOT_ALREADY_CLAIMED")
    self._rootClaimed=true
end
function Node:markDirty()
    local node = self
    while node do
        assert(not node.disposed, "DISPOSED_LAYOUT_NODE")
        node.dirty = true
        node.revision = node.revision + 1
        node = node.parent
    end
end
local function owned(self, item)
    assert(not self.disposed and item and item.owner == self, "INVALID_LAYOUT_ITEM")
end
local function clear(node)
    for i = #node.items, 1, -1 do
        local item = node.items[i]
        if item.child then clear(item.child)
        else node._rectPool[item.slotIndex].visible = false end
        item.target, item.owner, item.child = nil, nil, nil
        node.items[i] = nil
    end
    node.parent, node.parentItem, node.root = false, false, false
    node._rectPool = false
    node.disposed, node.dirty = true, true
end
function Node:add(target, props)
    assert(not self.disposed, "DISPOSED_LAYOUT_NODE")
    props = props or {}
    local child = getmetatable(target) == Node and target or nil
    if child then
        assert(not child.disposed and not child.parent, "LAYOUT_NODE_ALREADY_OWNED")
        assert(not child._rootLocked, "LAYOUT_ROOT_ALREADY_PUBLISHED")
        assert(not child._rootClaimed, "LAYOUT_ROOT_ALREADY_CLAIMED")
        local ancestor = self
        while ancestor do assert(ancestor ~= child, "LAYOUT_CYCLE"); ancestor = ancestor.parent end
    end
    local w, h = 0, 0
    if target and not child then
        if target.bounds then w, h = target.bounds.width or 0, target.bounds.height or 0
        else w, h = target.width or 0, target.height or 0 end
    end
    local row = self.direction == "row"
    local basis = props.basis
    if basis == nil then basis = row and w or h end
    local cross = props.crossBasis
    if cross == nil then cross = row and h or w end
    local grow = props.grow
    if grow == nil then grow = child and 1 or 0 end
    local item = { owner = self, target = target, child = child, grow = number(grow),
        resolvedBasis = number(basis), resolvedCrossBasis = number(cross),
        initialBasis = basis, initialCrossBasis = cross, visible = props.visible ~= false,
        margin = {}, alignSelf = props.alignSelf and alignment(props.alignSelf) or nil,
        _visible = false, _x = 0, _y = 0, _width = 0, _height = 0 }
    edges(item.margin, props.margin)
    self.items[#self.items + 1] = item
    if child then
        child.parent, child.parentItem = self, item
        bindRoot(child, self.root)
    else
        item.slotIndex = #self.root._rectPool + 1
        self.root._rectPool[item.slotIndex] = { x = 0, y = 0, width = 0, height = 0, visible = false }
    end
    self:markDirty()
    return item
end
function Node:remove(item)
    owned(self, item)
    for i = 1, #self.items do
        if self.items[i] == item then table.remove(self.items, i); break end
    end
    if item.child then
        clear(item.child)
    else
        self.root._rectPool[item.slotIndex].visible = false
    end
    item.owner, item.target, item.child = nil, nil, nil
    self:markDirty()
end
function Node:setItemGrow(item, grow)
    owned(self, item); grow=number(grow)
    if item.grow~=grow then item.grow=grow; self:markDirty() end
end
function Node:setItemBasis(item, basis)
    owned(self, item)
    if basis == nil then basis = item.initialBasis end
    basis=number(basis)
    if item.resolvedBasis~=basis then item.resolvedBasis=basis; self:markDirty() end
end
function Node:setItemCrossBasis(item, basis)
    owned(self, item)
    if basis == nil then basis = item.initialCrossBasis end
    basis=number(basis)
    if item.resolvedCrossBasis~=basis then item.resolvedCrossBasis=basis; self:markDirty() end
end
function Node:setItemVisible(item, visible)
    owned(self, item); assert(type(visible) == "boolean", "INVALID_VISIBILITY")
    if item.visible~=visible then item.visible=visible; self:markDirty() end
end
function Node:setItemMargin(item, margin)
    owned(self, item); if edges(item.margin, margin) then self:markDirty() end
end
function Node:setGap(gap)
    assert(not self.disposed, "DISPOSED_LAYOUT_NODE")
    gap=number(gap)
    if self.gap~=gap then self.gap=gap; self:markDirty() end
end
function Node:setPadding(padding)
    assert(not self.disposed, "DISPOSED_LAYOUT_NODE")
    if edges(self.padding, padding) then self:markDirty() end
end
function Node:setAlign(align)
    assert(not self.disposed, "DISPOSED_LAYOUT_NODE")
    align=alignment(align)
    if self.align~=align then self.align=align; self:markDirty() end
end
function Node:setJustify(value)
    assert(not self.disposed, "DISPOSED_LAYOUT_NODE")
    value=justify(value)
    if self.justify~=value then self.justify=value; self:markDirty() end
end
function Node:resolveIfDirty(bounds)
    assert(not self.disposed and self.root == self, "EXPECTED_LIVE_LAYOUT_ROOT")
    if not self.dirty then return self._rectPool, false end
    local pool, err = Solver.solve(self, bounds)
    if not pool then return nil, err end
    return pool, true
end
function Node:dispose()
    if self.disposed then return end
    if self.parent then self.parent:removeChildNode(self); return end
    clear(self)
end
function Node:removeChildNode(child)
    assert(child and child.parent == self, "INVALID_CHILD_NODE")
    self:remove(child.parentItem)
end
return Node
