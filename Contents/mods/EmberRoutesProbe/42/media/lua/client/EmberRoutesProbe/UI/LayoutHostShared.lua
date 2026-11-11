-- LayoutHostShared.lua - EmberRoutes UI
-- Shared leaf-ownership state and helpers for the LayoutHost split:
-- weak owner registry, scalar guards, native-leaf validation, auto-basis
-- measurement, and the detach/release/register primitives used by the
-- build, apply and lifecycle modules. Moved verbatim from the pre-split
-- LayoutHost.lua (P1 split); behaviour unchanged.
local UICache = require 'EmberRoutesProbe/UI/UICache'

local S = {}
local owners = setmetatable({}, {__mode='k'})
local function same(a,b) return a==b or (a~=a and b~=b) end
local function finite(n) return type(n)=='number' and n==n and n>-math.huge and n<math.huge end
local function supported(widget)
    assert(widget and type(widget.setX)=='function' and type(widget.setY)=='function'
        and type(widget.setWidth)=='function' and type(widget.setHeight)=='function'
        and type(widget.setVisible)=='function' and type(widget.getParent)=='function', 'INVALID_NATIVE_LEAF')
    assert(not widget.anchorRight and not widget.anchorBottom and widget.anchorLeft~=false
        and widget.anchorTop~=false and widget.keepOnScreen~=true, 'CONFLICTING_NATIVE_GEOMETRY')
end
local function resolveAutoBasis(inner, props)
    local text = props and props.autoText
    if not text and type(inner)=='table' then
        text = inner.title or inner.text or inner.label or inner.name
    end
    if not text then return 0 end
    local font = (props and props.font) or (type(inner)=='table' and inner.font) or (UIFont and UIFont.Small)
    local pad = (props and props.pad) or 16
    local measured = UICache.measure(font, tostring(text))
    return measured + pad
end
local function detach(host,target)
    host:removeChild(target)
    assert(not target.javaObject or target.javaObject:getParent()==nil, 'NATIVE_DETACH_FAILED')
    if target.parent==host then target.parent=nil end
end

local function release(host,entry,rollback)
    local target=entry.target
    host.errorSlot=entry.item and entry.item.slotIndex or false
    host.errorSetter='setVisible'
    if entry.kind=='native' then
        target:setVisible(false)
        if not rollback or entry.attached then host.errorSetter='removeChild'; detach(host,target) end
        target:setVisible(entry.wasVisible)
    elseif entry.kind=='rect' then
        target.visible=rollback and entry.wasVisible or false
    elseif entry.kind=='spacer' then
        -- Virtual leaf has no physical target to detach
    end
    if entry.item and entry.item.owner then entry.item.owner:remove(entry.item) end
    if target then owners[target]=nil end
    entry.target=false; entry.item=false
end
local function register(host,entry,node,props)
    entry.item=node:add(entry.target,props)
    if entry.kind=='native' then
        if entry.target:getParent()~=host then
            entry.attached=true -- AddChild may throw after partially linking the target.
            host:addChild(entry.target)
        end
        assert(entry.target.javaObject and entry.target.javaObject:getParent()==host.javaObject, 'NATIVE_PARENT_MISMATCH')
        entry.target:setVisible(false)
    elseif entry.kind=='rect' then
        entry.target.visible=false
    end
    host._leafItems[#host._leafItems+1]=entry
end

S.owners = owners
S.same = same
S.finite = finite
S.supported = supported
S.resolveAutoBasis = resolveAutoBasis
S.detach = detach
S.release = release
S.register = register

return S
