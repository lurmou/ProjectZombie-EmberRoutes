-- Controlled sequential phase facts. No native execution or effect settlement.
local R={LIMIT=32}
local names={'prepare','discussion','finish'}
local terminal={COMPLETED=true,INCOMPLETE=true,CANCELLED=true,FAILED=true}
local function id(s) return type(s)=='string' and #s>0 and #s<=128 end
local function number(n) return type(n)=='number' and n==n and n>=0 and n<100000000 end
local function integer(n) return type(n)=='number' and n==n and n>=1 and n<=9007199254740000 and n==math.floor(n) end
function R.new(event,index,actors,hours)
    local set,count={},0
    for npc,a in pairs(actors) do
        set[npc]={jobId=a.jobId,participantEpoch=a.participantEpoch or 1,roleId=npc==event.speakerId and 'speaker' or 'listener'}
        count=count+1
    end
    if not names[index] or count<2 or count>R.LIMIT or not set[event.speakerId] then return nil end
    return {format=2,id=names[index],index=index,scope={worldId=event.worldId,eventId=event.id,
        controlEpoch=event.controlEpoch,stageEpoch=event.stageEpoch},state='RUNNING',startedAt=hours,
        deadline=hours+(event.gatherDeadline-event.createdAt),
        actors=set,actorCount=count,exits={},exitCount=0}
end
local function shape(r)
    if type(r)~='table' or r.format~=2 or not integer(r.index) or r.index>3 or not id(r.id)
        or names[r.index]~=r.id or type(r.scope)~='table'
        or not id(r.scope.worldId) or not id(r.scope.eventId) or not integer(r.scope.controlEpoch) or not integer(r.scope.stageEpoch)
        or r.state~='RUNNING' and r.state~='CLOSING' and r.state~='CLOSED'
        or not number(r.startedAt) or not number(r.deadline) or r.deadline<r.startedAt
        or type(r.actors)~='table' or type(r.exits)~='table' or not integer(r.actorCount) or r.actorCount<2 or r.actorCount>R.LIMIT
        or not number(r.exitCount) or r.exitCount~=math.floor(r.exitCount) or r.exitCount>r.actorCount then return false end
    return true
end
function R.valid(r)
    if not shape(r) then return false end
    local n,x,speakers=0,0,0
    for npc,a in pairs(r.actors) do
        n=n+1
        if n>R.LIMIT or not id(npc) or type(a)~='table' or not id(a.jobId) or not integer(a.participantEpoch)
            or a.roleId~='speaker' and a.roleId~='listener' then return false end
        if a.roleId=='speaker' then speakers=speakers+1 end
    end
    for npc,v in pairs(r.exits) do if not r.actors[npc] or v~=true then return false end x=x+1 end
    if r.index==2 then
        local f=r.focus
        if type(f)~='table' or type(f.x)~='number' or type(f.y)~='number'
            or f.x~=f.x or f.y~=f.y or math.abs(f.x)>10000000 or math.abs(f.y)>10000000 then return false end
    end
    if r.sharedStart==nil and r.sharedEnd~=nil then return false end
    if r.sharedStart~=nil and (r.index~=2 or not number(r.sharedStart) or r.sharedStart<r.startedAt
        or not number(r.sharedEnd) or r.sharedEnd<r.sharedStart or r.sharedEnd>r.deadline) then return false end
    if r.state~='RUNNING' and not terminal[r.requestedOutcome] then return false end
    if r.state=='CLOSED' and (not terminal[r.outcome] or not number(r.endedAt) or x~=n) then return false end
    return n==r.actorCount and n>=2 and speakers==1 and x==r.exitCount
end
function R.duty(r,npc)
    local a=r and r.actors[npc] if not a then return nil end
    return r.index==1 and 'ROLE_READY' or r.index==3 and 'ROLE_EXIT' or a.roleId=='speaker' and 'ROLE_SPEAK' or 'ROLE_LISTEN'
end
function R.requestEnd(r,outcome,hours)
    if not R.valid(r) or not terminal[outcome] or not number(hours) then return false end
    if outcome=='COMPLETED' and r.index~=3 then return false end
    if r.state~='RUNNING' then return r.requestedOutcome==outcome end
    r.state='CLOSING' r.requestedOutcome=outcome r.endRequestedAt=hours return true
end
function R.exit(event,npc,jobId,epoch)
    local r=event.stage if not shape(r) then return false end
    local a=r.actors[npc]
    if not a then return true end
    if event.stageBlocked or r.scope.eventId~=event.id or r.scope.worldId~=event.worldId
        or a.jobId~=jobId or a.participantEpoch~=epoch then return false end
    if not r.exits[npc] then r.exits[npc]=true r.exitCount=r.exitCount+1 end
    return true
end
function R.finish(r,hours)
    if not R.valid(r) or not number(hours) then return false,'ACTIVITY_STAGE_UNSUPPORTED' end
    if r.state=='CLOSED' then return true,r.outcome end
    if r.state~='CLOSING' or r.exitCount~=r.actorCount then return false,'ACTIVITY_STAGE_EXIT_PENDING' end
    r.state='CLOSED' r.outcome=r.requestedOutcome r.endedAt=hours return true,r.outcome
end
return R
