-- TEST ONLY: Lua model of Phase 1 transaction order. NOT Java execution.
-- Work-capacity variant: independent set arithmetic and invocation-local work snapshot.
-- Models source order, not Java execution or bridge conformance.
-- Real JobStore/claims callbacks, real LaborJobCommit dispatch; no production fallback.
local M={calls={}}
local function empty(items)
    if type(items)~='table' then return false end
    for _ in pairs(items) do return false end
    return true
end
local function validWork(claims,token,key,c)
    return c.workAmount~=nil and c.token==token and empty(c.items)
        and c.count==0 and claims.owners['cooking:capacity:'..token.taskId]==token and key==token.capacityKey
end
local function setWork(claims,token,key,amount)
    if not token or not claims:valid(token,'cooking:capacity:'..token.taskId) then return 'STALE_CLAIM' end
    if type(key)~='string' or key=='' or type(amount)~='number' or amount~=amount
        or amount<=0 or amount==math.huge then return 'CAPACITY_UNAVAILABLE' end
    if token.capacityKey and token.capacityKey~=key then return 'CAPACITY_TARGET_CHANGED' end
    local b=claims.capacity[key] or {entries={},total=0,count=0}
    local c=b.entries[token.taskId]
    if c and (c.token~=token or c.count~=0 or not empty(c.items) or c.workAmount~=nil and not validWork(claims,token,key,c)) then return 'CAPACITY_UNAVAILABLE' end
    if not c then b.count=b.count+1 c={token=token,items={},count=0,amount=0} end
    b.total=b.total-c.amount+amount c.amount=amount c.workAmount=amount c.token=token
    b.entries[token.taskId]=c claims.capacity[key]=b token.capacityKey=key
end
M.setWork=setWork
function M.install(state,allocate,cleanup)
    local function result(ok,value,evidence) return {ok=ok,result=value,evidence=evidence} end
    local function change(jobs,owner,claims,contracts,clean,id,rev,p,cmd,cancel)
        M.calls[#M.calls+1]=cancel and 'laborCancel' or 'laborMutate'
        local j=jobs:get(id)
        if not j or j.revision~=rev then return result(false,'STALE_REVISION') end
        cmd=cmd or {} cancel=cancel or cmd.state=='CANCELLED' local token=owner.getToken(id)
        if not token then
            if cmd.workCapacity~=nil or cmd.capacity~=nil or #(cmd.addKeys or {})>0 or #(cmd.removeKeys or {})>0 then return result(false,'CLAIM_FAILURE') end
            local patch={payload=p,state=cancel and 'CANCELLED' or cmd.state,effects=cmd.effects,obligations=cmd.obligations}
            local ok,why
            if cancel then ok,why=jobs:cancel(id,rev,patch) else ok,why=jobs:update(id,rev,patch) end
            return result(ok,ok and why or 'TASK_WRITE_FAILURE')
        end
        if claims.tokensByTaskId[id]~=token or token.taskId~=id or token.claimId~=j.claimId then
            return result(false,'CLAIM_FAILURE','STALE_RUNTIME_TOKEN') end
        local work=cmd.workCapacity
        if work==nil then for _,k in ipairs(token.resources) do if claims.owners[k]~=token then return result(false,'CLAIM_FAILURE','STALE_CLAIM') end end end
        for _,k in ipairs(cmd.removeKeys or {}) do if claims.owners[k]~=token then return result(false,'CLAIM_FAILURE','RESOURCE_NOT_OWNED') end end
        if work~=nil then
            if not contracts.get(j.providerType).capacityMutable then return result(false,'INVALID_REQUEST','CAPACITY_MUTATION_UNSUPPORTED') end
            if work~=false then
                if type(work)~='table' or type(work.key)~='string' or work.key=='' or type(work.amount)~='number'
                    or work.amount~=work.amount or work.amount<=0 or work.amount==math.huge then
                    return result(false,'INVALID_REQUEST','CAPACITY_SHAPE_INVALID') end
                for k in pairs(work) do if k~='key' and k~='amount' then return result(false,'INVALID_REQUEST','CAPACITY_SHAPE_INVALID') end end
            end
            local workKey=token.capacityKey if work~=false then workKey=work.key end
            if token.capacityKey and token.capacityKey~=workKey then return result(false,'CAPACITY_FAILURE','CAPACITY_TARGET_CHANGED') end
            local b=claims.capacity[workKey] local c=b and b.entries[id]
            if c and c.workAmount~=nil and not validWork(claims,token,workKey,c) then return result(false,'CAPACITY_FAILURE','CAPACITY_ENTRY_INVALID') end
            if c and (c.token~=token or c.count>0 or not empty(c.items)) then return result(false,'CAPACITY_FAILURE','CAPACITY_UNAVAILABLE') end
        end
        if work~=nil then for _,k in ipairs(token.resources) do if claims.owners[k]~=token then return result(false,'CLAIM_FAILURE','STALE_CLAIM') end end end
        local touched=work~=nil or cmd.capacity~=nil or #(cmd.addKeys or {})>0 or #(cmd.removeKeys or {})>0
        local claimsRevision=claims.revision
        local before={} for _,k in ipairs(token.resources) do before[#before+1]=k end
        local key=token.capacityKey local amounts={}
        local bucket=key and claims.capacity[key]
        for i,a in pairs(bucket and bucket.entries[id] and bucket.entries[id].items or {}) do amounts[i]=a end
        local previous=bucket and bucket.entries[id]
        local workExists=previous and previous.workAmount~=nil
        local workAmount,workKey=previous and previous.workAmount or 0,key
        local function fail(code,why)
            if not touched then return result(false,code,why) end
            for _,k in ipairs(before) do if claims.owners[k] and claims.owners[k]~=token then
                return result(false,'ROLLBACK_FAILURE','RECONCILE_REQUIRED:PARTIAL_RESTORE:'..tostring(why)) end end
            local keep={} for _,k in ipairs(before) do keep[k]=true end
            for _,k in ipairs(token.resources) do if not keep[k] and claims.owners[k]==token then claims.owners[k]=nil end end
            for _,k in ipairs(before) do claims.owners[k]=token end
            token.resources=before
            claims:releaseCapacity(token)
            for i,a in pairs(amounts) do assert(claims:restore(token,key,i,a)) end
            if workExists then
                local err=setWork(claims,token,workKey,workAmount)
                if err then return result(false,'ROLLBACK_FAILURE','RECONCILE_REQUIRED:PARTIAL_RESTORE:'..tostring(why)) end
            end
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
        if cap~=nil and not contracts.get(j.providerType).capacityMutable then return result(false,'INVALID_REQUEST','CAPACITY_MUTATION_UNSUPPORTED') end
        if cap~=nil then
            if cap==false then claims:releaseCapacity(token)
            elseif cap.releaseItemId then claims:releaseCapacity(token,cap.releaseItemId)
            else
                if token.capacityKey and token.capacityKey~=cap.key then claims:releaseCapacity(token) end
                local ok,why=claims:reserveMany(token,cap.key,cap.items,cap.free)
                if not ok then return fail('CAPACITY_FAILURE',why) end
            end
        end
        if work~=nil then
            if not (work==false and not token.capacityKey) and not claims:valid(token,'cooking:capacity:'..id) then return fail('CAPACITY_FAILURE','STALE_CLAIM') end
            if work==false then claims:releaseCapacity(token)
            else local why=setWork(claims,token,work.key,work.amount) if why then return fail('CAPACITY_FAILURE',why) end end
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
            s.tokens[j.id]=token s.cookingTokens[j.id]=token return result(true,j.id)
        end}
end
return M
