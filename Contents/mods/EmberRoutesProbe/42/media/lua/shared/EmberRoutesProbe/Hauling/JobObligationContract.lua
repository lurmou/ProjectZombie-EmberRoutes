-- Domain evidence for the mandatory JobStore obligation boundary. No publishing.
local C={errorCodes={HAUL_OBLIGATION_MISMATCH='domain obligation evidence rejected',HAUL_OBLIGATION_MISSING='domain obligation evidence rejected'}}
function C.record(job,obligation,claims)
    if (obligation.type=='CARRIED_ITEM' or obligation.type=='DELIVERY_RETURN') then
        local found=false
        for _,line in ipairs(job.payload.manifest or {}) do
            if line.itemId==obligation.data.itemId and line.obligationId==obligation.id then found=true break end
        end
        if not found then return false,'HAUL_OBLIGATION_MISMATCH' end
    end
    return true
end
function C.references(job,ledger)
    if job.payload.executor=='ENTITY' then
        local attempt=job.payload.activeAttempt
        for _,line in ipairs(job.payload.manifest or {}) do
            local needs=line.custodyState=='CARRIED' or line.custodyState=='RECONCILE'
                or attempt and attempt.kind=='TAKE' and attempt.itemId==line.itemId
            if needs then
                local record=line.obligationId and ledger.byId[line.obligationId]
                if not record or record.state=='SETTLED' or record.jobId~=job.id
                    or record.data.itemId~=line.itemId
                    or record.type~=(job.payload.producer=='DELIVERY' and 'DELIVERY_RETURN' or 'CARRIED_ITEM') then
                    return false,'HAUL_OBLIGATION_MISSING'
                end
            end
        end
    end
    return true
end
return C
