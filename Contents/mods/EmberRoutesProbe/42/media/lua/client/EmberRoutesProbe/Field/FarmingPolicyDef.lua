-- Farming Policy Definition.
-- Declares settlement-level directives for farming operations. Targets
-- (water / harvest / clear / sow) are derived from live crop state, but they
-- are only meaningful inside the assigned farm zone: an unset zone means no
-- farming work at all, never "the whole settlement territory".
local Registry = require 'EmberRoutesProbe/Kernel/JobPolicyRegistry'

local FarmingPolicyDef = {
    category = 'farming',
    order = 15,
    titleKey = 'IGUI_EmberRoutesProbe_Policy_farm_title',
    descKey = 'IGUI_EmberRoutesProbe_Policy_farm_desc',
}

function FarmingPolicyDef.getDefaults()
    return {
        maxContinuousBatch = 8,
        farmZoneId = '',
        walkwayEvery = 4,
    }
end

function FarmingPolicyDef.getFields(settlementId)
    return {
        {
            key = 'farmZoneId',
            editor = 'zone_dropdown',
            label = 'IGUI_EmberRoutesProbe_Policy_farm_zone',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_farm_zone_tip',
        },
        {
            key = 'walkwayEvery',
            editor = 'slider',
            label = 'IGUI_EmberRoutesProbe_Policy_farm_walkway',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_farm_walkway_tip',
            min = 0,
            max = 8,
            step = 1,
            unit = 'rows',
        },
        {
            key = 'maxContinuousBatch',
            editor = 'slider',
            label = 'IGUI_EmberRoutesProbe_Policy_farm_maxBatch',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_farm_maxBatch_tip',
            min = 1,
            max = 16,
            step = 1,
            unit = 'targets',
        },
    }
end

function FarmingPolicyDef.validate(draft)
    if type(draft) ~= 'table' then return false, 'POLICY_INVALID_TYPE' end
    if draft.farmZoneId ~= nil and type(draft.farmZoneId) ~= 'string' then
        return false, 'INVALID_FARM_ZONE_ID'
    end
    if draft.walkwayEvery ~= nil and (type(draft.walkwayEvery) ~= 'number' or draft.walkwayEvery < 0
        or draft.walkwayEvery > 8 or draft.walkwayEvery ~= math.floor(draft.walkwayEvery)) then
        return false, 'INVALID_FARM_WALKWAY'
    end
    if draft.maxContinuousBatch ~= nil and (type(draft.maxContinuousBatch) ~= 'number' or draft.maxContinuousBatch < 1 or draft.maxContinuousBatch > 32) then
        return false, 'INVALID_MAX_CONTINUOUS_BATCH'
    end
    return true
end

Registry.register(FarmingPolicyDef)

return FarmingPolicyDef
