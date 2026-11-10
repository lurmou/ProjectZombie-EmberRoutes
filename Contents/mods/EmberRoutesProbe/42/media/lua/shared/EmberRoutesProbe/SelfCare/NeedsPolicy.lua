-- Normalized native Stats; no inventory access or physical side effects.
-- Thresholds live in this table only: enter/leave are the idle thresholds,
-- workEnter is the relaxed threshold while the NPC is on duty (working
-- NPCs tolerate worse needs before breaking off). The leisure gates in
-- LeisureConfig carry numerically equal values by coincidence, not by
-- contract; do not merge the two tables.
local Policy={}
local HYSTERESIS=0.15 -- added to the active need's score so it is not
    -- dropped by a marginal reading the next tick (debounce, not a threshold)
local rules={{kind='DRINK',field='thirst',enter=0.20,leave=0.05,workEnter=0.45},
    {kind='EAT',field='hunger',enter=0.25,leave=0.10,workEnter=0.50},
    {kind='SLEEP',field='fatigue',enter=0.70,leave=0.25,workEnter=0.85},
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
