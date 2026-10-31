-- Intentions and first-arrival facts. Never mirrors Runtime, Claims or custody.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Definitions=require 'EmberRoutesProbe/ActivityRegistry'
local Stages=require 'EmberRoutesProbe/ActivityStages'
local Duties=require 'EmberRoutesProbe/ActivityDuties'
local Relief=require 'EmberRoutesProbe/ActivityReliefRecord'
local Store={LIMIT=128}
local phases={GATHERING=true,RUNNING=true,WINDING_DOWN=true,SETTLING=true,CLOSED=true}
local world,opened,index,activeIds,activeAt,activeVersion
local function active(row)
    local at=activeAt[row.id]
    if row.state=='CLOSED' then
        if at then
            local last=activeIds[#activeIds] activeIds[at]=last activeIds[#activeIds]=nil
            activeAt[row.id]=nil if last~=row.id then activeAt[last]=at end
            activeVersion=activeVersion+1
        end
    elseif not at then activeIds[#activeIds+1]=row.id activeAt[row.id]=#activeIds activeVersion=activeVersion+1 end
end
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
        or not text(row.definition) or not integer(row.definitionVersion,1,1000000)
        or row.worldId~=nil and not text(row.worldId)
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
            or member.participantEpoch~=nil and not integer(member.participantEpoch,1,9007199254740000)
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
    if row.scriptProfile~=nil and (not text(row.scriptProfile) or not row.speakerId or not row.roster[row.speakerId]
        or count<2 or row.quorum<2 or row.gatherDeadline<=row.createdAt) then return false end
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
            or type(saved.events)~='table' or saved.worldId~=nil and not text(saved.worldId) then return nil,'ACTIVITY_FORMAT_UNSUPPORTED' end
        local count,requests=0,{}
        for id,row in pairs(saved.events) do
            count=count+1
            if count>Store.LIMIT or not valid(row) or row.id~=id or requests[row.requestId] then
                return nil,'ACTIVITY_DATA_INVALID'
            end
            requests[row.requestId]=true
        end
        if not saved.worldId then saved.worldId=Registry.id() saved.revision=saved.revision+1 end
        world,opened,index,activeIds,activeAt,activeVersion=root,saved,{},{},{},0
        root.communityActivities=saved
        for _,row in pairs(saved.events) do
            if not Relief.valid(row) then row.reliefBlocked=true end
            Relief.interrupt(row,'LOAD_INTERRUPTED')
            if row.state=='CLOSED' and Relief.pending(row) then row.state='SETTLING' end
            if row.scriptProfile~=nil and row.scriptProfile~='SPEECH_V1' then row.stageBlocked=true end
            if row.dutyFormat~=nil then
                if row.dutyFormat~=Duties.FORMAT or not row.stage then row.dutyBlocked=true
                else
                    for _,m in pairs(row.roster) do
                        if m.joined and not Duties.valid(m.duty) or not m.joined and m.duty~=nil
                            or row.state=='CLOSED' and m.duty and not Duties.clear(m.duty) then row.dutyBlocked=true end
                    end
                end
            end
            if row.stage~=nil then
                if not Stages.valid(row.stage) or row.worldId~=saved.worldId
                    or row.stage.scope.worldId~=row.worldId or row.stage.scope.eventId~=row.id
                    or row.stage.scope.stageEpoch~=row.stageEpoch then row.stageBlocked=true end
            end
            -- A scene never resumes after a world load, even without a save receipt.
            if row.state~='CLOSED' then
                local tracked=false for _,m in pairs(row.roster) do if m.jobId then tracked=true break end end
                row.state=tracked and 'WINDING_DOWN' or 'CLOSED'
                row.outcome='INCOMPLETE' row.reason='LOAD_INTERRUPTED' row.controlEpoch=(row.controlEpoch or 1)+1
                row.revision=row.revision+1
                saved.revision=saved.revision+1
                if row.stage and not row.stageBlocked and row.stage.state~='CLOSED' then Stages.requestEnd(row.stage,'INCOMPLETE',getGameTime():getWorldAgeHours()) end
                if row.stageBlocked or row.dutyBlocked or row.stage and not Stages.retirable(row.stage) or Relief.pending(row) then row.state='WINDING_DOWN' end
            end
            active(row)
        end
    end
    return opened
end
function Store.worldId()
    local saved,why=Store.current() return saved and saved.worldId or nil,why
end
-- Internal derived read-only index. No persisted second activity authority.
function Store.active()
    local saved,why=Store.current() if not saved then return nil,why end
    return activeIds,activeVersion
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
        if other.state=='CLOSED' and not other.stageBlocked and not other.dutyBlocked and not Relief.pending(other) and Stages.retirable(other.stage) and (not oldest or other.createdAt<oldest.createdAt
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
    active(row)
    if row.state=='GATHERING' or row.state=='RUNNING' then
        for id,member in pairs(row.roster) do if not member.withdrawn then index[id]=row end end
    end
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
-- Gathering-only roster edits keep withdrawn records until their own Jobs settle.
-- Keeping a participant never replaces its current body or original-item owner.
function Store.amend(id,expected,proposal,receipt)
    local saved,why=Store.current() if not saved then return nil,why end
    local row=saved.events[id]
    if not row then return nil,'ACTIVITY_MISSING' end
    if row.revision~=expected then return nil,'ACTIVITY_CHANGED' end
    if row.state~='GATHERING' then return nil,'ACTIVITY_EDIT_CLOSED' end
    local total=0 for _ in pairs(row.roster) do total=total+1 end
    for npc in pairs(proposal.roster) do
        local member=row.roster[npc]
        if member and member.withdrawn and not member.settled then return nil,'ACTIVITY_REINVITE_UNAVAILABLE' end
        if index[npc] and index[npc]~=row then return nil,'ACTIVITY_NPC_BUSY' end
        if not member then total=total+1 end
    end
    if total>256 then return nil,'ACTIVITY_LIMIT' end
    local nextRow=Store.copy(row)
    for npc,member in pairs(nextRow.roster) do
        if not proposal.roster[npc] and not member.withdrawn then
            member.withdrawn=true member.reason='ACTIVITY_ROSTER_REMOVED'
        end
    end
    for npc,member in pairs(proposal.roster) do
        if not nextRow.roster[npc] or nextRow.roster[npc].withdrawn then nextRow.roster[npc]=Store.copy(member) end
    end
    nextRow.name=proposal.name nextRow.organizerId=proposal.organizerId nextRow.quorum=proposal.quorum nextRow.speakerId=proposal.speakerId
    nextRow.editReceipt=Store.copy(receipt) nextRow.revision=nextRow.revision+1
    if not valid(nextRow) then return nil,'ACTIVITY_DATA_INVALID' end
    -- Mutate the existing scene identity: in-flight callbacks keep that identity.
    row.name,row.organizerId,row.quorum=nextRow.name,nextRow.organizerId,nextRow.quorum
    row.speakerId=nextRow.speakerId
    row.editReceipt=nextRow.editReceipt row.revision=nextRow.revision
    for npc,member in pairs(nextRow.roster) do
        if row.roster[npc] and not (row.roster[npc].withdrawn and not member.withdrawn) then
            row.roster[npc].withdrawn=member.withdrawn row.roster[npc].reason=member.reason
        else row.roster[npc]=member end
        if member.withdrawn then if index[npc]==row then index[npc]=nil end else index[npc]=row end
    end
    saved.revision=saved.revision+1 return row
end
function Store.close(id,expected,reason)
    local saved,why=Store.current() if not saved then return false,why end
    local row=saved.events[id]
    if not row then return false,'ACTIVITY_MISSING' end
    if row.state=='CLOSED' then return true end
    if row.state=='WINDING_DOWN' or row.state=='SETTLING' then return true end
    if row.revision~=expected then return false,'ACTIVITY_CHANGED' end
    local tracked=false for _,m in pairs(row.roster) do if m.jobId and not m.settled then tracked=true break end end
    row.state=tracked and 'WINDING_DOWN' or 'CLOSED' row.reason=reason
    row.controlEpoch=(row.controlEpoch or 1)+1
    row.outcome=reason=='COMPLETED' and 'COMPLETED' or reason=='CANCELLED' and 'CANCELLED' or 'INCOMPLETE'
    if row.stage and not row.stageBlocked and row.stage.state~='CLOSED' then
        local accepted=Stages.requestEnd(row.stage,row.outcome,getGameTime():getWorldAgeHours())
        if not accepted then
            row.outcome='INCOMPLETE' row.reason='ACTIVITY_STAGE_NOT_COMPLETE'
            Stages.requestEnd(row.stage,'INCOMPLETE',getGameTime():getWorldAgeHours())
        end
    end
    if row.stage and not Stages.retirable(row.stage) or row.stageBlocked or row.dutyBlocked or Relief.pending(row) then row.state='WINDING_DOWN' end
    row.revision=row.revision+1 saved.revision=saved.revision+1
    active(row)
    for npc in pairs(row.roster) do if index[npc]==row then index[npc]=nil end end
    return true
end
-- Internal trusted scalar mutations; public commands still go through Service.
function Store.touch(event,observation)
    local saved=Store.current()
    if not saved or saved.events[event.id]~=event then return false end
    if not observation then event.revision=event.revision+1 end
    active(event)
    saved.revision=saved.revision+1 return true
end
function Store.get(id)
    local saved=Store.current() return saved and saved.events[id]
end
return Store
