-- Golden fixtures for the idle candidate pipeline: activity ordering, return
-- protocol, budget accounting and per-offer state lifecycle. The A1 registry
-- refactor must keep every assertion byte-identical.
local root,now={},0 local hours=1
DebugLog={log=function() end}
getTimestampMs=function() return now end
getGameTime=function() return {getWorldAgeHours=function() return hours end,getTimeOfDay=function() return 12 end} end
local rolls={}
ZombRand=function(n) local r=table.remove(rolls,1) if r then return r end return n-1 end
CharacterStat={PAIN='pain'} CharacterTrait={SMOKER='smoker'}
local idle={} IdleState={instance=function() return idle end}
local entry={id='home',revision=1}
dofile('tests/lua/membership-fixture.lua')(function() return entry end,{'a'})
local mode={socialPending=false,readingDone=true,readingCandidate=nil,smoker=false,smoke=false,
    seat=false,seatDeferred=false}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,id=function() return 'x' end}
package.loaded['EmberRoutesProbe/TaskJobs']={current=function() return {forNpc=function() return {} end} end}
package.loaded['EmberRoutesProbe/StudyService']={changed=function() end,
    decorateLeisure=function(c) c.study=true return c end}
package.loaded['EmberRoutesProbe/Companion']={exportState=function() return {mode='HOLD'} end}
local settlementRoot={format=1,revision=1,entries={[entry.id]=entry},publicLifeZones={format=1,revision=0,byId={}}}
package.loaded['EmberRoutesProbe/SettlementLedger']={view=function() return entry end,data=function() return settlementRoot end}
package.loaded['EmberRoutesProbe/SettlementGeometry']={inside=function() return true end}
package.loaded['EmberRoutesProbe/SettlementFacilities']={describe=function() end,watch=function() return {slots={}} end,
    advance=function() return 0 end,reason=function() return 'PENDING' end}
package.loaded['EmberRoutesProbe/SocialCoordinator']={
    advertise=function() end,withdraw=function() end,reset=function() end,
    pending=function() return mode.socialPending and 'k1' or nil end,
    invite=function() return 'k2' end,
    view=function(key,id) return {other='b',point={x=1,y=1,z=0}} end}
package.loaded['EmberRoutesProbe/LibraryIndex']={choose=function(actor,npc,e,_,budget,offset,leisure)
    if mode.requireContainer then assert(budget.containers==1) budget.containers=budget.containers-1 end
    budget.scan=budget.scan-1
    if mode.readingDone then return mode.readingCandidate,true end
    return nil,false,'INDEX_PENDING' end}
package.loaded['EmberRoutesProbe/LeisureSmoke']={find=function(npc,budget,row)
    if mode.smoke then return {item={getID=function() return 7 end},fire={getID=function() return 8 end}},true end
    return nil,true end}
local seatIterators=0
package.loaded['EmberRoutesProbe/ReposeSites']={
    new=function() seatIterators=seatIterators+1 local steps=0
        return {step=function()
            if not mode.seat then return nil,true end
            if mode.seatDeferred then steps=steps+1
                if steps==1 then return nil,false,'SEAT_PENDING' end end
            return {object={},revision=1,key='seat',settlementId='home'},true end} end,
    prepare=function(f) return {id='s',partId='p',revision=1,parts={},key=f.key} end,
    keys=function() return {'repose:s:p'} end,
    resolve=function() end}
getCell=function() return {getGridSquare=function() end} end
local fitness={onGoingStiffness=function() return false end,getCurrentExeStiffnessTimer=function() return 0 end,
    getCurrentExeStiffnessInc=function() return 0 end,init=function() end}
local npc={getX=function() return 1 end,getY=function() return 1 end,getZ=function() return 0 end,
    getStats=function() return {get=function() return 0 end} end,
    getBodyDamage=function() return {getOverallBodyHealth=function() return 100 end,
        getBodyParts=function() return {size=function() return 0 end} end} end,
    getPrimaryHandItem=function() end,getSecondaryHandItem=function() end,
    hasTrait=function() return mode.smoker end,
    getFitness=function() return fitness end,getCurrentState=function() return idle end}
EmberRoutesProbeJava={reposeAtWithControl=function() return true end}
local Service=require 'EmberRoutesProbe/LeisureService'
local binding={id='a',handle=npc}
local s={safe=true,hunger=0,thirst=0,fatigue=0,endurance=1}
local function fresh() return {scan=32,paths=1,containers=4} end

-- Intentional new golden expectations for design 1.2: discover all bounded
-- candidates; unfinished scans cannot veto a known short activity.
Service.offer('a',entry)
mode.socialPending=true
local c=Service.candidate({},binding,s,fresh())
assert(c and c.leisure.activity=='SOCIAL','reserved partner retains acceptance continuity')
mode.socialPending=false mode.readingDone=false
c=Service.candidate({},binding,s,fresh())
assert(c and c.leisure.activity=='FITNESS','unfinished library does not block known activities')
mode.readingDone=true mode.readingCandidate={study=true,entry=entry}
-- Social chance consumes first roll; stroll direction second; weighted roll third.
rolls={9999,0,0}
c=Service.candidate({},binding,s,fresh())
assert(c and c.study,'reading participates in the same candidate pool')
mode.readingCandidate=nil mode.seat=true
Service.seatReleased('home')
local restingMemory={cooldowns={FITNESS=hours+1}}
local b=fresh() rolls={9999,0,0}
c=Service.candidate({},binding,s,b,restingMemory)
assert(c and c.site and c.leisure.activity=='SIT','usable seat beats standing even at fallback selection')
assert(b.scan<=32 and b.scan>=0,'bounded shared scan')
mode.seatDeferred=true
Service.reset() Service.offer('a',entry)
rolls={9999,0,9999}
c=Service.candidate({},binding,s,fresh())
assert(c and c.leisure.activity=='FITNESS','seat discovery does not block known activity')
rolls={9999,0,9999}
c=Service.candidate({},binding,s,fresh(),restingMemory)
assert(c and c.leisure.activity=='SIT','next discovery resumes seat iterator')
Service.failed('a',c.targetKey,'SITE_PATH_FAILED')
rolls={9999,0,0}
c=Service.candidate({},binding,s,fresh())
assert(c and c.leisure.activity~='SIT','failed target cools down without blocking alternatives')
Service.workState('a',entry,'OBSERVING')
c=Service.candidate({},binding,s,fresh())
assert(c and c.leisure.activity=='OBSERVE' and c.leisure.brief and not c.site,'unknown work permits only resource-free waiting')
Service.workState('a',entry,'READY')
assert(not Service.candidate({},binding,s,fresh()),'ready work wins')
print('P3.5 golden v1.2: shared pool, slow discovery, bounded target backoff, independent membership and work observations')

Service.workState('a',entry,'IDLE')
local c,done,why=Service.candidate({},binding,s,fresh(),{cooldowns={},decisionAfter=2})
assert(c and c.leisure.ambient and c.leisure.activity=='OBSERVE' and c.leisure.untilHours==2
    and not c.leisure.point and done and why=='LEISURE_PAUSE',
    'decision pause returns resource-free observation with the original deadline')
local Record=require 'EmberRoutesProbe/LeisureRecord'
assert(Record.valid({kind='LEISURE',settlementId=entry.id,leisure=c.leisure}))
local pausedMemory={cooldowns={OBSERVE=2},decisionAfter=2}
Service.finished({job={npcId='a'},reason='LEISURE_NEEDS_CARE',
    payload={leisure=c.leisure,leisureMemory=pausedMemory}},true)
assert(pausedMemory.decisionAfter==2 and pausedMemory.cooldowns.OBSERVE==2,
    'interrupted ambient waiting preserves the existing decision deadline and cooldown')
local memory={cooldowns={OBSERVE=2,STROLL=2,FITNESS=2,SIT=2,READING=2,SMOKE=2,SOCIAL=2}}
local fallback=Service.candidate({},binding,s,fresh(),memory)
assert(fallback and fallback.leisure.ambient and not fallback.leisure.point,
    'all activity cooldowns still permit resource-free ambient observation')
assert(Record.valid({kind='LEISURE',settlementId=entry.id,leisure=fallback.leisure}))
fallback.leisure.finished=true
Service.finished({job={npcId='a'},payload={leisure=fallback.leisure,leisureMemory=memory}},true)
assert(memory.cooldowns.OBSERVE==2 and memory.decisionAfter==nil,
    'ambient completion neither changes cooldowns nor starts another decision pause')
Service.workState('a',entry,'READY')
c,done,why=Service.candidate({},binding,s,fresh(),{cooldowns={},decisionAfter=2})
assert(not c and Service.status('a').reason=='WORK_READY','work takes precedence over an idle decision pause')
Service.workState('a',entry,'IDLE')
mode.socialPending=false mode.seat=false mode.readingCandidate=nil mode.readingDone=false
local incumbent={actor={},npc=npc,job={npcId='a'},sample=function() return s end,budget=fresh(),
    payload={leisure={activity='SIT'},leisureMemory={cooldowns={}}}}
assert(not Service.review(incumbent,45000) and Service.status('a').reason=='CONTINUING',
    'unfinished discovery keeps the incumbent seated without starting an invitation')
CharacterStat.BOREDOM='boredom'
npc.getStats=function() return {get=function(_,key) return key=='boredom' and 100 or 0 end} end
mode.readingDone=true mode.requireContainer=true mode.readingCandidate={item={getID=function() return 42 end},entry=entry}
incumbent.budget=fresh()
incumbent.payload.leisureMemory.cooldowns.FITNESS=hours+1
local seatedReview=Service.review(incumbent,3600000)
assert(not seatedReview and incumbent.budget.containers==4,'seated idle never scans books or stands merely from habituation')
incumbent.payload.leisure.activity='OBSERVE'
incumbent.budget=fresh()
assert(Service.review(incumbent,55000),'clearly better eligible reading crosses switch cost and margin')
assert(incumbent.budget.containers==3,'read-only review passes and charges bounded container discovery')
mode.requireContainer=false
incumbent.payload.leisure.finished=true
Service.finished(incumbent,true)
assert(not incumbent.payload.leisureMemory.decisionAfter,'prepared successor bypasses the post-activity blank pause')
local successor=Service.candidate({},binding,s,fresh(),{cooldowns={},decisionAfter=hours+1})
assert(successor and successor.item and successor.item:getID()==42,'revalidated successor keeps the reviewed target rather than rerolling SIT')
print('PASS incumbent retention, pure bounded review and successor handoff')

Service.reset() Service.offer('a',entry)
mode.seat=false mode.readingCandidate=nil mode.readingDone=true
Service.candidate({},binding,s,fresh(),restingMemory)
local before=seatIterators
Service.candidate({},binding,s,fresh(),restingMemory)
assert(seatIterators==before,'no-seat discovery sleeps between decisions')
Service.seatReleased('home') mode.seat=true mode.seatDeferred=false
local seated=Service.candidate({},binding,s,fresh(),restingMemory)
assert(seated and seated.leisure.activity=='SIT' and seatIterators>before,'released seat wakes failed discovery')
print('PASS ordered seat fallback, seated no-book-scan, seat retry sleep and release wake')

-- Cut 2 main chain: neutral interruption -> durable hint -> ordinary issuance /
-- consumption -> repeated interruption; a lost original falls back cleanly.
local function copy(v)
    if type(v)~='table' then return v end
    local t={} for k,x in pairs(v) do t[k]=copy(x) end return t
end
local Personal=require 'EmberRoutesProbe/SelfCareRecord'
local saved=Personal.create('care','a')
local api={forNpc=function() return {copy(saved)} end,
    update=function(_,id,revision,patch)
        assert(id==saved.id and revision==saved.revision)
        for k,v in pairs(patch) do saved[k]=copy(v) end
        saved.revision=saved.revision+1
        assert(Personal.valid(saved))
        return true
    end}
package.loaded['EmberRoutesProbe/TaskJobs'].current=function() return api end
local proof={id='chair',partId='part',revision=1,key='seat',settlementId='home',
    parts={{id='part',x=4,y=5,z=0}}}
local function interrupted(activity)
    local p={settlementId='home',leisureMemory=copy(saved.payload.leisureMemory)}
    if activity=='SIT' then p.leisure={activity='SIT',moving=true,seated=true} p.site=proof
    else p.study={leisure=true} p.itemId=42 p.reading={stopped=true} end
    local context={payload=p,job=saved,reason='LEISURE_WORK_READY'}
    if activity=='SIT' then Service.finished(context,true) else assert(Service.interrupted(context)) end
    assert(p.leisureMemory.resumeHint.activity==activity and Record.memory(p.leisureMemory))
    assert(not p.leisureMemory.last and not p.leisureMemory.cooldowns[activity]
        and not p.leisureMemory.moveAfter and not p.leisureMemory.decisionAfter,
        'work interruption adds no failure, repeat, move or decision penalty')
    saved.payload.leisureMemory=copy(p.leisureMemory)
end
Service.reset() Service.offer('a',entry)
mode.seat=false mode.readingCandidate=nil mode.requireContainer=false
local present=true
getCell=function() return {getGridSquare=function(_,x,y)
    if x~=4 or y~=5 then return end
    return {getObjects=function() return {size=function() return present and 1 or 0 end,
        get=function() return {getModData=function() return {EmberRoutesRepose={id='chair',partId='part',revision=1}} end} end} end}
end} end
package.loaded['EmberRoutesProbe/SettlementFacilities'].describe=function() return nil,1 end
package.loaded['EmberRoutesProbe/ReposeSites'].prepare=function(candidate)
    assert(candidate.object and candidate.revision==1)
    return copy(proof)
end
interrupted('SIT')
-- Supported record validation and a detached begin retain only the memory,
-- never the predecessor's claims or elapsed leisure record.
local begun=assert(Personal.begin(copy(saved),'EAT',{state='RESTORED'}))
assert(begun.leisureMemory.resumeHint.activity=='SIT' and #begun.claims==0 and not begun.leisure)
for _,state in ipairs({'RESTORED','INVALIDATED'}) do
    local restored=copy(saved) restored.payload.resume={state=state}
    assert(Personal.valid(restored) and restored.payload.leisureMemory.resumeHint.activity=='SIT')
end
Service.workState('a',entry,'READY')
assert(not Service.candidate({},binding,s,fresh(),copy(saved.payload.leisureMemory)))
assert(saved.payload.leisureMemory.resumeHint,'work discovery does not consume the hint')
Service.offer('a',entry)
local resumed=Service.candidate({},binding,s,fresh(),copy(saved.payload.leisureMemory))
assert(resumed and resumed.resume and resumed.site.id=='chair' and resumed.claims[1]=='repose:s:p')
assert(saved.payload.leisureMemory.resumeHint,'validation does not consume before issuance is accepted')
assert(Service.consumeResume('a',copy(saved.payload.leisureMemory)))
assert(not saved.payload.leisureMemory.resumeHint,'accepted issuance clears the durable hint before rollback snapshots')
interrupted('SIT') -- A new work interruption creates a fresh single hint.
present=false
local invalidMemory=copy(saved.payload.leisureMemory)
for kind in pairs({OBSERVE=1,STROLL=1,FITNESS=1,SIT=1,READING=1,SMOKE=1,SOCIAL=1}) do invalidMemory.cooldowns[kind]=2 end
local invalid=Service.candidate({},binding,s,fresh(),invalidMemory)
assert(invalid and invalid.leisure.ambient and not invalid.resume and not saved.payload.leisureMemory.resumeHint,
    'lost original is discarded once and normal discovery reaches cut-1 ambient')
interrupted('READING')
local book={getID=function() return 42 end}
package.loaded['EmberRoutesProbe/LibraryIndex'].choose=function(actor,body,e,target,budget,offset,leisure,itemId)
    assert(leisure and itemId==42,'resume re-finds only the original book through library discovery')
    budget.scan=budget.scan-1
    return {item=book,id=42,entry=entry},true
end
package.loaded['EmberRoutesProbe/StudyService'].valid=function(actor,body,id,p)
    return p.study and p.membershipRevision~=nil and p.settlementRevision==entry.revision
end
local reading=Service.candidate({},binding,s,fresh(),copy(saved.payload.leisureMemory))
assert(reading and reading.resume and reading.item==book and not reading.reading,'reading starts a fresh normal attempt')
assert(Service.consumeResume('a',copy(saved.payload.leisureMemory)))
assert(not saved.payload.leisureMemory.resumeHint)
assert(not Record.memory({cooldowns={},resumeHint={activity='SOCIAL',settlementId='home'}}))
print('PASS cut 2 neutral SIT/READING interruption, record continuity, single consumption and invalid-target ambient fallback')
