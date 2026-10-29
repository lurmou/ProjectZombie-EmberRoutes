local root,now={},0 local selectedJob,stopCount=nil,0
DebugLog={log=function() end}
getTimestampMs=function() return now end
getGameTime=function() return {getWorldAgeHours=function() return 1 end,getTimeOfDay=function() return 12 end} end
ZombRand=function(n) return n-1 end
CharacterStat={PAIN='pain'} CharacterTrait={SMOKER='smoker'}
local idle={} IdleState={instance=function() return idle end}
local entry={id='home',revision=1}
entry.factionId='f' entry.areas={{x=-10,y=-10,w=100,h=100}}
root.npcMembership={format=1,byNpc={a={npcId='a',factionId='f',settlementId='home',context='SETTLEMENT',revision=1}},receipts={},receiptOrder={}}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,id=function() return 'pair' end}
package.loaded['EmberRoutesProbe/TaskJobs']={current=function() return {forNpc=function() return selectedJob and {selectedJob} or {} end} end}
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return {stopJob=function() stopCount=stopCount+1 end} end}
package.loaded['EmberRoutesProbe/StudyService']={changed=function() end}
package.loaded['EmberRoutesProbe/Companion']={exportState=function() return {mode='HOLD'} end}
package.loaded['EmberRoutesProbe/SettlementLedger']={view=function() return entry end,data=function() return {factionId='f',entries={home=entry}} end}
package.loaded['EmberRoutesProbe/SettlementGeometry']={inside=function() return true end}
package.loaded['EmberRoutesProbe/LibraryIndex']={choose=function() return nil,true end}
package.loaded['EmberRoutesProbe/SettlementFacilities']={describe=function() end,watch=function() return {slots={}} end,advance=function() return 0 end}
getCell=function() return {getGridSquare=function() end} end
local fitness={onGoingStiffness=function() return false end,getCurrentExeStiffnessTimer=function() return 0 end,
    getCurrentExeStiffnessInc=function() return 0 end}
local npc={getX=function() return 1 end,getY=function() return 1 end,getZ=function() return 0 end,
    getStats=function() return {get=function() return 0 end} end,
    getBodyDamage=function() return {getOverallBodyHealth=function() return 100 end,
        getBodyParts=function() return {size=function() return 0 end} end} end,
    getPrimaryHandItem=function() end,getSecondaryHandItem=function() end,hasTrait=function() return false end,
    getFitness=function() return fitness end,getCurrentState=function() return idle end}
local s={safe=true,hunger=0,thirst=0,fatigue=0,endurance=1}
local Service=require 'EmberRoutesProbe/LeisureService' local binding={id='a',handle=npc}
local brief=Service.candidate({},binding,s,{scan=32,paths=1})
assert(brief and brief.leisure.brief,'membership independently permits a no-resource short wait while work is unknown')
Service.offer('a',entry)
local candidate,done=Service.candidate({},binding,s,{scan=32,paths=1})
assert(done and candidate.leisure.activity=='FITNESS','observed idle offer plus native eligibility produces an idle candidate')
s.fatigue=0.9 assert(not Service.candidate({},binding,s,{scan=32,paths=1}),'sleep care overrides all leisure') s.fatigue=0
selectedJob={id='job',effects='KNOWN',payload={step='ACTING',kind='LEISURE'}}
assert(Service.probeable('a')) Service.workReady('a') assert(stopCount==1)
Service.workState('a',entry,'READY')
assert(not Service.candidate({},binding,s,{scan=32,paths=1}),'ready work prevents new leisure')
selectedJob.effects='UNKNOWN' assert(not Service.probeable('a'),'unknown personal effects never permit work probing')
print('P3.5 discovery: native guards, idle freshness, work wakeup, UNKNOWN separation')
