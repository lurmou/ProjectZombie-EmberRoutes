-- Actual widget composition with synthetic read-only rows; no game renderer.
ERMonitorPreviewOnly=true
ERMonitorPreviewRows=function()
    return {{id='DELIVERY:preview',kind='DELIVERY',title=getText('IGUI_EmberRoutesProbe_Monitor_delivery'),
        name='Tobias Lavigne',state='RUNNING',phase='DELIVER',bucket='active',requested=3,target=3,delivered=2,
        cargoHeld=1,reason='RUNNING',carrierAvailable=true,canPause=true,canCancel=true,assets={
            {id=1,fullType='Base.Newspaper',kind='cargo',custodyState='DELIVERED',delivered=true},
            {id=2,fullType='Base.Newspaper',kind='cargo',custodyState='DELIVERED',delivered=true},
            {id=3,fullType='Base.Newspaper',kind='cargo',custodyState='CARRIED',held=true}},
        stages={{labelKey='IGUI_EmberRoutesProbe_Monitor_haulTake',status='COMPLETED'},
            {labelKey='IGUI_EmberRoutesProbe_Monitor_haulPut',status='ACTIVE'}},stageIndex=2}}
end
ERDemandPreviewRows=function()
    return {{id='DEMAND:cleaning:home',kind='DEMAND',compact=true,readOnly=true,
        title=getText('IGUI_EmberRoutesProbe_Public_cleaning'),bucket='active',state='active',
        stateText=getText('IGUI_EmberRoutesProbe_Demand_processing'),
        summaryText=getText('IGUI_EmberRoutesProbe_Demand_summary',getText('IGUI_EmberRoutesProbe_Demand_urgency_normal'),'Camp 1',getText('IGUI_EmberRoutesProbe_Demand_processing')),
        detailContext=getText('IGUI_EmberRoutesProbe_Demand_context',getText('IGUI_EmberRoutesProbe_Demand_urgency_normal'),'Camp 1'),
        demandSummary=getText('IGUI_EmberRoutesProbe_Demand_cleaningCount','54'),assets={},children={
            {name='Tobias Lavigne',bucket='active',carrierAvailable=true,assets={},stages={{labelKey='IGUI_EmberRoutesProbe_Monitor_work_STAIN',status='ACTIVE'}},stageIndex=1}}}}
end
dofile('tests/lua/settlement-tabs-test.lua')
getItemNameFromFullType=function(id)
    return ERTestTranslations and ERTestTranslations['TEST_ItemName_'..id] or id
end
