-- Executable behavior vocabulary only; no bodies, inventory or engine calls.
local R={}
local behaviors={'SOCIAL','READING','SIT','SMOKE','FITNESS','STROLL','OBSERVE'}
local known={} for _,id in ipairs(behaviors) do known[id]=true end
function R.behaviors()
    local result={} for i,id in ipairs(behaviors) do result[i]=id end return result
end
function R.rules(value)
    if type(value)~='table' then return nil end
    local result,count={},0
    for id,rule in pairs(value) do
        if not known[id] or rule~=0 and rule~=1 and rule~=2 then return nil end
        result[id]=rule count=count+1
    end
    -- Sparse overrides inherit ordinary area rules; an empty override is valid.
    return result,count
end
function R.get(id)
    if id~='FREE_GATHERING' then return nil end
    return {id=id,version=1,mode='FREE',behaviors=R.behaviors()}
end
-- Canonical command identity, independent of current membership/command epochs.
-- Length prefixes avoid delimiter aliases; the original request remains immutable.
function R.commandKey(args)
    if type(args)~='table' or type(args.roster)~='table' or not R.rules(args.rules)
        or type(args.durationHours)~='number' or args.durationHours~=args.durationHours then return nil end
    local ids={}
    for key,id in pairs(args.roster) do
        if type(key)~='number' or key<1 or key>256 or key~=math.floor(key) or type(id)~='string' or #id>128 then return nil end
        ids[#ids+1]=id if #ids>256 then return nil end
    end
    if #ids==0 then return nil end table.sort(ids)
    local parts={}
    local function put(v)
        local s=tostring(v) parts[#parts+1]=tostring(#s)..':'..s
    end
    put(type(args.name)=='string' and args.name:match('^%s*(.-)%s*$') or '')
    put(args.settlementId) put(args.zoneId) put(args.zoneRevision)
    put(args.organizerId or args.roster[1]) put(args.quorum or math.min(2,#ids))
    put(args.durationHours) put(args.gatherHours or math.min(args.durationHours,1/6))
    for _,id in ipairs(ids) do put(id) end
    for _,id in ipairs(behaviors) do put(id) put(args.rules[id]==nil and '-' or args.rules[id]) end
    local result=table.concat(parts,'|')
    return #result<=65536 and result or nil
end
return R
