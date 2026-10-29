-- Pure eligibility and weighted selection. Never reads or mutates a body.
local Config=require 'EmberRoutesProbe/LeisureConfig'
local P={}
function P.allowed(kind,s,context)
    if not s or not s.safe or not context or not context.hold or not s.healthy
        or s.hunger>=Config.gates.hunger or s.thirst>=Config.gates.thirst
        or s.fatigue>=Config.gates.fatigue or s.endurance<=Config.gates.endurance then return false end
    if kind=='FITNESS' then
        return (s.health or 100)>=95 and s.handsFree==true and s.fitnessKnown==true and not s.stiff
            and s.fatigue<Config.fitness.fatigue and s.endurance>Config.fitness.endurance and s.pain<Config.fitness.pain
    end
    if kind=='SMOKE' then return s.smoker==true and s.handsFree==true end
    if kind=='STROLL' then
        return (s.health or 100)>=85 and s.fatigue<Config.stroll.fatigue and s.endurance>Config.stroll.endurance and s.pain<Config.stroll.pain
    end
    return kind=='OBSERVE' or kind=='SOCIAL' or kind=='READING' or kind=='SIT'
end
function P.weight(kind,s,base)
    if kind=='READING' then return base*(1+math.min(1,s.boredom or 0)) end
    if kind=='SMOKE' then return base*(1+math.min(1,s.stress or 0)) end
    if kind=='SIT' then return base*(1+math.max(0,1-s.endurance)+s.fatigue) end
    if kind=='FITNESS' then return base*math.max(0.2,s.endurance-s.fatigue) end
    return base
end
function P.choose(candidates,memory,hours,roll)
    local weights,total={},0
    for i,c in ipairs(candidates) do
        local cooldown=memory and memory.cooldowns and memory.cooldowns[c.activity] or 0
        local w=hours>=cooldown and math.max(0,c.weight or 1) or 0
        if c.moving and memory and hours<(memory.moveAfter or 0) then w=0 end
        if memory and memory.last==c.activity then w=w*Config.repeatWeightFactor end
        weights[i]=w total=total+w
    end
    if total<=0 then return end
    local remaining=math.max(0,math.min(0.999999,roll))*total
    for i,c in ipairs(candidates) do remaining=remaining-weights[i] if remaining<0 then return c end end
end
function P.pause(memory,hours,roll)
    memory=memory or {cooldowns={}}
    local minutes=Config.decisionPauseMin+(Config.decisionPauseMax-Config.decisionPauseMin)*math.max(0,math.min(1,roll))
    memory.decisionAfter=hours+minutes/60
    return memory
end
function P.remember(memory,kind,hours,success)
    memory=memory or {cooldowns={}} memory.cooldowns=memory.cooldowns or {}
    memory.last=kind
    local delay=success and (Config.cooldownHours[kind] or Config.cooldownHours.default) or Config.cooldownHours.failed
    memory.cooldowns[kind]=hours+delay
    return memory
end
return P
