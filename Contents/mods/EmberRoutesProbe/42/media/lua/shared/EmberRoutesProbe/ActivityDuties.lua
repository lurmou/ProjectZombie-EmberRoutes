-- Compact duty facts, not execution state or a second Job store. Native owners
-- must prove stop/effects/custody before retiring the current attempt reference.
local D={FORMAT=2}
local terminal={SUCCEEDED=true,FAILED=true,CANCELLED=true}
local function id(s) return type(s)=='string' and #s>0 and #s<=256 and not s:find('[%c]') end
local function integer(n) return type(n)=='number' and n==math.floor(n) and n>=1 and n<=9007199254740000 end
function D.validRef(ref)
    return type(ref)=='table' and ref.dutyFormat==D.FORMAT and id(ref.worldId)
        and id(ref.dutyId) and integer(ref.stageEpoch) and integer(ref.dutyEpoch)
end
function D.new() return {epoch=1,serial=0} end
function D.valid(d)
    if type(d)~='table' or not integer(d.epoch) or type(d.serial)~='number'
        or not integer(d.serial+1) then return false end
    if d.current~=nil then
        local a=d.current
        if type(a)~='table' or not id(a.jobId) or not id(a.attemptId)
            or d.serial<1 or a.unknown~=nil and a.unknown~=true
            or a.result~=nil and not terminal[a.result] then return false end
    end
    if d.lastJob~=nil or d.lastAttempt~=nil or d.lastStatus~=nil then
        if not id(d.lastJob) or not id(d.lastAttempt) or not terminal[d.lastStatus] or d.serial<1 then return false end
    end
    return true
end
function D.canIssue(d,epoch,jobId,attemptId)
    if not D.valid(d) or d.epoch~=epoch or not id(jobId) or not id(attemptId) then return false end
    if d.current then return d.current.jobId==jobId and d.current.attemptId==attemptId and not d.current.unknown end
    return not (d.lastJob==jobId and d.lastAttempt==attemptId) and d.serial<9007199254739999
end
function D.issue(d,epoch,jobId,attemptId)
    if not D.canIssue(d,epoch,jobId,attemptId) then return false end
    if d.current then return true,false end
    d.serial=d.serial+1 d.current={jobId=jobId,attemptId=attemptId}
    return true,true
end
function D.record(d,epoch,jobId,attemptId,status,cleared,reconciled)
    if not D.valid(d) or d.epoch~=epoch then return false end
    local a=d.current
    if not a then
        return d.lastJob==jobId and d.lastAttempt==attemptId and d.lastStatus==status,false
    end
    if a.jobId~=jobId or a.attemptId~=attemptId then return false end
    if status=='UNKNOWN' then
        local changed=not a.unknown a.unknown=true return true,changed
    end
    if not terminal[status] or a.unknown and reconciled~=true or a.result and a.result~=status then return false end
    if not cleared then
        local changed=a.result~=status a.result=status return true,changed
    end
    d.lastJob=jobId d.lastAttempt=attemptId d.lastStatus=status d.current=nil
    return true,true
end
function D.clear(d) return D.valid(d) and d.current==nil end
return D
