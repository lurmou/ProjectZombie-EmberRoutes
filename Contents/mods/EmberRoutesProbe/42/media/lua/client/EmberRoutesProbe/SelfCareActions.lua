-- Native consumption leaves only. The owning routine supplies persistence and
-- original-ID custody; this module neither chooses work nor releases claims.
pcall(require, 'TimedActions/ISEatFoodAction')
pcall(require, 'TimedActions/ISDrinkFluidAction')
local Actions={}
local function needs(npc)
    if not npc.getStats or not CharacterStat then return nil end
    local stats=npc:getStats()
    return {hunger=stats:get(CharacterStat.HUNGER),thirst=stats:get(CharacterStat.THIRST)}
end
local function amount(item,kind)
    if kind=='EAT' then return math.max(0,-item:getHungChange()) end
    local fluid=item:getFluidContainer()
    return fluid and fluid:getAmount() or nil
end
local function inventory(npc)
    local items=npc:getInventory():getItems()
    if items:size()>512 then return nil end
    local seen={}
    for i=0,items:size()-1 do
        local id=items:get(i):getID()
        if seen[id] then return nil end seen[id]=true
    end
    return seen
end
function Actions.observe(c,item,fact)
    if type(fact)~='table' or (fact.kind~='EAT' and fact.kind~='DRINK')
        or type(fact.before)~='number' or fact.before~=fact.before or fact.before<=0 or fact.before==math.huge
        or fact.attemptId~=c.payload.attemptId then return 'UNKNOWN' end
    if not c.sameAttempt() or item:getID()~=fact.itemId or item:getFullType()~=fact.fullType then return 'UNKNOWN' end
    local after=amount(item,fact.kind)
    if not after or after~=after or after<0 or after>fact.before+0.0001 then return 'UNKNOWN' end
    fact.after=after fact.consumed=fact.before-after
    -- Disappearance without attributable native depletion is not consumption.
    if item:getContainer()~=c.npc:getInventory() and after>0.0001 then return 'UNKNOWN' end
    if fact.completed and fact.consumed<=0.0001 then return 'UNKNOWN' end
    if not fact.started and fact.consumed>0.0001 then return 'UNKNOWN' end
    return 'KNOWN'
end
-- Perf measures the engine-driven per-frame isValid/update callbacks; they
-- run outside every service bucket.
local Perf=require 'EmberRoutesProbe/RuntimeMetrics'
function Actions.consumption(c,kind,item,fraction)
    assert((kind=='EAT' or kind=='DRINK') and type(c.sameAttempt)=='function'
        and type(c.persist)=='function' and type(fraction)=='number' and fraction>0 and fraction<=1,'CONSUMPTION_SPEC_REQUIRED')
    local action,performed,stopped,completed,lastAmount
    local fact=c.payload.consumption
    local function retained() return c.sameAttempt() and c.body.retained() end
    local function active() return c.effects~='UNKNOWN' and c.sameAttempt() and c.body.current() and c.valid() end
    local function consumable()
        return item:getContainer()==c.npc:getInventory() and (not c.canConsume or c.canConsume(item,kind))
    end
    local function save()
        c.payload.consumption=fact
        if not c.persist() then error('PERSONAL_EFFECT_NOT_PERSISTED') end
    end
    local function unchanged()
        local current=amount(item,kind)
        if not current or not lastAmount or math.abs(current-lastAmount)>0.0001 then
            c.effects='UNKNOWN'
            if fact then fact.effects='UNKNOWN' save() end
            return false
        end
        return true
    end
    local function reconcile(beforeItems)
        local items=c.npc:getInventory():getItems() local added={}
        if not beforeItems or items:size()>512 then c.effects='UNKNOWN'
        else
            for i=0,items:size()-1 do
                local result=items:get(i)
                if not beforeItems[result:getID()] then added[#added+1]=result:getID() end
            end
            if #added>0 then
                fact.outputs=fact.outputs or {}
                for _,id in ipairs(added) do fact.outputs[#fact.outputs+1]=id end
                if not c.claimOutputs or c.claimOutputs(added)~=true then c.effects='UNKNOWN' end
            end
        end
        if Actions.observe(c,item,fact)~='KNOWN' then c.effects='UNKNOWN' end
        fact.needsAfter=needs(c.npc)
        fact.effects=c.effects or 'KNOWN' save()
    end
    local leaf={kind='Action'}
    function leaf.run()
        if c.effects=='UNKNOWN' or fact and fact.effects=='UNKNOWN' then c.effects='UNKNOWN' return 'Failure' end
        if fact and (fact.attemptId~=c.payload.attemptId or fact.kind~=kind
            or type(fact.before)~='number' or fact.before~=fact.before or fact.before<=0 or fact.before==math.huge) then
            c.effects='UNKNOWN' fact.effects='UNKNOWN' save() return 'Failure'
        end
        if fact and fact.effects=='KNOWN' and (fact.completed or fact.stopped) then return 'Success' end
        if not action then
            -- Restored started consumption is reconciled by the owning service;
            -- never rebuild a fresh native action from its old requested fraction.
            if fact and fact.started then c.effects='UNKNOWN' return 'Failure' end
            if not active() or item:getContainer()~=c.npc:getInventory() or not inventory(c.npc) then return 'Failure' end
            fact={attemptId=c.payload.attemptId,kind=kind,itemId=item:getID(),fullType=item:getFullType(),
                before=amount(item,kind),fraction=fraction,effects='KNOWN',started=false,needsBefore=needs(c.npc)}
            if not fact.before or fact.before<=0 then return 'Failure' end
            lastAmount=fact.before
            save()
            if (kind=='EAT' and type(ISEatFoodAction)~='table') or (kind=='DRINK' and type(ISDrinkFluidAction)~='table') then
                c.effects='UNKNOWN' return 'Failure'
            end
            action=kind=='EAT' and ISEatFoodAction:new(c.npc,item,fraction) or ISDrinkFluidAction:new(c.npc,item,fraction)
            local nativeStart,nativeUpdate,nativeValid=action.start,action.update,action.isValid
            local nativeStop,nativePerform,nativeComplete=action.stop,action.perform,action.complete
            local nativeServerStop=action.serverStop
            if kind=='EAT' and nativeServerStop then
                action.serverStop=function(self)
                    -- Vanilla single-player stop applies partial Eat here. A
                    -- foreign change is cleanup-only, never another consumption.
                    if c.effects~='UNKNOWN' and consumable() then return nativeServerStop(self) end
                end
            end
            action.useProgressBar,action.forceProgressBar=false,false
            action.isValid=function(self)
                local started=Perf.active() and Perf.now() or nil
                local result=active() and consumable() and nativeValid(self)
                if started then Perf.measureSpan('EngineActions',started) end
                return result
            end
            action.start=function(self)
                if not active() or fact.started then return end
                fact.started=true save() nativeStart(self)
            end
            action.update=function(self)
                local started=Perf.active() and Perf.now() or nil
                if active() and unchanged() then nativeUpdate(self) lastAmount=amount(item,kind) end
                if started then Perf.measureSpan('EngineActions',started) end
            end
            action.complete=function(self)
                if completed or stopped or not active() then return false end
                if not consumable() then self:stop() return false end
                if not unchanged() then return false end
                local before=inventory(c.npc)
                if not before then c.effects='UNKNOWN' save() return false end
                -- Fence synchronous duplicate callbacks before calling vanilla.
                completed=true
                local result=nativeComplete(self)
                lastAmount=amount(item,kind)
                fact.completed=true reconcile(before) return result
            end
            action.perform=function(self)
                if performed or stopped or not active() then return end
                performed=true nativePerform(self)
            end
            action.stop=function(self)
                if stopped or completed or not retained() then return end
                unchanged()
                stopped=true local before=inventory(c.npc)
                nativeStop(self) lastAmount=amount(item,kind) fact.stopped=true reconcile(before)
            end
            if not c.body.add(action) then return 'Failure' end
            return 'Running'
        end
        if ISTimedActionQueue.hasAction(action) then return 'Running' end
        if not fact.completed and not fact.stopped then
            c.effects='UNKNOWN' fact.effects='UNKNOWN' save() return 'Failure'
        end
        if Actions.observe(c,item,fact)~='KNOWN' then c.effects='UNKNOWN' save() return 'Failure' end
        return 'Success'
    end
    function leaf.halt()
        if not retained() or not c.body.clear() then return false end
        if fact then
            if Actions.observe(c,item,fact)~='KNOWN' then c.effects='UNKNOWN' end
            fact.effects=c.effects or 'KNOWN' save()
        end
        return c.effects~='UNKNOWN'
    end
    return leaf
end
return Actions
