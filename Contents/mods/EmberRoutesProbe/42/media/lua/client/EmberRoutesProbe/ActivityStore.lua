-- Intentions and first-arrival facts. Never mirrors Runtime, Claims or custody.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Definitions=require 'EmberRoutesProbe/ActivityRegistry'
local Store={LIMIT=128}
local phases={GATHERING=true,RUNNING=true,WINDING_DOWN=true,SETTLING=true,CLOSED=true}
local world,opened,index
local function integer(n,min,max)
    return type(n)=='number' and n==n and n==math.floor(n) and n>=min and n<=max
end
local function text(s) return type(s)=='string' and #s>0 and #s<=128 and not s:find('[%c]') end
local function finite(n) return type(n)=='number' and n==n and n>=0 and n<100000000 end
local function plain(value,seen,depth,budget)
    budget.n=budget.n+1 if budget.n>8192 or depth>8 then return false end
    local kind=type(value)
    if kind=='string' then
        budget.bytes=(budget.bytes or 0)+#value
        return #value<=65536 and budget.bytes<=262144
    end
    if kind=='number' then return value==value and math.abs(value)<9007199254740991 end
    if kind=='boolean' or kind=='nil' then return true end
    if kind~='table' or seen[value] then return false end
    seen[value]=true
    for key,item in pairs(value) do
        if type(key)~='string' and (not integer(key,1,256)) then return false end
        if type(key)=='string' and #key>128 or not plain(item,seen,depth+1,budget) then return false end
    end
    return true
end
function Store.schedules()
    local saved,why=Store.current() if not saved then return nil,why end
    if saved.schedules==nil then saved.schedules={} end
    if type(saved.schedules)~='table' then return nil,'ACTIVITY_SCHEDULE_INVALID' end
    return saved.schedules
end
function Store.scalar(value) return plain(value,{},0,{n=0,bytes=0}) end
local function valid(row)
    if type(row)~='table' or not plain(row,{},0,{n=0}) or not text(row.id)
        or row.definition~='FREE_GATHERING' or row.definitionVersion~=1
        or not text(row.settlementId) or not text(row.requesterId) or not text(row.requestId)
        or not text(row.name) or not integer(row.revision,1,9007199254740000)
        or not phases[row.state]
        or type(row.zone)~='table' or not text(row.zone.id) or not integer(row.zone.revision,1,9007199254740000)
        or not finite(row.createdAt) or not finite(row.endsAt) or row.endsAt<=row.createdAt
        or type(row.roster)~='table' or not Definitions.rules(row.rules) then return false end
    local count=0
    for id,member in pairs(row.roster) do
        count=count+1
        if count>256 or not text(id) or type(member)~='table'
            or not integer(member.membershipRevision,1,9007199254740000)
            or not integer(member.commandEpoch,0,9007199254740000)
            or (member.withdrawn~=nil and member.withdrawn~=true) then return false end
        if member.jobId~=nil and not text(member.jobId) or member.participationHours~=nil and not finite(member.participationHours)
            or member.joined~=nil and type(member.joined)~='boolean'
            or member.settled~=nil and type(member.settled)~='boolean' then return false end
        if member.arrival~=nil then
            local a=member.arrival
            if type(a)~='table' or not finite(a.at) then return false end
            for _,key in ipairs({'x','y','z'}) do
                local n=a[key]
                if type(n)~='number' or n~=n or math.abs(n)>10000000 then return false end
            end
            if a.z~=math.floor(a.z) then return false end
        end
    end
    if row.organizerId~=nil and (not row.roster[row.organizerId] or not integer(row.quorum,1,count)
        or not finite(row.durationHours) or row.durationHours<=0 or not finite(row.gatherDeadline)
        or not integer(row.controlEpoch,1,9007199254740000)) then return false end
    return count>0
end
function Store.arrived(id,npc,point,hours)
    local saved,why=Store.current() if not saved then return false,why end
    local row=saved.events[id] local member=row and row.roster[npc]
    if not member or member.withdrawn or row.state=='CLOSED' or hours>=row.endsAt then return false end
    if member.arrival then return true end -- First physical arrival fact, no reward.
    member.arrival={at=hours,x=point.x,y=point.y,z=point.z}
    row.revision=row.revision+1 saved.revision=saved.revision+1
    return true
end
function Store.copy(v)
    if type(v)~='table' then return v end
    local r={} for k,x in pairs(v) do r[k]=Store.copy(x) end return r
end
function Store.current()
    local root=Registry.data()
    if root~=world or root.communityActivities~=opened then
        local saved=root.communityActivities or {format=1,revision=0,events={}}
        if type(saved)~='table' or saved.format~=1 or not integer(saved.revision,0,9007199254740000)
            or type(saved.events)~='table' then return nil,'ACTIVITY_FORMAT_UNSUPPORTED' end
        local count,requests=0,{}
        for id,row in pairs(saved.events) do
            count=count+1
            if count>Store.LIMIT or not valid(row) or row.id~=id or requests[row.requestId] then
                return nil,'ACTIVITY_DATA_INVALID'
            end
            requests[row.requestId]=true
        end
        world,opened,index=root,saved,{}
        root.communityActivities=saved
        for _,row in pairs(saved.events) do
            -- A scene never resumes after a world load, even without a save receipt.
            if row.state~='CLOSED' then
                local tracked=false for _,m in pairs(row.roster) do if m.jobId then tracked=true break end end
                row.state=tracked and 'WINDING_DOWN' or 'CLOSED'
                row.outcome='INCOMPLETE' row.reason='LOAD_INTERRUPTED' row.controlEpoch=(row.controlEpoch or 1)+1
                row.revision=row.revision+1
                saved.revision=saved.revision+1
            end
        end
    end
    return opened
end
function Store.forNpc(id)
    local saved,why=Store.current() if not saved then return nil,why end
    return index[id]
end
function Store.insert(row)
    local saved,why=Store.current() if not saved then return nil,why end
    if not valid(row) or saved.events[row.id] then return nil,'ACTIVITY_DATA_INVALID' end
    local count,oldest=0,nil
    for _,other in pairs(saved.events) do
        count=count+1
        if other.requestId==row.requestId then return nil,'ACTIVITY_REQUEST_CONFLICT' end
        if other.state=='CLOSED' and (not oldest or other.createdAt<oldest.createdAt
            or other.createdAt==oldest.createdAt and other.id<oldest.id) then oldest=other end
    end
    for id in pairs(row.roster) do if index[id] then return nil,'ACTIVITY_NPC_BUSY' end end
    if count>=Store.LIMIT then
        if not oldest then return nil,'ACTIVITY_LIMIT' end
        -- CLOSED preference intents have no bodies/assets. Expired receipts never
        -- become fresh commands: their in-memory issued token was consumed.
        saved.events[oldest.id]=nil
    end
    row=Store.copy(row) saved.events[row.id]=row saved.revision=saved.revision+1
    for id in pairs(row.roster) do index[id]=row end
    return Store.copy(row)
end
function Store.withdraw(id,npc)
    local saved,why=Store.current() if not saved then return false,why end
    local row=saved.events[id] local member=row and row.roster[npc]
    if not member then return false,'ACTIVITY_MISSING' end
    if not member.withdrawn then
        member.withdrawn=true row.revision=row.revision+1 saved.revision=saved.revision+1
    end
    if index[npc]==row then index[npc]=nil end
    return true
end
function Store.close(id,expected,reason)
    local saved,why=Store.current() if not saved then return false,why end
    local row=saved.events[id]
    if not row then return false,'ACTIVITY_MISSING' end
    if row.revision~=expected then return false,'ACTIVITY_CHANGED' end
    if row.state=='CLOSED' then return true end
    if row.state=='WINDING_DOWN' or row.state=='SETTLING' then return true end
    local tracked=false for _,m in pairs(row.roster) do if m.jobId and not m.settled then tracked=true break end end
    row.state=tracked and 'WINDING_DOWN' or 'CLOSED' row.reason=reason
    row.controlEpoch=(row.controlEpoch or 1)+1
    row.outcome=reason=='COMPLETED' and 'COMPLETED' or reason=='CANCELLED' and 'CANCELLED' or 'INCOMPLETE'
    row.revision=row.revision+1 saved.revision=saved.revision+1
    for npc in pairs(row.roster) do if index[npc]==row then index[npc]=nil end end
    return true
end
-- Internal trusted scalar mutations; public commands still go through Service.
function Store.touch(event,observation)
    local saved=Store.current()
    if not saved or saved.events[event.id]~=event then return false end
    if not observation then event.revision=event.revision+1 end
    saved.revision=saved.revision+1 return true
end
function Store.get(id)
    local saved=Store.current() return saved and saved.events[id]
end
return Store
