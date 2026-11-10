-- Reuse the established ISUI host only; skip unrelated legacy warehouse assertions.
ERMonitorPreviewOnly=true
dofile('tests/lua/settlement-tabs-test.lua')
local hostPreview=ERSettlementPreview
function ERSettlementPreview(tab,height,screenWidth,screenHeight)
    local window=hostPreview(tab,height,screenWidth,screenHeight)
    window:selectTab('orders')
    package.loaded['EmberRoutesProbe/Settlement/MembershipService']={view=function() end}
    package.loaded['EmberRoutesProbe/Warehouse/DisplayNames']={name=function() return 'Worker A' end}
    local projector=require 'EmberRoutesProbe/Field/FieldWorkMonitor'
    local context={bind=function() end,runtime={status=function() return {state='ACTIVE',kind='FIELD_WORK'} end}}
    local clean=projector.project(context,{id='clean',npcId='a',revision=3,state='RUNNING',effects='KNOWN',
        payload={category='cleaning',phase='WORK',target={kind='STAIN',x=5,y=6,z=0},assets={},batchCount=3}})
    local logs=projector.project(context,{id='logs',npcId='a',revision=4,state='RUNNING',effects='KNOWN',
        payload={category='lumberjack',phase='COLLECT',workDone=true,target={kind='TREE',x=7,y=6,z=0},
            assets={{id=2,fullType='Base.Log',custody='GROUND'},{id=3,fullType='Base.Log',custody='HELD'}}}})
    local uncertain=projector.project(context,{id='unknown',npcId='a',revision=5,state='RECONCILE_REQUIRED',effects='UNKNOWN',
        payload={category='forager',phase='WORK',target={kind='FORAGE',x=8,y=6,z=0},assets={}}})
    -- Real demand projector; only world/worker/physical-supply observations are mocked.
    local previewRoot={} local area={id='preview',revision=1,areas={{x=0,y=0,w=30,h=30}}}
    package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry'].data=function() return previewRoot end
    package.loaded['EmberRoutesProbe/Settlement/SettlementLedger'].list=function() return {area} end
    package.loaded['EmberRoutesProbe/Settlement/SettlementLedger'].view=function() return area end
    package.loaded['EmberRoutesProbe/Field/FieldSpatial']={chunk=function() return {} end,square=function() return {} end}
    package.loaded['EmberRoutesProbe/Field/FieldDiscovery']={allowed=function() return true end}
    package.loaded['EmberRoutesProbe/Settlement/SettlementGeometry']={inside=function() return true end}
    package.loaded['EmberRoutesProbe/Field/ToolDiscovery']={findSupplies=function()
        return nil,'FIELD_TOOLS_UNAVAILABLE',{complete=true,missingRoles={'CLEAN_TOOL','CLEAN_FLUID'}}
    end}
    package.loaded['EmberRoutesProbe/Work/LaborSignals']={changed=function() end}
    EmberRoutesProbeJava={workerCount=function() return 1 end,workerIdAt=function() return 'a' end,
        cleaningSquareHasStains=function() return true end,cleaningScanStains=function()
            local points={} for x=1,12 do points[x]={x=x,y=1,z=0} end return points
        end}
    local observer=require 'EmberRoutesProbe/Field/FieldDemand'
    observer.advance({},1000,function() return {handle={}},area end,function() return {cleaning=2} end)
    local demand=assert(observer.rows('preview')[1])
    local page=window.pages.orders
    page.store:setState({snapshot={rows={demand,clean,logs,uncertain}},selection=demand.id})
    return window
end
