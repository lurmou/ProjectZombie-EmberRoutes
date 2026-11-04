-- TEST ONLY: Lua model of Phase 1 transaction order. NOT Java execution.
-- CRAFT-directed variant: models ClaimsKernel.extend copy and Tx.restore revision.
-- Real JobStore/claims callbacks, real LaborJobCommit dispatch; no production fallback.
local M={calls={}}
function M.install(state,allocate,cleanup)
    local function result(ok,value,evidence) return {ok=ok,result=value,evidence=evidence} end
    local function change(jobs,owner,claims,contracts,clean,id,rev,p,cmd,cancel)
        M.calls[#M.calls+1]=cancel and 'laborCancel' or 'laborMutate'
        local j=jobs:get(id)
        if not j or j.revision~=rev then return result(false,'STALE_REVISION') end
        cmd=cmd or {} local token=owner.getToken(id)
        if not token then
            if cmd.capacity~=nil or #(cmd.addKeys or {})>0 or #(cmd.removeKeys or {})>0 then return result(false,'CLAIM_FAILURE') end
            local ok,why=jobs:update(id,rev,{payload=p,state=cmd.state,effects=cmd.effects,obligations=cmd.obligations})
            return result(ok,ok and why or 'TASK_WRITE_FAILURE')
        end
        local claimsRevision=claims.revision
        local before={} for _,k in ipairs(token.resources) do before[#before+1]=k end
        local key=token.capacityKey local amounts={}
        local bucket=key and claims.capacity[key]
        for i,a in pairs(bucket and bucket.entries[id] and bucket.entries[id].items or {}) do amounts[i]=a end
        local function fail(code,why)
            assert(claims:replace(token,before))
            claims:releaseCapacity(token)
            for i,a in pairs(amounts) do assert(claims:restore(token,key,i,a)) end
            claims.revision=claimsRevision
            return result(false,code,why)
        end
        if cmd.addKeys and #cmd.addKeys>0 then
            -- Java ClaimsKernel.java:52 detaches before append; Lua primitive does not.
            local detached={} for _,k in ipairs(token.resources) do detached[#detached+1]=k end
            token.resources=detached
            local ok,why=claims:extend(token,cmd.addKeys) if not ok then return fail('CLAIM_FAILURE',why) end
        end
        local cap=cmd.capacity
        if cap~=nil then
            if cap==false then claims:releaseCapacity(token)
            elseif cap.releaseItemId then claims:releaseCapacity(token,cap.releaseItemId)
            else
                if token.capacityKey and token.capacityKey~=cap.key then claims:releaseCapacity(token) end
                local ok,why=claims:reserveMany(token,cap.key,cap.items,cap.free)
                if not ok then return fail('CAPACITY_FAILURE',why) end
            end
        end
        if cmd.removeKeys and #cmd.removeKeys>0 then
            local ok,why=claims:shrink(token,cmd.removeKeys) if not ok then return fail('CLAIM_FAILURE',why) end
        end
        local patch={payload=p,state=cancel and 'CANCELLED' or cmd.state,effects=cmd.effects,obligations=cmd.obligations}
        local ok,nextRev
        if cancel then ok,nextRev=jobs:cancel(id,rev,patch) else ok,nextRev=jobs:update(id,rev,patch) end
        if not ok then return fail('TASK_WRITE_FAILURE',nextRev) end
        if patch.state=='DONE' or patch.state=='CANCELLED' then claims:release(token) clean(id) end
        return result(true,nextRev)
    end
    EmberRoutesProbeJava={
        laborMutate=function(...) return change(...) end,
        laborCancel=function(j,o,c,contracts,clean,id,rev,p,cmd) return change(j,o,c,contracts,clean,id,rev,p,cmd,true) end,
        laborCreate=function(jobs,owner,s,contracts,alloc,j)
            M.calls[#M.calls+1]='laborCreate'
            j.claimId=alloc(s.root,j.id)
            s.claims.nextClaimSeq=math.max(s.claims.nextClaimSeq or 1,s.root.nextClaimSeq+1)
            local token,why=s.claims:acquireNew(j.id,j.payload.sequence,j.payload.claims,j)
            if not token then return result(false,'CLAIM_FAILURE',why) end
            local r=j.payload.reservation
            if r then for id,a in pairs(r.items) do
                if not s.claims:reserve(token,r.key,id,a,r.free) then s.claims:release(token) return result(false,'CAPACITY_FAILURE') end
            end end
            local ok,err=jobs:create(j)
            if not ok then s.claims:release(token) return result(false,'TASK_WRITE_FAILURE',err) end
            s.tokens[j.id]=token return result(true,j.id)
        end}
end
return M
