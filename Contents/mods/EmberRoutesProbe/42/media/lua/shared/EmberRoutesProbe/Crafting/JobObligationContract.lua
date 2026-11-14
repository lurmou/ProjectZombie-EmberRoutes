-- Domain evidence for the mandatory JobStore obligation boundary. No publishing.
local C={errorCodes={CRAFT_CONSUMPTION_UNPROVEN='domain obligation evidence rejected',CRAFT_OBLIGATION_MISMATCH='domain obligation evidence rejected',CRAFT_OBLIGATION_MISSING='domain obligation evidence rejected'}}
function C.record(job,obligation,claims)
    if obligation.type=='CARRIED_ITEM' then
        local found=false
        for _,name in ipairs({'materials','tools','outputs','held'}) do
            for _,asset in ipairs(job.payload[name] or {}) do
                if asset.id==obligation.data.itemId and asset.obligationId==obligation.id then found=true end
            end
        end
        if not found or obligation.data.purpose~='CRAFT_MATERIAL' and obligation.data.purpose~='CRAFT_ASSET' then
            return false,'CRAFT_OBLIGATION_MISMATCH'
        end
    end
    return true
end
function C.references(job,ledger)
    if job.payload.executor=='PRODUCTION' then
        for _,name in ipairs({'materials','tools','outputs','held'}) do
            for _,asset in ipairs(job.payload[name] or {}) do
                local record=asset.obligationId and ledger.byId[asset.obligationId]
                if not record or record.type~='CARRIED_ITEM' or record.jobId~=job.id
                    or record.data.itemId~=asset.id or record.data.purpose~='CRAFT_MATERIAL'
                        and record.data.purpose~='CRAFT_ASSET' then return false,'CRAFT_OBLIGATION_MISSING' end
            end
        end
    end
    return true
end
function C.operation(old,value,op,existing)
    if op.action=='SETTLE' and existing and existing.data.purpose=='CRAFT_MATERIAL'
        and op.evidence and op.evidence.kind=='CRAFT_CONSUMED' then
        local a=value.payload.nativeAttempt local receipt=a and a.observation local found=false
        if value.providerType~='CRAFT' or value.effects~='KNOWN' or not a or a.state~='APPLIED'
            or not receipt or receipt.complete~=true or receipt.attemptId~=a.id
            or op.evidence.attemptId~=a.id then return false,'CRAFT_CONSUMPTION_UNPROVEN' end
        for _,id in ipairs(receipt.consumed or {}) do if id==existing.data.itemId then found=true end end
        if not found then return false,'CRAFT_CONSUMPTION_UNPROVEN' end
    end
    return true
end
function C.retire(old,value,record,obligationOps)
    if record.type~='CARRIED_ITEM' then return false end
    if (record.data.purpose=='CRAFT_MATERIAL' or record.data.purpose=='CRAFT_ASSET') then
        local previous=false
        for _,name in ipairs({'materials','tools','outputs','held'}) do
            for _,asset in ipairs(old.payload[name] or {}) do if asset.obligationId==record.id then previous=true end end
            for _,asset in ipairs(value.payload[name] or {}) do if asset.obligationId==record.id then return false end end
        end
        local claimed=false
        for _,claim in ipairs(value.payload.claims or {}) do
            if claim=='item:'..tostring(record.data.itemId) then claimed=true break end
        end
        if claimed then
            local replacement
            for _,op in ipairs(obligationOps) do
                if op.action=='CREATE' and type(op.record)=='table' and op.record.jobId==old.id
                    and op.record.data and op.record.data.itemId==record.data.itemId then replacement=op.id end
            end
            if not replacement then return false end
            local linked=false
            for _,name in ipairs({'materials','tools','outputs','held'}) do
                for _,asset in ipairs(value.payload[name] or {}) do
                    if asset.id==record.data.itemId and asset.obligationId==replacement then linked=true end
                end
            end
            if not linked then return false end
        end
        return previous
    end
    return false
end
return C
