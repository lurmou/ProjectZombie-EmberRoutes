-- FIELD adapter for the sole TaskRuntime. Business progression remains FIELD-local.
local Signals=require 'EmberRoutesProbe/LaborSignals'
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
            c.done=true
            local assets=false for _,a in ipairs(c.job.payload.assets) do if a.custody~='DELIVERED' then assets=true end end
            c.abandon=c.job.effects=='KNOWN' and not assets and not c.job.payload.holding
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
                    ok=c.change(function(j)
                        j.state=c.abandon and 'CANCELLED' or 'DONE'
                        j.payload.phase='SETTLED' j.payload.claims={} j.obligations={}
                    end)
                    if c.abandon then cooldowns[c.job.payload.offerKey]=getTimestampMs()+10000 end
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
