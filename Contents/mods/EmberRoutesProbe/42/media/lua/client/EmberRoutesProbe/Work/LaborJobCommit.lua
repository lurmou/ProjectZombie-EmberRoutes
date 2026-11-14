-- Kernel intents only. Adapter commit exceptions remain classified in
-- docs/reviews/2026-11-04/dec003-entry-inventory.md; no Lua commit fallback.
local Contracts=require 'EmberRoutesProbe/Kernel/JobContracts'
local Kernel=require 'EmberRoutesProbe/Kernel/LaborKernelAvailability'
local M={}
-- JobStore api:create refusals; each returns before its first write
-- (JobStore.lua api:create, the checks before nextClaimSeq/byId).
local CREATE_REFUSALS={JOB_RECORD_INVALID=true,JOB_EXISTS=true,PERSONAL_JOB_EXISTS=true,
    PERSONAL_JOB_LIMIT=true,JOB_LIMIT=true,JOB_DATA_UNSERIALIZABLE=true}
-- True only when a failed createClaimedJob is proven to have written nothing.
-- laborCreate reports a store refusal as TASK_WRITE_FAILURE with the store's
-- code as evidence, and only after its one restore released the new token: a
-- failed restore is ROLLBACK_FAILURE, a throw after the write is prefixed
-- CAS_REACHED_RELOAD_FROM_SAVE:. Anything else (absent, unknown, prefixed,
-- another code) is unknown effects. shortcut: matches LaborCommitKernel.create
-- by its result text; upgrade to a structured refusal field if the kernel grows one.
function M.createRefusedBeforeWrite(code,evidence)
    if code~='TASK_WRITE_FAILURE' or type(evidence)~='string' then return false end
    return CREATE_REFUSALS[evidence]==true
        or Contracts.isScopeBlockedReason(evidence)
end
-- A failed createClaimedJob whose effects are unknown: a write failure not
-- proven to be a refusal, or a failed restore. Other failure codes are
-- returned before the write or after a successful restore.
function M.createEffectsUnknown(code,evidence)
    return (code=='TASK_WRITE_FAILURE' or code=='ROLLBACK_FAILURE') and not M.createRefusedBeforeWrite(code,evidence)
end
function M.install(Store,state,nextAuthoritativeClaimId,cleanToken)
    Store.createRefusedBeforeWrite=M.createRefusedBeforeWrite
    Store.createEffectsUnknown=M.createEffectsUnknown
    local function invoke(entry,...)
        local Fence=require 'EmberRoutesProbe/Kernel/CommitFence'
        local blocked=Fence.status()
        if blocked then return false,'COMMIT_BLOCKED',blocked end
        local available,diagnosis=Kernel.validate()
        if not available then return false,'KERNEL_UNAVAILABLE',diagnosis end
        local ok,r=pcall(EmberRoutesProbeJava[entry],...)
        if not ok then
            Fence.block(state.root,'KERNEL_BRIDGE_THROW:'..tostring(r))
            return false,'TASK_WRITE_FAILURE',tostring(r)
        end
        if type(r)~='table' or type(r.ok)~='boolean' then
            Fence.block(state.root,'INVALID_KERNEL_RESULT')
            return false,'TASK_WRITE_FAILURE','INVALID_KERNEL_RESULT'
        end
        if not r.ok and (r.result=='ROLLBACK_FAILURE' or type(r.evidence)=='string'
            and string.find(r.evidence,'CAS_REACHED_RELOAD_FROM_SAVE:',1,true)==1) then
            Fence.block(state.root,r.evidence or r.result)
        end
        return r.ok,r.result,r.evidence
    end
    function Store.createClaimedJob(job,obligationOps)
        local available,diagnosis=Kernel.validate()
        if not available then return false,'KERNEL_UNAVAILABLE',diagnosis end
        Store.data()
        -- Entry-shape/domain validation stays in Lua, before any allocation.
        local ok,valid=pcall(require('EmberRoutesProbe/Kernel/JobStore').validate,job)
        if not ok or not valid or job.state~='PREPARING' or job.revision~=1
            or obligationOps~=nil and type(obligationOps)~='table' then
            return false,'INVALID_REQUEST',not ok and tostring(valid) or 'INVALID_JOB_ENVELOPE'
        end
        return invoke('laborCreate',require('EmberRoutesProbe/Runtime/TaskJobs').current(),Store,state,Contracts,
            nextAuthoritativeClaimId,job,obligationOps)
    end
    -- One entry-shape policy; JobStore retains domain/transition/cancel policy.
    local function validIntent(id,revision,payload,mutation)
        if type(id)~='string' or type(revision)~='number' or type(payload)~='table'
            or type(payload.claims)~='table' or (mutation~=nil and type(mutation)~='table') then return false end
        for _,key in ipairs(payload.claims) do if type(key)~='string' then return false end end
        mutation=mutation or {}
        if mutation.obligationOps~=nil and type(mutation.obligationOps)~='table' then return false end
        for _,field in ipairs({'addKeys','removeKeys'}) do
            local list=mutation[field]
            if list~=nil then
                if type(list)~='table' then return false end
                for _,key in ipairs(list) do if type(key)~='string' then return false end end
            end
        end
        return true
    end
    function Store.mutateJob(jobId,expectedRevision,proposedPayload,mutation)
        local available,diagnosis=Kernel.validate()
        if not available then return false,'KERNEL_UNAVAILABLE',diagnosis end
        if not validIntent(jobId,expectedRevision,proposedPayload,mutation) then
            return false,'INVALID_REQUEST','INVALID_COMMIT_INTENT'
        end
        Store.data()
        return invoke('laborMutate',require('EmberRoutesProbe/Runtime/TaskJobs').current(),Store,state.claims,
            Contracts,cleanToken,jobId,expectedRevision,proposedPayload,mutation)
    end
    function Store.cancelJob(jobId,expectedRevision,proposedPayload,mutation)
        local available,diagnosis=Kernel.validate()
        if not available then return false,'KERNEL_UNAVAILABLE',diagnosis end
        if not validIntent(jobId,expectedRevision,proposedPayload,mutation) then
            return false,'INVALID_REQUEST','INVALID_COMMIT_INTENT'
        end
        Store.data()
        return invoke('laborCancel',require('EmberRoutesProbe/Runtime/TaskJobs').current(),Store,state.claims,
            Contracts,cleanToken,jobId,expectedRevision,proposedPayload,mutation)
    end
    function Store.transferJobOwner(jobId,expectedRevision,candidate,token,obligationOps)
        local available,diagnosis=Kernel.validate()
        if not available then return false,'KERNEL_UNAVAILABLE',diagnosis end
        if not EmberRoutesProbeJava.laborTransfer then return false,'KERNEL_UNAVAILABLE','MISSING_JAVA_ENTRY:laborTransfer' end
        if type(jobId)~='string' or type(expectedRevision)~='number' or type(candidate)~='table' or type(token)~='table'
            or obligationOps~=nil and type(obligationOps)~='table' then
            return false,'INVALID_REQUEST','INVALID_TRANSFER_INTENT'
        end
        Store.data()
        return invoke('laborTransfer',require('EmberRoutesProbe/Runtime/TaskJobs').current(),state,jobId,expectedRevision,candidate,token,obligationOps)
    end
    function Store.commitCustody(operation,retirementVerifier)
        local available,diagnosis=Kernel.validate()
        if not available then return false,'KERNEL_UNAVAILABLE',diagnosis end
        if not EmberRoutesProbeJava.laborCustody then return false,'KERNEL_UNAVAILABLE','MISSING_JAVA_ENTRY:laborCustody' end
        if type(operation)~='table' then return false,'INVALID_REQUEST','CUSTODY_INTENT_INVALID' end
        Store.data()
        return invoke('laborCustody',state,require('EmberRoutesProbe/Kernel/ObligationLedger'),operation,retirementVerifier)
    end
end
return M
