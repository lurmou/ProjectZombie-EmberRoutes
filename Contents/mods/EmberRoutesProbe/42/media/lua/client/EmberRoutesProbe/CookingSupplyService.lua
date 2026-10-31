-- One incremental meal observation per settlement. Callers supply the shared scan
-- budget; this module owns no tick, NPC body, persistent quota or asset mutation.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Wake=require 'EmberRoutesProbe/PlanningWake'
local Index=require 'EmberRoutesProbe/MealSupplyIndex'
local Policy=require 'EmberRoutesProbe/CookingPolicy'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Budget=require 'EmberRoutesProbe/CookingBudget'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Store=require 'EmberRoutesProbe/LaborStore'
local S={}
local world,scopes=nil,{}
local function load()
    local root=Registry.data()
    if world~=root then world,scopes=root,{} end
    return root
end
local function quota(root) return Budget.open(root,Jobs.current()) end
local function expired(row,now,hours)
    return now<row.at or now-row.at>=2000 or hours<row.hours or hours-row.hours>=1/60
end
local function fence(row,stamp)
    local owner,revision=Store.claimsVersion()
    return row.stamp==stamp and row.owner==owner and row.revision==revision and not Wake.changed(row.watch)
end
-- now is monotonic milliseconds, hours is the observed world age in game hours.
-- A cache miss/partial/unknown result has NO ready=0 value.
function S.observe(entry,now,hours,budget)
    local root=load()
    if type(entry)~='table' or type(entry.id)~='string' or type(entry.factionId)~='string'
        or not Policy.finite(now) or not Policy.finite(hours) or type(budget)~='table'
        or not Policy.finite(budget.scan) or budget.scan~=math.floor(budget.scan) then return nil,'SUPPLY_ARGUMENT_INVALID' end
    local members=root.npcMembership
    if not members or members.format~=1 then return nil,'POPULATION_UNKNOWN' end
    local population,why=Policy.population(members.byNpc,entry.id,entry.factionId)
    if population==nil then return nil,why end
    local book,reason=quota(root) if not book then return nil,reason end
    local live,reason2=book:view(entry.id) if not live then return nil,reason2 end
    local row=scopes[entry.id]
    if not row then
        local n=0 for _ in pairs(scopes) do n=n+1 end
        if n>=256 then return nil,'SUPPLY_SCOPE_LIMIT' end
        row={active=false} scopes[entry.id]=row
    end
    if row.watch and (not fence(row,live.stamp) or row.snapshot and expired(row,now,hours)) then
        row.scan=nil row.snapshot=nil row.watch=nil
    end
    if row.snapshot then
        if not row.snapshot.complete then return nil,row.snapshot.reason or 'SUPPLY_UNKNOWN' end
        local demand,err=Policy.demand(population,row.snapshot.ready,live.pending,live.blocked,row.active)
        if not demand then return nil,err end
        row.active=demand.active
        local result=Record.copy(row.snapshot)
        result.population=population result.stamp=live.stamp result.active=row.active result.demand=demand
        return result
    end
    if not row.scan then
        local scan,err=Index.new(entry,function() return now end)
        if not scan then return nil,err end
        row.scan=scan row.watch=Wake.capture(entry) row.stamp=live.stamp
        row.owner,row.revision=Store.claimsVersion()
        row.at=now row.hours=hours
    end
    -- Shared callers may ask in the same frame; only one bounded slice is pumped.
    local slice=math.floor(now/50)
    if row.pumped==slice or budget.scan<1 then return nil,'SUPPLY_NOT_OBSERVED' end
    row.pumped=slice
    local allowance=math.min(32,budget.scan) budget.scan=budget.scan-allowance
    local done,err=row.scan:step(allowance)
    if done==nil then row.scan=nil row.watch=nil return nil,err end
    if not done then return nil,'SUPPLY_NOT_OBSERVED' end
    -- TTL applies to completed observations, not the time needed to traverse a large pantry.
    -- Inventory/claims revisions and endpoint checks still fence every scan slice.
    if not fence(row,live.stamp) or now<row.at or hours<row.hours then
        row.scan=nil row.watch=nil return nil,'SUPPLY_CHANGED'
    end
    local snapshot,err2=row.scan:result()
    row.scan=nil
    if not snapshot then row.watch=nil return nil,err2 end
    snapshot.scanStartedAt=row.at snapshot.observedAt=now
    row.snapshot=snapshot row.at=now row.hours=hours
    -- No second scan: publish population/demand through the same cached branch.
    return S.observe(entry,now,hours,budget)
end
-- Admission must use a still-current observation AND the original Job quota.
-- The next contender must observe again; it cannot reuse a pre-admission gap.
function S.reserve(entry,job,snapshot,minimum,now,hours)
    if type(entry)~='table' or not Record.valid(job) then return false,'COOKING_ADMISSION_INVALID' end
    local root=load() local row=scopes[entry.id]
    if not row or not row.snapshot or not row.snapshot.complete or not snapshot
        or snapshot.observedAt~=row.snapshot.observedAt or snapshot.scopeId~=entry.id
        or job.scopeId~=entry.id or not Policy.finite(now) or not Policy.finite(hours)
        or expired(row,now,hours) then return false,'COOKING_SUPPLY_CHANGED' end
    local book,why=quota(root) if not book then return false,why end
    local live,why2=book:view(entry.id) if not live then return false,why2 end
    if not fence(row,live.stamp) or snapshot.stamp~=live.stamp then return false,'COOKING_SUPPLY_CHANGED' end
    local members=root.npcMembership
    local n,err=Policy.population(members and members.byNpc,entry.id,entry.factionId)
    if n==nil then return false,err end
    -- Do not trust mutable caller snapshot values for stock, population or hysteresis.
    local supply={scopeId=entry.id,stamp=live.stamp,complete=true,population=n,
        ready=row.snapshot.ready,active=row.active,minimum=minimum}
    local ok,reason=book:reserve(job,supply)
    if ok then row.scan=nil row.snapshot=nil row.watch=nil end
    return ok,reason
end
return S
