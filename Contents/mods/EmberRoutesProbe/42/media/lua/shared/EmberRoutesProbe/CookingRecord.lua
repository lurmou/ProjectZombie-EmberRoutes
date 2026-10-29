-- COOKING is an ordinary shared Job. Claims and furnace duty outlive its Session.
local Policy=require 'EmberRoutesProbe/CookingPolicy'
local Fluids=require 'EmberRoutesProbe/CraftFluids'
local R={limit=32,bindingLimit=64}
local phases={PREPARING=true,FETCHING=true,FILLING=true,ADDING=true,SEASONING=true,HEATING=true,
    UNLOADING=true,DELIVERING=true,RETURNING=true,SETTLED=true,RECONCILE=true}
local kinds={TRANSFER=true,ADD=true,CRAFT=true,TOGGLE=true,WATER=true,FLUID=true}
local states={PREPARING=true,RUNNING=true,STOPPING=true,SUSPENDED=true,SETTLING=true,
    DONE=true,CANCELLED=true,RECONCILE_REQUIRED=true}
local function id(v) return type(v)=='string' and v~='' and #v<=256 end
local function integer(v) return Policy.finite(v) and v==math.floor(v) end
local function itemId(v) return type(v)=='number' and v==v and math.abs(v)<9007199254740992 and v==math.floor(v) end
local function dense(t,limit)
    if type(t)~='table' or #t>limit then return false end
    local n=0 for k in pairs(t) do if not integer(k) or k<1 or k>#t then return false end n=n+1 end
    return n==#t
end
local function receiptValid(p)
    local a=p.attempt local r=a and a.receipt
    if type(r)~='table' or r.attemptId~=a.id or r.observed~=true then return false end
    if a.state=='ABORTED' then return r.unchanged==true end
    if a.kind=='WATER' then
        local s=a.spec
        return s and #a.itemIds==1 and r.itemId==a.itemIds[1] and r.sourceKey==s.sourceKey
            and r.nativeObserved==true and r.stopped==true and type(r.partial)=='boolean'
            and type(r.exhausted)=='boolean' and Fluids.equal(r.before,s.before)
            and Policy.finite(s.maximum) and Policy.finite(r.added) and r.added<=s.maximum+Policy.epsilon
            and Fluids.waterAdded(r.before,r.after,r.added)
            and (s.mode~='PLUMBED' or Fluids.equal(r.sourceBefore,s.sourceBefore)
                and (r.added<=Policy.epsilon and Fluids.equal(r.sourceBefore,r.sourceAfter)
                    or Fluids.consumed(r.sourceBefore,r.sourceAfter,r.added))) or false
    elseif a.kind=='FLUID' then
        local s=a.spec
        return s and #a.itemIds==2 and r.sourceId==a.itemIds[1] and r.targetId==a.itemIds[2]
            and r.nativeObserved==true and r.stopped==true and type(r.partial)=='boolean'
            and Policy.finite(s.maximum) and Policy.finite(r.moved) and r.moved<=s.maximum+Policy.epsilon
            and Fluids.equal(s.sourceBefore,r.sourceBefore) and Fluids.equal(s.targetBefore,r.targetBefore)
            and Fluids.transferred(r.sourceBefore,r.sourceAfter,r.targetBefore,r.targetAfter,r.moved) or false
    elseif a.kind=='TRANSFER' then
        if not itemId(r.itemId) or not id(r.fromId) or not id(r.toId) or r.fromId==r.toId
            or r.sourceAbsent~=true or r.destinationPresent~=true then return false end
        for _,key in ipairs(a.itemIds) do if key==r.itemId then return true end end
        return false
    elseif a.kind=='ADD' then
        if not itemId(r.baseBeforeId) or not itemId(r.baseAfterId) or not itemId(r.ingredientId)
            or r.baseBeforeId==r.ingredientId or r.baseKnown~=true
            or not Policy.finite(r.beforeAmount) or not Policy.finite(r.afterAmount)
            or r.beforeAmount<=r.afterAmount+Policy.epsilon then return false end
        local base,ingredient=false,false
        for _,key in ipairs(a.itemIds) do
            if key==r.baseBeforeId then base=true end
            if key==r.ingredientId then ingredient=true end
        end
        if not base or not ingredient then return false end
        for _,asset in ipairs(p.assets) do if asset.id==r.baseAfterId then return true end end
        return false
    elseif a.kind=='TOGGLE' then
        -- Historical proof remains valid after the furnace obligation is settled.
        return r.siteKey==a.siteKey and type(r.expectedActive)=='boolean'
            and r.actualActive==r.expectedActive and r.controlled==true
    elseif a.kind=='CRAFT' then
        if r.inputsObserved~=true or not dense(r.outputIds,R.limit) or #r.outputIds==0 then return false end
        local seen={}
        for _,key in ipairs(r.outputIds) do
            if not itemId(key) or seen[key] then return false end seen[key]=true
            local found=false
            for _,asset in ipairs(p.assets) do if asset.id==key then found=true break end end
            if not found then return false end
        end
        if a.spec and a.spec.flows then
            if not dense(a.spec.flows,R.limit) or not dense(r.flows,R.limit) or #a.spec.flows~=#r.flows then return false end
            local seenFlows={}
            for i,before in ipairs(a.spec.flows) do
                local flow=r.flows[i]
                if type(before)~='table' or type(flow)~='table' or seenFlows[before.itemId]
                    or flow.itemId~=before.itemId or flow.amount~=before.amount
                    or not Fluids.equal(flow.before,before.snapshot)
                    or not Fluids.consumed(flow.before,flow.after,flow.amount) then return false end
                local found=false for _,key in ipairs(a.itemIds) do if key==flow.itemId then found=true end end
                if not found then return false end seenFlows[before.itemId]=true
            end
        end
        return true
    end
    return false
end
local function copy(value,seen,budget,depth)
    budget.n=budget.n+1
    if budget.n>8192 or depth>16 then error('COOKING_DATA_LIMIT') end
    if type(value)~='table' then
        local t=type(value)
        if t=='nil' or t=='boolean' or t=='string' and #value<=16384
            or t=='number' and value==value and math.abs(value)<math.huge then return value end
        error('COOKING_DATA_UNSERIALIZABLE')
    end
    if seen[value] then error('COOKING_DATA_CYCLE') end
    seen[value]=true local result={}
    for k,v in pairs(value) do
        if type(k)~='string' and not integer(k) then error('COOKING_KEY_INVALID') end
        result[k]=copy(v,seen,budget,depth+1)
    end
    seen[value]=nil return result
end
function R.copy(value) return copy(value,{},{n=0},0) end
local function equal(a,b,depth)
    if type(a)~=type(b) or depth>16 then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k],depth+1) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
function R.valid(job)
    if type(job)~='table' or job.providerType~='COOKING' or not id(job.id) or not id(job.npcId)
        or not id(job.scopeId) or not states[job.state] or not integer(job.revision) or job.revision<1 or job.revision>1e12
        or (job.effects~='KNOWN' and job.effects~='UNKNOWN') or type(job.obligations)~='table' then return false end
    local p=job.payload
    if type(p)~='table' or p.format~=1 or not phases[p.phase] or not id(p.profileId)
        or not integer(p.sequence) or p.sequence>1e12 or not Policy.finite(p.quota) or p.quota<=0
        or not Policy.finite(p.target) or p.target<=0 or p.quota+Policy.epsilon<p.target
        or (p.source~='AUTO' and p.source~='REQUEST') or not id(p.sourceId)
        or not dense(p.claims,R.limit) or not dense(p.assets,R.limit) then return false end
    if p.expected~=nil and not Policy.finite(p.expected) then return false end
    if p.mealBatch~=nil and type(p.mealBatch)~='boolean' then return false end
    if p.capacity then
        local cap=p.capacity
        if type(cap)~='table' or not id(cap.endpointId) or not Policy.finite(cap.amount) or cap.amount<=0
            or not job.obligations.storage then return false end
    elseif job.obligations.storage then return false end
    if p.stopProof and (type(p.stopProof)~='table' or p.stopProof.npcId~=job.npcId
        or p.stopProof.bodyStopped~=true or not integer(p.stopProof.sequence)) then return false end
    if p.spiceCount~=nil and (not integer(p.spiceCount) or p.spiceCount>Policy.maxSpices) then return false end
    local keys,assets={},{}
    for _,key in ipairs(p.claims) do
        if not id(key) or keys[key] then return false end
        if not string.match(key,'^item:%-?%d+$') and not string.match(key,'^cooking:[%w_:%-]+$')
            and not string.match(key,'^craft%-surface:[%w_:%-]+$') then return false end
        keys[key]=true
    end
    for _,a in ipairs(p.assets) do
        if type(a)~='table' or not itemId(a.id) or assets[a.id] or not id(a.fullType)
            or (a.custody~='SOURCE' and a.custody~='HELD' and a.custody~='STATION'
                and a.custody~='DELIVERED' and a.custody~='RETURNED' and a.custody~='CONSUMED'
                and a.custody~='WORLD' and a.custody~='UNKNOWN') then return false end
        if a.role~=nil and a.role~='INPUT' and a.role~='TOOL' and a.role~='OUTPUT' then return false end
        if a.role=='OUTPUT' and a.custody=='DELIVERED' and not Policy.finite(a.effective) then return false end
        if a.raw~=nil and not Policy.finite(a.raw) or a.effective~=nil and not Policy.finite(a.effective) then return false end
        local retained=a.custody~='DELIVERED' and a.custody~='RETURNED' and a.custody~='CONSUMED'
        if retained~=(keys['item:'..a.id]==true) then return false end
        assets[a.id]=true
    end
    for key in pairs(keys) do
        if string.sub(key,1,5)=='item:' and not assets[tonumber(string.sub(key,6))] then return false end
    end
    if (p.capacity~=nil)~=(keys['cooking:capacity:'..job.id]==true) then return false end
    local fixed=p.fixed
    if p.liquidInputs then
        if not p.evolved or not dense(p.liquidInputs,8) then return false end
        local seen={}
        for _,input in ipairs(p.liquidInputs) do
            if type(input)~='table' or not itemId(input.id) or seen[input.id] or not assets[input.id]
                or not id(input.fullType) or input.sourceId~=nil and not id(input.sourceId) then return false end
            seen[input.id]=true
            for _,asset in ipairs(p.assets) do if asset.id==input.id
                and (asset.fullType~=input.fullType or asset.role~='TOOL') then return false end end
        end
    end
    if p.raw then
        local raw=p.raw
        if fixed or p.evolved or type(raw)~='table' or not itemId(raw.id) or not assets[raw.id]
            or not id(raw.fullType) or p.profileId~='heat:'..raw.fullType
            or raw.sourceId~=nil and not id(raw.sourceId) then return false end
    end
    if fixed then
        if type(fixed)~='table' or fixed.recipeId~=p.profileId or type(fixed.signature)~='string'
            or #fixed.signature==0 or #fixed.signature>16384 or not dense(fixed.inputs,16) or #fixed.inputs==0
            or fixed.craftSequence~=nil and (not integer(fixed.craftSequence) or fixed.craftSequence<1
                or fixed.craftSequence>p.sequence+1) then return false end
        local seen={}
        for _,input in ipairs(fixed.inputs) do
            if type(input)~='table' or not itemId(input.id) or seen[input.id] or not assets[input.id]
                or not integer(input.slot) or input.slot>63 or type(input.keep)~='boolean'
                or input.sourceId~=nil and not id(input.sourceId) then return false end
            seen[input.id]=true
        end
    end
    local evolved=p.evolved
    if evolved then
        if fixed or type(evolved)~='table' or evolved.recipeId~=p.profileId or not assets[evolved.originId]
            or type(evolved.signature)~='string' or #evolved.signature==0 or #evolved.signature>2048
            or not dense(evolved.inputs,16) or not integer(evolved.cursor) or evolved.cursor<1
            or evolved.cursor>#evolved.inputs+1 or not Policy.finite(evolved.target) or evolved.target<=0
            or evolved.target>p.quota+Policy.epsilon
            or not Policy.finite(evolved.minimum) or evolved.minimum<=0 or not Policy.finite(evolved.mainEffective)
            or not integer(evolved.baseSequence) or evolved.baseSequence>p.sequence
            or type(evolved.completed)~='boolean' or evolved.completed and evolved.mainEffective+Policy.epsilon<evolved.minimum
            or evolved.activeSequence~=nil and (not integer(evolved.activeSequence) or evolved.activeSequence<1
                or evolved.activeSequence>p.sequence+1) then return false end
        if evolved.originSourceId~=nil and not id(evolved.originSourceId)
            or evolved.provenance~=nil and type(evolved.provenance)~='boolean'
            or evolved.finalUnits~=nil and type(evolved.finalUnits)~='boolean' then return false end
        local seen={[evolved.originId]=true}
        for _,input in ipairs(evolved.inputs) do
            if type(input)~='table' or not itemId(input.id) or not assets[input.id] or seen[input.id]
                or type(input.spice)~='boolean' or input.sourceId~=nil and not id(input.sourceId) then return false end
            seen[input.id]=true
        end
        if evolved.baseSequence>0 then
            if not dense(p.bindings,R.bindingLimit) then return false end
            local found=false
            for _,binding in ipairs(p.bindings or {}) do
                if binding.sequence==evolved.baseSequence and binding.kind=='ADD' then found=true end
            end
            if not found then return false end
        end
    end
    if p.bindings~=nil then
        if not dense(p.bindings,R.bindingLimit) then return false end
        local previous=0
        for _,binding in ipairs(p.bindings) do
            if type(binding)~='table' or not integer(binding.sequence) or binding.sequence<=previous
                or binding.sequence>p.sequence or binding.attemptId~=job.id..':'..binding.sequence
                or (binding.kind~='ADD' and binding.kind~='CRAFT') or not dense(binding.outputIds,R.limit)
                or #binding.outputIds==0 or binding.kind=='ADD' and #binding.outputIds~=1 then return false end
            local seen={}
            for _,key in ipairs(binding.outputIds) do
                if not itemId(key) or seen[key] or not assets[key] then return false end seen[key]=true
            end
            previous=binding.sequence
        end
    end
    local attempt=p.attempt
    if attempt~=nil then
        if p.sequence<1 or type(attempt)~='table' or attempt.id~=job.id..':'..p.sequence or not kinds[attempt.kind]
            or (attempt.state~='PREPARED' and attempt.state~='COMMITTING' and attempt.state~='APPLIED' and attempt.state~='ABORTED'
                and attempt.state~='UNKNOWN') or not dense(attempt.itemIds,R.limit) then return false end
        if attempt.spec~=nil and type(attempt.spec)~='table' or attempt.dispatched~=nil and type(attempt.dispatched)~='boolean' then return false end
        local used={}
        for _,key in ipairs(attempt.itemIds) do if not itemId(key) or used[key] or not assets[key] then return false end used[key]=true end
        if (attempt.kind=='TRANSFER' or attempt.kind=='WATER') and #attempt.itemIds~=1
            or (attempt.kind=='ADD' or attempt.kind=='FLUID') and #attempt.itemIds~=2
            or attempt.kind=='CRAFT' and #attempt.itemIds==0 then return false end
        if attempt.kind=='TOGGLE' then
            if #attempt.itemIds~=0 or not id(attempt.siteKey) or string.sub(attempt.siteKey,1,8)~='cooking:' then return false end
            if attempt.state~='APPLIED' and attempt.state~='ABORTED' and (not p.duty or p.duty.siteKey~=attempt.siteKey) then return false end
        elseif attempt.siteKey~=nil then return false end
        if (attempt.state=='COMMITTING' or attempt.state=='UNKNOWN') and job.effects~='UNKNOWN' then return false end
        if (attempt.state=='APPLIED' or attempt.state=='ABORTED') and (job.effects~='KNOWN' or not receiptValid(p)) then return false end
    elseif p.sequence~=0 then return false end
    local water=p.waterSource
    if water then
        if type(water)~='table' or not id(water.id) or water.key~='cooking:water:'..water.id
            or not keys[water.key] or not job.obligations.water or type(water.position)~='table' then return false end
        for _,axis in ipairs({'x','y','z'}) do
            if not integer(water.position[axis]) or math.abs(water.position[axis])>10000000 then return false end
        end
        if water.backing then
            local b=water.backing
            if type(b)~='table' or not id(b.id) or b.id==water.id or b.key~='cooking:water:'..b.id
                or not keys[b.key] or type(b.position)~='table' then return false end
            for _,axis in ipairs({'x','y','z'}) do
                if not integer(b.position[axis]) or math.abs(b.position[axis])>10000000 then return false end
            end
        end
    elseif job.obligations.water then return false end
    for key in pairs(keys) do
        if string.sub(key,1,14)=='cooking:water:' and (not water or water.key~=key
            and (not water.backing or water.backing.key~=key)) then return false end
    end
    local station=p.station
    if station then
        if type(station)~='table' or not id(station.id) or not id(station.leaseId)
            or station.siteKey~='craft-surface:'..station.id or not keys[station.siteKey]
            or station.ownerId~=job.npcId or not job.obligations.station
            or (station.state~='RESERVED' and station.state~='ACQUIRING' and station.state~='ACQUIRED'
                and station.state~='RELEASED') or type(station.position)~='table' then return false end
        for _,axis in ipairs({'x','y','z'}) do
            if not integer(station.position[axis]) or math.abs(station.position[axis])>10000000 then return false end
        end
    elseif job.obligations.station then return false end
    for key in pairs(keys) do
        if string.sub(key,1,14)=='craft-surface:' and (not station or station.siteKey~=key) then return false end
    end
    local duty=p.duty
    if duty~=nil then
        if type(duty)~='table' or not id(duty.id) or not id(duty.siteKey) or not keys[duty.siteKey]
            or string.sub(duty.siteKey,1,8)~='cooking:' or duty.ownerId~=job.npcId
            or not integer(duty.revision) or duty.revision<1
            or type(duty.originalActive)~='boolean' or type(duty.openedByJob)~='boolean'
            or duty.lastActive~=nil and type(duty.lastActive)~='boolean'
            or duty.shutdownObserved~=nil and type(duty.shutdownObserved)~='boolean'
            or duty.originalActive and duty.openedByJob
            or (duty.state~='RESERVED' and duty.state~='HEATING' and duty.state~='TRANSFER_PENDING'
                and duty.state~='STOP_REQUIRED' and duty.state~='OBSERVATION_REQUIRED') then return false end
        if not job.obligations.furnace then return false end
        if duty.endpointId~=nil or duty.position~=nil then
            if not id(duty.endpointId) or duty.siteKey~='cooking:'..duty.endpointId or type(duty.position)~='table' then return false end
            for _,axis in ipairs({'x','y','z'}) do
                if not integer(duty.position[axis]) or math.abs(duty.position[axis])>10000000 then return false end
            end
        end
    elseif job.obligations.furnace then return false end
    local heat=p.heat
    if heat then
        if type(heat)~='table' or heat.format~=1 or not dense(heat.itemIds,16) or #heat.itemIds==0
            or type(heat.closed)~='boolean' or type(heat.aborted)~='boolean'
            or heat.reason~=nil and not id(heat.reason) then return false end
        local seen={}
        for _,key in ipairs(heat.itemIds) do if not itemId(key) or not assets[key] or seen[key] then return false end seen[key]=true end
    end
    if job.state=='DONE' or job.state=='CANCELLED' or p.phase=='SETTLED' then
        if (job.state~='DONE' and job.state~='CANCELLED') or p.phase~='SETTLED' or job.effects~='KNOWN'
            or #p.claims>0 or p.duty or attempt and attempt.state~='APPLIED' and attempt.state~='ABORTED' then return false end
        for _ in pairs(job.obligations) do return false end
    end
    return true
end
function R.new(jobId,npcId,scope,profile,source,sourceId,target,quota)
    local j={id=jobId,npcId=npcId,scopeId=scope,providerType='COOKING',revision=1,
        state='PREPARING',effects='KNOWN',obligations={},payload={format=1,phase='PREPARING',
        profileId=profile,source=source,sourceId=sourceId,sequence=0,target=target,quota=quota,claims={},assets={}}}
    if not R.valid(j) then return nil,'COOKING_RECORD_INVALID' end return j
end
function R.begin(job,kind,itemIds,spec)
    if not R.valid(job) or not kinds[kind] or job.effects~='KNOWN' or job.payload.phase=='SETTLED'
        or job.payload.attempt and job.payload.attempt.state~='APPLIED' and job.payload.attempt.state~='ABORTED' then return nil,'ATTEMPT_RETAINED' end
    local nextJob=R.copy(job) local p=nextJob.payload
    p.sequence=p.sequence+1 p.attempt={id=job.id..':'..p.sequence,kind=kind,state='PREPARED',itemIds=itemIds}
    if kind=='TOGGLE' then p.attempt.siteKey=p.duty and p.duty.siteKey end
    if spec then p.attempt.spec=R.copy(spec) p.attempt.dispatched=false end
    if not R.valid(nextJob) then return nil,'COOKING_ATTEMPT_INVALID' end return nextJob
end
-- Only an observed unchanged PREPARED operation can be cancelled as no-effect.
-- A COMMITTING/UNKNOWN operation never becomes retryable through this API.
function R.abort(job,attemptId)
    if not R.valid(job) or not job.payload.attempt or job.payload.attempt.id~=attemptId
        or job.payload.attempt.state~='PREPARED' or job.effects~='KNOWN' then return nil,'ATTEMPT_RETAINED' end
    local j=R.copy(job) j.payload.attempt.state='ABORTED'
    j.payload.attempt.receipt={attemptId=attemptId,observed=true,unchanged=true}
    return j
end
-- Must be persisted BEFORE calling vanilla. A crash cannot authorize replay.
function R.committing(job,attemptId)
    if not R.valid(job) or not job.payload.attempt or job.payload.attempt.id~=attemptId
        or job.payload.attempt.state~='PREPARED' or job.effects~='KNOWN' then return nil,'STALE_COOKING_ATTEMPT' end
    local j=R.copy(job) j.payload.attempt.state='COMMITTING' j.effects='UNKNOWN' return j
end
function R.confirm(job,attemptId,receipt)
    if not R.valid(job) or not job.payload.attempt or job.payload.attempt.id~=attemptId
        or (job.payload.attempt.state~='COMMITTING' and job.payload.attempt.state~='UNKNOWN') then
        return nil,'STALE_COOKING_ATTEMPT'
    end
    local j=R.copy(job) j.payload.attempt.state='APPLIED' j.payload.attempt.receipt=R.copy(receipt) j.effects='KNOWN'
    local p=j.payload local kind=p.attempt.kind
    if kind=='ADD' or kind=='CRAFT' then
        p.bindings=p.bindings or {}
        p.bindings[#p.bindings+1]={sequence=p.sequence,attemptId=attemptId,kind=kind,
            outputIds=kind=='ADD' and {receipt.baseAfterId} or R.copy(receipt.outputIds)}
    end
    if not R.valid(j) then return nil,'COOKING_EFFECT_NOT_OBSERVED' end return j
end
-- References resolve only to an observed original, never an inventory type match.
-- Pure, exact transfer contract. Never transfer an inventory still on the donor.
function R.handoff(job,npcId)
    if not R.valid(job) or not id(npcId) or npcId==job.npcId or job.state~='SUSPENDED'
        or job.effects~='KNOWN' or not job.payload.duty or not job.payload.heat
        or job.payload.station or job.payload.waterSource then return nil,'COOKING_HANDOFF_UNSAFE' end
    local p=job.payload local proof=p.stopProof local a=p.attempt
    if not proof or proof.sequence~=p.sequence or not p.duty.position
        or p.duty.state=='OBSERVATION_REQUIRED' or p.duty.state=='TRANSFER_PENDING'
        or a and a.state~='APPLIED' and a.state~='ABORTED' then return nil,'COOKING_STOP_PROOF_REQUIRED' end
    for _,asset in ipairs(p.assets) do
        if asset.custody=='HELD' or asset.custody=='WORLD' or asset.custody=='UNKNOWN' then return nil,'DONOR_ORIGINAL_RETAINED' end
    end
    local j=R.copy(job) j.npcId=npcId j.revision=j.revision+1
    j.payload.stopProof=nil
    j.payload.duty.ownerId=npcId j.payload.duty.revision=j.payload.duty.revision+1
    return j
end
function R.transferValid(before,after)
    local expected=R.handoff(before,after.npcId)
    return expected~=nil and R.valid(after) and equal(expected,after,0)
end
function R.outputReference(job,sequence,ordinal)
    if not R.valid(job) or not integer(sequence) or not integer(ordinal) or ordinal<1 then return nil end
    for _,binding in ipairs(job.payload.bindings or {}) do
        if binding.sequence==sequence and binding.outputIds[ordinal] then
            return {sequence=sequence,ordinal=ordinal,attemptId=binding.attemptId}
        end
    end
end
function R.resolveOutput(job,reference)
    if not R.valid(job) or job.effects~='KNOWN' or type(reference)~='table' then return nil,'OUTPUT_UNAVAILABLE' end
    local ref=R.outputReference(job,reference.sequence,reference.ordinal)
    if not ref or ref.attemptId~=reference.attemptId then return nil,'OUTPUT_REFERENCE_CHANGED' end
    for _,binding in ipairs(job.payload.bindings or {}) do if binding.sequence==ref.sequence then
        local key=binding.outputIds[ref.ordinal]
        for _,asset in ipairs(job.payload.assets) do if asset.id==key then
            if asset.custody=='CONSUMED' or asset.custody=='DELIVERED' or asset.custody=='RETURNED' then
                return nil,'OUTPUT_UNAVAILABLE'
            end
            return R.copy(asset)
        end end
    end end
    return nil,'OUTPUT_UNAVAILABLE'
end
function R.transition(before,after)
    if not R.valid(before) or not R.valid(after) then return false end
    for _,key in ipairs({'id','npcId','scopeId','providerType'}) do if before[key]~=after[key] then return false end end
    local a,b=before.payload,after.payload
    local previousLiquids,nextLiquids=a.liquidInputs or {},b.liquidInputs or {}
    if #nextLiquids<#previousLiquids or #nextLiquids>#previousLiquids+1 then return false end
    for i,row in ipairs(previousLiquids) do if not equal(row,nextLiquids[i],0) then return false end end
    if #nextLiquids>#previousLiquids and (before.effects~='KNOWN' or not a.evolved or a.evolved.completed) then return false end
    if a.mealBatch~=b.mealBatch then return false end
    if a.raw and not equal(a.raw,b.raw,0) or not a.raw and b.raw and (a.sequence~=0 or a.fixed or a.evolved) then return false end
    if before.effects=='UNKNOWN' and after.effects=='UNKNOWN' and not equal(a.capacity,b.capacity,0) then return false end
    if a.heat then
        if not b.heat or not equal(a.heat.itemIds,b.heat.itemIds,0) or a.heat.format~=b.heat.format
            or a.heat.closed and not b.heat.closed or a.heat.aborted and not b.heat.aborted then return false end
    elseif b.heat and before.effects~='KNOWN' then return false end
    if a.duty and b.duty then
        for _,key in ipairs({'id','siteKey','ownerId','originalActive','endpointId','position'}) do
            if not equal(a.duty[key],b.duty[key],0) then return false end
        end
        if a.duty.openedByJob and not b.duty.openedByJob or a.duty.shutdownObserved and not b.duty.shutdownObserved then return false end
    elseif a.duty then
        local attempt=a.attempt local receipt=attempt and attempt.receipt
        local shutdown=a.duty.shutdownObserved or attempt and attempt.kind=='TOGGLE' and attempt.state=='APPLIED'
            and receipt and receipt.siteKey==a.duty.siteKey and receipt.actualActive==false
        if before.effects~='KNOWN' or a.duty.lastActive~=false or a.duty.state=='OBSERVATION_REQUIRED'
            or a.duty.state=='TRANSFER_PENDING' or a.duty.openedByJob and not shutdown then return false end
        for _,asset in ipairs(b.assets) do if asset.custody=='STATION' then return false end end
    elseif b.duty and (before.effects~='KNOWN' or b.duty.state~='RESERVED' or b.duty.openedByJob) then return false end
    if a.evolved then
        local x,y=a.evolved,b.evolved
        if not y then return false end
        for _,key in ipairs({'recipeId','signature','originId','originSourceId','provenance','finalUnits','inputs','target','minimum'}) do
            if not equal(x[key],y[key],0) then return false end
        end
        if y.cursor<x.cursor or y.cursor>x.cursor+1 or x.completed and not y.completed then return false end
        local changedBase=x.baseSequence~=y.baseSequence
        if changedBase then
            local attempt=b.attempt local row=x.inputs[x.cursor]
            if not row or x.activeSequence~=y.baseSequence or not attempt or attempt.kind~='ADD'
                or attempt.state~='APPLIED' or b.sequence~=y.baseSequence or attempt.itemIds[2]~=row.id
                or y.cursor~=x.cursor+1 or y.activeSequence~=nil then return false end
            if row.spice and y.mainEffective~=x.mainEffective then return false end
        elseif y.mainEffective~=x.mainEffective then return false end
        if x.activeSequence~=y.activeSequence then
            if y.activeSequence then
                if x.activeSequence or y.activeSequence~=a.sequence+1 or before.effects~='KNOWN' then return false end
            elseif not changedBase and x.activeSequence~=a.sequence+1 and (not a.attempt
                or a.attempt.state~='ABORTED' or a.attempt.kind~='ADD' or a.sequence~=x.activeSequence) then return false end
        end
        if x.activeSequence and y.cursor~=x.cursor and not changedBase then return false end
    elseif b.evolved and (a.sequence~=0 or a.fixed) then return false end
    if a.waterSource and b.waterSource then
        if not equal(a.waterSource,b.waterSource,0) then return false end
    elseif a.waterSource and after.effects~='KNOWN' then return false
    elseif b.waterSource and before.effects~='KNOWN' then return false end
    if a.fixed then
        if not b.fixed or not equal(a.fixed.inputs,b.fixed.inputs,0) or a.fixed.signature~=b.fixed.signature
            or a.fixed.recipeId~=b.fixed.recipeId then return false end
        if a.fixed.craftSequence~=b.fixed.craftSequence then
            if b.fixed.craftSequence~=b.sequence+1 or before.effects~='KNOWN'
                or a.fixed.craftSequence and (not a.attempt or a.attempt.kind~='CRAFT'
                    or a.attempt.state~='ABORTED' or a.attempt.id~=before.id..':'..a.fixed.craftSequence) then return false end
        end
    elseif b.fixed and (a.sequence~=0 or #a.assets>0) then return false end
    if a.station and b.station then
        for _,key in ipairs({'id','leaseId','siteKey','ownerId','position'}) do
            if not equal(a.station[key],b.station[key],0) then return false end
        end
        local rank={RESERVED=1,ACQUIRING=2,ACQUIRED=3,RELEASED=4}
        if rank[b.station.state]<rank[a.station.state] then return false end
    elseif a.station and (a.station.state~='RELEASED' or after.effects~='KNOWN') then return false
    elseif not a.station and b.station and (before.effects~='KNOWN' or b.station.state~='RESERVED') then return false end
    local oldBindings,newBindings=a.bindings or {},b.bindings or {}
    if #newBindings<#oldBindings or #newBindings>#oldBindings+1 then return false end
    for i,binding in ipairs(oldBindings) do if not equal(binding,newBindings[i],0) then return false end end
    if #newBindings>#oldBindings then
        local attempt=b.attempt local binding=newBindings[#newBindings]
        if not a.attempt or (a.attempt.state~='COMMITTING' and a.attempt.state~='UNKNOWN')
            or not attempt or attempt.state~='APPLIED' or binding.sequence~=b.sequence
            or binding.attemptId~=attempt.id or binding.kind~=attempt.kind then return false end
        local outputs=attempt.kind=='ADD' and {attempt.receipt.baseAfterId} or attempt.receipt.outputIds
        if not equal(binding.outputIds,outputs,0) then return false end
    end
    for _,key in ipairs({'profileId','source','sourceId','target','quota','format'}) do if a[key]~=b[key] then return false end end
    if b.sequence==a.sequence+1 then
        return before.effects=='KNOWN' and (not a.attempt or a.attempt.state=='APPLIED' or a.attempt.state=='ABORTED')
            and b.attempt~=nil and b.attempt.state=='PREPARED' and after.effects=='KNOWN'
    end
    if b.sequence~=a.sequence or (a.attempt==nil)~=(b.attempt==nil) then return false end
    if not a.attempt then return true end
    if a.attempt.id~=b.attempt.id or a.attempt.kind~=b.attempt.kind or a.attempt.siteKey~=b.attempt.siteKey
        or #a.attempt.itemIds~=#b.attempt.itemIds or not equal(a.attempt.spec,b.attempt.spec,0) then return false end
    for i,key in ipairs(a.attempt.itemIds) do if b.attempt.itemIds[i]~=key then return false end end
    local from,to=a.attempt.state,b.attempt.state
    if a.attempt.dispatched==true and b.attempt.dispatched~=true then return false end
    if after.effects=='UNKNOWN' then
        -- An irreversible call may produce new originals before throwing. Keep
        -- every old declaration and append observed outputs for reconciliation.
        for i,asset in ipairs(a.assets) do if not equal(asset,b.assets[i],0) then return false end end
        local keys={} for _,key in ipairs(b.claims) do keys[key]=true end
        for _,key in ipairs(a.claims) do if not keys[key] then return false end end
        for _,asset in ipairs(b.assets) do
            if not keys['item:'..asset.id] and asset.custody~='CONSUMED' and asset.custody~='RETURNED'
                and asset.custody~='DELIVERED' then return false end
        end
    end
    if from==to then
        if from=='PREPARED' then return equal(a.attempt.receipt,b.attempt.receipt,0) end
        return equal(a.attempt,b.attempt,0)
    end
    return from=='PREPARED' and (to=='COMMITTING' or to=='ABORTED' or to=='UNKNOWN')
        or (from=='COMMITTING' or from=='UNKNOWN') and (to=='APPLIED' or to=='UNKNOWN')
end
return R
