--[[
    PublicOrderDialog.lua - EmberRoutes UI
    Public order creation dialog: pick a recipe / surface, set the
    quantity or stock rule, preview the blueprint and submit.
    Split (P1): the dialog is now assembled from focused modules in this
    directory -- PublicOrderDialogLayout, PublicOrderDialogQuery,
    PublicOrderDialogDescribe, PublicOrderDialogBlueprint,
    PublicOrderDialogSubmit, PublicOrderDialogRender and
    PublicOrderDialogLifecycle (each attaches its methods to this class).
    This file keeps only the class, construction and the assembly.
    Behaviour and displayed content are unchanged.
]]

require 'ISUI/ISCollapsableWindow'
local Draft = require 'EmberRoutesProbe/Work/PublicOrderDraft'
local Lifecycle = require 'EmberRoutesProbe/UI/PageLifecycle'
local Presentation = require 'EmberRoutesProbe/UI/ItemPresentation'
local Theme = require 'EmberRoutesProbe/UI/Theme'

local function text(key,...) return getText('IGUI_EmberRoutesProbe_Public_'..key,...) end

---@class EmberRoutesPublicOrderDialog:ISCollapsableWindow
---@field owner EmberRoutesSettlementDashboard
---@field actor IsoPlayer
---@field entry table
---@field fontHeight number
---@field pad number
---@field context table
---@field draft table?
---@field restoredDraft table?
---@field page integer
---@field rows table[]
---@field selectedRecipe any
---@field preferences table
---@field activeTab string
---@field presentation table
---@field submitting boolean
---@field blueprintList EmberRoutesCachedList
---@field previewData table?
---@field cancelPreview function?
---@field active boolean?
---@field disposed boolean?
--- -- Attached by PublicOrderDialogLayout:
---@field createChildren fun(self: EmberRoutesPublicOrderDialog)
---@field selectTab fun(self: EmberRoutesPublicOrderDialog, tab: string)
--- -- Attached by PublicOrderDialogQuery:
---@field query fun(self: EmberRoutesPublicOrderDialog)
---@field loadRule fun(self: EmberRoutesPublicOrderDialog)
--- -- Attached by PublicOrderDialogDescribe:
---@field updateConversion fun(self: EmberRoutesPublicOrderDialog)
---@field describe fun(self: EmberRoutesPublicOrderDialog)
---@field switchPrecursor fun(self: EmberRoutesPublicOrderDialog, product: string, nextRecipeId: string)
---@field requestPreview fun(self: EmberRoutesPublicOrderDialog)
--- -- Attached by PublicOrderDialogBlueprint:
---@field updateBlueprint fun(self: EmberRoutesPublicOrderDialog)
--- -- Attached by PublicOrderDialogSubmit:
---@field submitOrder fun(self: EmberRoutesPublicOrderDialog)
---@field submitRule fun(self: EmberRoutesPublicOrderDialog)
--- -- Attached by PublicOrderDialogRender:
---@field prerender fun(self: EmberRoutesPublicOrderDialog)
--- -- Attached by PublicOrderDialogLifecycle:
---@field isKeyConsumed fun(self: EmberRoutesPublicOrderDialog, key: integer): boolean
---@field onKeyPress fun(self: EmberRoutesPublicOrderDialog, key: integer): boolean
---@field close fun(self: EmberRoutesPublicOrderDialog)
EmberRoutesPublicOrderDialog=ISCollapsableWindow:derive('EmberRoutesPublicOrderDialog')

function EmberRoutesPublicOrderDialog.open(owner,context)
    if owner.publicDialog and not owner.publicDialog.disposed then
        owner.publicDialog:bringToTop()
        return owner.publicDialog
    end
    local h,p=owner.fontHeight,owner.pad
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    local targetW=math.floor(sw*0.58)
    local w=math.min(math.floor(sw*0.92),math.max(math.max(680,h*46),math.min(targetW,math.max(980,h*60))))
    local targetH=math.floor(sh*0.72)
    local height=math.min(math.floor(sh*0.92),math.max(math.max(480,h*32),math.min(targetH,math.max(720,h*46))))
    local o=ISCollapsableWindow.new(EmberRoutesPublicOrderDialog,(getCore():getScreenWidth()-w)/2,(getCore():getScreenHeight()-height)/2,w,height)
    o.owner,o.actor,o.entry=owner,owner.actor,owner.entry
    o.fontHeight,o.pad=h,p
    o.context=context or {}
    o.title=text('createOrder')
    o.draft=Draft.read(o.actor,o.entry.id)
    if o.draft and (not o.context.productType or o.context.productType==o.draft.product)
        and (not o.context.recipeId or o.context.recipeId==o.draft.recipe)
        and (not o.context.surfaceId or o.context.surfaceId==o.draft.surface) then
        o.context.recipeId=o.draft.recipe
        o.context.surfaceId=o.draft.surface
        o.restoredDraft=o.draft
    end
    o.page=1
    o.rows={}
    o.selectedRecipe=false
    o.preferences=o.restoredDraft and o.restoredDraft.preferences or {}
    o.activeTab='order' -- 'order' or 'stock'
    o.presentation=Presentation.new()
    o.resizable=false
    o.submitting=false
    o.backgroundColor=Theme.window
    o.borderColor=Theme.border
    o:setWantKeyEvents(true)
    Lifecycle.createActivationScope(o)
    o:initialise()
    o:addToUIManager()
    owner.publicDialog=o
    o:query()
    return o
end

function EmberRoutesPublicOrderDialog:initialise() ISCollapsableWindow.initialise(self) end

-- Attach the split-out behaviours. Each module returns attach(Page) and
-- only defines methods on the class; there is no circular require.
require 'EmberRoutesProbe/UI/PublicOrderDialogLayout'(EmberRoutesPublicOrderDialog)
require 'EmberRoutesProbe/UI/PublicOrderDialogQuery'(EmberRoutesPublicOrderDialog)
require 'EmberRoutesProbe/UI/PublicOrderDialogDescribe'(EmberRoutesPublicOrderDialog)
require 'EmberRoutesProbe/UI/PublicOrderDialogBlueprint'(EmberRoutesPublicOrderDialog)
require 'EmberRoutesProbe/UI/PublicOrderDialogSubmit'(EmberRoutesPublicOrderDialog)
require 'EmberRoutesProbe/UI/PublicOrderDialogRender'(EmberRoutesPublicOrderDialog)
require 'EmberRoutesProbe/UI/PublicOrderDialogLifecycle'(EmberRoutesPublicOrderDialog)

return EmberRoutesPublicOrderDialog
