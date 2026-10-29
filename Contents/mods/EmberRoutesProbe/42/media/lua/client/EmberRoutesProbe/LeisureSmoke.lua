require 'TimedActions/ISEatFoodAction'
local Store=require 'EmberRoutesProbe/LaborStore'
-- Perf measures the engine-driven per-frame isValid/update callbacks; they
-- run outside every service bucket.
local Perf=require 'EmberRoutesProbe/RuntimeMetrics'
local S={}
local function cigarette(item)
    local kind=item and item:getFullType()
    return kind=='Base.CigaretteSingle' or kind=='Base.CigaretteRolled' or kind=='Base.Cigarettes'
end
function S.find(npc,budget,row)
    local list=npc:getInventory():getItems()
    if list:size()>512 then return nil,true end
    if row.size~=list:size() then row.size=list:size() row.offset=0 row.fireOffset=0 row.item=nil end
    row.offset=row.offset or 0
    while budget.scan>0 do
        budget.scan=budget.scan-1
        if not row.item then
            if row.offset>=list:size() then row.offset=0 return nil,true end
            local item=list:get(row.offset) row.offset=row.offset+1
            if cigarette(item) and not Store.owner(item:getID()) then row.item=item row.fireOffset=0 end
        else
            if row.fireOffset>=list:size() then row.item=nil
            else
                local fire=list:get(row.fireOffset) row.fireOffset=row.fireOffset+1
                local required=row.item:getRequireInHandOrInventory()
                if required and required:contains(fire:getFullType()) and fire:getCurrentUsesFloat()>=fire:getUseDelta()
                    and not Store.owner(fire:getID()) then
                    return {item=row.item,fire=fire},true
                end
            end
        end
    end
    return nil,false
end
function S.new(c)
    local l=c.payload.leisure local action,ended,item,fire
    local function active() return not ended and c.valid() and c.sameAttempt() and c.body.retained() end
    local function save() if not c.persist() then error('SMOKE_EFFECT_NOT_PERSISTED') end end
    local function observe()
        if item:getContainer()~=c.npc:getInventory() and not l.finished then c.effects='UNKNOWN' end
        l.after=item:getContainer()==c.npc:getInventory() and item:getUses() or 0
        l.fireAfter=fire:getCurrentUsesFloat()
        if l.after>l.before or l.fireAfter>l.fireBefore+0.0001 or l.after<0 or l.fireAfter<0
            or not l.started and (l.after~=l.before or l.fireAfter~=l.fireBefore)
            or l.finished and l.after>=l.before then c.effects='UNKNOWN' end
        save()
    end
    local leaf={kind='Action'}
    function leaf.run()
        if not action then
            if not active() then return 'Failure' end
            local items=c.npc:getInventory():getItems()
            if items:size()>512 then return 'Failure' end
            for i=0,items:size()-1 do
                local v=items:get(i)
                if v:getID()==c.payload.itemId then item=v end
                if v:getID()==l.fireId then fire=v end
            end
            if not cigarette(item) or not fire or item:getContainer()~=c.npc:getInventory()
                or fire:getContainer()~=c.npc:getInventory() or not Store.validPersonal(c.job,c.token,'item:'..fire:getID())
                or not item:getRequireInHandOrInventory():contains(fire:getFullType()) or fire:getCurrentUsesFloat()<fire:getUseDelta() then return 'Failure' end
            l.before=item:getUses() l.fireBefore=fire:getCurrentUsesFloat() save()
            action=ISEatFoodAction:new(c.npc,item,1)
            local start,update,complete,stop,perform=action.start,action.update,action.complete,action.stop,action.perform
            local serverStop=action.serverStop
            action.openFlame=false action.carLighter=false action.useUtensil=false
            action.getRequiredItem=function() return fire end
            action.isValidStart=function() return active() end
            action.isValid=function()
                local started=Perf.active() and Perf.now() or nil
                local result=active() and item:getContainer()==c.npc:getInventory()
                    and fire:getContainer()==c.npc:getInventory()
                if started then Perf.measureSpan('EngineActions',started) end
                return result
            end
            action.start=function(self)
                if not active() or l.started then return end
                l.started=true l.applying=true save() start(self) l.applying=nil observe()
            end
            action.update=function(self)
                local started=Perf.active() and Perf.now() or nil
                if active() then update(self) end
                if started then Perf.measureSpan('EngineActions',started) end
            end
            action.serverStop=function(self) if not l.finished and c.sameAttempt() and c.body.retained() and serverStop then serverStop(self) end end
            action.complete=function(self)
                if not active() or item:getContainer()~=c.npc:getInventory() or fire:getContainer()~=c.npc:getInventory() then return false end
                l.applying=true save() local result=complete(self)
                l.finished=true l.applying=nil ended=true observe() return result
            end
            action.perform=function(self) if c.sameAttempt() and c.body.retained() then perform(self) end end
            action.stop=function(self)
                if ended or not c.sameAttempt() or not c.body.retained() then return end
                ended=true stop(self) l.stopped=true
                if l.applying then c.effects='UNKNOWN' end observe()
            end
            if not c.body.add(action) then return 'Failure' end
        end
        if ISTimedActionQueue.hasAction(action) then return 'Running' end
        return l.finished and c.effects~='UNKNOWN' and 'Success' or 'Failure'
    end
    function leaf.halt()
        if not c.sameAttempt() or not c.body.retained() then return false end
        return c.body.clear()
    end
    return leaf
end
return S
