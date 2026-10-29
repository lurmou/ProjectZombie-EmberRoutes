-- Shared quantities only. No native handles, scheduling or physical effects.
local P={unit=0.15,lowPerMember=1,highPerMember=2,maxSpices=2,epsilon=0.000001}
function P.finite(n) return type(n)=='number' and n==n and n>=0 and n<math.huge end
function P.population(rows,scope,faction)
    if type(rows)~='table' or type(scope)~='string' or type(faction)~='string' then return nil,'POPULATION_UNKNOWN' end
    local n=0
    for id,row in pairs(rows) do
        if type(row)~='table' or row.npcId~=id then return nil,'MEMBERSHIP_INVALID' end
        if row.settlementId==scope and row.factionId==faction and not row.retired then n=n+1 end
    end
    return n
end
function P.demand(n,ready,pending,blocked,active)
    if not P.finite(n) or n~=math.floor(n) or not P.finite(ready) or not P.finite(pending)
        or not P.finite(blocked) then return nil,'SUPPLY_UNKNOWN' end
    local low,high=n*P.unit*P.lowPerMember,n*P.unit*P.highPerMember
    local covered=ready+pending+blocked
    if not P.finite(covered) then return nil,'SUPPLY_INVALID' end
    local running=n>0 and (active==true or ready+P.epsilon<low)
    if covered+P.epsilon>=high or n==0 then running=false end
    return {population=n,low=low,high=high,ready=ready,pending=pending,blocked=blocked,
        active=running,gap=running and math.max(0,high-covered) or 0}
end
-- Minimum is the smallest verified complete native batch, never the pot capacity.
function P.batch(demand,minimum)
    if type(demand)~='table' or not P.finite(minimum) or minimum<=0 or not P.finite(demand.gap)
        or not P.finite(demand.ready) or not P.finite(demand.low) then return nil,'BATCH_ESTIMATE_UNKNOWN' end
    if not demand.active or demand.gap<=P.epsilon then return nil,'MEALS_SUFFICIENT' end
    if minimum>demand.gap+P.epsilon and demand.ready+P.epsilon>=demand.low then return nil,'SMALL_GAP_WAIT' end
    return {target=demand.gap,minimum=minimum,quota=math.max(minimum,demand.gap),
        minimumOverrun=math.max(0,minimum-demand.gap)}
end
return P
