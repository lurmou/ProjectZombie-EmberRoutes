-- Bounded, read-only native observation. Missing safety evidence is not safety.
local Observer={}
local world,health={},{ }
local function number(value) return type(value)=='number' and value==value and value>=0 and value<=1 end
function Observer.sample(npc,id,now)
    local root=require 'EmberRoutesProbe/ContainerRegistry'.data()
    if world~=root then world,health=root,{} end
    if not npc or not npc.getStats or not npc.getCurrentSquare or not npc:getCurrentSquare()
        or npc:isDead() or not CharacterStat then return nil,'OBSERVATION_UNAVAILABLE' end
    -- Single native batch when the extension provides it; same shape and rules
    -- as the Lua path below, including the spotted-list UNKNOWN contract.
    local bridge=EmberRoutesProbeJava
    if bridge and bridge.observerSample then
        local ok,facts=pcall(bridge.observerSample,npc)
        if ok and type(facts)=='table' then
            local sample={hunger=facts.hunger,thirst=facts.thirst,fatigue=facts.fatigue,
                endurance=facts.endurance,observedAt=now}
            for _,key in ipairs({'hunger','thirst','fatigue','endurance'}) do
                if not number(sample[key]) then return nil,'NEED_UNAVAILABLE' end
            end
            sample.safe=false
            if facts.onFire==true or type(facts.attacking)=='number' and facts.attacking>0
                or facts.spottedThreat==true then sample.safety='UNSAFE' return sample end
            if facts.spottedThreat==nil then sample.safety='UNKNOWN' return sample end
            local current=facts.health
            if type(current)~='number' or current~=current then return nil,'NEED_UNAVAILABLE' end
            local previous=health[id]
            local untilTime=previous and previous.untilTime or 0
            if previous and current<previous.value-0.01 then untilTime=now+3000 end
            health[id]={value=current,untilTime=untilTime}
            sample.safe=now>=untilTime sample.safety=sample.safe and 'SAFE' or 'RECENT_DAMAGE'
            return sample
        end
    end
    local stats=npc:getStats()
    local sample={hunger=stats:get(CharacterStat.HUNGER),thirst=stats:get(CharacterStat.THIRST),
        fatigue=stats:get(CharacterStat.FATIGUE),endurance=stats:get(CharacterStat.ENDURANCE),observedAt=now}
    for _,key in ipairs({'hunger','thirst','fatigue','endurance'}) do
        if not number(sample[key]) then return nil,'NEED_UNAVAILABLE' end
    end
    sample.safe=false
    if not npc.getSpottedList or not npc.getSurroundingAttackingZombies or not npc.isOnFire then
        sample.safety='UNKNOWN' return sample
    end
    local seen=npc:getSpottedList()
    if not seen or seen:size()>64 then sample.safety='UNKNOWN' return sample end
    if npc:isOnFire() or npc:getSurroundingAttackingZombies(false)>0 then sample.safety='UNSAFE' return sample end
    for i=0,seen:size()-1 do
        local object=seen:get(i)
        if instanceof(object,'IsoZombie') and not object:isDead() and math.abs(object:getZ()-npc:getZ())<1
            and (object:getX()-npc:getX())^2+(object:getY()-npc:getY())^2<=100 then
            sample.safety='UNSAFE' return sample
        end
    end
    local current=npc:getBodyDamage():getOverallBodyHealth()
    local previous=health[id]
    local untilTime=previous and previous.untilTime or 0
    if previous and current<previous.value-0.01 then untilTime=now+3000 end
    health[id]={value=current,untilTime=untilTime}
    sample.safe=now>=untilTime sample.safety=sample.safe and 'SAFE' or 'RECENT_DAMAGE'
    return sample
end
return Observer
