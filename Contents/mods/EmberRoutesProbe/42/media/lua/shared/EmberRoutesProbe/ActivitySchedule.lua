-- Bounded calendar arithmetic; never creates bodies or catches up missed scenes.
local R=require 'EmberRoutesProbe/ActivityRegistry'
local S={LIMIT=32,MAX_OCCURRENCES=366}
local function integer(n,min,max) return type(n)=='number' and n==n and n>=min and n<=max and n==math.floor(n) end
local function finite(n) return type(n)=='number' and n==n and n>=0 and n<100000000 end
local function intentValid(args)
    if type(args.roster)~='table' or not R.rules(args.rules) then return false end
    if args.definitionId~=nil and (type(args.definitionId)~='string' or #args.definitionId<1 or #args.definitionId>128) then return false end
    if args.definitionVersion~=nil and not integer(args.definitionVersion,1,1000000) then return false end
    local count,seen=0,{}
    for key,id in pairs(args.roster) do
        count=count+1
        if count>256 or not integer(key,1,256) or type(id)~='string' or #id<1 or #id>128 or seen[id] then return false end
        seen[id]=true
    end
    if args.speakerId~=nil and (type(args.speakerId)~='string' or #args.speakerId>128 or not seen[args.speakerId]) then return false end
    return count>0
end
function S.valid(row)
    return type(row)=='table' and row.format==1 and type(row.id)=='string' and #row.id>0 and #row.id<=128
        and type(row.owner)=='string' and type(row.key)=='string' and #row.key<=65536
        and integer(row.revision,1,9007199254740000) and type(row.requestId)=='string'
        and type(row.enabled)=='boolean' and finite(row.firstAt)
        and (row.series==nil or integer(row.series,1,9007199254740000))
        and finite(row.intervalHours) and (row.count==1 or row.intervalHours>=1/60)
        and integer(row.count,1,S.MAX_OCCURRENCES) and integer(row.lastIndex,-1,row.count-1)
        and type(row.args)=='table' and type(row.args.name)=='string' and type(row.args.settlementId)=='string'
        and type(row.args.zoneId)=='string' and integer(row.args.zoneRevision,1,9007199254740000)
        and finite(row.args.durationHours) and row.args.durationHours>=1/60 and row.args.durationHours<=24
        -- A missing add-on definition disables only its execution, not the
        -- structure of the whole saved calendar or its other plans.
        and intentValid(row.args)
end
function S.due(row,hours)
    if not row.enabled or hours<row.firstAt then return nil end
    local n=row.count==1 and 0 or math.floor((hours-row.firstAt)/row.intervalHours)
    if n>=row.count then return row.count-1,false end
    if n<=row.lastIndex then return nil end
    local at=row.firstAt+n*row.intervalHours
    local window=row.args.gatherHours or math.min(row.args.durationHours,1/6)
    return n,hours-at<window
end
return S
