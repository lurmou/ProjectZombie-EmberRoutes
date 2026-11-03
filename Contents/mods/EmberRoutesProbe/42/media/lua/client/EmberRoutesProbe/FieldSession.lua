-- FIELD adapter for the sole TaskRuntime. Business progression remains FIELD-local.
local Signals=require 'EmberRoutesProbe/LaborSignals'
local Store=require 'EmberRoutesProbe/LaborStore'
local Workflow=require 'EmberRoutesProbe/FieldWorkflow'
local S={}
function S.spec(c,def,cooldowns)
    local job,binding=c.job,c.binding
    local spec={npcId=job.npcId,jobId=job.id,kind='FIELD_WORK',binding=binding,
        nonPreemptive=true,captureStop=true,reconcileErrors=true}
    function spec.validate() return c.job.effects=='KNOWN' and c.valid() end
    function spec.start(body)
        c.body=body
        if c.job.state=='SUSPENDED' and not c.change(function(j) j.state='PREPARING' end) then return false end
        if not c.change(function(j) j.state='RUNNING' j.payload.reason=nil end) then return false end
        return true
    end
    function spec.tick()
        if not c.valid() then c.reason='FIELD_CONTEXT_CHANGED' c.done=true return end
        if getTimestampMs()<c.nextTick then return end c.nextTick=getTimestampMs()+100
        local result=Workflow.step(c,def)
        if result=='Success' then
            c.completed=true c.done=true
            c.change(function(j) j.state='SETTLING' end)
        elseif result=='Failure' then
            -- A claimed target that repeatedly cannot be approached must not pin
            -- the worker: count consecutive approach failures per job, and after
            -- the third, deliver whatever is already carried instead of retrying.
            local approach=c.job.payload.phase=='WORK' and (c.reason=='FIELD_NO_APPROACH'
                or type(c.reason)=='string' and string.find(c.reason,'^FIELD_PATH_')~=nil)
            if approach then
                local fails=(c.job.payload.approachFails or 0)+1
                c.change(function(j) j.payload.approachFails=fails end)
                if fails>=3 and c.job.effects=='KNOWN' and not c.job.payload.holding then
                    local cargo
                    for _,a in ipairs(c.job.payload.assets) do
                        if a.custody=='GROUND' then cargo='COLLECT' break end
                        if a.custody=='HELD' then cargo=cargo or 'DELIVER' end
                    end
                    if cargo and c.change(function(j) j.payload.phase=cargo j.payload.approachFails=0 end) then
                        c.node=nil c.path=nil c.reason=nil return
                    end
                end
            end
            c.done=true
            local assets=false for _,a in ipairs(c.job.payload.assets) do if a.custody~='DELIVERED' then assets=true end end
            c.abandon=c.job.effects=='KNOWN' and not assets and not c.job.payload.holding
        else
            if (c.job.payload.approachFails or 0)>0 then c.change(function(j) j.payload.approachFails=0 end) end
        end
    end
    function spec.finished() return c.done==true end
    function spec.stopAdapter(controller,ticket)
        return require('EmberRoutesProbe/TaskBusinessStop').new({controller=controller,ticket=ticket,
            npc=c.npc,npcId=job.npcId,jobId=job.id,same=c.same,
            pause=function(reason)
                c.stopping=true c.reason=c.reason or reason
                if reason=='MEMBERSHIP_COMMAND' or reason=='REPLACED' then
                    local retained=c.job.payload.holding==true
                    for _,asset in ipairs(c.job.payload.assets) do if asset.custody~='DELIVERED' then retained=true end end
                    c.abandon=not retained and c.job.effects=='KNOWN'
                end
                if c.job.state=='RUNNING' and not c.change(function(j) j.state='STOPPING' end) then return false end
                if not c.body.clear() then return false end
                if c.npc:isDraggingCorpse() then
                    if not c.job.payload.holding then c.unknown('FIELD_CORPSE_RELEASE_UNCONFIRMED') end
                    if not c.body.releaseCorpse() then return false end
                end
                return true
            end,
            effects=function()
                local native=c.body.snapshot()
                local q=ISTimedActionQueue.queues[c.npc]
                if native.available and native.nativeStopped and (not q or #q.queue==0 and q.current==nil)
                    then
                    if c.job.payload.holding and not require('EmberRoutesProbe/FieldOperations').settleCorpse(c) then return 'UNKNOWN' end
                    if c.node and not c.node.settle() then return 'UNKNOWN' end
                end
                return c.job.effects
            end,
            persist=function(fact)
                if not fact.bodyStopped then return false end
                if c.node and not c.node.settle() then return false end
                local ok=c.change(function(j)
                    j.payload.reason=string.sub(tostring(c.reason or 'FIELD_STOPPED'),1,256)
                    if (c.completed or c.abandon) and j.effects=='KNOWN' then
                        if j.state~='SETTLING' then j.state='SETTLING' end
                    else j.state=j.effects=='KNOWN' and 'SUSPENDED' or 'RECONCILE_REQUIRED' end
                end)
                if ok and (c.completed or c.abandon) and c.job.effects=='KNOWN' then
                    -- FieldRecord's terminal gate requires toolSupply to be gone,
                    -- and FieldSupplies (its only clearing path) no longer runs
                    -- once the session is stopping: roll the warehouse tool
                    -- reservations back here, or a PREPARE-phase job can never
                    -- reach a terminal state and wedges in the resubmit loop.
                    local supply=c.job.payload.toolSupply
                    if supply and not require('EmberRoutesProbe/FieldSupplies').releaseUncollected(c,supply) then
                        if not c.unknown('FIELD_TOOL_RETURN_UNCONFIRMED') then return false end
                        return c.change(function(j) j.state='RECONCILE_REQUIRED' end)
                    end
                    ok=c.change(function(j)
                        j.state=c.abandon and 'CANCELLED' or 'DONE'
                        j.payload.phase='SETTLED' j.payload.claims={} j.obligations={}
                        j.payload.toolSupply=nil
                    end)
                    if c.abandon then cooldowns[c.job.payload.offerKey]=getTimestampMs()
                        +((c.job.payload.approachFails or 0)>=3 and 600000 or 10000) end
                end
                if ok then Signals.changed(job.npcId) end
                return ok
            end})
    end
    function spec.persistFailure(fact,why)
        if not c.same() then return false end
        return c.change(function(j)
            j.state=fact.effects=='KNOWN' and 'SUSPENDED' or 'RECONCILE_REQUIRED'
            j.effects=fact.effects j.payload.reason=string.sub(tostring(why or 'FIELD_START_FAILED'),1,256)
        end)
    end
    return spec
end
return S
