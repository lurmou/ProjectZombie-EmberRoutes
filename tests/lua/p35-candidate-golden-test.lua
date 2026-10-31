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
assert(c==nil and done and why=='LEISURE_PAUSE','successful activity pause suppresses only new idle discovery')
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
