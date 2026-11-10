-- Normalized native Stats; no inventory access or physical side effects.
-- Thresholds live in this table only: enter/leave are the idle thresholds,
-- workEnter is the relaxed threshold while the NPC is on duty (working
-- NPCs tolerate worse needs before breaking off). The leisure gates in
-- LeisureConfig carry numerically equal values by coincidence, not by
-- contract; do not merge the two tables.
-- warn is the dispatch-side early warning, strictly below enter: a need at
-- warn is not yet forced self-care (choose() never reads warn), it only
-- lets dispatch deprioritize heavy work first (P0 pilot: HAUL). Only the
-- two pilot needs carry warn; DRINK/REST keep no warn level.
local Policy={}
local HYSTERESIS=0.15 -- added to the active need's score so it is not
    -- dropped by a marginal reading the next tick (debounce, not a threshold)
local rules={{kind='DRINK',field='thirst',enter=0.20,leave=0.05,workEnter=0.45},
    {kind='EAT',field='hunger',enter=0.25,leave=0.10,workEnter=0.50,warn=0.15},
    {kind='SLEEP',field='fatigue',enter=0.70,leave=0.25,workEnter=0.85,warn=0.50},
    {kind='REST',field='endurance',enter=0.25,leave=0.80,inverse=true,workEnter=0.15}}
function Policy.satisfied(kind,sample)
    for _,r in ipairs(rules) do
        if r.kind==kind then
            local v=sample[r.field]
            return type(v)=='number' and (r.inverse and v>=r.leave or not r.inverse and v<=r.leave)
        end
    end
    return false
end
function Policy.warned(sample)
    -- Dispatch-side early warning only (P0 pilot: low needs degrade first,
    -- forced self-care second). True when hunger or fatigue has reached its
    -- warn level; reaching warn alone must not trigger forced self-care,
    -- and a need already past enter is still warned (all the more reason
    -- to deprioritize heavy work). A missing sample or field is not a warning.
    if type(sample)~='table' then return false end
    for _,r in ipairs(rules) do
        if r.warn then
            local v=sample[r.field]
            if type(v)=='number' and v==v
                and (r.inverse and v<=r.warn or not r.inverse and v>=r.warn) then
                return true
            end
        end
    end
    return false
end
-- Emergency short-circuit (P0 pilot, cross-game RimWorld): decide skips
-- the provider scan entirely when the NPC is already bound for self-care.
-- Thresholds live in this table only; decide holds no literals. HUNGER and
-- THIRST are near-max on the 0-1 scale, far above the EAT/DRINK enter
-- thresholds (0.25/0.20): forced self-care already triggers at enter, the
-- short-circuit only fires when the need is extreme enough that dispatch
-- is certainly wasted. HEALTH is overall body health on the native 0-100
-- scale; 50 is pilot tuning, well below the WORK_MIN fitness line (95)
-- and above the canWork dead line (0). A deep injury (fracture, bullet,
-- glass, deep wound) is the native severe-injury flag and needs no number.
local EMERGENCY={HUNGER=0.90,THIRST=0.90,HEALTH=50}
Policy.EMERGENCY=EMERGENCY
-- SelfCare's MEDICAL semantics, as a decide-side predicate: the NPC needs
-- care now (bleeding, unbandaged injury, or a bandage due for replacement).
-- Deliberately stricter than Policy.choose's MEDICAL offer: choose only
-- offers MEDICAL when externally safe, but dispatching a hurt NPC is
-- wrong whether or not SelfCare can treat them right now.
function Policy.medicalEmergency(medical)
    return type(medical)=='table' and medical.needsCare==true
end
-- Extreme hunger or thirst. A missing/unreadable sample or field fails
-- open: no short-circuit, normal dispatch.
function Policy.extremeNeed(sample)
    if type(sample)~='table' then return false end
    local hunger,thirst=sample.hunger,sample.thirst
    return (type(hunger)=='number' and hunger==hunger and hunger>=EMERGENCY.HUNGER)
        or (type(thirst)=='number' and thirst==thirst and thirst>=EMERGENCY.THIRST)
end
-- Severe injury: a deep native injury, or overall health at/below the
-- emergency line (diffuse damage such as blood loss with every wound
-- already bandaged, which neither needsCare nor deep catches).
function Policy.severeInjury(medical)
    if type(medical)~='table' then return false end
    if medical.deep==true then return true end
    local health=medical.health
    return type(health)=='number' and health==health and health<=EMERGENCY.HEALTH
end
function Policy.choose(sample,previous,context,offers)
    if not context or context.safe~=true then return nil,'SAFETY_UNKNOWN_OR_UNSAFE' end
    if sample.medical and sample.medical.needsCare and offers.MEDICAL then return 'MEDICAL' end
    local isWorking=context and context.isWorking==true
    local best,score
    for _,r in ipairs(rules) do
        local v=sample[r.field]
        local active=previous==r.kind
        local threshold=active and r.leave or r.enter
        if isWorking and not active then threshold=r.workEnter end
        if type(v)=='number' and v==v and v>=0 and v<=1
            and (r.inverse and v<threshold or not r.inverse and v>threshold)
            and offers[r.kind]==true then
            local value=r.inverse and 1-v or v
            if active then value=value+HYSTERESIS end
            if not best or value>score then best,score=r.kind,value end
        end
    end
    return best
end
return Policy
