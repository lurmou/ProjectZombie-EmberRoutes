--[[
    PersonnelPage.lua - EmberRoutes UI
    Personnel roster: priority matrix, worker detail inspector and
    dossier drawer.

    Split: the page is now assembled from focused modules in this
    directory -- PersonnelPageConstants (shared text helpers,
    priority colours, bounds helper), PersonnelPageLayout,
    PersonnelPageLifecycle, PersonnelPagePriority,
    PersonnelPageRefresh, PersonnelPageRender and
    PersonnelPageInteraction (each attaches its methods to this
    class). This file keeps only the class, construction and the
    assembly. Behaviour and displayed content are unchanged.
]]

require 'ISUI/ISPanel'
local C = require 'EmberRoutesProbe/UI/PersonnelPageConstants'
local State = require 'EmberRoutesProbe/UI/State'

---@class EmberRoutesPersonnelPage:ISPanel
---@field owner EmberRoutesSettlementDashboard
---@field actor IsoPlayer
---@field entry table
---@field fontHeight number
---@field pad number
---@field store table
---@field matrixList EmberRoutesCachedList
---@field pageHost EmberRoutesLayoutHost
---@field active boolean?
---@field disposed boolean?
EmberRoutesPersonnelPage=ISPanel:derive('EmberRoutesPersonnelPage')

function EmberRoutesPersonnelPage.floorLabel(z)
    local floor=math.floor(z+0.5)
    return floor==0 and getText('IGUI_EmberRoutesProbe_Settlement_floorGround')
        or ((floor+1)..getText('IGUI_EmberRoutesProbe_Settlement_floorLevel'))
end

function EmberRoutesPersonnelPage:new(owner,bounds)
    local o=ISPanel.new(self,bounds.x,bounds.y,bounds.width,bounds.height)
    o.owner=owner
    o.actor,o.entry=owner.actor,owner.entry
    o.fontHeight,o.pad=owner.fontHeight,owner.pad
    o.background=false o.workFilter='all' o.overview={byNpc={}}
    o.topInfoBounds=C.initRect(o.topInfoBounds,o.fontHeight+o.pad)
    o.matrixBounds=C.initRect(o.matrixBounds)
    o.detailsBounds=C.initRect(o.detailsBounds)
    o.headerBounds=C.initRect(o.headerBounds,o.fontHeight*2+math.floor(o.pad/2))
    o.matrixListBounds=C.initRect(o.matrixListBounds)
    o.infoBounds=C.initRect(o.infoBounds)
    o.bottomNoticeBounds={x=0,y=bounds.height-o.fontHeight,width=bounds.width,height=o.fontHeight,visible=false}
    o.store=State.new({workers={},selected=nil,notice='',revision=0})
    return o
end


function EmberRoutesPersonnelPage:initialise() ISPanel.initialise(self) end

-- Attach the split-out behaviours. Each module returns attach(Page) and
-- only defines methods on the class; there is no circular require.
require 'EmberRoutesProbe/UI/PersonnelPageLayout'(EmberRoutesPersonnelPage)
require 'EmberRoutesProbe/UI/PersonnelPageLifecycle'(EmberRoutesPersonnelPage)
require 'EmberRoutesProbe/UI/PersonnelPagePriority'(EmberRoutesPersonnelPage)
require 'EmberRoutesProbe/UI/PersonnelPageRefresh'(EmberRoutesPersonnelPage)
require 'EmberRoutesProbe/UI/PersonnelPageRender'(EmberRoutesPersonnelPage)
require 'EmberRoutesProbe/UI/PersonnelPageInteraction'(EmberRoutesPersonnelPage)

return EmberRoutesPersonnelPage
