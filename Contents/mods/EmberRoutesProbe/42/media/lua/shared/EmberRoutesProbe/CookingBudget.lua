-- Admission quotas are derived from the SAME Jobs that own originals.
-- There is no second persistent quota ledger to drift during save/load.
local Record=require 'EmberRoutesProbe/CookingRecord'
local Policy=require 'EmberRoutesProbe/CookingPolicy'
local B={}
function B.open(root,jobs)
    if type(root)~='table' or not root.taskJobs or type(root.taskJobs.byId)~='table' then return nil,'JOB_ROOT_INVALID' end
    local api={}
    function api:view(scope)
        local pending,blocked,ids=0,0,{}
        for id,j in pairs(root.taskJobs.byId) do
            if j.providerType=='COOKING' then
                if not Record.valid(j) then return nil,'COOKING_RECORD_INVALID' end
                if j.scopeId==scope and j.payload.phase~='SETTLED' then
                    ids[#ids+1]=#id..':'..id..':'..j.revision
                    local p=j.payload
                    if p.source=='AUTO' or p.mealBatch==true then
                        if j.effects=='UNKNOWN' or p.expected==nil then blocked=blocked+p.quota
                        else
                            -- Released meals enter S. They must leave P in the same Job revision.
                            local delivered=0
                            for _,a in ipairs(p.assets) do
                                if a.role=='OUTPUT' and a.custody=='DELIVERED' then delivered=delivered+a.effective end
                            end
                            pending=pending+math.max(0,p.expected-delivered)
                        end
                    end
                end
            end
        end
        table.sort(ids)
        return {scopeId=scope,pending=pending,blocked=blocked,stamp=table.concat(ids,'|')}
    end
    function api:reserve(job,supply)
        if not Record.valid(job) or job.state~='PREPARING' or job.effects~='KNOWN' or #job.payload.claims~=0
            or #job.payload.assets~=0 or job.payload.sequence~=0 then return false,'COOKING_ADMISSION_INVALID' end
        local prior=root.taskJobs.byId[job.id]
        if prior then
            if prior.providerType=='COOKING' and prior.scopeId==job.scopeId and prior.npcId==job.npcId
                and prior.payload.source==job.payload.source and prior.payload.sourceId==job.payload.sourceId
                and prior.payload.profileId==job.payload.profileId then return false,'COOKING_ALREADY_ADMITTED' end
            return false,'JOB_ID_CONFLICT'
        end
        for _,other in pairs(root.taskJobs.byId) do
            if other.npcId==job.npcId and other.state~='DONE' and other.state~='CANCELLED' then
                if other.providerType~='SELF_CARE' then return false,'OTHER_TASK_RETAINED' end
                if other.effects=='UNKNOWN' then return false,'PERSONAL_EFFECT_UNKNOWN' end
                for _ in pairs(other.obligations) do return false,'PERSONAL_OBLIGATION_RETAINED' end
            end
        end
        local live,why=api:view(job.scopeId) if not live then return false,why end
        if type(supply)~='table' or supply.scopeId~=job.scopeId or supply.stamp~=live.stamp
            or supply.complete~=true then return false,'COOKING_SUPPLY_CHANGED' end
        if job.payload.source=='AUTO' then
            local demand,reason=Policy.demand(supply.population,supply.ready,live.pending,live.blocked,supply.active)
            if not demand then return false,reason end
            local batch,reason2=Policy.batch(demand,supply.minimum)
            if not batch then return false,reason2 end
            if job.payload.target>demand.gap+Policy.epsilon
                or job.payload.quota+Policy.epsilon<math.max(job.payload.target,supply.minimum)
                or job.payload.quota>batch.quota+Policy.epsilon then return false,'COOKING_QUOTA_CHANGED' end
        end
        return jobs:create(job)
    end
    return api
end
return B
