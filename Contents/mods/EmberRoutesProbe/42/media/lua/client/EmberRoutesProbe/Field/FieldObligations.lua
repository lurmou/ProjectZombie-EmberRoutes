-- Field originals are published with their Job and item claim by the labor kernel.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local M={}
function M.create(job,itemId,sourceId,uncertain)
    local id='field-obligation:'..Registry.id()
    local record={id=id,type='CARRIED_ITEM',jobId=job.id,npcId=job.npcId,revision=1,
        state=uncertain and 'RECONCILE_REQUIRED' or 'ACTIVE',data={itemId=itemId,sourceId=sourceId}}
    return id,{action='CREATE',id=id,record=record}
end
function M.record(id,jobId,itemId)
    local r=id and Registry.data().obligations.byId[id]
    if r and r.jobId==jobId and r.type=='CARRIED_ITEM' and r.data.itemId==itemId and r.state~='SETTLED' then return r end
end
return M
