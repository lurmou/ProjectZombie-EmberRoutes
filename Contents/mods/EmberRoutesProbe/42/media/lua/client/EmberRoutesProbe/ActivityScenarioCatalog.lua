-- Pure scenario catalog mapping player-facing scenarios to backend ActivityDefinitions.
-- Does not duplicate ActivityRegistry logic, create bodies, or invent backend rules.
local Definitions = require 'EmberRoutesProbe/ActivityRegistry'

local M = {}

local scenarios = {
    {
        id = 'free_gathering',
        activityDefinitionId = 'FREE_GATHERING',
        titleKey = 'IGUI_EmberRoutesProbe_Activity_Scenario_FreeGathering',
        tagKey = 'IGUI_EmberRoutesProbe_Activity_ScenarioTag_Daily',
        descriptionKey = 'IGUI_EmberRoutesProbe_Activity_Scenario_FreeGathering_Desc',
        purposeKey = 'IGUI_EmberRoutesProbe_Activity_Purpose_Relaxation',
        hardwareHintKey = 'IGUI_EmberRoutesProbe_Activity_Hardware_Lounge',
        requiresSpeaker = false,
        benefits = {
            kind = 'SELF_CARE_LEISURE',
            summaryKey = 'IGUI_EmberRoutesProbe_Activity_Benefit_FreeSummary',
        },
        defaultConfig = {
            nameKey = 'IGUI_EmberRoutesProbe_Activity_defaultName',
            durationHours = 1,
            gatherHours = 1 / 6,
            quorum = 2,
            rules = { SOCIAL = 2, OBSERVE = 1 },
        },
    },
    {
        id = 'leader_speech',
        activityDefinitionId = 'emberroutes:group_discussion',
        titleKey = 'IGUI_EmberRoutesProbe_Activity_Scenario_LeaderSpeech',
        tagKey = 'IGUI_EmberRoutesProbe_Activity_ScenarioTag_Morale',
        descriptionKey = 'IGUI_EmberRoutesProbe_Activity_Scenario_LeaderSpeech_Desc',
        purposeKey = 'IGUI_EmberRoutesProbe_Activity_Purpose_Morale',
        hardwareHintKey = 'IGUI_EmberRoutesProbe_Activity_Hardware_Assembly',
        requiresSpeaker = true,
        benefits = {
            kind = 'RELIEF',
            boredom = 6,
            unhappiness = 3,
            stressPercent = 2,
            summaryKey = 'IGUI_EmberRoutesProbe_Activity_Benefit_SpeechSummary',
        },
        defaultConfig = {
            nameKey = 'IGUI_EmberRoutesProbe_Activity_defaultSpeechName',
            durationHours = 1,
            gatherHours = 1 / 6,
            quorum = 2,
            rules = { OBSERVE = 1 },
        },
    },
}

local byId = {}
local byDefinition = {}

for _, sc in ipairs(scenarios) do
    byId[sc.id] = sc
    byDefinition[sc.activityDefinitionId] = sc
end

function M.list()
    local result = {}
    for i, sc in ipairs(scenarios) do
        -- Ensure backend definition is actually registered before presenting scenario
        if Definitions.get(sc.activityDefinitionId) then
            result[#result + 1] = sc
        end
    end
    return result
end

function M.get(id)
    return byId[id]
end

function M.fromDefinition(activityDefinitionId)
    return byDefinition[activityDefinitionId]
end

return M
