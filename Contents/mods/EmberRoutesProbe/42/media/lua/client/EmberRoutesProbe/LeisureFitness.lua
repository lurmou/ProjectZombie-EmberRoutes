require 'TimedActions/ISFitnessAction'
require 'Definitions/FitnessExercises'
local Config=require 'EmberRoutesProbe/LeisureConfig'
local F={}
local types={'squats','pushups','situp'}
function F.new(c)
    local action,ended,waitAt,cause,startedAt,finishing
    local leaf={kind='Action'} local l=c.payload.leisure
    local function retained() return c.sameAttempt() and c.body.retained() end
    local function active() return not ended and c.valid() and retained() end
    local function clean()
        c.npc:setVariable('ExerciseStarted',false) c.npc:setVariable('ExerciseEnded',true)
        -- FitnessFinished belongs to the native Out animation's End event.
        -- Setting it here jumps straight from a floor exercise to idle.
        c.npc:getFitness():setCurrentExercise(nil)
    end
    local function logStop(finished,why)
        require "EmberRoutesProbe/Log".write("LEISURE","FITNESS_STOP npc="..tostring(c.job and c.job.npcId or "?")
            .." cause="..tostring(why or cause or 'EXTERNAL_STOP')
            .." reps="..tostring(l.repetitions or 0)
            .." elapsedMs="..tostring(startedAt and getTimestampMs()-startedAt or -1))
        cause=nil
    end
    local function stop(self,finished,why)
        if ended or not retained() then return end
        ended=true l.stopped=not finished l.finished=finished==true
        logStop(finished,why)
        clean()
        if l.applying then c.effects='UNKNOWN' end
        if not c.persist() then error('FITNESS_PERSIST_FAILED') end
        -- Vanilla body cleanup without its player-only setGameSpeed(1).
        ISBaseTimedAction.stop(self)
    end
    local function updateCause(s)
        if not s then return 'UPDATE_SAMPLE_NIL' end
        if not s.safe then return 'UPDATE_UNSAFE' end
        if s.endurance<Config.fitnessExit.endurance then return 'UPDATE_ENDURANCE' end
        if s.hunger>=Config.fitnessExit.hunger then return 'UPDATE_HUNGER' end
        if s.thirst>=Config.fitnessExit.thirst then return 'UPDATE_THIRST' end
        if s.fatigue>=Config.fitnessExit.fatigue then return 'UPDATE_FATIGUE' end
        if c.npc:getPrimaryHandItem() or c.npc:getSecondaryHandItem() then return 'UPDATE_HANDS' end
        if c.npc:isAiming() then return 'UPDATE_AIM' end
        return 'UPDATE_CLIMB'
    end
    function leaf.run()
        if not action then
            if not active() then return 'Failure' end
            local exercise=types[ZombRand(3)+1] local data=FitnessExercises.exercisesType[exercise]
            if not data or data.item then return 'Failure' end
            -- Vanilla populates Fitness.exercises only via serverStart's init();
            -- an uninitialized NPC fitness makes setCurrentExercise silently
            -- store nil, killing the first ActiveAnimLooped (NO_CURRENT_EXE).
            local fitness=c.npc:getFitness()
            if fitness and fitness.init then fitness:init() end
            action=ISFitnessAction:new(c.npc,exercise,Config.fitnessMinutes,data,exercise)
            -- AI steering is not player input: IsoGameCharacter.StopAllActionQueueRunning/
            -- Aiming reads these flags and kills the action on carrier motion residue.
            -- The real danger conditions stay guarded by update() with custody handling.
            action.stopOnWalk=false action.stopOnRun=false action.stopOnAim=false
            action.useProgressBar=false
            local baseStart=action.start
            action.isValidStart=function()
                return active() and require('EmberRoutesProbe/LeisurePolicy').allowed('FITNESS',
                    require('EmberRoutesProbe/LeisureService').sample(c.npc,c.sample()),{hold=true})
            end
            action.isValid=function() return active() and c.npc:getVehicle()==nil end
            action.waitToStart=function(self)
                waitAt=waitAt or getTimestampMs()
                if c.npc:getCurrentState()==IdleState.instance() then return false end
                if getTimestampMs()-waitAt>=3000 then cause='WAIT_TIMEOUT' self:forceStop() return false end
                return true
            end
            action.start=function(self)
                if not active() or l.started then return end
                l.started=true l.repetitions=0
                l.untilHours=getGameTime():getWorldAgeHours()+Config.fitnessMinutes/60
                startedAt=getTimestampMs()
                if not c.persist() then error('FITNESS_PERSIST_FAILED') end
                require "EmberRoutesProbe/Log".write("LEISURE","FITNESS_START npc="
                    ..tostring(c.job and c.job.npcId or "?").." exercise="..tostring(exercise))
                baseStart(self)
            end
            action.update=function(self)
                if not active() then return end
                if finishing then return end
                local s=c.sample()
                if not s or not s.safe or s.endurance<Config.fitnessExit.endurance
                    or s.hunger>=Config.fitnessExit.hunger or s.thirst>=Config.fitnessExit.thirst
                    or s.fatigue>=Config.fitnessExit.fatigue or c.npc:getPrimaryHandItem() or c.npc:getSecondaryHandItem()
                    or c.npc:isAiming() or c.npc:isClimbing() then
                    cause=updateCause(s) self:forceStop() return
                end
                if getGameTime():getWorldAgeHours()>=(l.untilHours or math.huge) then
                    finishing=true cause='TIME_CAP'
                    clean()
                    return
                end
                c.npc:setMetabolicTarget(data.metabolics)
            end
            action.animEvent=function(self,event,parameter)
                if not active() or not l.started then return end
                if parameter=='FitnessFinished=TRUE' then
                    stop(self,finishing and (l.repetitions or 0)>0,cause or 'ANIM_FINISHED')
                    if self.action then self.action:forceStop() end
                    return
                end
                if event=='ActiveAnimLooped' and not finishing then
                    if not self.fitness:getCurrentExe() then self.fitness:setCurrentExercise(exercise) end
                    if not self.fitness:getCurrentExe() then cause='NO_CURRENT_EXE' self:forceStop() return end
                    l.applying=true if not c.persist() then error('FITNESS_PERSIST_FAILED') end
                    ISFitnessAction.exeLooped(self)
                    l.repetitions=l.repetitions+1 l.applying=nil
                    if not c.persist() then error('FITNESS_PERSIST_FAILED') end
                end
            end
            action.forceStop=function(self)
                if not active() then return end
                stop(self,false)
                if self.action then self.action:forceStop() end
            end
            action.stop=function(self) stop(self,false) end
            action.complete=function(self) if not active() then return false end stop(self,false,'COMPLETE') return true end
            action.perform=function(self) if retained() then clean() ISBaseTimedAction.perform(self) end end
            if not c.body.add(action) then clean() return 'Failure' end
        end
        if ISTimedActionQueue.hasAction(action) then return 'Running' end
        -- Queue cancellation can precede the native get-up animation. Keep the
        -- session until the body leaves FitnessState (also covered by stopMask).
        if l.started and c.npc:getCurrentState()==FitnessState.instance() then return 'Running' end
        return l.finished and 'Success' or 'Failure'
    end
    function leaf.halt()
        if not retained() then return false end
        if action and not ended then stop(action,false,'HALT') else clean() end
        return c.body.clear()
    end
    return leaf
end
return F
