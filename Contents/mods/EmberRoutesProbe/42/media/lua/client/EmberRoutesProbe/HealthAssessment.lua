-- Observable body facts, bounded to one native body-part list. No healing or asset writes.
local H={}
function H.read(npc)
    if not npc or not npc.isDead or npc:isDead() or not npc.getBodyDamage then return nil,'HEALTH_UNAVAILABLE' end
    local damage=npc:getBodyDamage()
    if not damage or not damage.getBodyParts or not damage.getOverallBodyHealth then return nil,'HEALTH_UNAVAILABLE' end
    local parts=damage:getBodyParts()
    if not parts or parts:size()<1 or parts:size()>64 then return nil,'HEALTH_UNAVAILABLE' end
    local s={health=damage:getOverallBodyHealth(),bleeding=false,needsCare=false,deep=false}
    if type(s.health)~='number' or s.health~=s.health or s.health<0 or s.health>100 then return nil,'HEALTH_UNAVAILABLE' end
    for i=0,parts:size()-1 do
        local p=parts:get(i)
        if not p or not p.HasInjury or not p.bandaged or not p.bleeding then return nil,'HEALTH_UNAVAILABLE' end
        local bleeding=p:bleeding() and not p:bandaged()
        local injured=p:HasInjury()
        local replace=injured and p:bandaged() and p:getBandageLife()<=0
        if bleeding then s.bleeding=true end
        if p.deepWounded and p:deepWounded() or p.haveBullet and p:haveBullet()
            or p.haveGlass and p:haveGlass() or p.getFractureTime and p:getFractureTime()>0 then s.deep=true end
        if bleeding or injured and not p:bandaged() or replace then
            s.needsCare=true
            if not s.partIndex or bleeding and not s.selectedBleeding then
                s.partIndex=i s.replace=replace s.selectedBleeding=bleeding
            end
        end
    end
    return s
end
local cache,world={}
function H.canWork(npc)
    if not npc then return false,'HEALTH_UNAVAILABLE' end
    local root=require('EmberRoutesProbe/ContainerRegistry').data()
    if world~=root then cache,world={},root end
    local now=getTimestampMs() local saved=cache[npc]
    if not saved or now-saved.at>=1000 or now<saved.at then
        local facts,why=H.read(npc) saved={at=now,facts=facts,reason=why} cache[npc]=saved
    end
    local s=saved.facts
    if not s then return false,saved.reason end
    if s.health<=0 or npc:isDead() then return false,'HEALTH_UNAVAILABLE' end
    if s.bleeding or s.needsCare then return false,'HEALTH_NEEDS_CARE' end
    if s.deep then return false,'HEALTH_NEEDS_DOCTOR' end
    return true
end
function H.part(npc,index)
    local parts=npc and npc:getBodyDamage():getBodyParts()
    if not parts or type(index)~='number' or index~=math.floor(index) or index<0 or index>=parts:size() then return end
    return parts:get(index)
end
return H
