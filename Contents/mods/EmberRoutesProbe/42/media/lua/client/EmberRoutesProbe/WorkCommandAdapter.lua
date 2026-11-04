local Monitor=require 'EmberRoutesProbe/OrderMonitorService'
local A={}
function A.capabilities(row)
    if not row then return {} end
    if row.kind=='FIELD_WORK' then return {stopBody=row.jobId~=nil and row.generation~=nil and not row.closed and row.carrierAvailable and row.bucket=='active'} end
    return {stop=row.canPause==true,resume=row.canResume==true,['return']=row.canCancel==true}
end
function A.command(actor,scope,row,action)
    if not row or not A.capabilities(row)[action] then return 'TASK_CHANGED' end
    if row.kind~='FIELD_WORK' then return Monitor.command(actor,scope,row.id,row.generation,action) end
    if action~='stopBody' then return 'INVALID_COMMAND' end
    local job=require('EmberRoutesProbe/TaskJobs').current():get(row.jobId)
    if not job or job.providerType~='FIELD_WORK' or job.scopeId~=scope or job.npcId~=row.npcId or job.revision~=row.generation then return 'TASK_CHANGED' end
    if not require('EmberRoutesProbe/SettlementLedger').view(actor,scope) then return 'DRIVER_UNAVAILABLE' end
    local runtime=require('EmberRoutesProbe/TaskRuntime').current()
    if not runtime then return 'TASK_CHANGED' end
    local ok,why=runtime:stopJob(row.npcId,row.jobId,'USER')
    return ok and 'STOP_REQUESTED' or why
end
return A
