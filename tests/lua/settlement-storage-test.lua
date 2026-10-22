package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local n=0
local function check(value,why) n=n+1 assert(value,why) end
local tables,uuid,reads={},0,0
ModData={getOrCreate=function(key) tables[key]=tables[key] or {} return tables[key] end}
function getRandomUUID() uuid=uuid+1 return "uuid-"..uuid end
local client=false
function isClient() return client end function isServer() return false end
local actor={x=1,y=1,isDead=function() return false end,getIndex=function() return 0 end,getPlayerNum=function() return 0 end,
    getX=function(self) return self.x end,getY=function(self) return self.y end,getZ=function(self) return self.z or 0 end}
function getSpecificPlayer() return actor end
local events={}
Events={}
for _,name in ipairs({'OnContainerUpdate','OnTick','OnTickEvenPaused','OnGameStart'}) do
    events[name]={} Events[name]={Add=function(fn) events[name][#events[name]+1]=fn end}
end
package.loaded['EmberRoutesProbe/Log']={write=function() end}
local squares={}
local function key(x,y,z) return x..":"..y..":"..z end
function getCell() return {getGridSquare=function(_,x,y,z) return squares[key(x,y,z)] end} end
local Geometry=require "EmberRoutesProbe/SettlementGeometry"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Membership=require "EmberRoutesProbe/SettlementMembership"
local Index=require "EmberRoutesProbe/WarehouseIndex"
local Filter=require "EmberRoutesProbe/StorageFilter"
local Query=require "EmberRoutesProbe/WarehouseQuery"
local function box(x,y,z)
    local object={data={}}
    local list={values={}}
    function list:size() return #self.values end
    function list:get(i) reads=reads+1 return self.values[i+1] end
    local container={getItems=function() return list end,getParent=function() return object end}
    function container:getType() return 'crate' end
    function container:getDisplayType() return 'crate' end
    function container:getCustomName() return nil end
    local sq={getX=function() return x end,getY=function() return y end,getZ=function() return z end}
    local objects={size=function() return 1 end,get=function() return object end,contains=function(_,other) return other==object end}
    function sq:getObjects() return objects end
    function object:getSquare() return sq end function object:getContainer() return container end
    function object:getModData() return self.data end
    squares[key(x,y,z)]=sq
    actor.x,actor.y,actor.z=x+0.5,y+0.5,z
    local config=Filter.new() config.groups.tools=true config.groups.other=true
    check(Registry.configure(actor,object,config)=='FILTER_CONFIGURED','real registry config accepted')
    local function item(id,fullType)
        local value={id=id,fullType=fullType or 'Base.Hammer',container=container}
        function value:getID() return self.id end function value:getFullType() return self.fullType end
        function value:getContainer() return self.container end
        function value:getCategory() return 'Normal' end
        function value:getDisplayCategory() return self.fullType=='Base.Hammer' and 'Tool' or 'Junk' end
        list.values[#list.values+1]=value return value
    end
    return {object=object,container=container,list=list,item=item,id=object.data.EmberRoutesContainer.id,config=config,square=sq}
end
local function configure(entry)
    actor.x,actor.y,actor.z=entry.square:getX()+0.5,entry.square:getY()+0.5,entry.square:getZ()
    return Registry.configure(actor,entry.object,entry.config)
end
local area=assert(Geometry.rectangle(5,5,0,0))
check(area.x==0 and area.w==6 and Geometry.contains(area,5.9,5.9) and not Geometry.contains(area,6,5),'half-open geometry and reversed corners')
check(not Geometry.rectangle(0,0,128,0) and not Geometry.rectangle(0/0,0,1,1),'invalid/oversized coordinates rejected')
check(not Geometry.overlap({x=0,y=0,w=2,h=2},{x=4,y=0,w=2,h=2},2),'minimum town gap boundary is exact')
local settlement=assert(Ledger.commit(actor,nil,'Base A',area))
local stableId,faction=settlement.id,Ledger.data().factionId
settlement=assert(Ledger.commit(actor,stableId,'Base renamed',assert(Geometry.rectangle(1,1,3,3))))
check(settlement.id==stableId and #settlement.areas==2,'extension/rename preserve stable ID')
local detached=Ledger.get(stableId) detached.name='uncommitted' detached.areas[1].x=99999
check(Ledger.get(stableId).name=='Base renamed' and Ledger.get(stableId).areas[1].x==0,'read DTO mutation cannot change authoritative ledger')
check(not Ledger.commit(actor,nil,'\n',area),'invalid name has no entry')
Ledger.validators[1]=function() return 'SYSTEM_TOWN_EXCLUSION' end
local blocked,reason=Ledger.commit(actor,nil,'Blocked',area)
check(not blocked and reason=='SYSTEM_TOWN_EXCLUSION','registered boundary validator rejects before ledger commit')
Ledger.validators={}
local other=assert(Ledger.commit(actor,nil,'Overlapping',area))
check(other.id~=stableId and other.factionId==faction,'same-faction overlap allowed without identity loss')
Ledger.data().entries.foreign={id='foreign',name='Foreign',factionId='other-faction',areas={area},revision=1}
local foreignRelease,foreignReason=Index.watch('foreign',function() error('must not publish foreign stock') end)
check(not foreignRelease and foreignReason=='ACCESS_DENIED','read model refuses unowned settlement scope')
check(not Ledger.commit(actor,'foreign','Changed',nil),'unowned settlement cannot be renamed')
local a,b,p,u,out=box(1,1,0),box(2,2,1),box(3,3,0),box(4,4,0),box(9,9,0)
local original=a.item(1)
a.item(2,'Base.Nails') b.item(3) p.item(99) u.item(33) out.item(55)
p.config.private=true configure(p)
squares[key(4,4,0)]=nil
local members=Membership.query(settlement)
check(#members==4,'overlapping rectangles deduplicate registered containers and include upstairs')
local membershipReads=reads
check(#Membership.query({areas={{x=0,y=0,w=128,h=128}}})==5 and reads==membershipReads,'wide sparse territory uses registered locators without inventory/world discovery')
local latest,notifications
notifications=0
local release=assert(Index.watch(stableId,function(snapshot) latest=snapshot notifications=notifications+1 end))
local function finish()
    for _=1,2000 do
        local before=reads
        local spent=Index.step()
        assert(spent<=Index.BUDGET and reads-before<=Index.BUDGET,'per-step inventory reads bounded')
        if latest.state~='UPDATING' then return end
    end
    error('query never completed')
end
finish()
check(latest.state=='READY' and latest.counts.loaded==2 and latest.counts.private==1 and latest.counts.unloaded==1 and latest.counts.items==3,'private/unloaded/outside stock never counted as available')
check(latest.coverage=='ROOT_ONLY' and original:getContainer()==a.container,'snapshot is explicit root coverage and does not move instances')
local hammer
for _,row in ipairs(latest.rows) do if row.fullType=='Base.Hammer' then hammer=row end end
check(hammer.count==2 and #hammer.sources==2,'fullType totals retain per-container source coordinates')
actor.x,actor.y,actor.z=1.5,1.5,0
local readBefore=reads
local candidates=assert(Index.candidates(actor,stableId,{fullType='Base.Hammer',origin={x=2,y=2,z=1},limit=1}))
check(candidates.state=='READY' and candidates.knownCount==2 and #candidates.sources==1 and candidates.sources[1].id==b.id
    and candidates.truncated and not candidates.complete,'candidate discovery uses exact type, geometry ranking and explicit partial coverage')
candidates.sources[1].count=999
check(Index.candidates(actor,stableId,{fullType='Base.Hammer'}).sources[2].count~=999 and reads==readBefore,'candidate DTO mutation cannot alter cache; queries do not reread inventory')
actor.x=900
local inaccessible,inaccessibleReason=Index.candidates(actor,stableId,{fullType='Base.Hammer'})
check(not inaccessible and inaccessibleReason=='OUTSIDE_SETTLEMENT','business discovery checks actor location')
actor.x=1.5
check(not Index.candidates(actor,stableId,{fullType='Base.Hammer',limit=0/0}),'nonfinite query limits rejected')
check(Index.candidates(actor,other.id,{fullType='Base.Hammer'}).state=='NOT_REQUESTED','unrequested stock is unknown rather than zero')
local absent=Index.candidates(actor,stableId,{fullType='Missing.Type'})
check(absent.knownCount==0 and not absent.complete,'absent type in partial coverage is not complete-world zero')
local legacy=Registry.data().containers[a.id]
legacy.containerIndex,legacy.containerType=nil,nil
check(Registry.resolve(a.id,'take').container==a.container,'legacy coordinate records retain primary ID without migration')
local descriptor=Registry.describe(a.id) descriptor.x=999
check(Registry.describe(a.id).x==1,'locator DTO cannot mutate persistent coordinates')
legacy.containerIndex=false
check(not Registry.describe(a.id),'boolean index is invalid rather than silently primary')
legacy.containerIndex=-1
local bad,badReason=Registry.resolve(a.id,'take')
check(not bad and badReason=='CONTAINER_RECORD_INVALID','malformed index rejected before engine lookup')
legacy.containerIndex=nil
local savedObjects=a.square:getObjects()
local twin={getContainer=function() return a.container end,getModData=function() return a.object.data end}
function a.square:getObjects() return {size=function() return 2 end,get=function(_,i) return i==0 and a.object or twin end} end
local duplicated,duplicateReason=Registry.resolve(a.id,'take')
check(not duplicated and duplicateReason=='CONTAINER_ID_DUPLICATED','two physical objects sharing an ID fail endpoint authority')
function a.square:getObjects() return savedObjects end
local beforeEndpoint=assert(Registry.resolve(a.id,'take'))
local originalContainer=a.container
local replacementContainer={getType=function() return 'crate' end}
function a.object:getContainer() return replacementContainer end
local replaced,replacedReason=Registry.revalidate(beforeEndpoint,'take','local-world')
check(not replaced and replacedReason=='CONTAINER_CHANGED','same-object replacement cannot reuse held physical endpoint')
function a.object:getContainer() return originalContainer end
local second
local release2=Index.watch(stableId,function(s) second=s end)
local before=reads Index.step()
check(second==latest and reads==before,'same settlement consumers share snapshot without second scan')
release2()
a.item(4)
local observerRan=false
Registry.inventoryListeners[#Registry.inventoryListeners+1]=function() error('expected observer failure') end
Registry.inventoryListeners[#Registry.inventoryListeners+1]=function() observerRan=true end
Registry.inventoryChanged(a.container)
check(observerRan,'failed read-model observer cannot veto verified effect or block later observers')
table.remove(Registry.inventoryListeners) table.remove(Registry.inventoryListeners)
check(latest.state=='UPDATING' and #latest.rows==0,'confirmed inventory effect invalidates old totals immediately')
check(latest.retain and latest.dirtySources[a.id] and not latest.dirtyAll,'physical effect publishes targeted display invalidation without stale business rows')
local firstInvalidation=latest
Registry.inventoryChanged(b.container)
check(latest.dirtySources[a.id] and latest.dirtySources[b.id] and not firstInvalidation.dirtySources[b.id],
    'later dirty source is published while pending; prior event metadata remains immutable')
local pendingCandidates=Index.candidates(actor,stableId,{fullType='Base.Hammer'})
check(pendingCandidates.state=='UPDATING' and #pendingCandidates.sources==0 and pendingCandidates.knownCount==nil,'invalidated generation never exposes old candidate quantities')
finish()
check(latest.counts.items==4,'targeted inventory change refreshes existing membership')
a.config.private=true configure(a)
check(latest.state=='UPDATING' and #latest.rows==0 and not latest.retain,'privacy change immediately removes previous visible totals')
finish()
check(latest.counts.items==1 and latest.counts.private==2,'private inventory is not enumerated into new snapshot')
a.config.private=false configure(a)
a.list.values={}
for i=1,500 do a.item(1000+i) end
Index.refresh(stableId)
Index.step()
check(latest.state=='UPDATING','large inventory spans bounded slices')
squares[key(1,1,0)]=nil Index.changed(a.id)
finish()
check(latest.state=='READY' and latest.counts.unloaded==2 and latest.counts.items==1,'unload during scan cannot publish old container as loaded')
squares[key(1,1,0)]=a.square a.list.values={} a.item(3)
Index.refresh(stableId) finish()
check(latest.state=='ERROR' and latest.reason=='ITEM_ID_DUPLICATED' and #latest.rows==0,'duplicate IDs fail closed instead of inflating stock')
release()
before=reads
for _=1,10 do Index.step() end
check(reads==before,'last consumer closes and cancels all inventory reads')
-- Flood from another compartment must not starve an unrelated active read.
a.list.values={}
for i=1,300 do a.item(5000+i) end
local normalBudget=Index.BUDGET Index.BUDGET=8
local floodRelease=Index.watch(stableId,function(value) latest=value end)
local floodBefore=reads
for _=1,130 do
    Index.changed(b.id) Index.step()
    if reads-floodBefore>=300 then break end
end
check(reads-floodBefore>=300,'continuous unrelated events cannot indefinitely debounce or cancel active source')
finish()
check(latest.state=='READY' and latest.counts.items==301,'flood settles to complete known inventory')
Index.refresh(stableId) Index.step()
for _=1,8 do
    Index.changed(a.id)
    for _=1,16 do Index.step() end
    if latest.state=='ERROR' then break end
end
check(latest.state=='ERROR' and latest.reason=='INVENTORY_UNSTABLE','repeated interrupted reads stop with explicit recoverable error')
Index.BUDGET=normalBudget Index.refresh(stableId) finish()
check(latest.state=='READY' and latest.counts.items==301,'manual refresh recovers bounded instability failure')
floodRelease()
-- Invalidate after physical enumeration but before the scalar merge completes.
a.list.values={} for i=1,10 do a.item(6000+i) end
Index.BUDGET=1
local mergeRelease=Index.watch(stableId,function(value) latest=value end)
local mergeBefore=reads
for _=1,100 do Index.step() if reads-mergeBefore>=11 then break end end
for _=1,5 do Index.step() end
a.item(7000) Registry.inventoryChanged(a.container)
Index.BUDGET=normalBudget finish()
check(latest.state=='READY' and latest.counts.items==12,'invalidation during scalar merge discards stale candidate generation')
mergeRelease()
local rows={}
for i=1,135 do rows[i]={fullType='Mod.'..i,node='tools',searchKey='translated hammer '..i} end
local page,current,pages,total=Query.page(rows,'hammer','tools',3)
check(#page==15 and current==3 and pages==3 and total==135,'query pagination bounds actual rendered rows')
check(#Query.page(rows,'not here',false,1)==0,'search filters cached strings only')
client=true
check(not Index.watch(stableId,function() end) and not Ledger.commit(actor,nil,'MP',area),'MP interfaces reject unsupported execution')
client=false
local oldRoot=tables
local oldRelease=Index.watch(stableId,function(s) latest=s end)
for _,fn in ipairs(events.OnGameStart) do fn() end
check(latest.state=='ERROR' and latest.reason=='WORLD_CHANGED' and #latest.rows==0,'world-session transition immediately clears prior visible stock')
local replacementNotifications=0
local newRelease=Index.watch(stableId,function(s) latest=s replacementNotifications=replacementNotifications+1 end)
oldRelease()
Index.step()
check(replacementNotifications>1,'old subscription release cannot cancel replacement world-session context')
Index.refresh(stableId)
tables={}
finish()
check(latest.state=='ERROR' and latest.reason=='WORLD_CHANGED','world identity change refuses old snapshot')
newRelease() tables=oldRoot
local failedWatch,failedReason=Index.watch(stableId,function() error('expected broken UI consumer') end)
check(not failedWatch and failedReason=='UI_SUBSCRIBER_ERROR','broken UI subscription is rejected and released')
before=reads Index.step()
check(reads==before,'failed UI consumer cannot leave orphan inventory scans')
check(Ledger.data().entries[stableId].name=='Base renamed' and Ledger.data().factionId==faction,'world ledger retains stable settlement/faction across normal table reload')
-- One physical fridge object, two distinct inventories and persistent policies.
local freezerList={values={},size=function(self) return #self.values end,get=function(self,i) reads=reads+1 return self.values[i+1] end}
local freezer={getType=function() return 'freezer' end,getParent=function() return a.object end,
    getItems=function() return freezerList end,getDisplayType=function() return 'freezer' end,getCustomName=function() end}
local frozen=a.item(9000,'Base.TinnedBeans') table.remove(a.list.values) frozen.container=freezer
freezerList.values[1]=frozen
function a.object:getContainerCount() return 2 end
function a.object:getContainerByIndex(i) return i==0 and a.container or (i==1 and freezer or nil) end
actor.x,actor.y,actor.z=1.5,1.5,0
local freezerPolicy=Filter.new() freezerPolicy.groups.food=true
check(Registry.configure(actor,a.object,freezerPolicy,freezer)=='FILTER_CONFIGURED','freezer independently configurable')
local freezerId=Registry.metadata(a.object,freezer).id
check(freezerId~=a.id and Registry.metadata(a.object,a.container).id==a.id,'primary identity preserved; freezer receives separate stable ID')
local endpoint=assert(Registry.resolve(freezerId,'take','local-world'))
check(endpoint.container==freezer and endpoint.filter.groups.food,'resolve targets exact secondary inventory and policy')
check(not Registry.filter(a.object,a.container).groups.food,'freezer configuration never overwrites primary policy')
local changed
Registry.inventoryListeners[#Registry.inventoryListeners+1]=function(id) changed=id end
Registry.inventoryChanged(freezer)
check(changed==freezerId,'physical freezer transfer invalidates freezer read model')
check(Registry.select(actor,a.object,'source',freezer):find('SELECTED',1,true) and Registry.data().source==freezerId,'freezer selectable as physical route endpoint')
local detachedEvent={getModData=function() return a.object.data end,getSquare=function() return nil end}
check(#Registry.affected(detachedEvent)==2,'post-removal object events still invalidate old registered locators')
local affected=Registry.affected(a.object)
check(#affected==2 and #Registry.affected(freezer)==1 and Registry.affected(freezer)[1]==freezerId,'object updates cover both compartments; inventory updates stay exact')
local registeredData=a.object.data
local cloned={}
local function clone(value)
    if type(value)~='table' then return value end
    local result={} for k,v in pairs(value) do result[k]=clone(v) end return result
end
a.object.data=clone(registeredData)
local stored=Registry.data().containers
Registry.data().containers=clone(stored)
check(Registry.resolve(a.id,'take').container==a.container and Registry.resolve(freezerId,'take').container==freezer,
    'reconstructed scalar save tables restore independent primary/freezer identities without cached objects')
local freezerRelease=Index.watch(stableId,function(value) latest=value end) finish()
actor.x,actor.y,actor.z=1.5,1.5,0
local frozenCandidates=assert(Index.candidates(actor,stableId,{fullType='Base.TinnedBeans'}))
check(frozenCandidates.knownCount==1 and #frozenCandidates.sources==1 and frozenCandidates.sources[1].id==freezerId,
    'physical freezer inventory contributes independently to business discovery')
Registry.data().containers['bad-locator']={x=0/0,y=0,z=0}
Registry.changed('bad-locator') finish()
check(latest.state=='ERROR' and latest.reason=='CONTAINER_RECORD_INVALID','unlocatable registration cannot be hidden behind a complete-looking inventory')
Registry.data().containers['bad-locator']=nil Registry.changed('bad-locator')
Index.refresh(stableId) finish()
check(latest.state=='READY','repair plus refresh restores scope after malformed position')
freezerRelease()
function a.object:getContainerByIndex(i) return i==0 and a.container or nil end
check(not Registry.resolve(freezerId,'take'),'removed freezer never resolves primary by fallback')
-- Pure aggregation: workload accounting includes duplicate detection and sorting.
local Rollup=require 'EmberRoutesProbe/WarehouseRollup'
local values={status='LOADED',count=20000,ids={},types={},x=0,y=0,z=0}
for i=1,20000 do values.ids[i]=true end
for i=2048,1,-1 do values.types[string.format('Mod.%04d',i)]={node='other',count=9+(i<=1568 and 1 or 0)} end
local merge=Rollup.new({'stress'},{stress=values},20000,2048)
local mergeSteps,mergeUnits=0,0
while merge.state=='MERGING' do
    local used=merge:step(17)
    assert(used<=17,'aggregation and sorting must yield within scalar budget')
    mergeSteps=mergeSteps+1 mergeUnits=mergeUnits+used
    assert(mergeSteps<4000,'aggregation must terminate')
end
check(merge.state=='READY' and merge.counts.items==20000 and #merge.rows==2048 and mergeUnits==44577,'20000 IDs and 2048 types aggregate/sort in accounted slices')
for i=2,#merge.rows do assert(merge.rows[i-1].fullType<merge.rows[i].fullType,'stable fullType sort') end
check(mergeSteps>1,'large final merge never collapses into one unbudgeted completion')
local duplicate=Rollup.new({'a','b'},{a={status='LOADED',count=1,ids={[1]=true},types={}},b={status='LOADED',count=1,ids={[1]=true},types={}}},20,20)
duplicate:step(100)
check(duplicate.state=='ERROR' and duplicate.reason=='ITEM_ID_DUPLICATED','cross-container duplicate IDs fail during bounded merge')
local oversized=Rollup.new({'a'},{a=values},20000,1) oversized:step(30000)
check(oversized.state=='ERROR' and oversized.reason=='INVENTORY_SCAN_LIMIT','bounded rollup enforces type limits before publishing')
local empty=Rollup.new({},{},20000,2048) empty:step(1)
check(empty.state=='READY' and #empty.rows==0 and empty.counts.items==0,'empty fully inspected scope yields explicit zero')
print('WORKLOAD rollup items=20000 types=2048 budget=17 units='..mergeUnits..' slices='..mergeSteps..'; not engine timing')
print('PASS '..n..' settlement/storage checks; PZ persistence and renderer NOT RUN')
