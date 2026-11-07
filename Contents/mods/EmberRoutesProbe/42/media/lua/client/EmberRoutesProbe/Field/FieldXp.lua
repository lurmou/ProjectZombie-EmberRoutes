-- Task-driven XP only, through the 6-arg AddXP overload: the 2/3/4-arg ones
-- return early for non-local characters, so engine-side action XP never lands.
local Award={}
local PERK={farming='Farming',lumberjack='Woodwork',forager='PlantScavenging',cooking='Cooking'}
function Award.job(npc,job)
    local payload=job and job.payload
    local name=payload and PERK[payload.category]
    local perk=name and Perks and Perks[name]
    if not perk or not npc or not npc.getXp then return false end
    local ok,xp=pcall(npc.getXp,npc)
    if not ok or not xp then return false end
    local amount=5*math.max(1,payload.batchCount or 1)
    return pcall(xp.AddXP,xp,perk,amount,true,false,false,false)
end
return Award
