-- One source original and the outputs of its evidenced use form a return duty.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Medical=require 'EmberRoutesProbe/SelfCare/MedicalRecord'
local M={}
function M.create(job,p)
    local id='personal-obligation:'..Registry.id()
    local record={id=id,type='CARRIED_ITEM',jobId=job.id,npcId=job.npcId,revision=1,state='ACTIVE',
        data={itemId=p.itemId,sourceId=p.sourceId,purpose='SELF_CARE'}}
    return id,{action='CREATE',id=id,record=record}
end
function M.record(job)
    local p=job.payload local r=p.obligationId and Registry.data().obligations.byId[p.obligationId]
    if r and r.type=='CARRIED_ITEM' and r.jobId==job.id and r.npcId==job.npcId
        and r.data.itemId==p.itemId and r.data.sourceId==p.sourceId then return r end
end
function M.outstanding(job)
    if not job.payload.obligationId then return false end
    local r=M.record(job)
    if not r then return nil,'PERSONAL_OBLIGATION_MISSING' end
    return r.state~='SETTLED'
end
local function endpoint(p,id)
    local destination=p.destinations and p.destinations[tostring(id)] or p.sourceId
    local target=destination and Registry.resolve(destination,'put','local-world')
    return target,destination
end
local function located(p,items,id)
    local item=items[id] local target,destination=endpoint(p,id)
    if not item or item:getID()~=id or not target or item:getContainer()~=target.container
        or not target.container:getItems():contains(item) then return nil end
    return destination
end
-- The caller supplies the live handles it inspected; no absence or stopped body
-- alone settles. Output destinations are checked individually.
function M.settlement(job,p,items,effects,unchanged)
    local record=M.record({id=job.id,npcId=job.npcId,payload=p})
    if not record or record.state=='SETTLED' or effects~='KNOWN' then return nil end
    local proof={effects='KNOWN',itemId=p.itemId,attemptId=p.attemptId,outputs={}}
    if unchanged then
        local source=Registry.resolve(p.sourceId,'take','local-world') local item=items[p.itemId]
        if p.transfer or p.consumption or p.medical and p.medical.applied
            or p.reading and p.reading.started or not source or not item or item:getID()~=p.itemId
            or item:getContainer()~=source.container or not source.container:getItems():contains(item) then return nil end
        proof.kind='UNCHANGED' proof.destinationId=p.sourceId proof.originalPresent=true
    else
        local destination=located(p,items,p.itemId)
        if destination then proof.destinationId=destination proof.originalPresent=true
        else
            local item=items[p.itemId]
            if item and item:getContainer()~=nil then return nil end
            local fact=p.consumption
            if fact and fact.effects=='KNOWN' and fact.started and (fact.completed or fact.stopped) and type(fact.after)=='number'
                and fact.after<=0.0001 and type(fact.consumed)=='number' and fact.consumed>0 then
                proof.kind='CONSUMED' proof.consumptionKind=fact.kind
            elseif Medical.consumed(p) then proof.kind='CONSUMED' proof.consumptionKind='MEDICAL'
            else return nil end
            proof.destinationId=p.sourceId
        end
        local seen={}
        for _,list in ipairs({p.consumption and p.consumption.outputs or {},p.medical and p.medical.outputs or {}}) do
            for _,id in ipairs(list) do
                if seen[id] then return nil end seen[id]=true
                local where=located(p,items,id) if not where then return nil end
                proof.outputs[#proof.outputs+1]={itemId=id,destinationId=where,originalPresent=true}
            end
        end
    end
    return {{action='SETTLE',id=record.id,expectedRevision=record.revision,evidence=proof}}
end
return M
