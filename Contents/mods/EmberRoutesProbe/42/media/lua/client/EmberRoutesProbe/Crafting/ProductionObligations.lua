-- Transaction intents for the exact production originals and native receipt.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local M={}
local names={'materials','tools','outputs','held'}
local function assets(payload)
    local result={}
    for _,name in ipairs(names) do for _,asset in ipairs(payload[name] or {}) do
        local entry=result[asset.id] or {assets={},name=name}
        entry.assets[#entry.assets+1]=asset result[asset.id]=entry
    end end
    return result
end
function M.prepare(job,previous)
    local ledger=Registry.data().obligations local ops={} local current=assets(job.payload)
    for itemId,group in pairs(current) do
        local first=group.assets[1]
        for _,asset in ipairs(group.assets) do
            if asset.obligationId then
                if first.obligationId and first.obligationId~=asset.obligationId then return nil,'PRODUCTION_OBLIGATION_CONFLICT' end
                first.obligationId=asset.obligationId
            end
        end
        local existing=first.obligationId and ledger.byId[first.obligationId]
        if not first.obligationId then
            local id='craft-obligation:'..Registry.id()
            local state=job.effects=='UNKNOWN' and 'RECONCILE_REQUIRED' or 'ACTIVE'
            local record={id=id,type='CARRIED_ITEM',jobId=job.id,npcId=job.npcId,revision=1,state=state,
                data={itemId=itemId,sourceId=first.source,purpose=group.name=='materials' and 'CRAFT_MATERIAL' or 'CRAFT_ASSET'}}
            first.obligationId=id
            ops[#ops+1]={action='CREATE',id=id,record=record}
        elseif not existing or existing.jobId~=job.id or existing.data.itemId~=itemId then
            return nil,'PRODUCTION_OBLIGATION_MISSING'
        end
        for _,asset in ipairs(group.assets) do
            if asset.obligationId and asset.obligationId~=first.obligationId then return nil,'PRODUCTION_OBLIGATION_CONFLICT' end
            asset.obligationId=first.obligationId
        end
        if existing and existing.state~='SETTLED' then
            local attempt=job.payload.nativeAttempt local receipt=attempt and attempt.observation
            local consumed=false
            if first.consumed and attempt and attempt.state=='APPLIED' and receipt and receipt.complete then
                for _,id in ipairs(receipt.consumed) do if id==itemId then consumed=true break end end
            end
            if consumed then
                ops[#ops+1]={action='SETTLE',id=existing.id,expectedRevision=existing.revision,
                    evidence={kind='CRAFT_CONSUMED',effects='KNOWN',itemId=itemId,destinationId='CRAFT',attemptId=attempt.id}}
            elseif first.returnEvidence then
                local proof=first.returnEvidence
                ops[#ops+1]={action='SETTLE',id=existing.id,expectedRevision=existing.revision,evidence=proof}
            end
        end
    end
    if previous then
        local old=assets(previous.payload)
        for itemId,group in pairs(old) do
            local id=group.assets[1].obligationId local record=id and ledger.byId[id]
            local nextGroup=current[itemId]
            if (not nextGroup or nextGroup.assets[1].obligationId~=id) and record and record.state=='SETTLED' then
                ops[#ops+1]={action='RETIRE',id=id,expectedRevision=record.revision}
            end
        end
    end
    return #ops>0 and ops or nil
end
function M.returned(r,itemId,destinationId,attemptId)
    local group=assets(r)[itemId] if not group then return false end
    for _,asset in ipairs(group.assets) do
        asset.returnEvidence={effects='KNOWN',itemId=itemId,destinationId=destinationId,
            attemptId=attemptId,originalPresent=true}
    end
    return true
end
function M.preparePickup(r,itemId)
    local group=assets(r)[itemId] if not group then return false,'PRODUCTION_ASSET_MISSING' end
    local record=group.assets[1].obligationId and Registry.data().obligations.byId[group.assets[1].obligationId]
    if not record then return false,'PRODUCTION_OBLIGATION_MISSING' end
    if record.state=='SETTLED' then
        for _,asset in ipairs(group.assets) do asset.obligationId=nil asset.returnEvidence=nil end
        return true,nil,true
    end
    return true,nil,false
end
return M
