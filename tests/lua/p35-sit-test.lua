local root,now={},0 local hours=1 local sitResting=false
DebugLog={log=function() end}
getTimestampMs=function() return now end
getGameTime=function() return {getWorldAgeHours=function() return hours end,getTimeOfDay=function() return 12 end} end
ZombRand=function(n) return n-1 end
CharacterStat={PAIN='pain'} CharacterTrait={SMOKER='smoker'}
local idle={} IdleState={instance=function() return idle end}
local entry={id='home',revision=1}
dofile('tests/lua/membership-fixture.lua')(function() return entry end,{'a'})
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,id=function() return 'x' end}
package.loaded['EmberRoutesProbe/TaskJobs']={current=function() return {forNpc=function() return {} end} end}
package.loaded['EmberRoutesProbe/StudyService']={changed=function() end}
package.loaded['EmberRoutesProbe/Companion']={exportState=function() return {mode='HOLD'} end}
local settlementRoot={format=1,revision=1,entries={[entry.id]=entry},publicLifeZones={format=1,revision=0,byId={}}}
package.loaded['EmberRoutesProbe/SettlementLedger']={view=function() return entry end,data=function() return settlementRoot end}
package.loaded['EmberRoutesProbe/SettlementGeometry']={inside=function() return true end}
package.loaded['EmberRoutesProbe/LibraryIndex']={choose=function() return nil,true end}
package.loaded['EmberRoutesProbe/SettlementFacilities']={describe=function() end,watch=function() return {slots={}} end,
    advance=function() return 0 end,reason=function() return 'PENDING' end}
getCell=function() return {getGridSquare=function() end} end
local seat={}
local prepared={id='s1',partId='p1',revision=1,parts={},key='seat:1'}
local resolvedKind,resolvedOwner
package.loaded['EmberRoutesProbe/ReposeSites']={
    new=function() return {step=function() return {object=seat,revision=1,key='seat:1',settlementId='home'},true end} end,
    prepare=function() return prepared end,
    keys=function(proof,kind) assert(kind=='REST') return {'repose:s1:p1'} end,
    resolve=function(proof,actor,npc,npcId,kind,owner)
        resolvedKind=kind resolvedOwner=owner return {object=seat,quality='averageBed'} end}
local fitness={onGoingStiffness=function() return false end,getCurrentExeStiffnessTimer=function() return 0 end,
    getCurrentExeStiffnessInc=function() return 0 end,init=function() end}
local npc={getX=function() return 1 end,getY=function() return 1 end,getZ=function() return 0 end,
    getStats=function() return {get=function() return 0 end} end,
    getBodyDamage=function() return {getOverallBodyHealth=function() return 100 end,
        getBodyParts=function() return {size=function() return 0 end} end} end,
    getPrimaryHandItem=function() end,getSecondaryHandItem=function() end,hasTrait=function() return false end,
    getFitness=function() return fitness end,getCurrentState=function() return idle end,
    isAsleep=function() return false end,isResting=function() return sitResting end}
local Service=require 'EmberRoutesProbe/LeisureService'
local binding={id='a',handle=npc}
local s={safe=true,hunger=0,thirst=0,fatigue=0,endurance=1}
-- Without the native repose bridge the seat branch must not even scan.
EmberRoutesProbeJava=nil
Service.offer('a',entry)
local fallback=Service.candidate({},binding,s,{scan=32,paths=1})
assert(fallback and fallback.leisure.activity=='FITNESS','no bridge falls back to standing activities')
EmberRoutesProbeJava={reposeAtWithControl=function() return true end}
Service.offer('a',entry)
local candidate=Service.candidate({},binding,s,{scan=32,paths=1},{cooldowns={OBSERVE=2,FITNESS=2}})
assert(candidate and candidate.leisure.activity=='SIT','seat scan yields a sitting candidate')
assert(candidate.site==prepared and candidate.claims[1]=='repose:s1:p1','proof and repose keys ride the payload')
assert(Service.valid({},npc,'a',{settlementId='home',leisure={activity='SIT'}})==false,'SIT without site proof is rejected')
assert(Service.valid({},npc,'a',{settlementId='home',membershipRevision=1,settlementRevision=1,leisure={activity='OBSERVE'}})==true)
assert(require('EmberRoutesProbe/LeisureRecord').valid({kind='LEISURE',settlementId='home',
    leisure={format=1,activity='SIT',hours=1,started=true,untilHours=2}}),'record accepts SIT payloads')

-- Execution leaf: enter REST through the body capability, sit out the game
-- duration, leave with verified native exit.
local entered,exited={},0
local body={retained=function() return true end,
    repose=function(kind,enterFlag,object,quality)
        if enterFlag then entered={kind,object,quality} sitResting=true return true end
        exited=exited+1 sitResting=false return true end}
local function context(jobId)
    return {npc=npc,actor={},job={npcId='a',id=jobId},
        payload={leisure={format=1,activity='SIT',hours=1},site=prepared,settlementId='home'},
        persist=function() return true end,valid=function() return true end,sameAttempt=function() return true end,
        body=body}
end
package.loaded['EmberRoutesProbe/LeisurePosture']={new=function() return {enter=function() return 'Success' end,leave=function() return true end} end}
local S=require 'EmberRoutesProbe/LeisureSit'
local switch,reviews=false,0
Service.review=function() reviews=reviews+1 return switch end
local c=context('j1')
local leaf=S.new(c)
assert(leaf.run()=='Running' and entered[1]=='REST' and entered[2]==seat and entered[3]=='averageBed',
    'enter uses native REST with the resolved seat')
assert(resolvedKind=='REST' and resolvedOwner=='j1','resolve revalidates with the owning job')
assert(leaf.run()=='Running','duration has not elapsed')
leaf.run()
hours=2
assert(leaf.run()=='Running' and exited==0,'game deadline is a review boundary, not forced get-up')
for _=1,600 do now=now+100 assert(leaf.run()=='Running') end
assert(reviews==2 and exited==0 and not c.payload.leisure.finished,'no better activity renews same seat with bounded reviews')
switch=true
local result
for _=1,100 do now=now+100 result=leaf.run() if result~='Running' then break end end
assert(result=='Success' and c.payload.leisure.finished==true and exited==1,'better successor triggers one native exit')
local c2=context('j2')
local leaf2=S.new(c2)
assert(leaf2.run()=='Running')
sitResting=false
assert(leaf2.run()=='Failure' and c2.payload.leisure.stopped==true and exited==2,'native interruption ends as stopped')
local c3=context('j3')
local leaf3=S.new(c3)
assert(leaf3.run()=='Running')
assert(leaf3.halt()==true and c3.payload.leisure.stopped==true and exited==3,'business halt leaves the seat')
local c4=context('j4')
local leaf4=S.new(c4)
assert(leaf4.halt()==true and exited==3,'halt before entry leaves nothing to end')
print('P3.5 sit: seat candidate via shared reservation, REST entry/leave protocol, interrupts')
