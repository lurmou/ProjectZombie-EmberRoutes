local R={}
local activities={OBSERVE=true,STROLL=true,FITNESS=true,SOCIAL=true,SMOKE=true,SIT=true}
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function point(p) return type(p)=='table' and finite(p.x) and finite(p.y) and finite(p.z) end
function R.tileKey(p) return 'leisureTile:'..math.floor(p.x)..':'..math.floor(p.y)..':'..p.z end
function R.valid(p)
    local l=p.leisure
    if not l then return p.kind~='LEISURE' end
    if p.kind~='LEISURE' or type(l)~='table' or l.format~=1 or not activities[l.activity] or not finite(l.hours) or l.hours<0 then return false end
    if type(p.settlementId)~='string' or #p.settlementId<1 or #p.settlementId>256 then return false end
    if l.roleDuty~=nil and (l.roleDuty~='ROLE_SPEAK' and l.roleDuty~='ROLE_LISTEN'
        or l.activity~='OBSERVE' or l.brief~=true or l.zoneVisit~=nil or type(p.activityRef)~='table'
        or p.activityRef.dutyId~=l.roleDuty or p.activityRef.dutyFormat~=2) then return false end
    if l.roleHours~=nil and (not finite(l.roleHours) or l.roleHours<0 or l.roleHours>24) then return false end
    for _,field in ipairs({'untilHours','before','after','fireBefore','fireAfter'}) do
        if l[field]~=nil and (not finite(l[field]) or l[field]<0) then return false end
    end
    if l.point~=nil and not point(l.point) then return false end
    if l.zoneVisit~=nil then
        local zone=l.zoneVisit
        if l.activity~='OBSERVE' or l.brief or not point(l.point) or l.moving~=true
            or type(zone)~='table' or type(zone.id)~='string' or #zone.id<1 or #zone.id>256
            or not finite(zone.revision) or zone.revision<1 or zone.revision~=math.floor(zone.revision)
            or zone.eventId~=nil and (type(zone.eventId)~='string' or #zone.eventId<1 or #zone.eventId>128)
              or zone.participantEpoch~=nil and (not finite(zone.participantEpoch) or zone.participantEpoch<1
                  or zone.participantEpoch~=math.floor(zone.participantEpoch))
            or l.point.z~=math.floor(l.point.z) then return false end
    end
    if l.activity=='SOCIAL' and (type(l.socialId)~='string' or #l.socialId<1 or #l.socialId>256) then return false end
    if l.repetitions~=nil and (not finite(l.repetitions) or l.repetitions<0 or l.repetitions~=math.floor(l.repetitions)) then return false end
    for _,field in ipairs({'moving','seated','brief','started','finished','applying','applied','stopped'}) do
        if l[field]~=nil and type(l[field])~='boolean' then return false end
    end
    if l.fireId~=nil and (not finite(l.fireId) or l.fireId~=math.floor(l.fireId)) then return false end
    return true
end
function R.memory(value)
    if value==nil then return true end
    if type(value)~='table' or type(value.cooldowns)~='table' then return false end
    local count=0
    for key,n in pairs(value.cooldowns) do
        count=count+1 if count>7 or not (activities[key] or key=='READING') or not finite(n) or n<0 then return false end
    end
    if value.decisionAfter~=nil and (not finite(value.decisionAfter) or value.decisionAfter<0) then return false end
    if value.moveAfter~=nil and (not finite(value.moveAfter) or value.moveAfter<0) then return false end
    if value.seatPreference~=nil and not point(value.seatPreference) then return false end
    return value.last==nil or activities[value.last] or value.last=='READING'
end
return R
