-- Pure presentation boundary: actual card projection, no native UI or world.
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
getText=function(key,...) return key end
getTextOrNull=function() return nil end
getItemNameFromFullType=function(id) return id end
local color={r=1,g=1,b=1,a=1}
package.loaded['EmberRoutesProbe/UI/CachedList']={}
package.loaded['EmberRoutesProbe/UI/Theme']={muted=color,textColor=color,gold=color,accent=color,status={ERROR=color}}
package.loaded['EmberRoutesProbe/UI/Text']={}
package.loaded['EmberRoutesProbe/UI/StatusVisual']={colors={done=color,paused=color,blocked=color}}
package.loaded['EmberRoutesProbe/UI/ItemPresentation']={new=function() return {} end}
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
print('PASS '..checks..' monitor presentation fact checks; native UI NOT RUN')
