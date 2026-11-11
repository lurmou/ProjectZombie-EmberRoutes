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
local Host = ISPanel:derive('EmberRoutesLayoutHost')

function Host:new(x,y,width,height,props)
    local o=ISPanel.new(self,x,y,width,height)
    setmetatable(o,self); self.__index=self
    o.background=false; o.moveWithMouse=false; o.wantMouseEvents=false
    o.rootNode=Node.new(props); o.rootNode:claimRoot(); o._leafItems={}; o._boundSnapshots={}; o._conditionals={}; o._bounds={width=width,height=height}
    o._autoBasisItems={}; o._debouncers={}; o._layoutRequested=false
    o.scope=false; o.closed=false; o.closing=false; o.sealed=false; o.built=false; o._pending=false
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
