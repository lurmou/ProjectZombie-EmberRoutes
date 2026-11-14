-- Transaction candidates only: never publishes, owns claims, or executes a duty.
-- The commit owner must publish a validated candidate together with its other
-- authoritative facts and must fence readers until that publication completes.
local L={FORMAT=1,LIMIT=4096}
local Validate=require 'EmberRoutesProbe/Kernel/Validate'
local Types=require 'EmberRoutesProbe/Kernel/ObligationTypes'
local function id(v) return type(v)=='string' and v~='' and #v<=256 end
local function integer(v) return type(v)=='number' and v==v and v>=0 and v<math.huge and v==math.floor(v) end
local function validRecord(r,key)
    if type(r)~='table' or r.id~=key or not id(r.id)
        or not id(r.npcId) or r.jobId~=nil and not id(r.jobId)
        or not integer(r.revision) or r.revision<1
        or (r.state~='ACTIVE' and r.state~='RECONCILE_REQUIRED' and r.state~='SETTLED') or type(r.data)~='table' then return false end
    if not Types.valid(r) then return false end
    if r.state=='SETTLED' and not Types.settle(r,r.settlement) then return false end
    if r.transfers~=nil then
        if not Validate.dense(r.transfers,16) or not integer(r.transferCount) or r.transferCount<#r.transfers then return false end
        for _,event in ipairs(r.transfers) do
            if type(event)~='table' or not id(event.from) or not id(event.to)
                or not id(event.siteKey) or event.from==event.to then return false end
        end
    end
    return true
end
local function copy(value,seen,depth,budget)
    budget.n=budget.n+1
    if budget.n>budget.limit or depth>16 then error('OBLIGATION_DATA_LIMIT') end
    local t=type(value)
    if t=='string' then if #value>16384 then error('OBLIGATION_DATA_LIMIT') end return value end
    if t=='number' then if value~=value or math.abs(value)==math.huge then error('OBLIGATION_DATA_INVALID') end return value end
    if t=='nil' or t=='boolean' then return value end
    if t~='table' or seen[value] then error('OBLIGATION_DATA_INVALID') end
    seen[value]=true local result={}
    for key,item in pairs(value) do
        if type(key)~='string' and not integer(key) then error('OBLIGATION_DATA_INVALID') end
        result[key]=copy(item,seen,depth+1,budget)
    end
    seen[value]=nil return result
end
local function detached(value,limit) return copy(value,{},0,{n=0,limit=limit or 8192}) end
function L.check(doc)
    if type(doc)~='table' or doc.format~=L.FORMAT or type(doc.byId)~='table' then return false,'OBLIGATION_FORMAT_UNSUPPORTED' end
    local n=0
    for key,r in pairs(doc.byId) do
        n=n+1
        if n>L.LIMIT or not validRecord(r,key) then return false,'OBLIGATION_RECORD_INVALID' end
        local ok=pcall(detached,r) if not ok then return false,'OBLIGATION_RECORD_INVALID' end
    end
    return true
end
function L.fresh() return {format=L.FORMAT,byId={}} end
function L.claimKey(record) return Types.claim(record) end
function L.outstanding(doc,jobId,npcId)
    local ok,why=L.check(doc) if not ok then return nil,why end
    local count=0
    for _,r in pairs(doc.byId) do
        if r.state~='SETTLED' and (not jobId or r.jobId==jobId) and (not npcId or r.npcId==npcId) then count=count+1 end
    end
    return count
end
-- Every operation carries an exact revision; a missing record never settles.
-- A handler may transfer only a furnace duty after its world-site evidence was
-- checked by the caller. Other types retain their original responsible owner.
function L.propose(doc,operations,verifyRetirement)
    local ok,why=L.check(doc) if not ok then return nil,why end
    if not Validate.dense(operations,L.LIMIT) then return nil,'OBLIGATION_INTENT_INVALID' end
    local success,candidate=pcall(detached,doc,8192*(L.LIMIT+1))
    if not success then return nil,'OBLIGATION_DATA_INVALID' end
    local touched={}
    for _,op in ipairs(operations) do
        if type(op)~='table' or not id(op.id) or touched[op.id] then return nil,'OBLIGATION_INTENT_INVALID' end
        touched[op.id]=true
        local old=candidate.byId[op.id]
        if op.action=='CREATE' then
            if old or type(op.record)~='table' or op.record.revision~=1 or op.record.state=='SETTLED'
                or not validRecord(op.record,op.id) then return nil,'OBLIGATION_CREATE_REJECTED' end
            local copied,value=pcall(detached,op.record) if not copied then return nil,'OBLIGATION_DATA_INVALID' end
            candidate.byId[op.id]=value
        elseif not old or old.revision~=op.expectedRevision then return nil,'OBLIGATION_CHANGED'
        elseif op.action=='RETIRE' then
            -- This is only the mechanics: the publishing authority must supply
            -- a verifier for the settled type's Job, claims and dependants.
            if old.state~='SETTLED' or type(verifyRetirement)~='function' then return nil,'OBLIGATION_RETIREMENT_UNPROVEN' end
            local checked,retirable=pcall(verifyRetirement,detached(old))
            if not checked or retirable~=true then return nil,'OBLIGATION_RETIREMENT_UNPROVEN' end
            candidate.byId[op.id]=nil
        elseif old.state=='SETTLED' then return nil,'OBLIGATION_CHANGED'
        elseif op.action=='RECONCILE' then
            old.state='RECONCILE_REQUIRED' old.revision=old.revision+1
            Types.reconcile(old,op)
        elseif op.action=='CONFIRM' then
            if old.state~='RECONCILE_REQUIRED' or not Types.confirm(old,op.evidence) then
                return nil,'OBLIGATION_EVIDENCE_REQUIRED'
            end
            old.state='ACTIVE' old.revision=old.revision+1
        elseif op.action=='SETTLE' then
            if not Types.settle(old,op.evidence) then return nil,'OBLIGATION_EVIDENCE_REQUIRED' end
            local copied,evidence=pcall(detached,op.evidence) if not copied then return nil,'OBLIGATION_DATA_INVALID' end
            old.state='SETTLED' old.settlement=evidence old.revision=old.revision+1
        elseif op.action=='TRANSFER' then
            local event=Types.transfer(old,op)
            if not event then return nil,'OBLIGATION_TRANSFER_REJECTED' end
            old.transfers=old.transfers or {}
            old.transferCount=(old.transferCount or 0)+1
            if #old.transfers>=16 then table.remove(old.transfers,1) end
            old.transfers[#old.transfers+1]=event
            old.npcId=op.npcId old.revision=old.revision+1
        else
            local applied,reason=Types.apply(old,op,detached)
            if not applied then return nil,reason end
            old.revision=old.revision+1
        end
    end
    local valid,reason=L.check(candidate) if not valid then return nil,reason end
    return candidate
end
return L
