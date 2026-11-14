-- Domain evidence for the mandatory JobStore obligation boundary. No publishing.
local C={errorCodes={FURNACE_OBLIGATION_MISMATCH='domain obligation evidence rejected',FURNACE_OBLIGATION_MISSING='domain obligation evidence rejected',FURNACE_OBLIGATION_RETAINED='domain obligation evidence rejected'}}
function C.record(job,obligation,claims)
    if obligation.type=='FURNACE_DUTY' then
        local duty=job.payload.duty
        if not duty or duty.id~=obligation.id or duty.siteKey~=obligation.data.siteKey then return false,'FURNACE_OBLIGATION_MISMATCH' end
    end
    return true
end
function C.references(job,ledger)
    if job.payload.duty then
        local duty=job.payload.duty local record=ledger.byId[duty.id]
        if not record or record.type~='FURNACE_DUTY' or record.state=='SETTLED' or record.jobId~=job.id then
            return false,'FURNACE_OBLIGATION_MISSING'
        end
    end
    return true
end
function C.operation(old,value,op,existing)
    if op.action=='SETTLE' and existing and existing.type=='FURNACE_DUTY' and old.providerType=='COOKING' then
        local duty=old.payload.duty local evidence=op.evidence
        if not duty or duty.id~=op.id or old.effects~='KNOWN' or duty.lastActive~=false
            or type(evidence)~='table' or evidence.shutdownRequired~=duty.openedByJob then
            return false,'FURNACE_OBLIGATION_RETAINED'
        end
    end
    return true
end
return C
