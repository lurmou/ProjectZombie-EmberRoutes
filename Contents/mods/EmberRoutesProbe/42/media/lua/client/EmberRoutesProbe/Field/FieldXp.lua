-- Task-driven XP only, through the 6-arg AddXP overload: the 2/3/4-arg ones
-- return early for non-local characters, so engine-side action XP never lands.
-- Third arg (ignoreBoosts) is false so vanilla skill books, traits (Fast Learner),
-- and starting profession boosts are respected.
local Award={}
local PERK={farming='Farming',lumberjack='Woodwork',forager='PlantScavenging',cooking='Cooking'}
local BASE_XP={farming=10,lumberjack=8,cooking=8,forager=5}
function Award.job(npc,job)
    local payload=job and job.payload
    local cat=payload and payload.category
    local name=cat and PERK[cat]
    local perk=name and Perks and Perks[name]
    if not perk or not npc or not npc.getXp then return false end
    local ok,xp=pcall(npc.getXp,npc)
    if not ok or not xp then return false end
    local base=BASE_XP[cat] or 5
    local amount=base*math.max(1,payload.batchCount or 1)
    return pcall(xp.AddXP,xp,perk,amount,false,false,false,false)
end
return Award
