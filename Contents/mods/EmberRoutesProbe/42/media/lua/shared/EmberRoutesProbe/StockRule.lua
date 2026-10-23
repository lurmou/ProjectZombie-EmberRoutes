-- Pure maintain-stock rule logic: validation, gap calculation, batch limits, and unique keys.
-- No world reading, no side effects, safe for shared usage and tests.
local StockRule={}

local function integer(v)
    return type(v)=="number" and v==v and math.abs(v)~=math.huge and v==math.floor(v)
end

local validPhases={PREPARED=true,ATTACHED=true,SETTLING=true,RECONCILE_REQUIRED=true}

function StockRule.uniqueKey(settlementId,fullType)
    if type(settlementId)~="string" or settlementId=="" or type(fullType)~="string" or fullType=="" then
        return nil
    end
    return settlementId..":"..fullType
end

function StockRule.validateCycle(c)
    if type(c)~="table" then return false end
    if not integer(c.sequence) or c.sequence<1 then return false end
    if type(c.taskId)~="string" or c.taskId=="" then return false end
    if not integer(c.ruleRevision) or c.ruleRevision<0 then return false end
    if not validPhases[c.phase] then return false end
    if not integer(c.requested) or c.requested<1 or c.requested>9999 then return false end
    if c.snapshotRevision~=nil and not integer(c.snapshotRevision) then return false end
    if c.settlementRevision~=nil and not integer(c.settlementRevision) then return false end
    return true
end

function StockRule.validate(r)
    if type(r)~="table" then return false end
    if type(r.id)~="string" or r.id=="" then return false end
    if type(r.settlementId)~="string" or r.settlementId=="" then return false end
    if type(r.fullType)~="string" or r.fullType=="" then return false end
    if type(r.recipeId)~="string" or r.recipeId=="" then return false end
    if type(r.recipeSignature)~="string" or r.recipeSignature=="" then return false end
    if type(r.npcId)~="string" or r.npcId=="" then return false end
    if r.surfaceId~=nil and (type(r.surfaceId)~="string" or r.surfaceId=="") then return false end
    if not integer(r.minimum) or r.minimum<1 or r.minimum>9999 then return false end
    if type(r.enabled)~="boolean" then return false end
    if not integer(r.revision) or r.revision<0 then return false end
    if not integer(r.nextCycle) or r.nextCycle<1 then return false end
    if r.deleting~=nil and type(r.deleting)~="boolean" then return false end
    if r.activeCycle~=nil and not StockRule.validateCycle(r.activeCycle) then return false end
    return true
end

-- Evaluates inventory stock against the rule.
-- inventory: { complete=boolean, state=string, count=number }
-- orders: { hasManualOrder=boolean }
-- recipeYield: integer (default 1)
function StockRule.evaluate(rule,inventory,orders,recipeYield)
    if not StockRule.validate(rule) then
        return {state="ERROR",reason="RULE_INVALID"}
    end
    if rule.deleting then
        return {state="DELETING",reason="RULE_DELETING",active=rule.activeCycle~=nil}
    end
    if not rule.enabled then
        return {state="DISABLED",reason="RULE_DISABLED",active=rule.activeCycle~=nil}
    end

    local yield=recipeYield or 1
    if not integer(yield) or yield<1 or yield>32 then
        return {state="ERROR",reason="INVALID_YIELD"}
    end

    -- If active cycle already exists, rule is actively running or settling.
    if rule.activeCycle then
        local cycle=rule.activeCycle
        return {
            state=cycle.phase=="RECONCILE_REQUIRED" and "RECONCILE_REQUIRED" or "RESTOCKING",
            reason="CYCLE_ACTIVE",
            cycle=cycle,
            requested=cycle.requested,
            target=math.ceil(cycle.requested/yield)*yield
        }
    end

    -- Check inventory readiness and completeness
    if not inventory or inventory.state~="READY" or not inventory.complete then
        return {
            state="WAIT_INVENTORY",
            reason=inventory and inventory.state=="ERROR" and "INVENTORY_ERROR" or "INVENTORY_NOT_READY",
            knownCount=inventory and inventory.count or 0
        }
    end

    -- Check manual order collision
    if orders and orders.hasManualOrder then
        return {
            state="WAIT_EXISTING_ORDER",
            reason="MANUAL_ORDER_ACTIVE",
            knownCount=inventory.count
        }
    end

    local P=inventory.count or 0
    local M=rule.minimum
    local D=math.max(0,M-P)

    if D<=0 then
        return {
            state="SATISFIED",
            reason="TARGET_MET",
            knownCount=P,
            minimum=M,
            deficit=0
        }
    end

    -- Calculate bounded replenishment: max 32 batches of root recipe, capped at 9999
    local maxBatchItems=32*yield
    local requested=math.min(D,maxBatchItems,9999)
    local target=math.ceil(requested/yield)*yield

    return {
        state="DEFICIT",
        reason="STOCK_DEFICIT",
        knownCount=P,
        minimum=M,
        deficit=D,
        requested=requested,
        target=target,
        yield=yield,
        batches=math.ceil(requested/yield)
    }
end

return StockRule
