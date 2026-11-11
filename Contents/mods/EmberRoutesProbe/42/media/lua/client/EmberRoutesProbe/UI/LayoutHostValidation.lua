-- LayoutHostValidation.lua - EmberRoutes UI
-- Preflight validation for declarative layout descriptors: known
-- container/item property sets, value validation, and the recursive
-- descriptor-cycle / duplicate-key / already-registered target check.
-- Moved verbatim from the pre-split LayoutHost.lua (P1 split); behaviour
-- unchanged. Returns the preflight function used by LayoutHostBuild.
local S = require 'EmberRoutesProbe/UI/LayoutHostShared'
local owners = S.owners
local supported = S.supported
local finite = S.finite
local KNOWN_CONTAINER_PROPS = { padding=true, gap=true, align=true, justify=true }
local KNOWN_ITEM_PROPS = { key=true, grow=true, basis=true, margin=true, bind=true, when=true, visible=true, pad=true, font=true, autoText=true }
local VALID_ALIGN = { stretch=true, start=true, center=true, ['end']=true }
local VALID_JUSTIFY = { start=true, center=true, ['end']=true, ['space-between']=true }
-- Preflight validation for declarative layout descriptors
local function validateContainerProps(props)
    props=props or {}
    for k in pairs(props) do
        assert(KNOWN_CONTAINER_PROPS[k], 'UNKNOWN_CONTAINER_PROP: '..tostring(k))
    end
    if props.gap~=nil then
        assert(finite(props.gap) and props.gap>=0, 'INVALID_GAP')
    end
    if props.align~=nil then
        assert(VALID_ALIGN[props.align], 'INVALID_ALIGN: '..tostring(props.align))
    end
    if props.justify~=nil then
        assert(VALID_JUSTIFY[props.justify], 'INVALID_JUSTIFY: '..tostring(props.justify))
    end
    if props.padding~=nil then
        if type(props.padding)=='table' then
            for pk,pv in pairs(props.padding) do
                assert(pk=='top' or pk=='bottom' or pk=='left' or pk=='right', 'INVALID_PADDING_KEY: '..tostring(pk))
                assert(finite(pv) and pv>=0, 'INVALID_PADDING_VALUE')
            end
        else
            assert(finite(props.padding) and props.padding>=0, 'INVALID_PADDING')
        end
    end
end
local function validateItemProps(props)
    props=props or {}
    for k in pairs(props) do
        assert(KNOWN_ITEM_PROPS[k], 'UNKNOWN_ITEM_PROP: '..tostring(k))
    end
    if props.key~=nil then
        assert(type(props.key)=='string' and #props.key>0, 'INVALID_ITEM_KEY')
    end
    if props.grow~=nil then
        assert(finite(props.grow) and props.grow>=0, 'INVALID_GROW')
    end
    if props.basis~=nil then
        assert(props.basis=="auto" or (finite(props.basis) and props.basis>=0), 'INVALID_BASIS')
    end
    if props.pad~=nil then
        assert(finite(props.pad) and props.pad>=0, 'INVALID_PAD')
    end
    if props.autoText~=nil then
        assert(type(props.autoText)=='string', 'INVALID_AUTO_TEXT')
    end
    if props.bind~=nil then
        assert(type(props.bind)=='table' and getmetatable(props.bind)==nil, 'INVALID_BIND_TABLE')
    end
    if props.when~=nil then
        assert(type(props.when)=='function' or type(props.when)=='boolean', 'INVALID_WHEN_PREDICATE')
    end
    if props.visible~=nil then
        assert(type(props.visible)=='boolean', 'INVALID_ITEM_VISIBILITY')
    end
    if props.margin~=nil then
        if type(props.margin)=='table' then
            for mk,mv in pairs(props.margin) do
                assert(mk=='top' or mk=='bottom' or mk=='left' or mk=='right', 'INVALID_MARGIN_KEY: '..tostring(mk))
                assert(finite(mv) and mv>=0, 'INVALID_MARGIN_VALUE')
            end
        else
            assert(finite(props.margin) and props.margin>=0, 'INVALID_MARGIN')
        end
    end
end
local function preflight(host,spec,seenSpecs,seenKeys,seenTargets)
    assert(type(spec)=='table' and spec.isLayoutSpec, 'INVALID_LAYOUT_SPEC')
    assert(spec.type=='row' or spec.type=='column', 'INVALID_LAYOUT_TYPE')
    assert(not seenSpecs[spec], 'DESCRIPTOR_CYCLE')
    seenSpecs[spec]=true
    validateContainerProps(spec.props)
    local children=spec.children or {}
    assert(type(children)=='table', 'INVALID_CHILDREN_LIST')
    for i=1,#children do
        local child=children[i]
        assert(child~=nil, 'CHILD_SPEC_NIL')
        if child.isSpacer then
            assert(finite(child.grow) and child.grow>=0, 'INVALID_SPACER_GROW')
        elseif child.isLayoutItemSpec then
            validateItemProps(child.props)
            if child.props and child.props.key then
                local k=child.props.key
                assert(not seenKeys[k], 'DUPLICATE_ITEM_KEY: '..k)
                seenKeys[k]=true
            end
            local inner=child.child
            if inner.isLayoutSpec then
                assert(not child.props or child.props.basis~="auto", 'CONTAINER_AUTO_BASIS_UNSUPPORTED')
                preflight(host,inner,seenSpecs,seenKeys,seenTargets)
            elseif inner.isSpacer then
                assert(finite(inner.grow) and inner.grow>=0, 'INVALID_SPACER_GROW')
            else
                assert(not seenTargets[inner] and not owners[inner], 'TARGET_ALREADY_REGISTERED')
                seenTargets[inner]=true
                if type(inner)=='table' and type(inner.setX)=='function' then
                    supported(inner)
                    assert(not inner:getParent() or inner:getParent()==host, 'FOREIGN_NATIVE_PARENT')
                end
            end
        elseif child.isLayoutSpec then
            error('BARE_CONTAINER_NOT_ALLOWED: nested container must be wrapped in UI.Item')
        else
            -- Bare native widget or rect leaf
            assert(not seenTargets[child] and not owners[child], 'TARGET_ALREADY_REGISTERED')
            seenTargets[child]=true
            if type(child)=='table' and type(child.setX)=='function' then
                supported(child)
                assert(not child:getParent() or child:getParent()==host, 'FOREIGN_NATIVE_PARENT')
            end
        end
    end
end

return preflight
