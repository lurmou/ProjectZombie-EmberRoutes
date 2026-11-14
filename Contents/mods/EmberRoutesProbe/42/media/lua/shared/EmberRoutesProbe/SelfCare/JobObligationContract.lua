-- Domain evidence for the mandatory JobStore obligation boundary. No publishing.
local C={errorCodes={PERSONAL_OBLIGATION_MISMATCH='domain obligation evidence rejected',PERSONAL_OBLIGATION_MISSING='domain obligation evidence rejected',PERSONAL_OUTPUT_CLAIM_RETAINED='domain obligation evidence rejected',PERSONAL_SETTLEMENT_UNPROVEN='domain obligation evidence rejected'}}
function C.record(job,obligation,claims)
    if obligation.type=='CARRIED_ITEM' then
        local p=job.payload
        if obligation.data.purpose~='SELF_CARE' or p.obligationId~=obligation.id
            or p.itemId~=obligation.data.itemId or p.sourceId~=obligation.data.sourceId then
            return false,'PERSONAL_OBLIGATION_MISMATCH'
        end
        for _,outputs in ipairs({p.consumption and p.consumption.outputs or {},p.medical and p.medical.outputs or {}}) do
            for _,itemId in ipairs(outputs) do
                if not claims['item:'..tostring(itemId)] then return false,'PERSONAL_OUTPUT_CLAIM_RETAINED' end
            end
        end
    end
    return true
end
function C.references(job,ledger)
    if job.payload.sourceId and job.payload.itemId
        and job.payload.step~='IDLE' and not job.payload.obligationId then return false,'PERSONAL_OBLIGATION_MISSING' end
    if job.payload.obligationId then
        local p=job.payload local record=ledger.byId[p.obligationId]
        if not record or record.type~='CARRIED_ITEM' or record.data.purpose~='SELF_CARE'
            or record.jobId~=job.id or record.npcId~=job.npcId or record.data.itemId~=p.itemId
            or record.data.sourceId~=p.sourceId then return false,'PERSONAL_OBLIGATION_MISSING' end
    end
    return true
end
function C.operation(old,value,op,existing)
    if op.action=='SETTLE' and existing and existing.data.purpose=='SELF_CARE' then
        local p=value.payload local evidence=op.evidence
        if value.providerType~='SELF_CARE' or value.effects~='KNOWN' or p.obligationId~=existing.id
            or type(evidence)~='table' or evidence.attemptId~=p.attemptId then
            return false,'PERSONAL_SETTLEMENT_UNPROVEN'
        end
        if evidence.kind=='UNCHANGED' then
            if p.transfer or p.consumption or p.medical and p.medical.applied
                or p.reading and p.reading.started then return false,'PERSONAL_SETTLEMENT_UNPROVEN' end
        else
            local expected={} local count=0
            for _,list in ipairs({p.consumption and p.consumption.outputs or {},p.medical and p.medical.outputs or {}}) do
                for _,itemId in ipairs(list) do
                    if expected[itemId] then return false,'PERSONAL_SETTLEMENT_UNPROVEN' end
                    expected[itemId]=true count=count+1
                end
            end
            if not require('EmberRoutesProbe/Kernel/Validate').dense(evidence.outputs,512) or #evidence.outputs~=count then return false,'PERSONAL_SETTLEMENT_UNPROVEN' end
            for _,output in ipairs(evidence.outputs) do
                if type(output)~='table' then return false,'PERSONAL_SETTLEMENT_UNPROVEN' end
                local destination=p.destinations and p.destinations[tostring(output.itemId)] or p.sourceId
                if not expected[output.itemId] or output.originalPresent~=true
                    or output.destinationId~=destination then return false,'PERSONAL_SETTLEMENT_UNPROVEN' end
                expected[output.itemId]=nil
            end
            if evidence.kind=='CONSUMED' then
                local f=p.consumption
                local consumed=f and f.effects=='KNOWN' and f.started and (f.completed or f.stopped)
                    and type(f.after)=='number' and f.after<=0.0001 and type(f.consumed)=='number' and f.consumed>0
                    and f.kind==evidence.consumptionKind
                if not consumed and not (evidence.consumptionKind=='MEDICAL'
                    and require('EmberRoutesProbe/SelfCare/MedicalRecord').consumed(p)) then
                    return false,'PERSONAL_SETTLEMENT_UNPROVEN'
                end
            else
                local destination=p.destinations and p.destinations[tostring(p.itemId)] or p.sourceId
                if evidence.originalPresent~=true or evidence.destinationId~=destination then
                    return false,'PERSONAL_SETTLEMENT_UNPROVEN'
                end
            end
        end
    end
    return true
end
function C.retire(old,value,record,obligationOps)
    if record.type~='CARRIED_ITEM' then return false end
    return old.effects=='KNOWN' and record.data.purpose=='SELF_CARE'
        and old.payload.obligationId==record.id and value.payload.obligationId~=record.id
        and #(old.payload.claims or {})==0

end
return C
