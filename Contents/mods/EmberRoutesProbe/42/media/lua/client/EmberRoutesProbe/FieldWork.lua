-- Composed field providers. TaskRuntime owns bodies; JobStore/LaborStore own facts/claims.
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Store=require 'EmberRoutesProbe/LaborStore'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Driver=require 'EmberRoutesProbe/Driver'
local Members=require 'EmberRoutesProbe/MembershipService'
local Record=require 'EmberRoutesProbe/FieldRecord'
local Probe=require 'EmberRoutesProbe/Boot'
local Signals=require 'EmberRoutesProbe/LaborSignals'
local Log=require 'EmberRoutesProbe/Log'
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
    local c={actor=actor,npc=binding.handle,job=job,reason=nil,nextTick=0}
    c.token=Store.claimField(job) if not c.token then return false end
    function c.same() return Registry.data()==root and Store.validField(c.job,c.token) end
    function c.change(edit)
        if not c.same() then return false end
        local j=Jobs.current():get(c.job.id) edit(j)
        local ok,value=Store.replaceField(c.job,c.token,j)
        if not ok then c.reason=value return false end
        c.job=value return true
    end
    function c.unknown(why)
        c.reason=tostring(why or 'FIELD_EFFECT_UNKNOWN')
        return c.change(function(j)
            j.effects='UNKNOWN' j.payload.reason=string.sub(c.reason,1,256)
            if j.payload.attempt then j.payload.attempt.state='UNKNOWN' end
        end)
    end
    local function recoveryRequested()
        local member=Members.view(job.npcId)
        local command=member and member.pending
        return member and not member.retired and member.settlementId==job.scopeId
            and (member.context=='RETURN' or command and (command.kind=='UNASSIGN'
                or (command.kind=='TRANSFER' or command.kind=='SETTLE') and command.settlementId~=job.scopeId)) or false
    end
    -- Accepted membership changes wait on old custody. Only already observed
    -- originals may finish delivery under RECOVERY; never resume field labour.
    if recoveryRequested() and c.job.effects=='KNOWN' then
        local cargo=false
        for _,asset in ipairs(c.job.payload.assets) do if asset.custody~='DELIVERED' then cargo=true break end end
        if cargo and not c.job.payload.holding then
            c.recoveryOnly=true
            if not c.change(function(j) j.payload.phase=def.collect and 'COLLECT' or 'DELIVER' end) then return false end
        end
    end
    function c.valid()
        if not c.same() or c.stopping or c.npc:isDead() or actor:isDead() then return false end
        local recovery=c.job.payload.phase~='WORK'
        if not recovery and require('EmberRoutesProbe/ActivityAttendance').blocksOrdinary(job.npcId) then return false end
        local entry,_,memberRevision=Members.entry(job.npcId,job.scopeId)
        if not entry then return false end
        c.entry=entry -- trusted internal read-only view; never modify it
        local ledger=require('EmberRoutesProbe/SettlementLedger').data()
        local policyRevision=ledger.jobPolicies and ledger.jobPolicies.revision or 0
        local zoneRevision=require('EmberRoutesProbe/SettlementZones').revision()
        local cached=c.validity local now=getTimestampMs()
        if cached and cached.target==c.job.payload.target and cached.recovery==recovery
            and cached.member==memberRevision and cached.entry==entry.revision
            and cached.policy==policyRevision and cached.zones==zoneRevision and now<cached.untilAt then return cached.allowed end
        local purpose=c.recoveryOnly and recovery and recoveryRequested() and 'RECOVERY' or 'FIELD_WORK'
        local m=Members.check(job.npcId,purpose,
            {x=c.npc:getX(),y=c.npc:getY(),z=c.npc:getZ(),scopeId=job.scopeId})
        local allowed=m.allowed==true and (recovery or not def.valid or def.valid(c))
        c.validity={target=c.job.payload.target,recovery=recovery,member=memberRevision,entry=entry.revision,
            policy=policyRevision,zones=zoneRevision,untilAt=now+500,allowed=allowed}
        return allowed
    end
    function c.move(square,arrived)
        if arrived then c.path=nil return 'Success' end
        if not square then c.reason='FIELD_NO_APPROACH' return 'Failure' end
        local key=square:getX()..':'..square:getY()..':'..square:getZ()
        if not c.path or c.path.key~=key then
            local ok,result=c.body.move(actor,{x=square:getX()+0.5,y=square:getY()+0.5,z=square:getZ()})
            if not ok or type(result)~='string' or not string.find(result,'^MOVE_REQUESTED') then
                c.reason=tostring(result) return 'Failure'
            end
            c.path={key=key,at=getTimestampMs()} return 'Running'
        end
        local result=EmberRoutesProbeJava.motionResult(c.npc)
        if result=='MOVING' and getTimestampMs()-c.path.at<185000 then return 'Running' end
        c.reason='FIELD_PATH_'..tostring(result) return 'Failure'
    end
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
        local result
        if c.job.payload.phase=='PREPARE' then result=require('EmberRoutesProbe/FieldSupplies').step(c)
        elseif c.job.payload.phase=='WORK' then result=def.step(c)
        else result=require('EmberRoutesProbe/FieldCargo').step(c,def) end
        if result=='Success' and c.job.payload.phase=='WORK' then
            c.change(function(j) j.payload.phase=def.collect and 'COLLECT' or 'DELIVER' end)
            c.node=nil c.path=nil
        elseif result=='Success' then
            if not c.recoveryOnly and def.continue and def.continue(c) then c.node=nil c.path=nil return end
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
        for _,key in ipairs(keys) do if Store.resourceOwner(key) then return 'FIELD_RESOURCE_RESERVED' end end
        local j={id=jobId,npcId=npcId,providerType='FIELD_WORK',scopeId=env.entry.id,
            revision=1,state='PREPARING',effects='KNOWN',obligations={work=true},
            payload={format=1,category=def.category,offerKey=selected.key,target=target,
                phase=target.toolSupply and 'PREPARE' or 'WORK',sequence=0,claims=keys,assets={},
                toolSupply=target.toolSupply}}
        local ok,err=Jobs.current():create(j)
        if not ok then
            if target.toolSupply and target.toolSupply.requirements then
                for _,req in ipairs(target.toolSupply.requirements) do Store.releaseCustody(req.custodyId) end
            end
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
            if target.toolSupply and target.toolSupply.requirements then
                for _,req in ipairs(target.toolSupply.requirements) do Store.releaseCustody(req.custodyId) end
            end
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
