-- Policies for the four existing responsibility types. No publishing or claims.
local V=require 'EmberRoutesProbe/Kernel/Validate'
local T={}
local function id(v) return type(v)=='string' and v~='' and #v<=256 end
local function integer(v) return type(v)=='number' and v==v and v>=0 and v<math.huge and v==math.floor(v) end
local function itemValid(r) return id(r.jobId) and V.itemId(r.data.itemId)
    and (r.data.sourceId==nil or id(r.data.sourceId)) end
local function itemSettle(r,e)
    if e.itemId~=r.data.itemId or not id(e.destinationId) then return false end
    if e.kind=='CRAFT_CONSUMED' then
        return r.type=='CARRIED_ITEM' and r.data.purpose=='CRAFT_MATERIAL' and e.destinationId=='CRAFT' and id(e.attemptId)
    end
    if e.kind=='CONSUMED' then
        return r.type=='CARRIED_ITEM' and r.data.purpose=='SELF_CARE' and e.destinationId==r.data.sourceId
            and (e.consumptionKind=='EAT' or e.consumptionKind=='DRINK' or e.consumptionKind=='MEDICAL')
            and id(e.attemptId) and V.dense(e.outputs,512)
    end
    if e.kind=='UNCHANGED' then return r.data.sourceId~=nil and e.destinationId==r.data.sourceId
        and e.originalPresent==true and id(e.attemptId) end
    return e.originalPresent==true and id(e.attemptId)
end
local function itemConfirm(r,e) return e.itemId==r.data.itemId and e.originalPresent==true end
local handlers={
    CARRIED_ITEM={valid=itemValid,settle=itemSettle,confirm=itemConfirm,claim=function(r) return 'item:'..tostring(r.data.itemId) end},
    DELIVERY_RETURN={valid=itemValid,settle=itemSettle,confirm=itemConfirm,claim=function(r) return 'item:'..tostring(r.data.itemId) end},
    FURNACE_DUTY={valid=function(r) return id(r.jobId) and id(r.data.siteKey) end,
        settle=function(r,e) return e.siteKey==r.data.siteKey and e.inactive==true and e.foodClear==true
            and type(e.shutdownRequired)=='boolean' and (not e.shutdownRequired or e.shutdownObserved==true) end,
        confirm=function(r,e) return e.siteKey==r.data.siteKey and e.siteObserved==true end,
        claim=function(r) return r.data.siteKey end},
    TOOL_CUSTODY={valid=function(r)
        local d=r.data local states={RESERVED=true,HELD=true,PENDING_RETURN=true,RECONCILE_REQUIRED=true}
        if r.jobId~=nil or not V.itemId(d.itemId) or not id(d.role) or not states[d.custodyState]
            or not integer(d.sequence) or not id(d.claimId) or not string.match(d.claimId,'^'..r.id:gsub('([^%w])','%%%1')..':c%d+$')
            or d.sourceId~=nil and not id(d.sourceId) or d.activeJobId~=nil and not id(d.activeJobId)
            or d.returnJobId~=nil and not id(d.returnJobId) then return false end
        if d.sourceId==nil and d.initialInventory~=true then return false end
        if r.state=='RECONCILE_REQUIRED' and d.custodyState~='RECONCILE_REQUIRED' then return false end
        local intent=d.returnIntent
        return intent==nil or type(intent)=='table' and intent.format==1 and id(intent.jobId)
            and id(intent.destinationId) and id(intent.scopeId)
            and (d.custodyState~='PENDING_RETURN' or intent.jobId==d.returnJobId)
    end,settle=function(r,e)
        if e.itemId~=r.data.itemId or not id(e.destinationId) then return false end
        if e.kind=='UNCHANGED' then return r.data.custodyState=='RESERVED' and e.originalPresent==true
            and (r.data.sourceId~=nil and e.destinationId==r.data.sourceId
                or r.data.sourceId==nil and r.data.initialInventory==true and e.initialInventory==true and e.npcId==r.npcId) end
        return e.destinationKind=='STORAGE' and e.originalPresent==true and e.returnJobId==r.data.returnJobId
            and r.data.returnIntent and e.destinationId==r.data.returnIntent.destinationId
    end,confirm=itemConfirm}
}
function T.valid(r) local h=handlers[r.type] return h~=nil and h.valid(r) end
function T.claim(r) local h=handlers[r.type] return h and h.claim and h.claim(r) or nil end
function T.settle(r,e) local h=handlers[r.type] return h and type(e)=='table' and e.effects=='KNOWN' and h.settle(r,e) or false end
function T.confirm(r,e) local h=handlers[r.type] return h and type(e)=='table' and e.effects=='KNOWN' and h.confirm(r,e) or false end
function T.reconcile(r,op)
    if r.type=='TOOL_CUSTODY' then
        r.data.custodyState='RECONCILE_REQUIRED'
        if type(op.reason)=='string' then r.data.reason=string.sub(op.reason,1,256) end
    end
end
function T.transfer(r,op)
    local e=op.evidence
    if r.type~='FURNACE_DUTY' or r.state~='ACTIVE' or not id(op.npcId) or op.npcId==r.npcId
        or type(e)~='table' or e.siteKey~=r.data.siteKey or e.siteVerified~=true
        or e.originalsVerified~=true or e.bodyReleased~=true then return nil end
    return {from=r.npcId,to=op.npcId,siteKey=e.siteKey}
end
function T.apply(r,op,detached)
    if r.type~='TOOL_CUSTODY' then return false,'OBLIGATION_INTENT_INVALID' end
    if op.action=='ASSIGN_TOOL' then
        if (r.data.custodyState~='RESERVED' and r.data.custodyState~='HELD')
            or op.jobId~=nil and not id(op.jobId) then return false,'TOOL_CUSTODY_UNRESOLVED' end
        r.data.activeJobId=op.jobId
    elseif op.action=='TOOL_HELD' then
        local e=op.evidence
        if (r.data.custodyState~='RESERVED' and r.data.custodyState~='HELD')
            or type(e)~='table' or e.itemId~=r.data.itemId or e.npcId~=r.npcId or e.inInventory~=true then return false,'TOOL_HELD_UNPROVEN' end
        r.data.custodyState='HELD'
    elseif op.action=='TOOL_RETURN' then
        local intent=op.intent
        if (r.data.custodyState~='HELD' and r.data.custodyState~='RESERVED') or type(intent)~='table'
            or intent.format~=1 or not id(intent.jobId) or not id(intent.destinationId) or not id(intent.scopeId) then return false,'RETURN_INTENT_INVALID' end
        r.data.custodyState='PENDING_RETURN' r.data.returnJobId=intent.jobId
        r.data.returnIntent=detached(intent) r.data.activeJobId=nil
    elseif op.action=='TOOL_ABORT' then
        local e=op.evidence
        if r.data.returnJobId~=op.returnJobId or (r.data.custodyState~='PENDING_RETURN' and r.data.custodyState~='RECONCILE_REQUIRED')
            or type(e)~='table' or e.itemId~=r.data.itemId or e.npcId~=r.npcId or e.inInventory~=true then return false,'TOOL_ABORT_UNPROVEN' end
        r.state='ACTIVE' r.data.custodyState='HELD' r.data.returnJobId=nil r.data.returnIntent=nil
    else return false,'OBLIGATION_INTENT_INVALID' end
    return true
end
return T
