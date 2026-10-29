-- Native reading effects only. Never grants recipes, edits pages or replaces
-- books. The owner supplies the same original-instance custody as other care.
require 'TimedActions/ISReadABook'
-- Perf measures the engine-driven per-frame isValid/update callbacks; they
-- run outside every service bucket.
local Perf=require 'EmberRoutesProbe/RuntimeMetrics'
local Actions={}
function Actions.observe(c,item,fact)
    if not fact or fact.attemptId~=c.payload.attemptId or fact.itemId~=c.payload.itemId
        or fact.completing or not item or item:getID()~=fact.itemId
        or item:getFullType()~=fact.fullType or item:getContainer()~=c.npc:getInventory() then return 'UNKNOWN' end
    local pages=c.npc:getAlreadyReadPages(fact.fullType)
    if type(pages)~='number' or pages<fact.before or fact.total>0 and pages>fact.total then return 'UNKNOWN' end
    fact.pages=fact.total>0 and pages or nil
    if fact.completed then
        if fact.total>0 and item:getAlreadyReadPages()<fact.total then return 'UNKNOWN' end
        if c.payload.study.knowledge and not c.npc:getKnownRecipes():contains(c.payload.study.knowledge) then return 'UNKNOWN' end
    end
    return 'KNOWN'
end
function Actions.read(c,item)
    local action,performed,completed,stopped,nextSample,readingUntil
    local fact=c.payload.reading
    local leaf={kind='Action'}
    local function save()
        c.payload.reading=fact
        if not c.persist() then error('STUDY_EFFECT_NOT_PERSISTED') end
    end
    local function active()
        return c.effects~='UNKNOWN' and c.valid() and c.sameAttempt() and c.body.current() and c.body.retained()
            and item:getContainer()==c.npc:getInventory()
    end
    local function record()
        if Actions.observe(c,item,fact)~='KNOWN' then c.effects='UNKNOWN' end
        fact.effects=c.effects or 'KNOWN' save()
    end
    function leaf.run()
        if c.payload.study.leisure then
            local activity=require 'EmberRoutesProbe/ActivityService'
            local policy=activity.policyAt(c.payload.settlementId,c.job.npcId,
                c.npc:getX(),c.npc:getY(),math.floor(c.npc:getZ()),'READING')
            if not policy or policy==0 or not activity.allowsPoint(c.payload.settlementId,c.job.npcId,
                {x=c.npc:getX(),y=c.npc:getY(),z=math.floor(c.npc:getZ())}) then
                c.reason='READ_ZONE_DISABLED' return 'Failure'
            end
        end
        if c.effects=='UNKNOWN' or fact and fact.effects=='UNKNOWN' then c.effects='UNKNOWN' return 'Failure' end
        if fact and (fact.attemptId~=c.payload.attemptId or fact.itemId~=item:getID()) then c.effects='UNKNOWN' return 'Failure' end
        if not action then
            if fact and fact.started then
                if fact.completed or fact.stopped then return 'Success' end
                c.effects='UNKNOWN' return 'Failure'
            end
            if not active() then return 'Failure' end
            local Library=require 'EmberRoutesProbe/LibraryIndex'
            if not Library.useful(c.npc,item,c.payload.study.knowledge,c.payload.study.leisure) then c.reason='STUDY_NOT_USEFUL' return 'Failure' end
            if c.npc:tooDarkToRead() then c.reason='STUDY_TOO_DARK' return 'Failure' end
            fact={attemptId=c.payload.attemptId,itemId=item:getID(),fullType=item:getFullType(),
                before=math.max(0,c.npc:getAlreadyReadPages(item:getFullType())),total=math.max(0,item:getNumberOfPages()),
                started=false,effects='KNOWN'}
            save()
            action=ISReadABook:new(c.npc,item)
            if c.payload.study.leisure then
                -- The NPC owns native reading effects, never the player's media/map UI.
                action.displayPrintMedia=function() end
                action.revealPrintMediaLocationsOnMap=function() end
            end
            local nativeStart,nativeUpdate,nativeValid=action.start,action.update,action.isValid
            local nativeStop,nativePerform,nativeComplete=action.stop,action.perform,action.complete
            action.useProgressBar,action.forceProgressBar=false,false
            action.isValid=function(self)
                local started=Perf.active() and Perf.now() or nil
                local result=active() and nativeValid(self)
                if started then Perf.measureSpan('EngineActions',started) end
                return result
            end
            action.start=function(self)
                if not active() or fact.started then return end
                fact.started=true save() nativeStart(self)
                if c.payload.study.leisure or not c.payload.study.orderId then
                    readingUntil=getGameTime():getWorldAgeHours()+require('EmberRoutesProbe/LeisureConfig').readingMinutes/60
                end
            end
            action.update=function(self)
                local started=Perf.active() and Perf.now() or nil
                if active() then
                    nativeUpdate(self)
                    if readingUntil and not completed and not stopped and getGameTime():getWorldAgeHours()>=readingUntil then
                        fact.windowEnded=true c.reason='LEISURE_READING_WINDOW_END' self:forceStop()
                        if started then Perf.measureSpan('EngineActions',started) end
                        return
                    end
                    local now=getTimestampMs()
                    if fact.total>0 and now>=(nextSample or 0) then
                        nextSample=now+1000
                        if fact.pages~=c.npc:getAlreadyReadPages(fact.fullType) then record() end
                    end
                end
                if started then Perf.measureSpan('EngineActions',started) end
            end
            action.complete=function(self)
                if completed or stopped or not active() then return false end
                -- Persist intent before vanilla: an exception here is UNKNOWN,
                -- never permission to replay the learning effect after loading.
                completed=true fact.completing=true save()
                local result=nativeComplete(self)
                fact.completing=nil fact.completed=true record()
                if c.effects~='UNKNOWN' then
                    require('EmberRoutesProbe/StudyService').completed(c.job.npcId,c.payload.settlementId)
                end
                return result
            end
            action.perform=function(self)
                if performed or stopped or not active() then return end
                performed=true nativePerform(self)
            end
            action.stop=function(self)
                if stopped or completed or not c.sameAttempt() or not c.body.retained() then return end
                stopped=true nativeStop(self) fact.stopped=true record()
                local Probe=require 'EmberRoutesProbe/Boot'
                if Probe.invalidatePersonnel then Probe.invalidatePersonnel(c.job.npcId) end
            end
            if not c.body.add(action) then return 'Failure' end
            return 'Running'
        end
        if ISTimedActionQueue.hasAction(action) then return 'Running' end
        if not fact.completed and not fact.stopped then c.effects='UNKNOWN' save() return 'Failure' end
        if Actions.observe(c,item,fact)~='KNOWN' then c.effects='UNKNOWN' save() return 'Failure' end
        return 'Success'
    end
    function leaf.halt()
        if not c.sameAttempt() or not c.body.retained() or not c.body.clear() then return false end
        if fact then record() end
        return c.effects~='UNKNOWN'
    end
    return leaf
end
return Actions
