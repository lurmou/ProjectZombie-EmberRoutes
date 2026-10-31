-- Lumberjack Policy Definition.
-- Declares settlement-level directives for lumberjack operations (log stockpile limit,
-- assigned lumber zone, continuous batch chopping).
local Registry = require 'EmberRoutesProbe/JobPolicyRegistry'

local LumberjackPolicyDef = {
    category = 'lumberjack',
    order = 20,
    titleKey = 'IGUI_EmberRoutesProbe_Policy_lumber_title',
    descKey = 'IGUI_EmberRoutesProbe_Policy_lumber_desc',
}

function LumberjackPolicyDef.getDefaults()
    return {
        maxStoredLogs = 20,
        lumberZoneId = '',
        continuousBatch = true,
    }
end

function LumberjackPolicyDef.getFields(settlementId)
    return {
        {
            key = 'maxStoredLogs',
            editor = 'slider',
            label = 'IGUI_EmberRoutesProbe_Policy_lumber_maxLogs',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_lumber_maxLogs_tip',
            min = 0,
            max = 100,
            step = 5,
            unit = 'logs',
        },
        {
            key = 'lumberZoneId',
            editor = 'zone_dropdown',
            label = 'IGUI_EmberRoutesProbe_Policy_lumber_zone',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_lumber_zone_tip',
        },
        {
            key = 'continuousBatch',
            editor = 'toggle',
            label = 'IGUI_EmberRoutesProbe_Policy_lumber_continuousBatch',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_lumber_continuousBatch_tip',
        },
    }
end

function LumberjackPolicyDef.validate(draft)
    if type(draft) ~= 'table' then return false, 'POLICY_INVALID_TYPE' end
    if draft.maxStoredLogs ~= nil and (type(draft.maxStoredLogs) ~= 'number' or draft.maxStoredLogs < 0 or draft.maxStoredLogs > 500) then
        return false, 'INVALID_MAX_STORED_LOGS'
    end
    if draft.lumberZoneId ~= nil and type(draft.lumberZoneId) ~= 'string' then
        return false, 'INVALID_LUMBER_ZONE_ID'
    end
    if draft.continuousBatch ~= nil and type(draft.continuousBatch) ~= 'boolean' then
        return false, 'INVALID_CONTINUOUS_BATCH'
    end
    return true
end

Registry.register(LumberjackPolicyDef)

return LumberjackPolicyDef
