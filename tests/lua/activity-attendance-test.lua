-- Real attendance/context/discovery/movement adapters. Native body and cargo are substitutes.
local checks=0
local function check(v,label) assert(v,label) checks=checks+1 end
local root,entry={}, {id='home',revision=1,areas={{x=0,y=0,w=30,h=30}}}
local spatial={entries={home=entry}}
local actor,serial,now,hours={},0,100,5
getTimestampMs=function() return now end
getGameTime=function() return {getWorldAgeHours=function() return hours end} end
CharacterStat={PAIN='pain'} DebugLog={log=function() end}
local x,y,z=.5,.5,0
local nativeEmpty,cargo,accepting=true,false,true
local npc={getX=function() return x end,getY=function() return y end,getZ=function() return z end,
    getCharacterActions=function() return {isEmpty=function() return nativeEmpty end} end,
    getStats=function() return {get=function() return 0 end} end,
    getBodyDamage=function() return {getOverallBodyHealth=function() return 100 end} end,
    getPrimaryHandItem=function() end,getSecondaryHandItem=function() end,hasTrait=function() return false end}
local binding={id='a',handle=npc}
local jobs,current,stops,inventoryReads={},nil,0,0
local formal=assert(require('EmberRoutesProbe/JobStore').open(root))
local jobApi={visitNpc=function(_,id,visit) for _,j in ipairs(jobs) do if j.npcId==id then visit(j) end end formal:visitNpc(id,visit) end,
    peekPersonal=function() for _,j in ipairs(jobs) do if j.providerType=='SELF_CARE' then return j end end end,
    forNpc=function() return jobs end,
    ordinaryCount=function() return formal:ordinaryCount()+#jobs end,
    create=function(_,job) return formal:create(job) end,
    peek=function(_,id) return formal:peek(id) end,
    get=function(_,id) return formal:get(id) end,
    update=function(_,id,revision,patch) return formal:update(id,revision,patch) end,
    removeSettled=function(_,id,revision) return formal:removeSettled(id,revision) end}
local runtime={accepting=function() return accepting end,owns=function() return current~=nil end,
    status=function() return current end,
    stopJob=function(_,id,jobId) stops=stops+1 current.state='STOPPING' return true end}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,
    id=function() serial=serial+1 return 'id-'..serial end}
package.loaded['EmberRoutesProbe/SettlementLedger']={data=function() return spatial end,
    view=function(a,scope) if a==actor and scope=='home' then return entry end end}
package.loaded['EmberRoutesProbe/MembershipService']={
    view=function(id) if id=='a' then return {revision=1,context='SETTLEMENT',settlementId='home'} end end,
    entry=function() return entry end,character=function() return 'owner' end,
    check=function() return {allowed=true,revision=1,entryRevision=1,settlementId='home'} end}
package.loaded['EmberRoutesProbe/TaskResume']={epoch=function() return 0 end}
package.loaded['EmberRoutesProbe/TaskJobs']={current=function() return jobApi end}
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return runtime end}
package.loaded['EmberRoutesProbe/Driver']={bindId=function() return binding end,valid=function(b) return b==binding end}
package.loaded['EmberRoutesProbe/Work']={hasCargo=function() inventoryReads=inventoryReads+1 return cargo end}
package.loaded['EmberRoutesProbe/LaborStore']={resourceOwner=function() return nil end}
package.loaded['EmberRoutesProbe/RuntimeMetrics']={active=function() return false end}
local square={TreatAsSolidFloor=function() return true end,isSolid=function() return false end,
    isSolidTrans=function() return false end,HasStairs=function() return false end,
    isDoorSquare=function() return false end,isFree=function() return true end,isOutside=function() return false end,
    getMovingObjects=function() return {size=function() return 0 end} end}
getCell=function() return {getGridSquare=function() return square end} end
local Zones=require 'EmberRoutesProbe/SettlementZones'
local Store=require 'EmberRoutesProbe/ActivityStore'
local Service=require 'EmberRoutesProbe/ActivityService'
local Attendance=require 'EmberRoutesProbe/ActivityAttendance'
local zone=assert(Zones.save(actor,'home',nil,nil,{name='Gathering',enabled=true,
    area={x=10,y=10,w=4,h=4,z=0},rules={OBSERVE=0}}))
-- Arrival can use an explicit event quiet-stance rule without erasing area geometry.
local args={name='Friends',settlementId='home',zoneId=zone.id,zoneRevision=zone.revision,
    durationHours=1,roster={'a'},rules={SOCIAL=2,OBSERVE=1}}
local event=assert(Service.start(actor,args,assert(Service.issue(actor,'home'))))
local ref=assert(Service.context('a'))
check(Attendance.blocksOrdinary('a') and not Attendance.blocksOrdinary('b'),'only roster blocks new ordinary work')
check(not Service.allowsPoint('home','a',{x=1,y=1,z=0}),'gatherer cannot choose another area')
check(Attendance.inspect(actor,'a',ref)=='READY','idle known actor is eligible')
local function job(kind,payload,state,effects,obligations)
    return {id=kind,npcId='a',providerType=kind,payload=payload or {},state=state or 'RUNNING',
        effects=effects or 'KNOWN',obligations=obligations or {}}
end
jobs={job('CRAFT',{released=false})}
local before=inventoryReads
check(Attendance.inspect(actor,'a',ref)=='WAIT' and inventoryReads==before,'unreleased craft blocks without inventory rescan')
jobs[1].state='SUSPENDED'
check(Attendance.inspect(actor,'a',ref)=='WAIT','paused craft is not a settlement proof')
jobs[1].effects='UNKNOWN'
check(Attendance.inspect(actor,'a',ref)=='UNKNOWN','unknown effect cannot admit')
jobs={job('HAUL',{state='PAUSED'})}
check(Attendance.inspect(actor,'a',ref)=='WAIT','paused haul retains responsibility')
jobs[1].payload.state='DONE' jobs[1].state='DONE'
check(Attendance.inspect(actor,'a',ref)=='READY','settled haul allows travel')
jobs={job('COOKING',{duty={stoveId='oven'},claims={}},'SUSPENDED')}
check(Attendance.inspect(actor,'a',ref)=='WAIT','independent stove duty blocks without a body')
jobs={job('OTHER',{},'DONE','KNOWN',{returnBook=true})}
check(Attendance.inspect(actor,'a',ref)=='WAIT','terminal name cannot erase obligations')
jobs={} cargo=true
check(Attendance.inspect(actor,'a',ref)=='WAIT','retained native cargo blocks')
cargo=false nativeEmpty=false
check(Attendance.inspect(actor,'a',ref)=='WAIT','orphan native queue blocks')
nativeEmpty=true current={jobId='prior',state='PENDING',pending=true}
check(Attendance.inspect(actor,'a',ref)=='WAIT','pending runtime grant blocks')
current={jobId='SELF_CARE',state='ACTIVE'}
jobs={job('SELF_CARE',{kind='STUDY',step='ACTING',claims={'book'},study={leisure=true}})}
Attendance.request(actor,binding,ref)
check(stops==1 and jobs[1].payload.claims[1]=='book','reading stops through owner without releasing its original')
Attendance.request(actor,binding,ref)
check(stops==1,'stopping owner is not stopped repeatedly')
jobs[1].payload.kind='SLEEP' current.state='ACTIVE'
Attendance.request(actor,binding,ref)
check(stops==1,'attendance does not stop urgent personal care')
jobs={} current=nil
local Leisure=require 'EmberRoutesProbe/LeisureService'
local sample={safe=true,healthy=true,hunger=0,thirst=0,fatigue=0,endurance=1,pain=0}
local candidate=assert(Leisure.candidate(actor,binding,sample,{scan=8,paths=1,containers=1},{cooldowns={},decisionAfter=99}))
check(candidate.leisure.zoneVisit.eventId==event.id,'explicit destination works without idle work offer')
check(Zones.location('home',ref,candidate.point) and not Zones.destination('home',ref,candidate.point),'event stance can override ordinary observation ban')
check(require('EmberRoutesProbe/LeisureRecord').valid({kind='LEISURE',settlementId='home',leisure=candidate.leisure}),'event route is persistable scalar data')
local l=candidate.leisure
local p={kind='LEISURE',step='ACTING',claims={require('EmberRoutesProbe/LifeZoneVisits').tileKey(l.point)},
    leisure=l,settlementId='home',membershipRevision=1,settlementRevision=1}
jobs={job('SELF_CARE',p)} current={jobId='SELF_CARE',state='ACTIVE'} accepting=false
check(Leisure.valid(actor,npc,'a',p),'transit is not rejected for being outside the gathering')
local moves,stopCalls=0,0
EmberRoutesProbeJava={motionResult=function() return 'MOVING' end}
local c={actor=actor,npc=npc,payload=p,job=jobs[1],valid=function() return true end,budget={paths=1},
    body={move=function() moves=moves+1 return true,'MOVE_REQUESTED' end,stop=function() stopCalls=stopCalls+1 return true end},
    persist=function() return true end}
local action=require('EmberRoutesProbe/LeisureActions').new(c)
check(action.run()=='Running' and moves==1,'travel uses the existing movement adapter')
x,y,z=l.point.x,l.point.y,l.point.z
check(action.run()=='Success' and l.finished,'owned route can report arrival inside Runtime.step')
local arrived=Store.current().events[event.id].roster.a.arrival
check(arrived and arrived.x==x and arrived.at==hours,'only actual arrival records a physical fact')
check(not Store.current().events[event.id].outcome and not l.applied,'arrival does not grant entertainment or completion')
check(Service.arrived(actor,binding,ref,'SELF_CARE') and Store.current().events[event.id].roster.a.arrival==arrived,'arrival receipt is idempotent')
local tile=p.claims[1] p.claims[1]='unrelated'
check(not Service.arrived(actor,binding,ref,'SELF_CARE'),'unrelated personal claim is not an owned route proof')
p.claims[1]=tile
x=9.9
check(not Service.arrived(actor,binding,ref,'SELF_CARE'),'distance tolerance cannot fake inside-area arrival')
x=l.point.x
jobs[1].effects='UNKNOWN'
check(not Service.arrived(actor,binding,ref,'SELF_CARE'),'unknown route effects cannot refresh arrival proof')
jobs[1].effects='KNOWN'
local fresh=Service.view(actor,'home')[1]
check(Service.cancel(actor,event.id,fresh.revision) and not Service.context('a') and Attendance.blocksOrdinary('a'),
    'cancel revokes invitation but retained personal claims still block unrelated work')
check(action.run()=='Failure','cancel invalidates an old travel leaf')
check(action.halt() and #p.claims==1 and stopCalls>0,'normal stop owns cleanup, leaf does not clear claims')
print('activity-attendance: '..checks..' PASS (native movement/cargo/runtime substitutes)')
