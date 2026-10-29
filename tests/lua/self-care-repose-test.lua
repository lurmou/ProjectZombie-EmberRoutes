local checks=0 local function check(v,s) checks=checks+1 assert(v,s) end
package.loaded['EmberRoutesProbe/Log']={write=function() end}
local asleep,resting=false,false local fatigue,endurance=0.9,0.1 local hours=10
local owner,active=true,true local enters,wakes,saves=0,0,0
CharacterStat={FATIGUE='fatigue',ENDURANCE='endurance'}
getGameTime=function() return {getWorldAgeHours=function() return hours end} end
local npc={getStats=function() return {get=function(_,key) return key=='fatigue' and fatigue or endurance end} end,
    isAsleep=function() return asleep end,isResting=function() return resting end}
local function context(kind)
    return {npc=npc,payload={kind=kind,attemptId='care:1'},effects='KNOWN',
        sameAttempt=function() return owner end,valid=function() return active and owner end,
        persist=function() saves=saves+1 return true end,
        body={retained=function() return owner end,repose=function(kind,enter)
            if not owner or enter and not active then return false end
            if enter then enters=enters+1 asleep=kind=='SLEEP' resting=kind=='REST'
            else if asleep then wakes=wakes+1 end asleep=false resting=false end
            return true
        end}}
end
local Repose=require 'EmberRoutesProbe/SelfCareRepose'
local c=context('SLEEP') local leaf=Repose.new(c)
check(leaf.run()=='Running' and asleep and fatigue==0.9 and saves>0,'sleep entry records fact and leaves native Stats untouched')
hours=11 fatigue=0.6
check(leaf.run()=='Running' and asleep,'observed partial native recovery continues sleeping')
fatigue=0.2
check(leaf.run()=='Success' and not asleep and wakes==1,'actual fatigue target wakes before task completion')
check(c.payload.repose.after==0.2 and c.payload.repose.completed,'persist actual post-wake effect')
check(leaf.halt() and wakes==1,'repeated stop cannot wake or apply native waking effects twice')
local rest=context('REST') local r=Repose.new(rest)
check(r.run()=='Running' and resting and endurance==0.1,'rest does not invent endurance')
endurance=0.4 active=false
check(r.halt() and not resting and rest.payload.repose.after==0.4,'save interruption preserves partial endurance and clears resting flag')
active=true fatigue=0.9 local stopped=context('SLEEP') local s=Repose.new(stopped)
assert(s.run()=='Running') owner=false
check(not s.halt() and asleep,'stale ticket cannot wake the successor')
owner=true assert(s.halt())
local timeout=context('SLEEP') local t=Repose.new(timeout)
assert(t.run()=='Running') hours=hours+9
check(t.run()=='Failure' and not asleep and timeout.reason=='NATIVE_REPOSE_TIMEOUT' and fatigue==0.9,
    'missing native recovery times out without fixed-stat fallback')
local foreign=context('REST') foreign.payload.repose={attemptId='care:0',kind='REST',effects='KNOWN',started=true}
check(Repose.new(foreign).run()=='Failure' and foreign.effects=='UNKNOWN','restored foreign episode cannot be replayed')
print('PASS '..checks..' rest/sleep ownership and observed-effect checks; native Stats mocked')
-- Furniture sleep uses the existing native seating adapter, then an owned
-- sleep pose. No GetOnBed directions or arbitrary adjacent points are built.
local bed={} local now=0 local sitting=false local poseReady=false local poseStarted=false
getTimestampMs=function() return now end
npc.isSittingOnFurniture=function() return sitting end
npc.getSitOnFurnitureObject=function() return sitting and bed or nil end
package.loaded['EmberRoutesProbe/ReposeSites']={resolve=function() return {object=bed,quality='goodBed'} end}
package.loaded['EmberRoutesProbe/LeisurePosture']={new=function(_,object)
    assert(object==bed)
    return {enter=function() sitting=true resting=true return 'Success' end,
        leave=function() return not sitting end}
end}
EmberRoutesProbeJava={motionResult=function() return 'REACHED' end,reachedSeat=function() return bed end,
    bedPoseReady=function(_,pose) assert(pose=='Asleep') return poseReady end}
fatigue=0.9 owner=true active=true
local native=context('SLEEP') native.payload.site={} native.actor={} native.job={id='care',npcId='a'} native.budget={paths=1}
native.body.move=function(_,point)
    assert(point.furniture==bed and point.sleep and point.locations==nil)
    return true,'MOVE_REQUESTED_SEAT'
end
native.body.furniture=function(object,phase)
    assert(object==bed and phase=='LIE' and sitting and not resting and not asleep)
    poseStarted=true return true
end
native.body.stop=function() asleep=false return not sitting end
local B=require 'EmberRoutesProbe/SleepBed'
local approach=B.move(native)
check(approach.run()=='Running' and approach.run()=='Success','sleep uses same exact native seat planner and goal validation')
local bedLeaf=Repose.new(native)
check(bedLeaf.run()=='Running' and sitting and poseStarted and not asleep,'native sitting must precede lying and sleep effects')
check(bedLeaf.run()=='Running' and not asleep,'unconfirmed lying never starts fatigue recovery')
poseReady=true
check(bedLeaf.run()=='Running' and asleep,'observed owned pose admits native sleep effects')
fatigue=0.2
check(bedLeaf.run()=='Running' and not asleep and native.effects=='KNOWN','wake waits for reverse pose and original get-up')
sitting=false
check(bedLeaf.run()=='Success' and native.payload.repose.completed,'only a drained native exit finishes the sleep episode')
local cancelled=context('SLEEP') cancelled.payload.site={} cancelled.actor={} cancelled.job={id='cancel',npcId='a'}
cancelled.body.furniture=native.body.furniture cancelled.body.stop=native.body.stop
poseReady=false poseStarted=false fatigue=0.9
local pending=Repose.new(cancelled)
assert(pending.run()=='Running') owner=false
check(not pending.halt(),'stale owner cannot reverse another session pose')
owner=true sitting=false assert(pending.halt())
print('PASS native seating -> owned bed pose -> wake/seat/get-up handoff; engine animation mocked')