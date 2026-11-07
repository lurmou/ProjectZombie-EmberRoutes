-- Pure presentation boundary: actual card projection, no native UI or world.
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
getText=function(key,...) return key end
getTextOrNull=function() return nil end
getItemNameFromFullType=function(id) return id end
getTextManager=function() return {MeasureStringX=function(_,_,value) return #value*7 end} end
local color={r=1,g=1,b=1,a=1}
package.loaded['EmberRoutesProbe/UI/CachedList']={}
package.loaded['EmberRoutesProbe/UI/CardPanel']={draw=function() end}
package.loaded['EmberRoutesProbe/UI/Theme']={muted=color,textColor=color,gold=color,accent=color,status={ERROR=color},dossier={background=color,panel=color,separator=color,gold=color,active=color,alert=color,muted=color}}
package.loaded['EmberRoutesProbe/UI/Text']={wrapLimited=function(value) return {value} end}
package.loaded['EmberRoutesProbe/UI/StatusVisual']={colors={done=color,paused=color,blocked=color}}
package.loaded['EmberRoutesProbe/UI/ItemPresentation']={new=function() return {icon=function() end} end}
local detail
package.loaded['EmberRoutesProbe/UI/InfoList']={new=function() return {list={},set=function(_,lines) detail=lines end} end}
local Cards=require 'EmberRoutesProbe/UI/OrderMonitorCards'
check(Cards.assetStatus({}, {kind='outputs',delivered=false})~='STORED','output role alone is not storage evidence')
check(Cards.assetStatus({}, {kind='outputs',held=true})=='WITHDRAWN','carried output is not stored')
check(Cards.assetStatus({}, {kind='outputs',delivered=true})=='STORED','delivery proof is shown as stored')
check(Cards.assetStatus({bucket='attention'}, {custodyState='RECONCILE'})=='RECONCILE','unknown is not falsely labelled missing')
check(Cards.assetStatus({bucket='attention'}, {held=true})=='WITHDRAWN','unknown result does not erase known custody')
for _,custody in ipairs({'STATION','RETURNED','CONSUMED'}) do
 check(Cards.assetStatus({}, {kind='outputs',custodyState=custody})==custody,'custody stays distinct from stored output')
end
local stages={{labelKey='work'},{labelKey='collect'},{labelKey='deliver',progress='1/2'}}
local row={id='field',kind='FIELD_WORK',title='Lumber',name='Worker',state='SUSPENDED',phase='DELIVER',bucket='waiting',
 target=2,requested=2,delivered=1,readOnly=true,noteKey='automatic',stages=stages,stageIndex=3,carrierAvailable=true,
 assets={{id=1,fullType='Base.Log',kind='cargo',held=true,custodyState='WITHDRAWN'}}}
check(Cards.phaseIndex(row)==3 and Cards.stageProgress(row,3)=='1/2' and #Cards.stageNames(row)==3,'card consumes domain stage facts')
local track=Cards.phaseTrackText(row)
check(track:find('work',1,true) and track:find('deliver',1,true) and not track:find('Order_stage_craft',1,true),'field track does not invent crafting steps')
local card=Cards.details({}, {}) card:set(row)
local asset for _,line in ipairs(detail) do if line.isAssetRow then asset=line end end
check(asset and asset.status=='WITHDRAWN','detail grouping preserves actual output custody')
row.closed=true row.state='DONE'
check(Cards.phaseIndex(row)==4,'completion is after the configured stage count')
row.state='CANCELLED'
check(Cards.phaseIndex(row)==0,'cancelled is closed without inventing completed stages')
check(Cards.phaseIndex({phase='HEATING'})==3,'legacy cooking stages remain supported')
local oldSignature=Cards.signature(row)
row.stages[2].labelKey='new-route' row.stages[2].status='PLANNED'
check(Cards.signature(row)~=oldSignature,'step changes invalidate cache even when phase and job version stay the same')
package.loaded['EmberRoutesProbe/Settlement/MembershipService']={view=function() end}
package.loaded['EmberRoutesProbe/Warehouse/DisplayNames']={name=function() return 'Worker' end}
local projector=require 'EmberRoutesProbe/Field/FieldWorkMonitor'
local fieldJob={id='clean',npcId='n',revision=1,state='RUNNING',effects='KNOWN',payload={category='cleaning',
    phase='WORK',target={kind='STAIN',x=1,y=1,z=0},assets={}}}
local view=projector.project({bind=function() end},fieldJob)
check(#view.stages==1 and view.stages[1].key=='work','zero-output cleaning does not invent cargo steps')
fieldJob.payload.assets={{id=2,fullType='Base.Log',custody='GROUND'}} fieldJob.payload.workDone=true
view=projector.project({bind=function() end},fieldJob)
check(#view.stages==3 and view.stages[1].status=='COMPLETED' and view.stages[2].status=='PLANNED',
    'ground originals add conditional collection/delivery without marking unexecuted steps done')
fieldJob.effects='UNKNOWN'
view=projector.project({bind=function() end},fieldJob)
check(view.stages[1].status=='UNCERTAIN','unknown work cannot be painted completed')
UIFont={Small='small'}
local visual=Cards.rows().prepare({emberPad=4,emberFontHeight=12,width=450},view)
check(visual.badge.id=='RECONCILE' and visual.fraction==0,'navigation card preserves uncertainty and only meters confirmed delivered cargo')
local need={id='need',kind='DEMAND',compact=true,title='Cleaning',stateText='Processing',summaryText='Routine / Home / Processing',
    children={{name='Worker',phase='WORK',bucket='active',assets={},stages={{labelKey='Wipe blood',progress='target 1'}},stageIndex=1}},assets={}}
card:set(need,false)
local hasState,hasTarget=false,false
for _,line in ipairs(detail) do
    hasState=hasState or line.text=='Processing'
    hasTarget=hasTarget or line.text and line.text:find('target 1',1,true)~=nil
end
check(not hasState and not hasTarget,'need detail does not repeat its state or expose per-target step counters by default')
local delivery={kind='DELIVERY',title='Delivery',name='Worker',state='RUNNING',bucket='active',target=3,requested=3,
    delivered=2,cargoHeld=1,reason='RUNNING',carrierAvailable=true,source={x=1,y=2,z=1},destination={x=3,y=4,z=0},
    assets={{kind='cargo',fullType='Base.Newspaper',delivered=true},{kind='cargo',fullType='Base.Newspaper',delivered=true},
        {kind='cargo',fullType='Base.Newspaper',custodyState='CARRIED',held=true}}}
local blocks=Cards.detailRows(delivery,false)
check(blocks[1].isCardRow and blocks[1].meters[1].fraction==2/3,'overview uses real delivered count as its meter')
local items,transit=0,false
for _,block in ipairs(blocks) do if block.isAssetRow then
    items=items+1 transit=transit or block.status=='TRANSIT'
end end
check(items==2 and transit,'materials are grouped by real custody, and carried cargo is transit rather than prepared crafting material')
check(#Cards.detailRows(delivery,true)>#blocks,'route and recovery information is available only in expanded details')
print('PASS '..checks..' monitor presentation fact checks; native UI NOT RUN')
