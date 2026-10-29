-- Real Runtime/Controller/Jobs/Claims and activity services. Native bodies and
-- quiet personal actions are substitutes; this is not a game/save-disk test.
local checks=0
local function check(v,m) assert(v,m) checks=checks+1 end
local root,spatial={}, {entries={home={id='home',revision=1,areas={{x=0,y=0,w=20,h=20}}}}}
local now,hours,serial=0,5,0
getTimestampMs=function() return now end
getGameTime=function() return {getWorldAgeHours=function() return hours end} end
isClient=function() return false end isServer=function() return false end
local actor={isDead=function() return false end}
getSpecificPlayer=function() return actor end
local bodies,keys,masks,delay={},{},{},{}
for i,id in ipairs({'a','b','c'}) do
    local body={id=id,x=1.5+i,y=2.5,z=0,dead=false}
    function body:getX() return self.x end function body:getY() return self.y end function body:getZ() return self.z end
    function body:isDead() return self.dead end
    function body:getCharacterActions() return {isEmpty=function() return true end} end
    bodies[id]=body
end
ISTimedActionQueue={queues={},clear=function(body) ISTimedActionQueue.queues[body]={queue={}} end}
EmberRoutesProbeJava={carrierFor=function(id) return bodies[id] end,carrierPresent=function(b) return bodies[b.id]==b end,
    carrierId=function(b) return b.id end,
    acquireBodyControl=function(b,job,generation) assert(not keys[b.id],'second body owner') keys[b.id]=job..':'..generation return keys[b.id] end,
    stopWithControl=function(b,key) assert(key==keys[b.id]) if not delay[b.id] then masks[b.id]=0 end return true end,
    bodyStopMask=function(b,key) assert(key==keys[b.id]) return masks[b.id] or 0 end,
    releaseBodyControl=function(b,key) assert(key==keys[b.id] and (masks[b.id] or 0)==0) keys[b.id]=nil return true end,
    freezeBodyControl=function() return true end,thawBodyControl=function() return not keys.a and not keys.b end,
    retireBodyControl=function() return true end}
local memberRevision={a=1,b=1,c=1} local epochs={a=0,b=0,c=0}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,
    id=function() serial=serial+1 return 'id-'..serial end}
package.loaded['EmberRoutesProbe/SettlementLedger']={data=function() return spatial end,
    view=function(a,id) if a==actor then return spatial.entries[id] end end}
package.loaded['EmberRoutesProbe/MembershipService']={view=function(id)
    if memberRevision[id] then return {context='SETTLEMENT',settlementId='home',revision=memberRevision[id]} end end,
    entry=function() return spatial.entries.home end,character=function() return 'player' end,
    check=function(id) return {allowed=true,revision=memberRevision[id],entryRevision=1,settlementId='home'} end}
package.loaded['EmberRoutesProbe/TaskResume']={epoch=function(id) return epochs[id] end}
package.loaded['EmberRoutesProbe/NeedsObserver']={sample=function(body,id,time)
    return {safe=not body.dead,observedAt=time,hunger=0,thirst=0,fatigue=0,endurance=1,health=100,healthy=true} end}
package.loaded['EmberRoutesProbe/Work']={hasCargo=function() return false end}
package.loaded['EmberRoutesProbe/Log']={write=function() end}
local square={TreatAsSolidFloor=function() return true end,isSolid=function() return false end,
    isSolidTrans=function() return false end,HasStairs=function() return false end,isDoorSquare=function() return false end,
    isFree=function() return true end,isOutside=function() return false end,
    getMovingObjects=function() return {size=function() return 0 end} end}
getCell=function() return {getGridSquare=function() return square end} end
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local runtime=Runtime.new()
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return runtime end}
local Probe=require 'EmberRoutesProbe/Boot' Probe.ready=true Probe.runtimeReady=true
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Store=require 'EmberRoutesProbe/ActivityStore'
local Service=require 'EmberRoutesProbe/ActivityService'
local Assets=require 'EmberRoutesProbe/LaborStore'
local Driver=require 'EmberRoutesProbe/Driver'
local Record=require 'EmberRoutesProbe/SelfCareRecord'
local Stop=require 'EmberRoutesProbe/TaskBusinessStop'
local Zones=require 'EmberRoutesProbe/SettlementZones'
local zone=assert(Zones.save(actor,'home',nil,nil,{name='Garden',enabled=true,area={x=0,y=0,w=9,h=9,z=0},rules={OBSERVE=1}}))
local function args(roster)
    return {name='Gathering',settlementId='home',zoneId=zone.id,zoneRevision=zone.revision,
        organizerId='a',quorum=2,roster=roster or {'a','b'},rules={OBSERVE=1,SOCIAL=2},gatherHours=.1,durationHours=.2}
end
local function start(a) local e=assert(Service.start(actor,a or args(),assert(Service.issue(actor,'home')))) return Store.get(e.id) end
local function pump(n,delta)
    for _=1,n do now=now+100 hours=hours+(delta or .0001) Service.tick() assert(runtime:step()) end
end
local function free(e)
    for _=1,80 do pump(1) if e.state=='RUNNING' and not runtime:owns('a') and not runtime:owns('b') then break end end
end
local function quiet(e,id)
    local job=Jobs.current():peekPersonal(id)
    if not job then local j=Record.create('care-'..id,id) assert(Jobs.current():create(j)) job=Jobs.current():get(j.id) end
    if job.state=='SUSPENDED' then assert(Jobs.current():update(job.id,job.revision,{state='PREPARING'})) job=Jobs.current():get(job.id) end
    local p=assert(Record.begin(job,'LEISURE')) p.step='STOP_CONFIRMED' p.settlementId='home'
    p.membershipRevision=1 p.settlementRevision=1 p.activityRef=assert(Service.context(id))
    p.leisure={format=1,activity='OBSERVE',hours=hours}
    assert(Jobs.current():update(job.id,job.revision,{payload=p}))
    local key=job.id local done=false
    local function same() local j=Jobs.current():peek(key) return j and j.payload.attemptId==p.attemptId end
    local function persist(fact)
        local j=Jobs.current():get(key) local copy=j.payload copy.step='IDLE' copy.leisure.stopped=true
        if j.state=='RUNNING' then assert(Jobs.current():update(key,j.revision,{state='STOPPING',payload=copy})) j=Jobs.current():get(key) end
        return Jobs.current():update(key,j.revision,{state='SUSPENDED',payload=copy,effects=fact.effects})
    end
    local spec={npcId=id,jobId=key,kind='SELF_CARE',binding=assert(Driver.bindId(actor,id)),nonPreemptive=true,
        validate=function() return same() and Service.validRef(id,p.activityRef) end,
        start=function()
            local j=Jobs.current():get(key) p.step='ACTING' p.leisure.started=true
            return Jobs.current():update(key,j.revision,{state='RUNNING',payload=p}) end,
        tick=function() done=not Service.validRef(id,p.activityRef) end,finished=function() return done end,
        persistFailure=persist}
    spec.stopAdapter=function(controller,ticket)
        return Stop.new({controller=controller,ticket=ticket,npc=bodies[id],npcId=id,jobId=key,same=same,
            pause=function() return true end,effects=function() return 'KNOWN' end,persist=persist}) end
    assert(runtime:submit(spec))
end
local e=start()
check(e.state=='GATHERING' and e.roster.a.jobId and e.roster.b.jobId,'participant Jobs precede body admission')
check(not e.startedAt and not e.outcome,'invitation does not imply opening')
free(e)
check(e.state=='RUNNING' and e.roster.a.joined and e.roster.b.joined,'real owned wait Sessions satisfy quorum and open early')
check(not keys.a and not keys.b,'formal wait bodies stop before FREE behavior admission')
check(not Assets.resourceOwner('leisureTile:2:2:0') and not Assets.resourceOwner('leisureTile:3:2:0'),'standing claims release only after stop confirmation')
check(Jobs.current():peek(e.roster.a.jobId).payload.step=='FREE','participant Job outlives the wait Session')
quiet(e,'a') quiet(e,'b') pump(20,.002)
check((e.roster.a.participationHours or 0)>0 and (e.roster.b.participationHours or 0)>0,'only actual personal Sessions accrue participation')
local revision=e.revision pump(2,.001)
check(e.revision==revision,'observation counters do not invalidate control commands')
delay.a=true delay.b=true masks.a=1 masks.b=1
check(Service.cancel(actor,e.id,e.revision),'cancel is accepted')
check(e.state~='CLOSED' and e.outcome=='CANCELLED','cancel does not fake completed body cleanup')
check(not Service.validRef('a',Jobs.current():peekPersonal('a').payload.activityRef),'cancel invalidates old personal attempt context')
local accrued=e.roster.a.participationHours pump(5,.001)
check(e.state~='CLOSED' and keys.a and e.roster.a.participationHours==accrued,'delayed native stop retains ownership and freezes participation')
delay.a=false delay.b=false masks.a=0 masks.b=0 pump(25)
check(e.state=='CLOSED' and e.roster.a.settled and e.roster.b.settled and not keys.a and not keys.b,'confirmed stops settle each participant and close the scene')
check(not Jobs.current():peek(e.roster.a.jobId),'known stopped participant Job retires through normal lifecycle')
local completed=start() free(completed) quiet(completed,'a') quiet(completed,'b') pump(15,.002)
hours=completed.endsAt+.001 pump(25)
check(completed.state=='CLOSED' and completed.outcome=='COMPLETED','duration completion requires actual participation and current presence')
local absent=start() free(absent) quiet(absent,'a') quiet(absent,'b') pump(15,.002)
epochs.a=epochs.a+1 pump(25)
check(absent.outcome=='INCOMPLETE' and absent.state=='CLOSED','new organizer command ends the scene without replacement')
local saved=start() free(saved) quiet(saved,'a') quiet(saved,'b') pump(10,.001)
check(Service.finishScenes('SAVE_INTERRUPTED'),'saving initiates normal wind-down')
assert(runtime:beginSave()) pump(20)
check(runtime:saveReady(),'group and personal stop receipts permit the existing save barrier')
assert(runtime:finishSave(true)) pump(20)
check(saved.state=='CLOSED' and saved.outcome=='INCOMPLETE','same-world save does not resume the performance')
local key=assert(Service.issue(actor,'home')) local first=assert(Service.start(actor,args(),key))
local changed=args() changed.name='Different'
check(not Service.start(actor,changed,key),'changed payload cannot reuse a committed request token')
assert(Service.cancel(actor,first.id,Store.get(first.id).revision)) pump(20)
local plan=assert(Service.schedule(actor,args(),assert(Service.issue(actor,'home')),hours+.1,1,3))
hours=hours+1.11 pump(12)
local schedules=assert(Service.schedules(actor,'home')) local s=schedules[1]
check(s.lastIndex==1,'missed calendar occurrences advance without backlog')
local occurrences=0 for _,row in pairs(Store.current().events) do if row.scheduleId==plan.id then occurrences=occurrences+1 end end
check(occurrences==1,'only the latest in-window occurrence is attempted')
check(Service.cancelSchedule(actor,plan.id,s.revision),'future schedule can be canceled independently')
local live=Store.get(s.lastEventId)
check(live.state=='GATHERING' or live.state=='RUNNING','canceling schedule leaves already-created scene intact')
print('activity-lifecycle: '..checks..' PASS (real Runtime/Controller/Jobs/Claims; native/personal actions mocked)')
