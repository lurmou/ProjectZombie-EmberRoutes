-- One personal attempt under TaskRuntime. The BT is transient; only original-ID
-- custody, observed effects and the predecessor relation survive save/reload.
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Store=require 'EmberRoutesProbe/LaborStore'
local Tree=require 'EmberRoutesProbe/BehaviorTree'
local Actions=require 'EmberRoutesProbe/SelfCareActions'
local Custody=require 'EmberRoutesProbe/SelfCareCustody'
local Execution={}
function Execution.new(actor,binding,job,candidate,budgets,settle,items,safe,reliefOnly,interruptCompanion)
    local world=Registry.data()
    local c={actor=actor,npc=binding.handle,job=job,payload=job.payload,effects=job.effects,
        obligations=job.obligations,items=items or {},origin=candidate and candidate.container,
        leisureTarget=candidate and candidate.leisureTarget,leisureKey=candidate and candidate.targetKey}
    if candidate and candidate.id then c.items[candidate.id]=candidate.item end
    function c.sample() return require('EmberRoutesProbe/NeedsObserver').sample(c.npc,job.npcId,getTimestampMs()) end
    function c.sameAttempt()
        if Registry.data()~=world then return false end
        -- peek is the live read view; detached get() stays the fallback for
        -- replaced TaskJobs modules that only expose the copy-on-read API.
        local api=Jobs.current()
        local live=api.peek and api:peek(job.id) or api:get(job.id)
        return live and live.npcId==job.npcId and live.payload.attemptId==c.payload.attemptId or false
    end
    function c.persist()
        if not c.sameAttempt() then return false end
        local api=Jobs.current()
        local live=api.peek and api:peek(job.id) or api:get(job.id)
        -- Explicit player commands may invalidate the predecessor between native
        -- callbacks. Never overwrite that fact from a captured payload.
        c.payload.resume=live.payload.resume
        return Jobs.current():update(job.id,live.revision,{payload=c.payload,effects=c.effects,obligations=c.obligations})
    end
    -- The safety closure crosses into native zombie proximity per call; engine
    -- isValid and per-tick validation would otherwise scan every frame. Safety
    -- evidence is advisory (the design already tolerates 1s-old observe samples).
    -- ONLY positive results are memoized: a cached false must never veto a fresh
    -- pass in c.valid()'s hard-failure path while spec.tick's fresh pre-check
    -- already passed — that mismatch once aborted a healthy execution with
    -- PERSONAL_AUTHORITY_LOST (and a multi-second Kahlua stack capture).
    local safeAt,safeValue
    local function safeRecent()
        if not safe then return true end
        local now=getTimestampMs()
        if safeValue and now-safeAt<200 then return true end
        local value=safe()
        if value then safeValue,safeAt=true,now end
        return value
    end
    function c.valid()
        return not c.stopping and c.sameAttempt() and c.body and c.body.current()
            and Store.validPersonal(job,c.token) and not c.npc:isDead() and safeRecent()
    end
    function c.canConsume(item,kind)
        return require('EmberRoutesProbe/SelfCareResources').eligible(item,kind)
    end
    function c.claimOutputs(ids)
        for _,id in ipairs(ids) do
            local key='item:'..id local found=false
            for _,value in ipairs(c.payload.claims) do if value==key then found=true break end end
            if not found then
                if #c.payload.claims>=16 then return false end
                c.payload.claims[#c.payload.claims+1]=key
            end
            local list=c.npc:getInventory():getItems()
            for i=0,list:size()-1 do local item=list:get(i) if item:getID()==id then c.items[id]=item break end end
        end
        return c.persist() and Store.extendPersonal(job,c.token)
    end
    local function finish(fact)
        if fact.effects~='KNOWN' then c.effects='UNKNOWN' end
        if c.payload.readingSite and fact.bodyStopped then
            if not require('EmberRoutesProbe/StudySeat').release(c) then return false end
        end
        if c.payload.study and (c.payload.study.leisure or not c.payload.study.orderId) then
            c.payload.leisureMemory=require('EmberRoutesProbe/LeisurePolicy').remember(c.payload.leisureMemory,
                'READING',getGameTime():getWorldAgeHours(),c.payload.reading and (c.payload.reading.completed or c.payload.reading.windowEnded))
            if c.payload.reading and (c.payload.reading.completed or c.payload.reading.windowEnded) then
                c.payload.leisureMemory=require('EmberRoutesProbe/LeisureService').pause(c.payload.leisureMemory)
            end
        end
        if c.payload.leisure then
            if c.payload.leisure.applying then c.effects='UNKNOWN' end
            require('EmberRoutesProbe/LeisureService').finished(c,fact.bodyStopped==true)
        end
        if c.effects=='UNKNOWN' then c.payload.step='RECONCILE_REQUIRED'
        else
            -- Reconcile a take interrupted before native movement. Its original
            -- never left the source, so there is no outstanding return.
            if c.payload.sourceId and not c.payload.consumption then
                local endpoint=Registry.resolve(c.payload.sourceId,'take','local-world')
                local item=c.items[c.payload.itemId]
                if endpoint and item and item:getContainer()==endpoint.container then c.obligations={} end
            end
            local owed=false for _ in pairs(c.obligations) do owed=true break end
            c.payload.step=owed and 'SETTLING' or 'IDLE'
            c.payload.lastKind=c.payload.kind
        end
        c.payload.reason=c.reason
        if not c.persist() then return false end
        if c.payload.step=='IDLE' then
            -- Preparation can own claims before a body is granted. A rejected
            -- pending candidate must settle those claims even when start never ran.
            c.token=c.token or Store.claimPersonal(Jobs.current():get(job.id))
            if not c.token then return false end
            if not Store.finishPersonal(job,c.token) then return false end
            c.payload.claims={} c.token=nil
        end
        local live=Jobs.current():get(job.id)
        if live.state=='RUNNING' then
            if not Jobs.current():update(live.id,live.revision,{state='STOPPING'}) then return false end
            live=Jobs.current():get(job.id)
        end
        local state=c.effects=='UNKNOWN' and 'RECONCILE_REQUIRED' or 'SUSPENDED'
        return live.state==state or Jobs.current():update(live.id,live.revision,{state=state})
    end
    local spec={npcId=job.npcId,jobId=job.id,kind='SELF_CARE',binding=binding,replaceReason='SELF_CARE',
        nonPreemptive=c.payload.kind=='LEISURE' or settle==true and interruptCompanion~=true,reconcileErrors=true}
    function spec.validate()
        if not c.sameAttempt() or c.effects~='KNOWN' or c.npc:isDead() or not safeRecent() then return false end
        if settle then return true end
        if c.payload.activityRef and not require('EmberRoutesProbe/ActivityService').validRef(job.npcId,c.payload.activityRef) then return false end
        if c.payload.kind=='STUDY' and not require('EmberRoutesProbe/StudyService').valid(actor,c.npc,job.npcId,c.payload) then return false end
        if c.payload.kind=='LEISURE' then return require('EmberRoutesProbe/LeisureService').valid(actor,c.npc,job.npcId,c.payload) end
        if c.payload.kind=='REST' or c.payload.kind=='SLEEP' then
            if c.payload.floorSite then return require('EmberRoutesProbe/FloorSleep').valid(c) end
            return not c.payload.site or require('EmberRoutesProbe/ReposeSites').resolve(c.payload.site,
                actor,binding.handle,job.npcId,c.payload.kind,job.id)~=nil
        end
        -- Admission is checked before claiming the item, then again after claim.
        return candidate and require('EmberRoutesProbe/SelfCareResources').revalidate(candidate,c.payload.kind,job.id)
            and (candidate.container==c.npc:getInventory() or c.npc:getInventory():hasRoomFor(c.npc,candidate.item)) or false
    end
    function spec.start(body)
        c.body=body c.payload=Jobs.current():get(job.id).payload
        if not settle and c.payload.step~='STOP_CONFIRMED' then return false,'STOP_NOT_CONFIRMED','UNCHANGED' end
        c.token=Store.claimPersonal(job)
        if not c.token then return false,'PERSONAL_CLAIM_CONFLICT','UNCHANGED' end
        local live=Jobs.current():get(job.id)
        if live.state=='SUSPENDED' then
            if not Jobs.current():update(live.id,live.revision,{state='PREPARING'}) then return false,'JOB_CHANGED','UNCHANGED' end
            live=Jobs.current():get(job.id)
        end
        if not Jobs.current():update(live.id,live.revision,{state='RUNNING'}) then return false,'JOB_CHANGED','UNCHANGED' end
        c.payload.step=settle and 'SETTLING' or 'ACTING'
        if c.payload.kind=='STUDY' then c.payload.reliefOnly=reliefOnly==true end
        if not c.persist() then return false,'PERSONAL_RECORD_CHANGED','UNCHANGED' end
        local leaves={}
        if not settle and c.payload.kind=='LEISURE' then
            leaves[#leaves+1]=require('EmberRoutesProbe/LeisureActions').new(c)
        elseif not settle and (c.payload.kind=='REST' or c.payload.kind=='SLEEP') then
            if c.payload.site then leaves[#leaves+1]=require('EmberRoutesProbe/SelfCareFurniture').move(c) end
            if c.payload.floorSite then leaves[#leaves+1]=require('EmberRoutesProbe/FloorSleep').move(c) end
            leaves[#leaves+1]=require('EmberRoutesProbe/SelfCareRepose').new(c)
        elseif not settle then
            leaves[#leaves+1]=Custody.take(c,candidate)
            if c.payload.kind=='STUDY' then
                leaves[#leaves+1]=require('EmberRoutesProbe/StudySeat').new(c,candidate.item)
            else leaves[#leaves+1]=Actions.consumption(c,c.payload.kind,candidate.item,c.payload.fraction or 0.25) end
        end
        if settle and c.payload.kind=='STUDY' then leaves[#leaves+1]=require('EmberRoutesProbe/StudyRelief').new(c) end
        if not reliefOnly then leaves[#leaves+1]=Custody.returns(c) end
        c.tree=assert(Tree.new({kind='Sequence',children=leaves}))
        if not settle and c.payload.leisure then
            require('EmberRoutesProbe/LeisureService').started(job.npcId,c.payload.leisure.activity,c.payload.leisure.brief,c.payload.leisure.zoneVisit)
        end
        return true
    end
    function spec.tick()
        c.budget=budgets()
        if not settle and c.payload.activityRef and not require('EmberRoutesProbe/ActivityService').validRef(job.npcId,c.payload.activityRef) then
            c.done=true c.reason='ACTIVITY_END' return
        end
        if safe and not safe() then c.done=true c.reason='SELF_CARE_UNSAFE' return end
        if not c.valid() then error('PERSONAL_AUTHORITY_LOST') end
        if not c.payload.transfer then Custody.prepareReturn(c) end
        local state=Tree.tick(c.tree,c,c.budget)
        c.done=state~='Running' or c.effects=='UNKNOWN'
    end
    function spec.finished() return c.done==true end
    function spec.persistFailure(fact,reason)
        c.reason=reason
        if not c.body then return finish(fact) end
        if not fact.bodyStopped then c.effects='UNKNOWN' end
        return finish(fact)
    end
    function spec.stopAdapter(controller,ticket)
        return require('EmberRoutesProbe/TaskBusinessStop').new({controller=controller,ticket=ticket,
            jobId=job.id,npcId=job.npcId,npc=c.npc,same=function() return c.sameAttempt() end,
            pause=function(reason)
                c.stopping=true c.reason=c.reason or reason
                if c.tree then Tree.halt(c.tree,c) end
                if c.body and not c.body.clear() then return false end
                Custody.observe(c)
                return true
            end,
            effects=function()
                local fact=c.payload.consumption local item=c.items[c.payload.itemId]
                local reading=c.payload.reading
                if reading and (reading.effects~='KNOWN' or not (reading.completed or reading.stopped)) then c.effects='UNKNOWN' end
                local relief=c.payload.relief
                if relief and (relief.fact and (relief.fact.effects~='KNOWN'
                    or relief.fact.started and not (relief.fact.completed or relief.fact.stopped))
                    or relief.repose and (relief.repose.effects~='KNOWN'
                    or relief.repose.started and not relief.repose.finished)) then c.effects='UNKNOWN' end
                if fact and (fact.effects~='KNOWN' or not (fact.completed or fact.stopped))
                    and (not item or Actions.observe(c,item,fact)~='KNOWN') then c.effects='UNKNOWN' end
                if c.npc.isAsleep and c.npc:isAsleep() or c.npc.isResting and c.npc:isResting() then
                    c.effects='UNKNOWN'
                end
                return c.effects
            end,persist=finish})
    end
    return spec,c
end
return Execution
