-- Composed field providers. TaskRuntime owns bodies; JobStore/LaborStore own facts/claims.
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Store=require 'EmberRoutesProbe/LaborStore'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Driver=require 'EmberRoutesProbe/Driver'
local Probe=require 'EmberRoutesProbe/Boot'
local Signals=require 'EmberRoutesProbe/LaborSignals'
local Context=require 'EmberRoutesProbe/FieldContext'
local Session=require 'EmberRoutesProbe/FieldSession'
local F={}
local definitions,live={},{}
local world,nextAdvance
local cooldowns={}
local retries={}
local function reset()
    local root=Registry.data()
    if world~=root then world,live,nextAdvance,cooldowns,retries=root,{},0,{},{} end
    return root
end
local function pending(j)
    return j.providerType=='FIELD_WORK' and j.state~='DONE' and j.state~='CANCELLED'
end
function F.retained(id)
    local retained=false
    Jobs.current():visitNpc(id,function(j) if pending(j) then retained=true end end)
    return retained
end
local function submit(actor,job,careId)
    local runtime=Runtime.current()
    if not runtime or not runtime:accepting() or runtime:owns(job.npcId) then return false end
    if not careId and Probe.careBlocksWork and Probe.careBlocksWork(job.npcId) then return false end
    local binding=Driver.bindId(actor,job.npcId)
    if not binding or not Driver.valid(binding) or binding.handle:isDead() then return false end
    local def=definitions[job.payload.category] if not def then return false end
    local root=reset()
    local c=Context.new(actor,job,binding,def,root)
    if not c then return false end
    local spec=Session.spec(c,def,cooldowns)
    local handle=runtime:submit(spec)
    if not handle then return false end
    live[job.id]={c=c,handle=handle,runtime=runtime,root=root}
    return true
end
function F.wake(actor,id,jobId,careId)
    local j=Jobs.current():get(jobId)
    return j and j.npcId==id and pending(j) and j.effects=='KNOWN' and submit(actor,j,careId) or false
end
function F.prepareRecovery()
    reset()
    local root=Registry.data()
    for id,j in pairs(root.taskJobs and root.taskJobs.byId or {}) do
        if pending(j) and (j.state=='RUNNING' or j.state=='STOPPING' or j.state=='PREPARING') then
            local a=j.payload.attempt
            local unknown=j.effects~='KNOWN' or a and a.state=='PREPARED' and a.dispatched
            local p=Jobs.current():get(id).payload p.reason='LOAD_RECOVERY'
            if unknown and p.attempt then p.attempt.state='UNKNOWN' end
            assert(Jobs.current():update(id,j.revision,{state=unknown and 'RECONCILE_REQUIRED' or 'SUSPENDED',
                effects=unknown and 'UNKNOWN' or 'KNOWN',payload=p}))
        end
    end
    return true
end
function F.advance(env)
    reset()
    if env.now<nextAdvance then return end nextAdvance=env.now+500
    local runtime=Runtime.current() if not runtime or not runtime:accepting() then return end
    local root=Registry.data() local budget=4
    for id,j in pairs(root.taskJobs and root.taskJobs.byId or {}) do
        if j.providerType=='FIELD_WORK' then
            local l=live[id]
            if l and not runtime:status(j.npcId,id) then
                local result=l.runtime:inspect(l.handle)
                if result and (result.state=='REJECTED' or result.state=='CANCELLED') and j.effects=='KNOWN'
                    and #j.payload.assets==0 and not j.payload.holding then
                    local p=Jobs.current():get(id).payload p.claims={} p.reason=result.reason p.phase='SETTLED'
                    if j.state=='PREPARING' or j.state=='SUSPENDED' then
                        local token=Store.claimField(j)
                        local proposed=Jobs.current():get(id) proposed.state='SETTLING' proposed.payload=p proposed.obligations={}
                        if token then
                            local changed,saved=Store.replaceField(j,token,proposed)
                            if changed then Jobs.current():update(id,saved.revision,{state='CANCELLED'}) j=Jobs.current():peek(id) end
                        end
                    end
                end
                live[id]=nil l=nil
            end
            if not l and not runtime:status(j.npcId,id) then
                if j.state=='DONE' or j.state=='CANCELLED' then
                    if env.directory then env.directory:release(j.payload.offerKey,id,{effects='KNOWN',obligationsCleared=true}) end
                    if Store.finishField(j) and not Store.hasTaskClaims(id) then Jobs.current():removeSettled(id,j.revision) Signals.changed(j.npcId) end
                elseif j.effects=='KNOWN' and (j.state=='SUSPENDED' or j.state=='PREPARING') and budget>0 then
                    local retry=retries[id] or 0
                    if env.now>=retry then
                        retries[id]=env.now+5000
                        submit(env.actor,Jobs.current():get(id))
                        budget=budget-1
                    end
                end
            end
        end
    end
end
function F.provider(def)
    definitions[def.category]=def
    local p={category=def.category,defaultPriority=def.defaultPriority or 3}
    function p.discover(env)
        if F.retained(env.npcId) then return end
        return def.discover(env)
    end
    function p.claim(selected,npcId,jobId,env)
        reset()
        if F.retained(npcId) then return 'FIELD_JOB_RETAINED' end
        local runtime=Runtime.current()
        if not runtime or not runtime:accepting() or runtime:owns(npcId) then return 'NPC_BUSY' end
        local binding=Driver.bindId(env.actor,npcId) if not binding or not Driver.valid(binding) then return 'BINDING_INVALID' end
        local target,keys,why=def.claim(selected,binding.handle,env.entry)
        if not target then return why or 'FIELD_TARGET_CHANGED' end
        local function rollbackCustodies()
            if target.createdCustodies then
                for _,cid in ipairs(target.createdCustodies) do Store.releaseCustody(cid) end
            elseif target.toolSupply and target.toolSupply.requirements then
                for _,req in ipairs(target.toolSupply.requirements) do Store.releaseCustody(req.custodyId) end
            end
        end
        for _,key in ipairs(keys) do
            if Store.resourceOwner(key) then
                rollbackCustodies()
                return 'FIELD_RESOURCE_RESERVED'
            end
        end
        local j={id=jobId,npcId=npcId,providerType='FIELD_WORK',scopeId=env.entry.id,
            revision=1,state='PREPARING',effects='KNOWN',obligations={work=true},
            payload={format=1,category=def.category,offerKey=selected.key,target=target,
                phase=target.toolSupply and 'PREPARE' or 'WORK',sequence=0,claims=keys,assets={},
                toolSupply=target.toolSupply}}
        local ok,err=Jobs.current():create(j)
        if not ok then
            rollbackCustodies()
            return err
        end
        if target.tools then
            for _,itemId in ipairs(target.tools) do
                local c=Store.custodyByItem(itemId)
                if c then Store.assignToolUse(c.id,jobId) end
            end
        elseif target.toolSupply and target.toolSupply.requirements then
            for _,req in ipairs(target.toolSupply.requirements) do Store.assignToolUse(req.custodyId,jobId) end
        end
        local token=Store.claimField(Jobs.current():get(jobId))
        if not token then
            rollbackCustodies()
            local saved=Jobs.current():get(jobId)
            saved.payload.claims={} saved.payload.phase='SETTLED' saved.payload.toolSupply=nil
            assert(Jobs.current():update(jobId,saved.revision,{state='SETTLING',payload=saved.payload,obligations={}}))
            saved=Jobs.current():get(jobId)
            assert(Jobs.current():update(jobId,saved.revision,{state='CANCELLED'}))
            return 'FIELD_RESOURCE_RESERVED'
        end
        local accepted=submit(env.actor,Jobs.current():get(jobId))
        if accepted then return 'QUEUED' end
        -- No body or native effect occurred; retain a versioned retry intent.
        return 'STARTED'
    end
    p.advance=F.advance
    p.continue=def.continue
    function p.hasWork()
        local root=Registry.data()
        for _,j in pairs(root and root.taskJobs and root.taskJobs.byId or {}) do
            if j.providerType=='FIELD_WORK' then return true end
        end
        return false
    end
    function p.retained(id) return F.retained(id) end
    function p.reconcile() return true end
    return p
end
function F.offer(env,category,target,score)
    local key='field:'..category..':'..env.entry.id..':'..target.kind..':'..target.x..':'..target.y..':'..target.z
        ..':'..tostring(target.identity or target.itemId or '')
    if env.now<(cooldowns[key] or 0) or env.candidateReady and not env.candidateReady(key) then return false end
    local rev=env.entry.revision
    local offer=env.directory:upsert(key,rev,category,env.entry.id)
    if offer and not offer.jobId then
        env.candidates[#env.candidates+1]={key=key,revision=rev,category=category,
            allowed=true,score=score or 0.8,point=target,settlementId=env.entry.id}
        return true
    end
    return false
end
return F
