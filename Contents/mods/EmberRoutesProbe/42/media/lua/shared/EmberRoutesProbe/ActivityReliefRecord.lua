-- SPEECH_V1 outcome facts only. No native state, timers or body ownership.
local R={VERSION=1,EFFECT='SPEECH_RELIEF',COOLDOWN=2.5,BOREDOM=6,UNHAPPINESS=3,STRESS=0.02}
local states={PREPARED=true,APPLYING=true,APPLIED=true,SKIPPED=true,UNKNOWN=true}
function R.finite(n) return type(n)=='number' and n==n and n>=0 and n<100000000 end
function R.terminal(receipt) return receipt and (receipt.state=='APPLIED' or receipt.state=='SKIPPED') or false end
function R.valid(event)
    if event.reliefVersion==nil then return not event.reliefPrepared end
    if event.reliefVersion~=R.VERSION or event.scriptProfile~='SPEECH_V1'
        or event.reliefPrepared~=nil and event.reliefPrepared~=true
        or event.reliefInterrupted~=nil and event.reliefInterrupted~=true
        or event.reliefPrepared and not R.finite(event.reliefAt) then return false end
    for _,m in pairs(event.roster) do
        local r=m.relief
        if r~=nil then
            if type(r)~='table' or r.effectId~=R.EFFECT or r.ruleVersion~=R.VERSION or not states[r.state]
                or not R.finite(r.hours) or r.hours>1 or r.participantEpoch~=(m.participantEpoch or 1) then return false end
        elseif event.reliefPrepared then return false end
    end
    return true
end
function R.pending(event)
    if event.reliefBlocked then return true end
    if not event.reliefVersion then return false end
    if not event.reliefPrepared then return true end
    for _,m in pairs(event.roster) do if not R.terminal(m.relief) then return true end end
    return false
end
function R.prepare(event,hoursNow)
    if not event.reliefVersion or event.reliefPrepared or event.reliefBlocked then return end
    for _,m in pairs(event.roster) do
        local hours=R.finite(m.participationHours) and math.min(m.participationHours,1) or 0
        local eligible=not event.reliefInterrupted and not event.dutyBlocked and event.outcome=='COMPLETED' and m.joined and not m.withdrawn
            and m.duty and not m.duty.current and m.duty.lastStatus=='SUCCEEDED' and hours>0
        m.relief={effectId=R.EFFECT,ruleVersion=R.VERSION,participantEpoch=m.participantEpoch or 1,
            hours=hours,state=eligible and 'PREPARED' or 'SKIPPED',reason=not eligible and 'INELIGIBLE' or nil}
    end
    event.reliefAt=hoursNow event.reliefPrepared=true
end
function R.interrupt(event,reason)
    if not event.reliefVersion then return end
    event.reliefInterrupted=true
    for _,m in pairs(event.roster) do
        local r=m.relief
        if type(r)=='table' then
            if r.state=='APPLYING' then r.state='UNKNOWN' r.reason='INTERRUPTED_WRITE'
            elseif r.state=='PREPARED' then r.state='SKIPPED' r.reason=reason end
        end
    end
end
return R
