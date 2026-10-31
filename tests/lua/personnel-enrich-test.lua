-- PersonnelService enrichWorkers and caching test
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;" .. package.path
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local root={}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}

local mockNpc={
    getPerkLevel=function(_,perk)
        if perk=='Cooking' then return 5 end
        if perk=='Strength' then return 7 end
        if perk=='Woodwork' then return 4 end
        return 0
    end,
    getStats=function()
        return {
            getFatigue=function() return 0.2 end,
            getHunger=function() return 0.3 end,
            getThirst=function() return 0.1 end,
            getEndurance=function() return 0.9 end,
        }
    end,
    getBodyDamage=function()
        return {
            getOverallBodyHealth=function() return 95 end,
            getNumPartsBleeding=function() return 0 end,
            isInfected=function() return false end,
            hasInjury=function() return false end
        }
    end,
    getDescriptor=function()
        return {
            isFemale=function() return true end,
            getProfession=function() return 'carpenter' end
        }
    end
}

Perks={
    None='None',
    Cooking='Cooking',
    Strength='Strength',
    Fitness='Fitness',
    Woodwork='Woodwork',
    MetalWelding='MetalWelding',
    Electricity='Electricity',
    Mechanics='Mechanics',
    Tailoring='Tailoring'
}

package.loaded['EmberRoutesProbe/Driver']={
    bindId=function(_,id)
        if id=='worker1' then return {id=id,handle=mockNpc} end
        return nil
    end,
    valid=function() return true end
}
package.loaded['EmberRoutesProbe/PublicWork']={
    priorities=function(id) return {crafting=2,hauling=1,revision=1} end
}

local Service=require 'EmberRoutesProbe/PersonnelService'

local rawWorkers={
    {id='worker1',name='Alice',busy=false}
}

-- 1. Enrich call
local enriched=Service.enrichWorkers(nil,'home',rawWorkers)
if #enriched~=1 then error('enriched count should be 1') end
local w=enriched[1]
if w.id~='worker1' or w.name~='Alice' then error('id or name mismatch') end
if w.craftSkill~=5 then error('craftSkill mismatch: '..tostring(w.craftSkill)) end
if w.haulSkill~=7 then error('haulSkill mismatch: '..tostring(w.haulSkill)) end
if w.cookSkill~=5 then error('cookSkill mismatch: '..tostring(w.cookSkill)) end
if w.health~=95 then error('health mismatch: '..tostring(w.health)) end
if w.fatigue~=0.2 then error('fatigue mismatch: '..tostring(w.fatigue)) end
if w.hunger~=0.3 then error('hunger mismatch: '..tostring(w.hunger)) end
if not w.isFemale then error('isFemale should be true') end

-- 2. Modify mockNpc to test caching
mockNpc.getPerkLevel=function() return 10 end

-- Without invalidate, skills should remain cached (craftSkill should still be 5)
local enriched2=Service.enrichWorkers(nil,'home',rawWorkers)
if enriched2[1].craftSkill~=5 then error('craftSkill should be cached, got: '..tostring(enriched2[1].craftSkill)) end

-- 3. With invalidate, skills should update to 10
Service.invalidate('worker1')
local enriched3=Service.enrichWorkers(nil,'home',rawWorkers)
if enriched3[1].craftSkill~=10 then error('craftSkill should be 10 after invalidate, got: '..tostring(enriched3[1].craftSkill)) end

print('PASS PersonnelService enrichWorkers and cache lifecycle test')
