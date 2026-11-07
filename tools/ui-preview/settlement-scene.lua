-- Actual Overview page body; a debug ISPanel owns it instead of the full game Dashboard.
require 'env'
require 'ISUI/ISPanelJoypad'
require 'ISUI/ISScrollBar'
require 'ISUI/ISTextEntryBox'
local actorData={}
local actor={getIndex=function() return 0 end,getJoypadBind=function() return -1 end,getModData=function() return actorData end}
function getSpecificPlayer(index) if index==0 then return actor end end
local entry={id='preview-settlement',name='Riverside / preview data'}
-- Keep fixture titles ASCII. Chinese string literals inside a Lua fixture are
-- read as raw bytes by the preview host and render as '?' in the list font;
-- production titles come from getText()/services and are not affected.
local snapshot={works={
    {key='preview-haul',state='working',category='hauling',title='Haul Order',row={id='preview-haul',kind='HAUL',bucket='active',npcId='ada',stage='DELIVER',targetCount=1,source={x=2155,y=6086},destination={x=2157,y=6089},assets={{id='a1',kind='cargo',fullType='Base.Pickles',custodyState='UNCOLLECTED'}}}},
    {key='preview-craft',state='working',category='hauling',title='Haul Order',workerName='Cleo Hillman',row={id='preview-craft',kind='HAUL',bucket='active',npcId='noah',assets={{id='a2',kind='cargo',fullType='Base.Pickles',count=2,custodyState='CARRIED'}}}},
    {key='preview-clean',state='blocked',category='cleaning',title='Clean Infirmary',row={id='preview-clean',kind='FIELD',bucket='attention',reason='FIELD_TOOL_MISSING'}}
},byNpc={ada={state='working'},noah={state='working'}},alerts={},revision=1}
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
local workers={{id='ada',name='Ada Mercer',health=96},{id='noah',name='Noah Brooks',health=88},{id='ruth',name='Ruth Chen',health=45,hasInjury=true}}
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
local page=Overview:new(panel,{x=8,y=36,width=panel.width-16,height=panel.height-44})
page:initialise()
panel:addChild(page)
page:activate()
page:applyContext({orderId = 'preview-haul'})
panel.render=function(self)
    self:drawText('Production SettlementOverviewPage / synthetic service data / debug host',12,10,1,1,1,1,UIFont.Small)
end
NativePreview=panel
NativePreview.previewBanner=false
NativePreview.smoke=function(self)
    assert(page.active, 'Actual overview page did not activate')
    assert(page.active, 'Actual overview page did not activate')
    assert(page.store.value.vitals.population==3, 'Overview did not project fixture workers')
    assert(#page.store.value.works==3, 'Overview did not project fixture work orders')

    -- Expanded-state fixture: the first order is open, so the virtual drawer,
    -- BOM rows, geometric stage track and command buttons are all on screen.
    assert(page.expandedKey=='preview-haul', 'Expanded drawer fixture did not activate')
    local expanded=false
    for _,entry in ipairs(page.orderList.items or {}) do
        if (entry.height or 0)>54 then expanded=true end
    end
    assert(expanded, 'Expanded drawer row height was not projected')
    assert(page.listContentH and page.listBounds.height<page.listMaxHeight,
        'Order list did not shrink to its content')

    -- All four purpose-drawn mechanisms must be projected, not just updated.
    assert(page.cachedDriveStrip, 'Drive gear strip was not projected')
    assert(page.cachedPopRoller, 'Population odometer was not projected')
    assert(page.cachedBelt, 'Logistics conveyor was not projected')
    assert(page.cachedAlerts and page.cachedAlerts.dialRadius>=36,
        'Readiness radial dial was not projected at an ergonomic size')

    -- The real button creates its native tooltip lazily, on hover/controller focus.
    page.editAreaButton.joypadFocused=true
    page.editAreaButton:updateTooltip()
    assert(page.editAreaButton.tooltipUI and page.editAreaButton.tooltipUI:getIsVisible(), 'Native Overview tooltip did not open')
    self.smokeSummary='Production Overview: 3 workers, 3 orders, expanded drawer, 4 drawn mechanisms; full Dashboard shell not loaded'
end
PreviewTestTooltip=function(visible)
    page.editAreaButton.joypadFocused=visible
    if not visible then page.editAreaButton.isMouseOver=function() return false end end
    page.editAreaButton:updateTooltip()
    assert(page.editAreaButton.tooltipUI:getIsVisible()==visible, 'Native tooltip visibility did not follow focus')
end
PreviewDispose=function()
    page:dispose()
    panel:setVisible(false)
    assert(page.disposed and releases==0, 'Overview preview did not release owned watches')
end
PreviewRegions=function()
    local regions={}
    local source='Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/SettlementOverviewPage.lua'
    for _,area in ipairs({{id='vitals',label='Population / workforce',bounds=page.leftVitalsBounds},
        {id='stock',label='Stockpile reserves',bounds=page.leftStockBounds},
        {id='alerts',label='Readiness dial / alerts',bounds=page.leftAlertsBounds},
        {id='drive',label='Production drive',bounds=page.rightDriveBounds},
        {id='belt',label='Logistics conveyor',bounds=page.rightBeltBounds}}) do
        local b=area.bounds
        regions[#regions+1]={id=area.id,label=area.label,x=page:getAbsoluteX()+b.x,y=page:getAbsoluteY()+b.y,
            width=b.width,height=b.height,source=source}
    end
    local list=page.orderList local y=list:getAbsoluteY()+list:getYScroll()
    for _,item in ipairs(list.items) do
        local height=item.height or list.itemheight
        local top=math.max(y,list:getAbsoluteY()) local bottom=math.min(y+height,list:getAbsoluteY()+list.height)
        local row=item.item and (item.item.value or item.item)
        if bottom>top and row then regions[#regions+1]={id='order:'..tostring(row.key),label=row.title or 'Order',
            x=list:getAbsoluteX(),y=top,width=list.width,height=bottom-top,source=source} end
        y=y+height
    end
    return regions
end
