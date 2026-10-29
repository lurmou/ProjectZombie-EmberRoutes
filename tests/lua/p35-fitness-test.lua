local now,hours=0,1 local queued,live=nil,true local repeats,constructed=0,0
local logs={} DebugLog={log=function(m) logs[#logs+1]=m end}
getTimestampMs=function() return now end getGameTime=function() return {getWorldAgeHours=function() return hours end} end
ZombRand=function() return 0 end
local idle,exercising={},{} local state=idle
IdleState={instance=function() return idle end} FitnessState={instance=function() return exercising end}
package.loaded['TimedActions/ISFitnessAction']=true package.loaded['Definitions/FitnessExercises']=true
FitnessExercises={exercisesType={squats={metabolics='fitness'}}}
local current
local inits=0
local fitness={setCurrentExercise=function(_,v) current=v end,getCurrentExe=function() return current end,
    init=function() inits=inits+1 end}
local variables={}
local npc={getFitness=function() return fitness end,getCurrentState=function() return state end,
    getVehicle=function() end,getPrimaryHandItem=function() end,getSecondaryHandItem=function() end,
    isAiming=function() return false end,isClimbing=function() return false end,
    setVariable=function(_,k,v) variables[k]=v end,setMetabolicTarget=function() end}
local s={safe=true,hunger=0,thirst=0,fatigue=0,endurance=1}
package.loaded['EmberRoutesProbe/LeisureService']={sample=function() return {safe=true,hunger=0,thirst=0,
    fatigue=0,endurance=1,pain=0,healthy=true,handsFree=true,fitnessKnown=true,stiff=false} end}
ISBaseTimedAction={stop=function() queued=nil end,perform=function() queued=nil end}
ISFitnessAction={new=function(_,character,exercise)
    constructed=constructed+1 fitness:setCurrentExercise(exercise)
    return {character=character,fitness=fitness,start=function() end,
        forceStop=function(self) fitness:setCurrentExercise(nil) self:stop() end}
end,exeLooped=function() repeats=repeats+1 end}
ISTimedActionQueue={hasAction=function(a) return a==queued end}
local c={npc=npc,payload={leisure={activity='FITNESS'}},sample=function() return s end,persist=function() return true end,
    valid=function() return live end,sameAttempt=function() return live end,
    body={retained=function() return live end,add=function(a) queued=a a:start() return true end,
        clear=function() if queued then queued:stop() end return true end}}
local F=require 'EmberRoutesProbe/LeisureFitness'
local leaf=F.new(c)
assert(constructed==0,'construction waits for authorized run')
assert(leaf.run()=='Running' and constructed==1)
assert(inits>=1,'NPC fitness must be initialized or setCurrentExercise silently stores nil')
local a=queued
assert(a.stopOnWalk==false and a.stopOnRun==false and a.stopOnAim==false,
    'AI steering residue must not let Java stopOnRun/Aim cancel the exercise')
assert(logs[#logs]:find('FITNESS_START',1,true) and logs[#logs]:find('exercise=squats',1,true))
a:animEvent('ActiveAnimLooped','') assert(repeats==1)
current=nil a:animEvent('ActiveAnimLooped','') assert(repeats==2 and current=='squats')
s.endurance=0.2 a:update() assert(not queued and c.payload.leisure.stopped)
assert(logs[#logs]:find('FITNESS_STOP',1,true) and logs[#logs]:find('cause=UPDATE_ENDURANCE',1,true),
    'update-condition stops carry a machine-readable cause')
a:forceStop() a:animEvent('ActiveAnimLooped','') assert(repeats==2 and current==nil,'late loop cannot restart or grant XP')
live=false assert(leaf.halt()==false)
live=true queued=nil c.payload.leisure={activity='FITNESS'}
local second=F.new(c)
assert(second.run()=='Running')
queued:animEvent('','FitnessFinished=TRUE')
assert(not queued and c.payload.leisure.stopped,'vanilla finish event ends the exercise')
assert(logs[#logs]:find('cause=ANIM_FINISHED',1,true))
live=false assert(second.halt()==false)
live=true queued=nil s.endurance=1 c.payload.leisure={activity='FITNESS'}
local third=F.new(c)
assert(third.run()=='Running')
local finishing=queued state=exercising
finishing:animEvent('ActiveAnimLooped','')
hours=hours+1 finishing:update()
assert(queued==finishing and variables.ExerciseEnded==true and variables.FitnessFinished==nil,
    'time cap requests native Out animation without publishing its completion')
local before=repeats finishing:animEvent('ActiveAnimLooped','')
assert(repeats==before and current==nil,'closing cannot grant another repetition')
finishing:animEvent('','FitnessFinished=TRUE')
assert(c.payload.leisure.finished and third.run()=='Running','native state still owns body after queue exits')
state=idle assert(third.run()=='Success','release only after native fitness state exits')
assert(logs[#logs]:find('cause=TIME_CAP',1,true))
print('P3.5 fitness: authorization, vanilla repetitions, cancellation, late-loop fence, stop causes; no player speed API')
