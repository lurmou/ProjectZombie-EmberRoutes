-- Declarative layout DSL facade producing side-effect-free layout descriptors.
local UI = {}

local function copyShallow(t)
    if not t then return {} end
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function flattenChildren(...)
    local out = {}
    local function append(list)
        for i = 1, #list do
            local child = list[i]
            if child ~= nil and child ~= false then
                if type(child) == "table" and child[1] ~= nil and not child.isLayoutSpec and not child.isLayoutItemSpec then
                    append(child)
                else
                    out[#out + 1] = child
                end
            end
        end
    end
    append({ ... })
    return out
end

local function normalize(props, children)
    if type(props) == "table" and props[1] ~= nil and children == nil then
        return {}, props
    end
    return props or {}, children or {}
end

---Creates a horizontal row layout descriptor.
---@param props table? Styling properties (padding, gap, align, justify)
---@param children table? Array of child specifications
---@return table Layout descriptor
function UI.Row(props, children)
    local p, c = normalize(props, children)
    return {
        isLayoutSpec = true,
        type = "row",
        props = p,
        children = c
    }
end

---Creates a vertical column layout descriptor.
---@param props table? Styling properties (padding, gap, align, justify)
---@param children table? Array of child specifications
---@return table Layout descriptor
function UI.Column(props, children)
    local p, c = normalize(props, children)
    return {
        isLayoutSpec = true,
        type = "column",
        props = p,
        children = c
    }
end

---Wraps a child (native widget or nested container) with parent layout properties.
---@param child any Native widget, rect leaf, or nested UI.Row/Column
---@param props table? Layout properties (key, grow, basis, margin, bind, when, pad, font, autoText)
---@return table Layout item descriptor
function UI.Item(child, props)
    assert(child ~= nil, "UI_ITEM_CHILD_NIL")
    local p = copyShallow(props)
    if p.height ~= nil and p.basis == nil then
        p.basis = p.height
        p.height = nil
    elseif p.width ~= nil and p.basis == nil then
        p.basis = p.width
        p.width = nil
    end
    return {
        isLayoutItemSpec = true,
        child = child,
        props = p
    }
end

---Creates a pure geometric elastic spacer without native widget.
---@param grow number? Elastic weight, default 1
---@return table Spacer descriptor
function UI.Spacer(grow)
    local g = grow == nil and 1 or grow
    assert(type(g) == "number" and g >= 0 and g == g and g < math.huge, "INVALID_SPACER_GROW")
    return {
        isSpacer = true,
        grow = g
    }
end

---Creates a standard form configuration row descriptor (Label + Control + Action).
---Produces a pure UI.Item descriptor wrapping a UI.Row, ready for direct inclusion in UI.Column.
---@param label any Label widget, text element, or layout descriptor
---@param control any Input widget (e.g. StepperInput, ISTextEntryBox, Dropdown)
---@param action any? Optional button or action widget (e.g. Save, Reset)
---@param opts table? Optional styling/proportions ({ gap, labelWidth, actionWidth, height, align, margin, key, bind, grow, padding, when })
---@return table Layout item descriptor
function UI.FormRow(label, control, action, opts)
    assert(label ~= nil, "FORM_ROW_LABEL_NIL")
    assert(control ~= nil, "FORM_ROW_CONTROL_NIL")
    opts = opts or {}
    local gap = opts.gap or 8
    local labelW = opts.labelWidth or 120
    local actionW = opts.actionWidth or 64
    local align = opts.align or "center"

    local labelWidget = label
    if type(label) == "string" then
        labelWidget = { text = label, x = 0, y = 0, width = labelW, height = opts.height or 24, visible = true }
    end

    local children = {
        UI.Item(labelWidget, { basis = labelW, grow = 0 }),
        UI.Item(control, { grow = 1 })
    }
    if action ~= nil then
        children[#children + 1] = UI.Item(action, { basis = actionW, grow = 0 })
    end

    local rowProps = { gap = gap, align = align }
    if opts.padding then rowProps.padding = opts.padding end

    local rowSpec = UI.Row(rowProps, children)
    return UI.Item(rowSpec, {
        key = opts.key,
        grow = opts.grow or 0,
        basis = opts.height or 24,
        margin = opts.margin,
        bind = opts.bind,
        when = opts.when
    })
end

---Creates a 2D grid layout descriptor composed of rows within a column.
---@param props table? Styling properties (columns, colGap, rowGap, gap, rowHeight, align, grow, height, width, margin, key, bind, when)
---@param ... any Child specifications or array of specifications
---@return table Layout item descriptor
function UI.Grid(props, ...)
    props = props or {}
    local cols = props.columns or 2
    assert(type(cols) == "number" and cols > 0 and math.floor(cols) == cols, "INVALID_GRID_COLUMNS")
    local colGap = props.colGap or props.gap or 0
    local rowGap = props.rowGap or props.gap or 0
    local rowH = props.rowHeight
    local children = flattenChildren(...)

    local rows = {}
    local currentRow = {}
    for i = 1, #children do
        local child = children[i]
        if not child.isLayoutItemSpec and not child.isSpacer then
            child = UI.Item(child, { grow = 1 })
        elseif not child.props or (child.props.grow == nil and child.props.basis == nil) then
            local cp = copyShallow(child.props or {})
            cp.grow = 1
            child = copyShallow(child)
            child.props = cp
        end
        currentRow[#currentRow + 1] = child
        if #currentRow == cols or i == #children then
            if #currentRow < cols then
                for _ = #currentRow + 1, cols do
                    currentRow[#currentRow + 1] = UI.Spacer(1)
                end
            end
            local rowProps = {
                gap = colGap,
                align = props.align or "stretch"
            }
            local rowItemProps = {
                grow = (rowH and 0 or 1),
                basis = rowH or 0
            }
            rows[#rows + 1] = UI.Item(UI.Row(rowProps, currentRow), rowItemProps)
            currentRow = {}
        end
    end

    local colProps = {
        gap = rowGap,
        align = props.align or "stretch"
    }
    if props.padding then colProps.padding = props.padding end

    local colSpec = UI.Column(colProps, rows)
    return UI.Item(colSpec, {
        key = props.key,
        grow = props.grow,
        basis = props.height,
        margin = props.margin,
        bind = props.bind,
        when = props.when
    })
end

---Creates a conditional item descriptor.
---When the condition is met, the item is displayed; otherwise it collapses to 0 geometry without re-slicing.
---@param predicate function|boolean Function taking state context or boolean
---@param item any Main child specification to display when true
---@param fallback any? Optional fallback child specification to display when false
---@return table|table[] Layout item descriptor (or array if fallback provided)
function UI.Show(predicate, item, fallback)
    assert(type(predicate) == "function" or type(predicate) == "boolean", "INVALID_SHOW_PREDICATE")
    assert(item ~= nil, "SHOW_ITEM_NIL")

    local function wrap(target, cond, initVis)
        if target.isLayoutItemSpec then
            local cloned = copyShallow(target)
            local p = copyShallow(target.props or {})
            p.when = cond
            if initVis ~= nil then p.visible = initVis end
            cloned.props = p
            return cloned
        elseif target.isLayoutSpec then
            return UI.Item(target, { when = cond, visible = initVis })
        else
            return UI.Item(target, { when = cond, visible = initVis, grow = 1 })
        end
    end

    local initTrue = type(predicate) == "boolean" and predicate or nil
    local trueItem = wrap(item, predicate, initTrue)

    if fallback ~= nil then
        local fallbackCond = false
        if type(predicate) == "function" then
            fallbackCond = function(ctx) return not predicate(ctx) end
        else
            fallbackCond = not predicate
        end
        local initFalse = type(predicate) == "boolean" and (not predicate) or false
        local falseItem = wrap(fallback, fallbackCond, initFalse)
        return { trueItem, falseItem }
    end

    return trueItem
end

---Creates a structured card container layout descriptor.
---Encapsulates optional header row (title + action) and content body,
---binding its outer geometry to props.bind for zero-GC card background rendering.
---@param props table? Styling and binding properties (title, action, headerHeight, headerGap, bodyGap, padding, headerPadding, bodyPadding, margin, grow, basis, height, bind, key, when)
---@param ... any Child specifications or array of specifications
---@return table Layout item descriptor
function UI.Card(props, ...)
    props = props or {}
    local children = flattenChildren(...)

    local cardItems = {}

    -- 1. Optional Header Row
    if props.title ~= nil or props.action ~= nil then
        local headerChildren = {}
        if props.title ~= nil then
            local titleWidget = props.title
            if type(titleWidget) == "string" then
                titleWidget = {
                    text = titleWidget,
                    title = titleWidget,
                    x = 0, y = 0, width = 0, height = 0,
                    visible = true
                }
            end
            headerChildren[#headerChildren + 1] = UI.Item(titleWidget, {
                basis = props.titleWidth or "auto",
                grow = props.titleGrow or 0,
                autoText = type(props.title) == "string" and props.title or nil
            })
        end

        headerChildren[#headerChildren + 1] = UI.Spacer(1)

        if props.action ~= nil then
            headerChildren[#headerChildren + 1] = UI.Item(props.action, {
                basis = props.actionWidth or "auto",
                grow = 0
            })
        end

        local headerRow = UI.Row({
            gap = props.headerGap or 8,
            align = "center",
            padding = props.headerPadding
        }, headerChildren)

        cardItems[#cardItems + 1] = UI.Item(headerRow, {
            basis = props.headerHeight or 28,
            grow = 0,
            margin = props.headerMargin
        })
    end

    -- 2. Body Column
    local bodyCol = UI.Column({
        gap = props.bodyGap or 8,
        padding = props.bodyPadding,
        align = props.align or "stretch"
    }, children)

    cardItems[#cardItems + 1] = UI.Item(bodyCol, {
        grow = props.bodyGrow == nil and 1 or props.bodyGrow
    })

    -- 3. Outer Card Container
    local cardCol = UI.Column({
        gap = 0,
        padding = props.padding,
        align = "stretch"
    }, cardItems)

    return UI.Item(cardCol, {
        key = props.key,
        grow = props.grow or 0,
        basis = props.basis or props.height,
        margin = props.margin,
        bind = props.bind,
        when = props.when
    })
end

local debouncerMeta = {
    trigger = function(self, ...)
        if not self.scope or not self.scope:isCurrent() then
            self:cancel()
            return
        end
        local n = select("#", ...)
        self.nArgs = n
        for i = 1, n do self.args[i] = select(i, ...) end
        for i = n + 1, #self.args do self.args[i] = nil end
        local now = getTimestampMs and getTimestampMs() or (os.time() * 1000)
        self.targetTime = now + self.delayMs
        self.pending = true
    end,
    tick = function(self, now)
        if not self.pending then return false end
        if not self.scope or not self.scope:isCurrent() then
            self:cancel()
            return false
        end
        now = now or (getTimestampMs and getTimestampMs() or (os.time() * 1000))
        if now >= self.targetTime then
            self:flush()
            return true
        end
        return false
    end,
    flush = function(self)
        if not self.pending then return end
        self.pending = false
        if self.scope and self.scope:isCurrent() then
            local fn = self.fn
            local a = self.args
            local n = self.nArgs
            if n == 0 then fn()
            elseif n == 1 then fn(a[1])
            elseif n == 2 then fn(a[1], a[2])
            elseif n == 3 then fn(a[1], a[2], a[3])
            elseif n == 4 then fn(a[1], a[2], a[3], a[4])
            else fn(unpack(a, 1, n)) end
        end
    end,
    cancel = function(self)
        self.pending = false
        self.nArgs = 0
        for i = 1, #self.args do self.args[i] = nil end
    end
}
debouncerMeta.__index = debouncerMeta
debouncerMeta.__call = function(t, ...)
    t:trigger(...)
end

---Creates a zero-GC lifecycle-bound debounced function.
---Execution is tied to scope:isCurrent() and automatically cancelled when the page unmounts.
---If host is provided, the host's update loop will tick the debouncer automatically.
---@param scope table Page or component lifecycle scope with :isCurrent()
---@param fn function Callback to execute after debounce delay
---@param delayMs number? Milliseconds delay (default 150)
---@param host table? LayoutHost instance to register tick listener with
---@return table Debouncer callable table
function UI.debounce(scope, fn, delayMs, host)
    assert(scope and type(scope.isCurrent) == "function", "INVALID_DEBOUNCE_SCOPE")
    assert(type(fn) == "function", "INVALID_DEBOUNCE_FN")
    delayMs = delayMs or 150
    assert(type(delayMs) == "number" and delayMs >= 0, "INVALID_DEBOUNCE_DELAY")

    local inst = setmetatable({
        scope = scope,
        fn = fn,
        delayMs = delayMs,
        host = host,
        targetTime = -1,
        pending = false,
        args = {},
        nArgs = 0
    }, debouncerMeta)

    if host and type(host.registerDebouncer) == "function" then
        host:registerDebouncer(inst)
    end
    return inst
end

UI.validate = require("EmberRoutesProbe/UI/FormValidator").validate
UI.createFilter = require("EmberRoutesProbe/UI/ListFilter").new
UI.ScrollContainer = require("EmberRoutesProbe/UI/ScrollContainer")

function UI.showModal(opts)
    return require("EmberRoutesProbe/UI/ModalDialog").show(opts)
end

setmetatable(UI, {
    __index = function(t, k)
        if k == "Modal" then
            local M = require("EmberRoutesProbe/UI/ModalDialog")
            rawset(t, "Modal", M)
            return M
        end
    end
})

return UI
