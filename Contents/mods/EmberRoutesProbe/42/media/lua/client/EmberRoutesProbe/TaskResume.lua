-- Durable cross-session relation. Never owns a body or reclaims public work.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Resume={}
local kinds={PRODUCTION='CRAFT',TRANSFER='HAUL',COMPANION='COMPANION',COOKING='COOKING',FIELD_WORK='FIELD_WORK'}
local function epochs()
    local root=Registry.data()
    if root.careCommandEpochs==nil then root.careCommandEpochs={format=1,byNpc={}} end
    local data=root.careCommandEpochs
    if type(data)~='table' or data.format~=1 or type(data.byNpc)~='table' then error('COMMAND_EPOCH_INVALID') end
    return data.byNpc
end
function Resume.epoch(id)
    local value=epochs()[id] or 0
    if type(value)~='number' or value<0 or value>=9007199254740991 or value~=math.floor(value) then error('COMMAND_EPOCH_INVALID') end
    return value
end
local function personal(id)
    for _,job in ipairs(Jobs.current():forNpc(id,'SELF_CARE')) do if job.providerType=='SELF_CARE' then return job end end
end
function Resume.invalidate(id,reason)
    if type(id)~='string' or id=='' then return false end
    epochs()[id]=Resume.epoch(id)+1
    local job=personal(id)
    if job and job.payload.resume then
        local p=job.payload p.resume.state='INVALIDATED' p.resume.reason=reason
        return Jobs.current():update(job.id,job.revision,{payload=p})
    end
    return true
end
local function business(ref,id)
    if ref.kind=='COOKING' or ref.kind=='FIELD_WORK' then
        local j=Jobs.current():peek(ref.jobId)
        if j and j.npcId==id then return {id=j.id,generation=j.revision,
            state=j.state=='SUSPENDED' and 'PAUSED' or j.state,reason=j.payload.reason,uncertain=j.effects~='KNOWN'} end
    end
    if ref.kind=='PRODUCTION' then return require('EmberRoutesProbe/BusinessJobs').crafts()[id] end
    if ref.kind=='TRANSFER' then return require('EmberRoutesProbe/Work').record(id) end
end
function Resume.prepare(actor,id,careId)
    local receipt=Registry.data().executionSave
    if receipt and receipt.state=='BLOCKED' then return false,'SAVE_RECONCILE_REQUIRED' end
    local jobs=Jobs.current() local job=jobs:get(careId)
    local borrowed=job and job.payload.kind=='STUDY' and job.payload.step=='SETTLING'
    if not job or job.npcId~=id or job.providerType~='SELF_CARE'
        or job.payload.step~='REQUESTED' and not borrowed then return false,'PERSONAL_ATTEMPT_INVALID' end
    local runtime=require('EmberRoutesProbe/TaskRuntime').current()
    if not runtime or not runtime:accepting() then return false,'ADMISSION_CLOSED' end
    local current=runtime:status(id)
    local p=job.payload
    if current and current.kind=='MEMBERSHIP_RETURN' and not current.pending and current.state=='ACTIVE' then
        -- Macro intent is already durable; after self care the same arbiter proposes a fresh return.
        p.step='STOP_CONFIRMED' p.resume=nil
        return jobs:update(job.id,job.revision,{payload=p})
    end
    if not current then
        -- A second drink may start while the original work is still paused.
        -- Its durable relation survives until restored or explicitly superseded.
        p.step='STOP_CONFIRMED'
        return jobs:update(job.id,job.revision,{payload=p})
    end
    if current.pending or current.state~='ACTIVE' or current.started~=true or not kinds[current.kind] then return false,'PREDECESSOR_NOT_READY' end
    if borrowed and current.kind~='COMPANION' then return false,'PREDECESSOR_NOT_READY' end
    local ref={jobId=current.jobId,kind=current.kind,epoch=Resume.epoch(id),state='REQUESTED'}
    if current.kind=='COMPANION' then
        ref.intent=require('EmberRoutesProbe/Companion').exportState(id)
        if ref.intent.jobId~=ref.jobId then return false,'PREDECESSOR_CHANGED' end
    else
        local r=business(ref,id)
        if not r or r.id~=ref.jobId then return false,'PREDECESSOR_CHANGED' end
        ref.beforeGeneration=r.generation
    end
    p.resume=ref
    return jobs:update(job.id,job.revision,{payload=p})
end
function Resume.stopped(fact)
    local job=personal(fact.npcId)
    if not job then return true end
    local p=job.payload local ref=p.resume
    if not ref or ref.jobId~=fact.jobId or ref.kind~=fact.kind then return true end
    if ref.state=='RESTORE_QUEUED' then
        if fact.started~=true then return true end
        ref.state=fact.effects=='KNOWN' and 'RESTORED' or 'BLOCKED'
        ref.reason=fact.effects~='KNOWN' and 'RESTORED_EFFECT_UNKNOWN' or nil
        return Jobs.current():update(job.id,job.revision,{payload=p})
    end
    if ref.state~='REQUESTED' then return true end
    if ref.epoch~=Resume.epoch(job.npcId) then ref.state='INVALIDATED'
    elseif fact.state~='CLOSED' or fact.reason~='SELF_CARE' or fact.effects~='KNOWN' then
        ref.state='BLOCKED' ref.reason='PREDECESSOR_EFFECT_UNKNOWN_OR_REPLACED'
    else
        local r=business(ref,job.npcId)
        local saved=Jobs.current():peek(ref.jobId)
        local settled=saved and saved.npcId==job.npcId and saved.effects=='KNOWN'
            and (saved.state=='DONE' or saved.state=='CANCELLED')
        if settled then for _ in pairs(saved.obligations) do settled=false break end end
        if settled then ref.state='INVALIDATED' ref.reason='PREDECESSOR_SETTLED'
        elseif ref.kind~='COMPANION' and (not r or r.id~=ref.jobId or r.state~='PAUSED' or r.reason~='SELF_CARE') then
            ref.state='BLOCKED' ref.reason='PREDECESSOR_CHANGED'
        else ref.state='STOP_CONFIRMED' ref.generation=r and r.generation end
    end
    p.step='STOP_CONFIRMED'
    return Jobs.current():update(job.id,job.revision,{payload=p})
end
function Resume.resume(actor,id,careId)
    local receipt=Registry.data().executionSave
    if receipt and receipt.state=='BLOCKED' then return false,'SAVE_RECONCILE_REQUIRED' end
    local jobs=Jobs.current() local job=jobs:get(careId)
    if not job or job.npcId~=id or job.effects~='KNOWN' then return false,'PERSONAL_EFFECT_UNKNOWN' end
    local ref=job.payload.resume
    if not ref then return true,'NO_PREDECESSOR' end
    if ref.state=='INVALIDATED' or ref.epoch~=Resume.epoch(id) then return true,'INTENT_SUPERSEDED' end
    if ref.state=='RESTORED' then return true,'RESTORED' end
    if ref.state~='STOP_CONFIRMED' and ref.state~='RESTORE_QUEUED' then return false,ref.reason or 'PREDECESSOR_NOT_CONFIRMED' end
    local runtime=require('EmberRoutesProbe/TaskRuntime').current()
    if not runtime or not runtime:accepting() then return false,'WAIT' end
    if runtime:owns(id) then
        local active=runtime:status(id)
        if ref.state=='RESTORE_QUEUED' and active and active.jobId==ref.jobId and active.kind==ref.kind
            and active.state=='ACTIVE' and active.started then
            ref.state='RESTORED'
            local ok,why=jobs:update(job.id,job.revision,{payload=job.payload})
            return ok,why or 'RESTORED'
        end
        return false,'WAIT'
    end
    if ref.kind=='COMPANION' then
        local accepted,why=require('EmberRoutesProbe/Companion').restoreState(actor,ref.intent)
        if not accepted then return false,why end
        ref.state='RESTORE_QUEUED'
        local ok,reason=jobs:update(job.id,job.revision,{payload=job.payload})
        return false,ok and 'QUEUED' or reason
    end
    local r=business(ref,id)
    if ref.kind=='COOKING' or ref.kind=='FIELD_WORK' then
        local saved=jobs:peek(ref.jobId)
        if not saved or saved.npcId~=id or saved.state=='DONE' or saved.state=='CANCELLED' then
            ref.state='INVALIDATED' ref.reason='COOKING_SETTLED_OR_TRANSFERRED'
            local ok,why=jobs:update(job.id,job.revision,{payload=job.payload}) return ok,why or 'INTENT_SUPERSEDED'
        end
        if not r or r.generation~=ref.generation or r.state~='PAUSED' or r.uncertain then return false,'PREDECESSOR_CHANGED' end
        local service=ref.kind=='COOKING' and require('EmberRoutesProbe/CookingService') or require('EmberRoutesProbe/FieldWork')
        if not service.wake(actor,id,ref.jobId,job.id) then return false,'WAIT' end
        ref.state='RESTORE_QUEUED'
        local ok,why=jobs:update(job.id,job.revision,{payload=job.payload}) return false,ok and 'QUEUED' or why
    end
    if not r or r.id~=ref.jobId or r.generation~=ref.generation or r.state~='PAUSED' or r.reason~='SELF_CARE'
        or r.uncertain or r.controlUncertain then return false,'PREDECESSOR_CHANGED' end
    local result
    if ref.kind=='PRODUCTION' then
        result=require('EmberRoutesProbe/Production').execute(actor,'resume',nil,id,{nonPreemptive=true})
    else result=require('EmberRoutesProbe/Work').resumeFor(actor,id) end
    if result=='QUEUED' or result=='STARTED' then
        ref.state='RESTORE_QUEUED'
        local ok,reason=jobs:update(job.id,job.revision,{payload=job.payload})
        return false,ok and 'QUEUED' or reason
    end
    return false,result
end
function Resume.prepareRecovery(receipt)
    local states={REQUESTED=true,STOP_CONFIRMED=true,RESTORE_QUEUED=true,RESTORED=true,INVALIDATED=true,BLOCKED=true}
    local rows=Registry.data().taskJobs and Registry.data().taskJobs.byId or {}
    for _,job in pairs(rows) do
        if job.providerType=='SELF_CARE' then
            if not require('EmberRoutesProbe/SelfCareRecord').valid(job) then error('PERSONAL_RECORD_INVALID') end
            local ref=job.payload.resume
            if ref and (type(ref)~='table' or not kinds[ref.kind] or type(ref.jobId)~='string'
                or not states[ref.state] or type(ref.epoch)~='number' or ref.epoch<0
                or ref.epoch~=math.floor(ref.epoch) or ref.epoch>=9007199254740991) then error('PERSONAL_RESUME_INVALID') end
            if ref and ref.kind=='COMPANION' and (type(ref.intent)~='table'
                or ref.intent.id~=job.npcId or ref.intent.jobId~=ref.jobId) then error('PERSONAL_RESUME_INVALID') end
        end
    end
    -- The saved body receipt is independent of the cancelled pending successor.
    -- It can complete a REQUESTED relation even if no later tick ran before exit.
    if receipt and receipt.state=='CAPTURED' then
        for id,f in pairs(receipt.byNpc) do
            if f.bodyStopped and f.persisted and f.effects=='KNOWN' then
                if not Resume.stopped({npcId=id,jobId=f.jobId,kind=f.kind,state='CLOSED',reason=f.reason,
                    effects=f.effects,started=f.started==true}) then error('PERSONAL_RECEIPT_RESTORE_FAILED') end
            end
        end
    end
    -- Only remap the generation whose increment LaborStore actually performed;
    -- never bless an arbitrary newer record merely because its ID still matches.
    for _,saved in pairs(rows) do
        if saved.providerType=='SELF_CARE' then
            local job=Jobs.current():get(saved.id) local ref=job.payload.resume
            if ref and ref.kind=='TRANSFER' and (ref.state=='STOP_CONFIRMED' or ref.state=='RESTORE_QUEUED') then
                local Store=require 'EmberRoutesProbe/LaborStore'
                local stamp=Store.recoveryGeneration(ref.jobId) local r=business(ref,job.npcId)
                if stamp and r and r.id==ref.jobId and r.state=='PAUSED' and r.reason=='SELF_CARE'
                    and ref.generation==stamp.before and r.generation==stamp.after then
                    ref.generation=stamp.after
                    if not Jobs.current():update(job.id,job.revision,{payload=job.payload}) then error('PERSONAL_RESUME_REMAP_FAILED') end
                end
            end
        end
    end
    return true
end
function Resume.install()
    local Probe=require 'EmberRoutesProbe/Boot'
    if Probe.careProtocolInstalled then return end
    local previous=Probe.taskStopped
    Probe.taskStopped=function(fact)
        if previous and previous(fact)~=true then return false end
        return Resume.stopped(fact)
    end
    Probe.invalidateCare=Resume.invalidate
    Probe.prepareCareRecovery=Resume.prepareRecovery
    Probe.careProtocolInstalled=true
end
return Resume
