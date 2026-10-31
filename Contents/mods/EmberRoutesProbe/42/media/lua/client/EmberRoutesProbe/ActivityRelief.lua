-- Sole activity effect writer, invoked only by the existing world's Pump.
-- Does not issue bodies, clear Claims or settle another action's effects.
local Record=require 'EmberRoutesProbe/ActivityReliefRecord'
local Store=require 'EmberRoutesProbe/ActivityStore'
local Driver=require 'EmberRoutesProbe/Driver'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local E={}
local remaining=0
function E.budget(n) remaining=n end
local function finish(event,r,state,reason)
    r.state=state r.reason=reason Store.touch(event) return Record.terminal(r)
end
local function nativeValid(marker,event,id)
    return type(marker)=='table' and marker.format==1 and marker.ruleVersion==Record.VERSION and marker.worldId==event.worldId and marker.npcId==id
        and type(marker.eventId)=='string' and Record.finite(marker.untilHours)
        and (marker.state=='APPLIED' or marker.state=='APPLYING' or marker.state=='UNKNOWN')
end
function E.step(event,id,allow)
    if not event.reliefVersion then return true end
    if event.reliefBlocked or not event.reliefPrepared then return false end
    local m=event.roster[id] local r=m and m.relief
    if Record.terminal(r) then return true end
    if not r or r.state=='UNKNOWN' or not allow or remaining<=0 then return false end
    if r.state=='APPLYING' then return finish(event,r,'UNKNOWN','INTERRUPTED_WRITE') end
    if Store.get(event.id)~=event or event.outcome~='COMPLETED' or event.reliefInterrupted then
        return finish(event,r,'SKIPPED','INTERRUPTED')
    end
    local rt=Runtime.current()
    if not rt or rt:status(id) then return false end -- do not interrupt new self care/work
    remaining=remaining-1
    local binding=Driver.bindId(getSpecificPlayer(0),id)
    if not binding or not Driver.valid(binding) or binding.handle:isDead() then
        return finish(event,r,'SKIPPED','CARRIER_UNAVAILABLE')
    end
    local npc=binding.handle
    if not npc.getModData or not npc.getStats or not CharacterStat or not CharacterStat.BOREDOM
        or not CharacterStat.UNHAPPINESS or not CharacterStat.STRESS then return finish(event,r,'SKIPPED','UNSUPPORTED') end
    local data=npc:getModData() local stats=npc:getStats()
    if not data or not stats or not stats.get or not stats.set then return finish(event,r,'SKIPPED','UNSUPPORTED') end
    local marker=data.EmberRoutesSpeechRelief local hours=getGameTime():getWorldAgeHours()
    if not Record.finite(hours) then return false end
    if marker~=nil then
        if not nativeValid(marker,event,id) or marker.state~='APPLIED' or marker.eventId==event.id then
            return finish(event,r,'UNKNOWN','NATIVE_RECEIPT_UNRESOLVED')
        end
        if hours<marker.untilHours or event.reliefAt<marker.untilHours then return finish(event,r,'SKIPPED','COOLDOWN') end
    end
    local before={stats:get(CharacterStat.BOREDOM),stats:get(CharacterStat.UNHAPPINESS),stats:get(CharacterStat.STRESS)}
    if not Record.finite(before[1]) or before[1]>100 or not Record.finite(before[2]) or before[2]>100
        or not Record.finite(before[3]) or before[3]>1 then return finish(event,r,'SKIPPED','UNSUPPORTED') end
    local after={math.max(0,before[1]-Record.BOREDOM*r.hours),math.max(0,before[2]-Record.UNHAPPINESS*r.hours),
        math.max(0,before[3]-Record.STRESS*r.hours)}
    if after[1]==before[1] and after[2]==before[2] and after[3]==before[3] then return finish(event,r,'SKIPPED','NO_CHANGE') end
    r.before=before r.after=after r.state='APPLYING' r.at=hours
    if not Store.touch(event) then r.state='UNKNOWN' r.reason='STORE_CHANGED' return false end
    marker={format=1,ruleVersion=Record.VERSION,worldId=event.worldId,npcId=id,eventId=event.id,state='APPLYING',untilHours=hours+Record.COOLDOWN}
    data.EmberRoutesSpeechRelief=marker
    -- Deliberately narrow fault boundary: any partial native write is unknown.
    -- Stats.set(false) is a valid no-op, never evidence that a write failed.
    local ok=pcall(function()
        stats:set(CharacterStat.BOREDOM,after[1])
        stats:set(CharacterStat.UNHAPPINESS,after[2])
        stats:set(CharacterStat.STRESS,after[3])
        r.observed={stats:get(CharacterStat.BOREDOM),stats:get(CharacterStat.UNHAPPINESS),stats:get(CharacterStat.STRESS)}
    end)
    if not ok or not r.observed or not Record.finite(r.observed[1]) or not Record.finite(r.observed[2]) or not Record.finite(r.observed[3])
        or math.abs((r.observed and r.observed[1] or -1)-after[1])>0.0001
        or math.abs((r.observed and r.observed[2] or -1)-after[2])>0.0001
        or math.abs((r.observed and r.observed[3] or -1)-after[3])>0.000001 then
        marker.state='UNKNOWN' return finish(event,r,'UNKNOWN','WRITE_UNCONFIRMED')
    end
    marker.state='APPLIED'
    return finish(event,r,'APPLIED',nil)
end
return E
