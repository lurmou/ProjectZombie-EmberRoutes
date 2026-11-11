--[[
    LayoutHost.lua - EmberRoutes UI
    Declarative layout host: mounts a UI.Row / UI.Column descriptor tree
    onto native widgets and rect leaves, solves it through LayoutNode and
    applies the solved geometry.

    Split (P1): the host is now assembled from focused modules in this
    directory -- LayoutHostShared (owner registry and detach/release/
    register primitives), LayoutHostValidation (descriptor preflight),
    LayoutHostBuild (registration and Host:build), LayoutHostApply
    (geometry application and resolve scheduling) and LayoutHostLifecycle
    (activation, update, disposal and conditional visibility), each
    attaching its methods to this class. This file keeps only the class,
    construction, initialise and the assembly. Behaviour unchanged.
]]
require 'ISUI/ISPanel'
local Node = require 'EmberRoutesProbe/UI/LayoutNode'

---@class EmberRoutesLayoutHost:ISPanel
---@field rootNode table
---@field _leafItems table
---@field _boundSnapshots table
---@field _conditionals table
---@field _bounds table
---@field _autoBasisItems table
---@field _debouncers table
---@field _layoutRequested boolean
---@field scope any
---@field closed boolean
---@field closing boolean
---@field sealed boolean
---@field built boolean
---@field _pending boolean
---@field _building boolean
---@field _buildPending table|false
---@field cleanupError any
---@field _rollbackBuild fun(self: EmberRoutesLayoutHost): boolean?, any
---@field solvedRevision integer
---@field appliedRevision integer
---@field failedSolveRevision integer
---@field failedApplyRevision integer
---@field errorStage any
---@field errorMessage any
---@field errorSlot any
---@field errorSetter any
--- -- Attached by LayoutHostBuild:
---@field _register fun(self: EmberRoutesLayoutHost, node: table, target: any, props: table, kind: string): table
---@field addNative fun(self: EmberRoutesLayoutHost, node: table, target: any, props?: table): table
---@field addRect fun(self: EmberRoutesLayoutHost, node: table, rect: table, props?: table): table
---@field build fun(self: EmberRoutesLayoutHost, spec: table, initialContext?: table): table
--- -- Attached by LayoutHostApply:
---@field onResize fun(self: EmberRoutesLayoutHost)
---@field _syncBounds fun(self: EmberRoutesLayoutHost): boolean
---@field requestLayout fun(self: EmberRoutesLayoutHost)
---@field flushLayout fun(self: EmberRoutesLayoutHost): boolean
---@field invalidateAutoBasis fun(self: EmberRoutesLayoutHost)
---@field resolveLayout fun(self: EmberRoutesLayoutHost): boolean
---@field retryLayout fun(self: EmberRoutesLayoutHost): boolean
--- -- Attached by LayoutHostLifecycle:
---@field setItemVisible fun(self: EmberRoutesLayoutHost, handle: table, visible: boolean)
---@field deactivate fun(self: EmberRoutesLayoutHost)
---@field setActivation fun(self: EmberRoutesLayoutHost, scope: table)
---@field isActivationValid fun(self: EmberRoutesLayoutHost): boolean
---@field _tickDebouncers fun(self: EmberRoutesLayoutHost, now: number)
---@field registerDebouncer fun(self: EmberRoutesLayoutHost, d: table)
---@field unregisterDebouncer fun(self: EmberRoutesLayoutHost, d: table)
---@field update fun(self: EmberRoutesLayoutHost)
---@field dispose fun(self: EmberRoutesLayoutHost)
---@field syncVisibility fun(self: EmberRoutesLayoutHost, context?: table)
local Host = ISPanel:derive('EmberRoutesLayoutHost')

function Host:new(x,y,width,height,props)
    local o=ISPanel.new(self,x,y,width,height)
    setmetatable(o,self); self.__index=self
    o.background=false; o.moveWithMouse=false; o.wantMouseEvents=false
    o.rootNode=Node.new(props); o.rootNode:claimRoot(); o._leafItems={}; o._boundSnapshots={}; o._conditionals={}; o._bounds={width=width,height=height}
    o._autoBasisItems={}; o._debouncers={}; o._layoutRequested=false
    o.scope=false; o.closed=false; o.closing=false; o.sealed=false; o.built=false; o._pending=false
    o._building=false; o._buildPending=false; o.cleanupError=false
    o.solvedRevision=-1; o.appliedRevision=-1; o.failedSolveRevision=-1; o.failedApplyRevision=-1
    o.errorStage=false; o.errorMessage=false; o.errorSlot=false; o.errorSetter=false
    return o
end

function Host:initialise() ISPanel.initialise(self) end

-- Attach the split-out behaviours. Each module returns attach(Host).
require 'EmberRoutesProbe/UI/LayoutHostBuild'(Host)
require 'EmberRoutesProbe/UI/LayoutHostApply'(Host)
require 'EmberRoutesProbe/UI/LayoutHostLifecycle'(Host)

return Host
