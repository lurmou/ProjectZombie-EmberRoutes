-- Actual Job/Labor authority; no engine effects or disk codec.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local root={format=1,taskJobs={format=1,byId={}},containers={},quarantineResources={}}
Registry.data=function() return root end
local Store=require 'EmberRoutesProbe/Work/LaborStore'
local Jobs=require 'EmberRoutesProbe/Runtime/TaskJobs'
local n=0 local function check(value,label) n=n+1 assert(value,label) end
local nativeCalls=0
if ERLaborTestBridge then
    local native=EmberRoutesProbeJava.laborMutate
    EmberRoutesProbeJava.laborMutate=function(...) nativeCalls=nativeCalls+1 return native(...) end
end
local function create(id,first)
    local claims,manifest,items={},{},{}
    for i=first,first+3 do claims[#claims+1]='item:'..i manifest[#manifest+1]={itemId=i,custodyState='UNCOLLECTED'} items[i]=1 end
    local job={id=id,npcId='npc-'..id,providerType='HAUL',scopeId='scope-'..id,revision=1,state='PREPARING',effects='KNOWN',obligations={},
	payload={format=3,sequence=1,source='source',destination='dest-'..id,claims=claims,manifest=manifest,
	    reservation={format=2,key='dest-'..id,items=items,free=100}}}
    check(Store.createClaimedJob(job),'Create claimed HAUL') return job
end
local a=create('rollback',100)
local token=Store.getToken(a.id)
local p=Jobs.current():get(a.id).payload p.reservation.key='other'
local ok,why=Store.mutateJob(a.id,1,p,{capacity={key='other',items=p.reservation.items,free=0}})
check(not ok and why=='CAPACITY_FAILURE','Rejected target switch reports Phase 1 capacity failure')
check(token.capacityKey=='dest-rollback' and Store.capacityTotalForTests('dest-rollback')==4 and Store.capacityTotalForTests('other')==nil,'Failed switch restores sole capacity responsibility')
check(Jobs.current():get(a.id).revision==1,'Rejected capacity change never submits Job')
p=Jobs.current():get(a.id).payload
local ledger=Jobs.current() local original=ledger.update local injected=false
ledger.update=function(self,id,rev,patch)
    if not injected then injected=true return false,'INJECTED_CAS' end
    return original(self,id,rev,patch)
end
ok,why=Store.mutateJob(a.id,1,p,{capacity={key=p.reservation.key,items=p.reservation.items,free=100}})
ledger.update=original
check(not ok and why=='TASK_WRITE_FAILURE','Explicit CAS refusal remains observable')
check(token.capacityKey=='dest-rollback' and Store.capacityTotalForTests('dest-rollback')==4,'CAS failure restores prior capacity')
check(Jobs.current():get(a.id).effects=='KNOWN' and Jobs.current():get(a.id).revision==1 and Store.owner(100),
    'Phase 1 explicit rejection restores resources and preserves the unmodified Job')
local b=create('shrink',200)
p=ledger:get(b.id).payload
p.manifest[1].custodyState='DELIVERED' p.claims={'item:201','item:202','item:203'} p.reservation.items[200]=nil
local changed=false local shrinkBeforeCas=false
ledger.update=function(self,id,rev,patch)
    local accepted,value=original(self,id,rev,patch)
    if accepted and not changed then
        changed=true shrinkBeforeCas=Store.resourceOwner('item:200')==nil
        Store.setOwnerForTests('item:200',{taskId='unexpected',resources={'item:200'}})
    end
    return accepted,value
end
ok,why=Store.mutateJob(b.id,1,p,{removeKeys={'item:200'},capacity={releaseItemId=200}})
ledger.update=original
check(ok and why==2 and shrinkBeforeCas,'Phase 1 shrinks before CAS; a later callback does not rerun the transaction')
check(ledger:get(b.id).state=='PREPARING' and ledger:get(b.id).effects=='KNOWN','Successful ordinary change preserves requested state and effects')
check(Store.resourceOwner('item:200').taskId=='unexpected','No post-CAS shrink overwrites a later owner')
check(Store.owner(201) and Store.capacityTotalForTests('dest-shrink')==3,'Other originals and promises remain owned')
local c=create('settle',300)
p=ledger:get(c.id).payload
check(Store.mutateJob(c.id,1,p,{state='SETTLING'}),'Enter settlement through ordinary Lua path')
for _,line in ipairs(p.manifest) do line.custodyState='DELIVERED' end
local removed=p.claims p.claims={} p.reservation=nil
local observed=false
local unwatch=ledger:watch(function(scope,id)
    if id==c.id then observed=ledger:get(id).state=='DONE' end
end)
ok,why=Store.mutateJob(c.id,2,p,{state='DONE',removeKeys=removed,capacity=false})
unwatch()
check(ok and why==3 and observed,'Native commit publishes through Lua observer and supports nested reads')
check(not Store.getToken(c.id) and not Store.owner(300) and Store.capacityTotalForTests('dest-settle')==nil,'Verified terminal clears token, originals and capacity')
if ERLaborTestBridge then check(nativeCalls==5,'All mutations, including SETTLING, exercise the single Java entry') end
print('PASS '..n..' capacity commit/rollback/CAS/post-CAS checks; game/disk NOT RUN')
