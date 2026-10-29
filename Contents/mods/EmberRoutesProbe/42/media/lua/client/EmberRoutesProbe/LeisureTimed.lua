require 'TimedActions/ISBaseTimedAction'
-- One authorized native action; callbacks cannot survive their body/attempt.
-- Perf measures the engine-driven per-frame callbacks (isValid/update): they
-- run outside every service bucket, called straight from ISTimedActionQueue.
local Perf=require 'EmberRoutesProbe/RuntimeMetrics'
local T={}
function T.new(c,hooks)
    local action,ended
    local continuity=require('EmberRoutesProbe/LeisureContinuity').new(c)
    local leaf={kind='Action'} local l=c.payload.leisure
    local function retained() return c.sameAttempt() and c.body.retained() end
    local function active() return not ended and c.valid() and retained() end
    function leaf.run()
        if not action then
            if not active() then return 'Failure' end
            action=ISBaseTimedAction:new(c.npc)
            action.maxTime=-1 action.stopOnWalk=false action.stopOnRun=false action.stopOnAim=false
            action.useProgressBar=false
            action.isValid=function()
                if not Perf.active() then return active() end
                local started=Perf.now() local result=active()
                Perf.measureSpan('EngineActions',started) return result
            end
            action.start=function(self)
                if not active() or l.started then return end
                l.started=true if not c.persist() then error('LEISURE_PERSIST_FAILED') end
                continuity.start()
                if hooks.start then hooks.start(self) end
            end
            action.update=function(self)
                continuity.tick()
                if not Perf.active() then
                    if not active() then return end
                    local state=hooks.update(self)
                    if state=='Failure' then c.reason=c.reason or 'LEISURE_TARGET_CHANGED' self:forceStop()
                    elseif state=='Success' and continuity.boundary() then self:forceComplete() end
                    return
                end
                local started=Perf.now()
                if not active() then Perf.measureSpan('EngineActions',started) return end
                local state=hooks.update(self)
                Perf.measureSpan('EngineActions',started)
                if state=='Failure' then c.reason=c.reason or 'LEISURE_TARGET_CHANGED' self:forceStop()
                elseif state=='Success' and continuity.boundary() then self:forceComplete() end
            end
            action.complete=function(self)
                if not active() then return false end
                if hooks.complete and hooks.complete(self)~=true then return false end
                l.finished=true ended=true
                if not c.persist() then error('LEISURE_PERSIST_FAILED') end
                return true
            end
            action.perform=function(self) if retained() then ISBaseTimedAction.perform(self) end end
            action.stop=function(self)
                if ended or not retained() then return end
                ended=true l.stopped=true
                if hooks.stop then hooks.stop(self) end
                if l.applying then c.effects='UNKNOWN' end
                if not c.persist() then error('LEISURE_PERSIST_FAILED') end
                ISBaseTimedAction.stop(self)
            end
            if not c.body.add(action) then return 'Failure' end
        end
        if ISTimedActionQueue.hasAction(action) then return 'Running' end
        return l.finished and 'Success' or 'Failure'
    end
    function leaf.halt()
        if not retained() then return false end
        if hooks.stop then hooks.stop(action) end
        return c.body.clear()
    end
    return leaf
end
return T
