-- Native timed action inside the existing body Session. The engine, rather
-- than the paced business tick, advances turning and the pre-sit delay.
require 'TimedActions/ISRestAction'
local P={}
function P.new(c,object)
    local action,deadline,leaving,cancelled,begun
    local function owned() return c.sameAttempt() and c.body.retained() end
    return {
        enter=function()
            if not owned() or leaving then return 'Failure' end
            deadline=deadline or getTimestampMs()+8000
            if getTimestampMs()>deadline then c.reason='SIT_POSE_TIMEOUT' return 'Failure' end
            if not action then
                if c.npc:getCurrentActionContextStateName()~='idle' or c.npc:isSittingOnFurniture()
                    or c.npc:isSitOnGround() or c.npc:getSitOnFurnitureObject()~=nil then return 'Running' end
                c.npc:clearVariable('forceGetUp')
                action=ISRestAction:new(c.npc,object,true)
                if not action:furnitureHasSittingData(object) then c.reason='SIT_NO_ANIMATION' return 'Failure' end
                if not c.body.furniture(object,'PREPARE') then c.reason='SIT_ACTION_REJECTED' return 'Failure' end
                action.stopOnWalk=false action.stopOnRun=false action.stopOnAim=false
                action.forceProgressBar=false action.useProgressBar=false
                local baseStart,baseStop,basePerform=action.start,action.stop,action.perform
                action.isValidStart=function() return owned() and not leaving and c.valid() end
                action.isValid=action.isValidStart
                action.start=function(self)
                    if not owned() or leaving then self:forceStop() return end
                    if not c.body.furniture(object,'STAND_TARGET') then self:forceStop() return end
                    begun=true baseStart(self)
                end
                action.stop=function(self)
                    if not owned() then return end
                    cancelled=true baseStop(self)
                end
                action.perform=function(self) if owned() then basePerform(self) end end
                action.forceCancel=function(self)
                    cancelled=true
                    if owned() and not begun then self:interruptWaitToStart() end
                end
                -- The surrounding Session owns REST lifetime. Native completion
                -- must not end the seated idle or reset a following reading leaf.
                action.complete=function() return true end
                if not c.body.add(action) then c.reason='SIT_ACTION_REJECTED' return 'Failure' end
            end
            if cancelled then c.reason='SIT_ACTION_CANCELLED' return 'Failure' end
            if ISTimedActionQueue.hasAction(action) then return 'Running' end
            if c.npc:isSittingOnFurniture() and c.npc:getVariableBoolean('SitOnFurnitureStarted') then return 'Success' end
            return 'Running'
        end,
        leave=function()
            if not owned() then return false end
            leaving=true
            if action and ISTimedActionQueue.hasAction(action) then
                if not c.body.clear() or not c.body.stop() then return false end
            end
            if c.npc:isSittingOnFurniture() then
                c.npc:setVariable('forceGetUp',true)
                return false
            end
            return c.npc:getSitOnFurnitureObject()==nil
        end,
    }
end
return P
