-- Cleaning Policy Definition.
-- Declares settlement-level directives for cleaning operations (corpse dumping zones,
-- clean radius, stain/rotten handling).
local Registry = require 'EmberRoutesProbe/JobPolicyRegistry'

local CleaningPolicyDef = {
    category = 'cleaning',
    order = 10,
    titleKey = 'IGUI_EmberRoutesProbe_Policy_clean_title',
    descKey = 'IGUI_EmberRoutesProbe_Policy_clean_desc',
}

function CleaningPolicyDef.getDefaults()
    return {
        corpseZoneId = '',
        cleanRadius = 20,
        haulRottenFood = true,
        cleanBloodOnly = false,
    }
end

function CleaningPolicyDef.getFields(settlementId)
    return {
        {
            key = 'corpseZoneId',
            editor = 'zone_dropdown',
            label = 'IGUI_EmberRoutesProbe_Policy_clean_corpseZone',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_clean_corpseZone_tip',
        },
        {
            key = 'cleanRadius',
            editor = 'slider',
            label = 'IGUI_EmberRoutesProbe_Policy_clean_radius',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_clean_radius_tip',
            min = 5,
            max = 50,
            step = 5,
            unit = 'sq',
        },
        {
            key = 'haulRottenFood',
            editor = 'toggle',
            label = 'IGUI_EmberRoutesProbe_Policy_clean_haulRottenFood',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_clean_haulRottenFood_tip',
        },
        {
            key = 'cleanBloodOnly',
            editor = 'toggle',
            label = 'IGUI_EmberRoutesProbe_Policy_clean_cleanBloodOnly',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_clean_cleanBloodOnly_tip',
        },
    }
end

function CleaningPolicyDef.validate(draft)
    if draft.cleanRadius ~= nil then
        if type(draft.cleanRadius) ~= 'number' or draft.cleanRadius < 1 or draft.cleanRadius > 100 then
            return false, 'INVALID_CLEAN_RADIUS'
        end
    end
    if draft.corpseZoneId ~= nil and type(draft.corpseZoneId) ~= 'string' then
        return false, 'INVALID_CORPSE_ZONE'
    end
    return true
end

-- Auto-register upon loading
Registry.register(CleaningPolicyDef)

return CleaningPolicyDef
