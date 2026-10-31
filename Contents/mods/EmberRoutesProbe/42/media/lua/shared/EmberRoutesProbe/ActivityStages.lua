-- Finite, scalar stage facts. No action execution, timers, assets or callbacks.
-- Receipt admission is internal: a native owner must verify its live Job first.
local M={MAX_STAGES=16,MAX_ROLES=16,MAX_ACTORS=256}
local outcomes={RUNNING=true,SUCCEEDED=true,FAILED=true,CANCELLED=true,UNKNOWN=true}
local endings={COMPLETED=true,INCOMPLETE=true,CANCELLED=true,FAILED=true,SKIPPED=true}
local function integer(n,a,b) return type(n)=='number' and n==n and n==math.floor(n) and n>=a and n<=b end
local function id(s) return type(s)=='string' and #s>0 and #s<=128 and not s:find('[%c]') end
local function number(n) return type(n)=='number' and n==n and n>=0 and n<100000000 end
local function copy(t) if type(t)~='table' then return t end local r={} for k,v in pairs(t) do r[k]=copy(v) end return r end
local function array(t,max)
    if type(t)~='table' then return nil end
    local n=0 for key in pairs(t) do n=n+1 if not integer(key,1,max) or n>max then return nil end end
    for i=1,n do if t[i]==nil then return nil end end return n
end
local fields={id=true,roleBehaviorIds=true,completionRule=true,durationGameMinutes=true,
    timeoutGameMinutes=true,requiredReceipts=true,optional=true,timeoutPolicy=true,lateJoin=true}
function M.plan(value)
    local n=array(value,M.MAX_STAGES) if not n or n<1 then return nil,'ACTIVITY_STAGE_INVALID' end
    local result,seen={},{}
    for i=1,n do
        local s=value[i] if type(s)~='table' then return nil,'ACTIVITY_STAGE_INVALID' end
        for key in pairs(s) do if not fields[key] then return nil,'ACTIVITY_STAGE_INVALID' end end
        if not id(s.id) or seen[s.id] or type(s.roleBehaviorIds)~='table'
            or s.completionRule~='DURATION' and s.completionRule~='RECEIPTS' and s.completionRule~='BOTH'
            or s.optional~=nil and type(s.optional)~='boolean' or s.lateJoin~=nil and type(s.lateJoin)~='boolean' then return nil,'ACTIVITY_STAGE_INVALID' end
        local roles,count={},0
        for role,behavior in pairs(s.roleBehaviorIds) do
            count=count+1 if count>M.MAX_ROLES or not id(role) or not id(behavior) then return nil,'ACTIVITY_STAGE_INVALID' end
            roles[role]=behavior
        end
        if count==0 then return nil,'ACTIVITY_STAGE_INVALID' end
        local required={} local r=array(s.requiredReceipts or {},M.MAX_ROLES)
        if not r then return nil,'ACTIVITY_STAGE_INVALID' end
        for _,role in ipairs(s.requiredReceipts or {}) do
            if not roles[role] or required[role] then return nil,'ACTIVITY_STAGE_INVALID' end required[role]=true
        end
        local duration=s.durationGameMinutes or 0 local timeout=s.timeoutGameMinutes or duration
        if not number(duration) or duration>1440 or not number(timeout) or timeout<=0 or timeout>1440 or timeout<duration
            or s.completionRule~='RECEIPTS' and duration<=0
            or s.completionRule~='DURATION' and r==0
            or s.timeoutPolicy~=nil and s.timeoutPolicy~='INCOMPLETE' and s.timeoutPolicy~='SKIP'
            or s.timeoutPolicy=='SKIP' and not s.optional then return nil,'ACTIVITY_STAGE_INVALID' end
        result[i]={id=s.id,roles=roles,required=required,completion=s.completionRule,durationHours=duration/60,
            timeoutHours=timeout/60,optional=s.optional==true,lateJoin=s.lateJoin==true,timeoutPolicy=s.timeoutPolicy or 'INCOMPLETE'}
        seen[s.id]=true
    end
    return result
end
local function specValid(s)
    if type(s)~='table' or not id(s.id) or type(s.roles)~='table' or type(s.required)~='table'
        or s.completion~='DURATION' and s.completion~='RECEIPTS' and s.completion~='BOTH'
        or not number(s.durationHours) or s.durationHours>24 or not number(s.timeoutHours)
        or s.timeoutHours<=0 or s.timeoutHours>24 or s.timeoutHours<s.durationHours
        or s.completion~='RECEIPTS' and s.durationHours<=0
        or type(s.optional)~='boolean' or type(s.lateJoin)~='boolean'
        or s.timeoutPolicy~='INCOMPLETE' and s.timeoutPolicy~='SKIP'
        or s.timeoutPolicy=='SKIP' and not s.optional then return false end
    local n,r=0,0
    for role,behavior in pairs(s.roles) do n=n+1 if n>M.MAX_ROLES or not id(role) or not id(behavior) then return false end end
    for role,required in pairs(s.required) do r=r+1 if r>M.MAX_ROLES or not s.roles[role] or required~=true then return false end end
    return n>0 and (s.completion=='DURATION' or r>0)
end
function M.supports(plan,capabilities)
    local n=array(plan,M.MAX_STAGES)
    if not n or n==0 or type(capabilities)~='table' then return false end
    for _,s in ipairs(plan) do
        if not specValid(s) then return false end
        for _,behavior in pairs(s.roles) do if capabilities[behavior]~=true then return false end end
    end
    return true
end
local function scope(s)
    return type(s)=='table' and id(s.worldId) and id(s.eventId) and integer(s.controlEpoch,1,9007199254740000)
        and integer(s.stageEpoch,1,9007199254740000)
end
local function shape(r)
    return type(r)=='table' and r.format==1 and scope(r.scope) and id(r.id) and integer(r.index,1,M.MAX_STAGES)
        and (r.state=='RUNNING' or r.state=='CLOSING' or r.state=='CLOSED') and number(r.startedAt)
        and specValid(r.spec) and r.spec.id==r.id
        and type(r.actors)=='table' and type(r.receipts)=='table' and type(r.exits)=='table'
        and integer(r.actorCount,1,M.MAX_ACTORS) and integer(r.exitCount,0,r.actorCount)
end
function M.valid(r)
    if type(r)=='table' and r.format==2 then return require('EmberRoutesProbe/ActivityPhaseRecord').valid(r) end
    if not shape(r) then return false end
    local n,x,roles=0,0,{}
    for npc,a in pairs(r.actors) do
        n=n+1 if n>M.MAX_ACTORS or not id(npc) or type(a)~='table' or not id(a.jobId)
            or not integer(a.participantEpoch,1,9007199254740000) or not r.spec.roles[a.roleId]
            or a.attemptId~=nil and not id(a.attemptId) then return false end
        roles[a.roleId]=true
    end
    for npc,receipt in pairs(r.receipts) do
        if not r.actors[npc] or not r.actors[npc].attemptId or type(receipt)~='table' or receipt.attemptId~=r.actors[npc].attemptId
            or not outcomes[receipt.status] or type(receipt.bodyStopped)~='boolean' or type(receipt.effectsKnown)~='boolean' then return false end
    end
    for npc,exited in pairs(r.exits) do
        if not r.actors[npc] or exited~=true then return false end
        local receipt=r.receipts[npc]
        if r.actors[npc].attemptId and (not receipt or receipt.status=='UNKNOWN' or receipt.status=='RUNNING'
            or not receipt.bodyStopped or not receipt.effectsKnown) then return false end
        x=x+1
    end
    for role in pairs(r.spec.required) do if not roles[role] then return false end end
    if r.state~='RUNNING' and (not endings[r.requestedOutcome] or not number(r.endRequestedAt)) then return false end
    if r.state=='CLOSED' and not number(r.endedAt) then return false end
    return n==r.actorCount and x==r.exitCount and (r.state~='CLOSED' or x==n and endings[r.outcome]==true)
end
function M.begin(plan,index,ref,actors,hours,previous)
    local n=array(plan,M.MAX_STAGES) if not n or not integer(index,1,n) then return nil,'ACTIVITY_STAGE_INVALID' end
    for _,item in ipairs(plan) do if not specValid(item) then return nil,'ACTIVITY_STAGE_INVALID' end end
    local s=plan[index]
    if not s or not scope(ref) or not number(hours) or type(actors)~='table' then return nil,'ACTIVITY_STAGE_INVALID' end
    if previous then
        if not M.valid(previous) or previous.state~='CLOSED' or previous.outcome~='COMPLETED' and previous.outcome~='SKIPPED'
            or index~=previous.index+1 or ref.worldId~=previous.scope.worldId or ref.eventId~=previous.scope.eventId
            or ref.controlEpoch~=previous.scope.controlEpoch or ref.stageEpoch~=previous.scope.stageEpoch+1 then return nil,'ACTIVITY_STAGE_PREDECESSOR_PENDING' end
    elseif index~=1 then return nil,'ACTIVITY_STAGE_PREDECESSOR_PENDING' end
    local frozen,count,roles={ },0,{}
    for npc,a in pairs(actors) do
        count=count+1
        if count>M.MAX_ACTORS or not id(npc) or type(a)~='table' or not id(a.jobId)
            or not integer(a.participantEpoch,1,9007199254740000) or not s.roles[a.roleId] then return nil,'ACTIVITY_STAGE_INVALID' end
        if previous and not previous.actors[npc] and not s.lateJoin then return nil,'ACTIVITY_STAGE_LATE_JOIN' end
        frozen[npc]={jobId=a.jobId,participantEpoch=a.participantEpoch,roleId=a.roleId} roles[a.roleId]=true
    end
    if count==0 then return nil,'ACTIVITY_STAGE_INVALID' end
    for role in pairs(s.required) do if not roles[role] then return nil,'ACTIVITY_STAGE_REQUIRED_ROLE' end end
    if previous then
        for npc,a in pairs(previous.actors) do
            if previous.spec.required[a.roleId] and (not frozen[npc] or frozen[npc].participantEpoch~=a.participantEpoch) then return nil,'ACTIVITY_STAGE_REQUIRED_ROLE' end
        end
    end
    return {format=1,id=s.id,index=index,scope={worldId=ref.worldId,eventId=ref.eventId,
        controlEpoch=ref.controlEpoch,stageEpoch=ref.stageEpoch},spec=copy(s),state='RUNNING',startedAt=hours,
        actors=frozen,actorCount=count,receipts={},exits={},exitCount=0}
end
local function matches(r,m)
    if not shape(r) or r.state=='CLOSED' or type(m)~='table' then return nil,'ACTIVITY_STAGE_STALE' end
    local a=r.actors[m.npcId] if not a then return nil,'ACTIVITY_STAGE_STALE' end
    for _,key in ipairs({'worldId','eventId','controlEpoch','stageEpoch'}) do if m[key]~=r.scope[key] then return nil,'ACTIVITY_STAGE_STALE' end end
    if m.jobId~=a.jobId or m.participantEpoch~=a.participantEpoch then return nil,'ACTIVITY_STAGE_STALE' end
    return a
end
function M.issue(r,m)
    local a,why=matches(r,m) if not a then return false,why end
    if r.state~='RUNNING' or r.exits[m.npcId] or not id(m.actionAttemptId) then return false,'ACTIVITY_STAGE_STALE' end
    if a.attemptId and a.attemptId~=m.actionAttemptId then return false,'ACTIVITY_STAGE_ATTEMPT_CONFLICT' end
    a.attemptId=m.actionAttemptId return true
end
function M.record(r,m)
    local a,why=matches(r,m) if not a then return false,why end
    if not a.attemptId or m.actionAttemptId~=a.attemptId or not outcomes[m.status]
        or type(m.bodyStopped)~='boolean' or type(m.effectsKnown)~='boolean' then return false,'ACTIVITY_STAGE_STALE' end
    local old=r.receipts[m.npcId]
    if old and old.status=='UNKNOWN' and not (m.reconciled==true and m.status~='UNKNOWN'
        and m.status~='RUNNING' and m.bodyStopped and m.effectsKnown) then return false,'ACTIVITY_STAGE_UNKNOWN' end
    if old and old.status~='RUNNING' and old.status~='UNKNOWN' and old.status~=m.status and m.status~='UNKNOWN' then return false,'ACTIVITY_STAGE_ATTEMPT_CONFLICT' end
    if old and old.bodyStopped and not m.bodyStopped and m.status~='UNKNOWN' then return false,'ACTIVITY_STAGE_STALE' end
    if old and old.effectsKnown and not m.effectsKnown and m.status~='UNKNOWN' then return false,'ACTIVITY_STAGE_STALE' end
    r.receipts[m.npcId]={attemptId=a.attemptId,status=m.status,bodyStopped=m.bodyStopped,effectsKnown=m.effectsKnown}
    if (m.status=='UNKNOWN' or not m.bodyStopped or not m.effectsKnown) and r.exits[m.npcId] then
        r.exits[m.npcId]=nil r.exitCount=r.exitCount-1
    end
    return true
end
function M.evaluate(r,hours)
    if not shape(r) or not number(hours) then return 'UNKNOWN','ACTIVITY_STAGE_UNSUPPORTED' end
    local complete=true
    for npc,a in pairs(r.actors) do
        local receipt=r.receipts[npc]
        if receipt and (receipt.status=='UNKNOWN' or not receipt.effectsKnown) then return 'UNKNOWN','ACTIVITY_STAGE_UNKNOWN' end
        if r.spec.required[a.roleId] then
            if receipt and (receipt.status=='FAILED' or receipt.status=='CANCELLED') then return 'FAILED','ACTIVITY_STAGE_FAILED' end
            if not receipt or receipt.status~='SUCCEEDED' then complete=false end
        end
    end
    local timed=hours>=r.startedAt+r.spec.durationHours
    if (r.spec.completion=='DURATION' or complete) and (r.spec.completion=='RECEIPTS' or timed) then return 'COMPLETED' end
    if hours>=r.startedAt+r.spec.timeoutHours then return r.spec.optional and r.spec.timeoutPolicy=='SKIP' and 'SKIPPED' or 'INCOMPLETE','ACTIVITY_STAGE_TIMEOUT' end
    return 'WAIT'
end
function M.requestEnd(r,outcome,hours)
    if type(r)=='table' and r.format==2 then return require('EmberRoutesProbe/ActivityPhaseRecord').requestEnd(r,outcome,hours) end
    if not shape(r) or not endings[outcome] or not number(hours) then return false,'ACTIVITY_STAGE_UNSUPPORTED' end
    if r.state~='RUNNING' then return r.requestedOutcome==outcome end
    if outcome=='COMPLETED' or outcome=='SKIPPED' then
        local status=M.evaluate(r,hours) if status~=outcome then return false,'ACTIVITY_STAGE_NOT_COMPLETE' end
    end
    r.state='CLOSING' r.requestedOutcome=outcome r.endRequestedAt=hours return true
end
function M.exit(r,m)
    local a,why=matches(r,m) if not a then return false,why end
    if m.bodyStopped~=true or m.effectsKnown~=true then return false,'ACTIVITY_STAGE_UNKNOWN' end
    local receipt=r.receipts[m.npcId]
    if a.attemptId and (not receipt or m.actionAttemptId~=a.attemptId or receipt.status=='RUNNING'
        or receipt.status=='UNKNOWN' or not receipt.bodyStopped or not receipt.effectsKnown) then return false,'ACTIVITY_STAGE_UNKNOWN' end
    if not r.exits[m.npcId] then r.exits[m.npcId]=true r.exitCount=r.exitCount+1 end
    return true
end
function M.finish(r,hours)
    if type(r)=='table' and r.format==2 then return require('EmberRoutesProbe/ActivityPhaseRecord').finish(r,hours) end
    if not shape(r) or not number(hours) then return false,'ACTIVITY_STAGE_UNSUPPORTED' end
    if r.state=='CLOSED' then return true,r.outcome end
    if r.state~='CLOSING' or r.exitCount~=r.actorCount then return false,'ACTIVITY_STAGE_EXIT_PENDING' end
    local status=M.evaluate(r,hours)
    if status=='UNKNOWN' then return false,'ACTIVITY_STAGE_UNKNOWN' end
    local outcome=r.requestedOutcome
    if outcome=='COMPLETED' and status~='COMPLETED' then
        if status=='WAIT' then return false,'ACTIVITY_STAGE_NOT_COMPLETE' end outcome='INCOMPLETE'
    end
    r.state='CLOSED' r.outcome=outcome r.endedAt=hours return true,outcome
end
function M.retirable(r) return r==nil or (type(r)=='table' and r.format==2 and M.valid(r) or shape(r)) and r.state=='CLOSED' and r.exitCount==r.actorCount end
function M.free(event,set,hours,epoch)
    local plan=M.plan({{id='free',roleBehaviorIds={participant='EXISTING_FREE_SELECTOR'},completionRule='DURATION',
        durationGameMinutes=event.durationHours*60,requiredReceipts={},lateJoin=false}})
    local actors={}
    for npc in pairs(set) do local m=event.roster[npc] actors[npc]={jobId=m.jobId,participantEpoch=m.participantEpoch or 1,roleId='participant'} end
    return M.begin(plan,1,{worldId=event.worldId,eventId=event.id,controlEpoch=event.controlEpoch,stageEpoch=epoch},actors,hours)
end
-- Called only after Participant has proved both its ACTIVITY Job and associated
-- personal/original-item cleanup. It is not an action completion notification.
function M.participantExit(event,npc,jobId,participantEpoch)
    local r=event.stage
    if not r then return true end
    if type(r)~='table' then return false end
    if r.format==2 then return require('EmberRoutesProbe/ActivityPhaseRecord').exit(event,npc,jobId,participantEpoch) end
    if event.stageBlocked or not shape(r) or r.id~='free' or r.scope.worldId~=event.worldId or r.scope.eventId~=event.id then return false end
    if not r.actors[npc] then return true end
    if r.exits[npc] then return true end
    local m=copy(r.scope) m.npcId=npc m.jobId=jobId m.participantEpoch=participantEpoch m.bodyStopped=true m.effectsKnown=true
    return M.exit(r,m)
end
M.freeExit=M.participantExit -- legacy internal caller name; proof semantics unchanged
return M
