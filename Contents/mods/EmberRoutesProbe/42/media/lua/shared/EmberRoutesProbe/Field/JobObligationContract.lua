-- Domain evidence for the mandatory JobStore obligation boundary. No publishing.
local C={errorCodes={FIELD_OBLIGATION_MISMATCH='domain obligation evidence rejected',FIELD_OBLIGATION_MISSING='domain obligation evidence rejected'}}
function C.record(job,obligation,claims)
    if obligation.type=='CARRIED_ITEM' then
        local found=false
        for _,asset in ipairs(job.payload.assets or {}) do
            if asset.id==obligation.data.itemId and asset.obligationId==obligation.id
                and asset.custody~='DELIVERED' then found=true break end
        end
        if not found then return false,'FIELD_OBLIGATION_MISMATCH' end
    end
    return true
end
function C.references(job,ledger)
    do
        for _,asset in ipairs(job.payload.assets or {}) do
            if asset.custody~='DELIVERED' then
                local record=ledger.byId[asset.obligationId]
                if not record or record.type~='CARRIED_ITEM' or record.state=='SETTLED'
                    or record.jobId~=job.id or record.data.itemId~=asset.id then return false,'FIELD_OBLIGATION_MISSING' end
            end
        end
    end
    return true
end
return C
