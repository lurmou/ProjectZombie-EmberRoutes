-- Settlement Overview page with 0 work orders (Empty State verification).
require 'env'
require 'ISUI/ISPanelJoypad'
require 'ISUI/ISScrollBar'
require 'ISUI/ISTextEntryBox'
local actorData={}
local actor={getIndex=function() return 0 end,getJoypadBind=function() return -1 end,getModData=function() return actorData end}
function getSpecificPlayer(index) if index==0 then return actor end end
local entry={id='preview-settlement',name='Riverside / preview data'}

local snapshot={works={},byNpc={ada={state='idle'},noah={state='idle'}},alerts={},revision=1}
local releases=0
local function watch()
    releases=releases+1
    local done=false
    return function() if not done then done=true releases=releases-1 end end
end
PreviewServices['EmberRoutesProbe/Work/WorkOverviewService']={status=function() return snapshot end,watch=watch}
PreviewServices['EmberRoutesProbe/Work/WorkCommandAdapter']={
    capabilities=function() return {stop=false,stopBody=false} end,
    command=function() error('World commands disabled in preview') end
}
local workers={{id='ada',name='Ada Mercer',health=96},{id='noah',name='Noah Brooks',health=88}}
PreviewServices['EmberRoutesProbe/Crafting/CraftingService']={status=function() return {workers=workers} end}
PreviewServices['EmberRoutesProbe/Settlement/PersonnelService']={enrichWorkers=function(_,_,rows) return rows end}
local stock={rows={
    {fullType='Base.CannedBeans',node='food.stable',count=36},
    {fullType='Base.WaterBottle',node='water',count=48},
    {fullType='Base.Bandage',node='medical',count=18},
    {fullType='Base.Plank',node='wood',count=64}
}}
local function watchStock(a, b)
    releases=releases+1
    local cb = type(a)=='function' and a or (type(b)=='function' and b)
    if cb then cb(stock) end
    local done=false
    return function() if not done then done=true releases=releases-1 end end
end
PreviewServices['EmberRoutesProbe/Warehouse/WarehouseIndex']={status=function() return stock end,watch=watchStock}
require 'ISUI/ISPanel'
local panel=ISPanel:new(16,16,getCore():getScreenWidth()-32,getCore():getScreenHeight()-32)
panel:initialise() panel:instantiate()
panel.actor=actor panel.entry=entry
function panel:selectTab() return false, 'Preview does not navigate to unloaded pages' end
local Overview=require 'EmberRoutesProbe/UI/SettlementOverviewPage'
local page=Overview:new(panel,{x=8,y=36,width=panel.width-16,height=panel.height-44-36})
page:initialise()
panel:addChild(page)
page:activate()

panel.render=function(self)
    self:drawText('Production SettlementOverviewPage / 0 Orders Empty State / debug host',12,10,1,1,1,1,UIFont.Small)
end
NativePreview=panel
NativePreview.previewBanner=false
NativePreview.smoke=function(self)
    assert(page.active, 'Actual overview page did not activate')
    assert(#page.store.value.works==0, 'Overview should have 0 work orders')
    assert(#page.orderList.items==0, 'Order list should have 0 items')
    self.smokeSummary='Empty State Overview: 0 orders, EmptyState component verified'
end
PreviewDispose=function()
    page:dispose()
    panel:setVisible(false)
end
