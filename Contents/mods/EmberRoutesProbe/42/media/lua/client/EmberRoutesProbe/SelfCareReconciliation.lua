local Commit=require 'EmberRoutesProbe/SelfCareCommit'
-- Evidence-only exit for a detached UNKNOWN personal attempt. The service owns
-- this cursor and its retry cadence; native execution stays in the settle path.
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Custody=require 'EmberRoutesProbe/SelfCareCustody'
local Record=require 'EmberRoutesProbe/SelfCareRecord'
local Store=require 'EmberRoutesProbe/LaborStore'
local M={}
function M.run(binding,job,row,budget,runtime)
    if job.effects~='UNKNOWN' or job.payload.step~='RECONCILE_REQUIRED' then return false,'PERSONAL_NOT_RECONCILABLE' end
    if runtime:status(job.npcId,job.id) then row.reconcile=nil return false,'PERSONAL_RUNTIME_LIVE' end
    local owner=runtime:status(job.npcId)
    if runtime:owns(job.npcId) and (not owner or owner.jobId==job.id) then
        row.reconcile=nil return false,'PERSONAL_BODY_BUSY'
    end
    local npc=binding and binding.handle
    if not npc or binding.id~=job.npcId or npc:isDead() then row.reconcile=nil return false,'PERSONAL_CARRIER_UNAVAILABLE' end
    if not require('EmberRoutesProbe/Driver').valid(binding) then row.reconcile=nil return false,'PERSONAL_BINDING_INVALID' end
    local queues=ISTimedActionQueue and ISTimedActionQueue.queues
    if type(queues)~='table' then row.reconcile=nil return false,'PERSONAL_QUEUE_UNAVAILABLE' end
    local queue=queues[npc]
    if queue and (type(queue.queue)~='table' or #queue.queue>0 or queue.current~=nil) then
        row.reconcile=nil return false,'PERSONAL_QUEUE_BUSY'
    end
    if npc:isAsleep() or npc:isResting() or npc:isSittingOnFurniture() or npc:getSitOnFurnitureObject()~=nil then
        row.reconcile=nil return false,'PERSONAL_POSTURE_UNCONFIRMED'
    end
    local member=require('EmberRoutesProbe/MembershipService').view(job.npcId)
    if not member or member.retired then row.reconcile=nil return false,'NPC_DIED' end
    local p=job.payload
    local held=Store.getToken(job.id)
    if held then
        local declared={} for _,key in ipairs(p.claims) do declared[key]=true end
        for _,key in ipairs(held.resources) do
            if not declared[key] then return false,'PERSONAL_CLAIM_SET_UNCONFIRMED' end
        end
    end
    -- Existing returns handles one primary original plus consumption outputs.
    -- Never invent a route for an obligation outside that contract.
    for name,owed in pairs(job.obligations) do
        if name~='RETURN_ORIGINALS' or type(owed)~='table' or owed.itemId~=p.itemId
            or owed.sourceId~=p.sourceId then return false,'PERSONAL_OBLIGATION_UNSUPPORTED' end
    end
    local scan=row.reconcile
    if not scan or scan.revision~=job.revision then
        scan={revision=job.revision,ids={},seen={},items={},index=1}
        local function add(id)
            if id==p.itemId and require('EmberRoutesProbe/MedicalRecord').consumed(p) then return end
            if p.relief and p.relief.medical and id==p.relief.itemId
                and require('EmberRoutesProbe/MedicalRecord').consumed({medical=p.relief.medical}) then return end
            if id and not scan.seen[id] then scan.seen[id]=true scan.ids[#scan.ids+1]=id end
        end
        add(p.itemId) add(p.transfer and p.transfer.itemId)
        for _,id in ipairs(p.consumption and p.consumption.outputs or {}) do add(id) end
        for _,id in ipairs(p.medical and p.medical.outputs or {}) do add(id) end
        if p.relief then
            add(p.relief.itemId)
            for _,id in ipairs(p.relief.fact and p.relief.fact.outputs or {}) do add(id) end
            for _,id in ipairs(p.relief.medical and p.relief.medical.outputs or {}) do add(id) end
        end
        for _,key in ipairs(p.claims) do
            local id=string.match(key,'^item:(%d+)$')
            if id then add(tonumber(id)) end
        end
        row.reconcile=scan
    end
    local c={npc=npc,payload=p,items=scan.items}
    while scan.index<=#scan.ids do
        local id=scan.ids[scan.index]
        local item,done,cursor=Custody.findOriginal(c,id,budget,scan.cursor)
        scan.cursor=cursor
        if not done then return false,'PERSONAL_RECONCILING',true end
        if not item then row.reconcile=nil return false,'RETURN_ORIGINAL_MISSING' end
        scan.items[id]=item scan.index=scan.index+1 scan.cursor=nil
    end
    -- Recheck every cached handle at commit time. No partial fact publication.
    local ok,reason=require('EmberRoutesProbe/SelfCareExecution').reconcile(job,npc,scan.items)
    row.reconcile=nil
    if not ok then return false,reason end
    p.readingSite=nil -- the posture gate above proved physical exit
    local obligations={}
    if p.sourceId and p.itemId then obligations.RETURN_ORIGINALS={sourceId=p.sourceId,itemId=p.itemId} end
    p.step=obligations.RETURN_ORIGINALS and 'SETTLING' or 'IDLE'
    p.lastKind=p.kind p.reason='PERSONAL_RECONCILED'
    job.effects='KNOWN' job.obligations=obligations
    assert(Record.valid(job),'PERSONAL_RECORD_INVALID')
    -- Claim conflicts cannot be cured by classifying physical custody. Keep
    -- UNKNOWN if the authority cannot restore this attempt's declared claims.
    local live=Jobs.current():get(job.id)
    if not live or live.revision~=job.revision then return false,'PERSONAL_JOB_CHANGED' end
    local token=Store.claimPersonal(live)
    if not token then return false,'PERSONAL_CLAIM_CONFLICT' end
    if not Commit.update(job.id,job.revision,{payload=p,obligations=obligations,effects='KNOWN',state='SUSPENDED'}) then
        return false,'PERSONAL_JOB_CHANGED'
    end
    if p.step=='IDLE' and not Store.finishPersonal(Jobs.current():get(job.id),token) then return false,'PERSONAL_RELEASE_FAILED' end
    return true
end
return M
