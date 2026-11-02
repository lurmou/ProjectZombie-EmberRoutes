-- Farming Policy Definition.
-- Declares settlement-level directives for farming operations. Farming's
-- targets (water / harvest / clear) are derived from live crop state, so the
-- only settlement knob is the continuous-batch size the shared field-work
-- skeleton reads for every category.
local Registry = require 'EmberRoutesProbe/JobPolicyRegistry'

local FarmingPolicyDef = {
    category = 'farming',
    order = 15,
    titleKey = 'IGUI_EmberRoutesProbe_Policy_farm_title',
    descKey = 'IGUI_EmberRoutesProbe_Policy_farm_desc',
}

function FarmingPolicyDef.getDefaults()
    return {
        maxContinuousBatch = 8,
    }
end

function FarmingPolicyDef.getFields(settlementId)
    return {
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
    if draft.maxContinuousBatch ~= nil and (type(draft.maxContinuousBatch) ~= 'number' or draft.maxContinuousBatch < 1 or draft.maxContinuousBatch > 32) then
        return false, 'INVALID_MAX_CONTINUOUS_BATCH'
    end
    return true
end

Registry.register(FarmingPolicyDef)

return FarmingPolicyDef
