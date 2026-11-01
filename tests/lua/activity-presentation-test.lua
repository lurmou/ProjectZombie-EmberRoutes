-- Unit test for ActivityScenarioCatalog and ActivityPresentation in installed Kahlua.
local checks = 0
local function check(v, m) assert(v, m) checks = checks + 1 end

getTextOrNull = getTextOrNull or function(key)
    if ERTestTranslations and ERTestTranslations[key] then return ERTestTranslations[key] end
    return nil
end
getText = getText or function(key, ...)
    local s = getTextOrNull(key) or key
    for i, v in ipairs({...}) do s = s:gsub('%%' .. i, function() return tostring(v) end) end
    return s
end

local Catalog = require 'EmberRoutesProbe/ActivityScenarioCatalog'
local Presentation = require 'EmberRoutesProbe/UI/ActivityPresentation'

-- 1. Catalog Tests
local list = Catalog.list()
check(#list == 2, 'Catalog exposes exactly 2 supported scenarios')

local free = Catalog.get('free_gathering')
check(free and free.activityDefinitionId == 'FREE_GATHERING', 'free_gathering maps to FREE_GATHERING')
check(free.benefits and free.benefits.kind == 'SELF_CARE_LEISURE', 'free_gathering has SELF_CARE_LEISURE benefits')
check(free.defaultConfig and free.defaultConfig.durationHours == 1, 'free_gathering default duration is 1h')

local speech = Catalog.get('leader_speech')
check(speech and speech.activityDefinitionId == 'emberroutes:group_discussion', 'leader_speech maps to group_discussion')
check(speech.requiresSpeaker == true, 'leader_speech requires speaker')
check(speech.benefits and speech.benefits.boredom == 6 and speech.benefits.unhappiness == 3 and speech.benefits.stressPercent == 2, 'leader_speech declares exact factual benefits')

check(Catalog.fromDefinition('FREE_GATHERING') == free, 'fromDefinition maps FREE_GATHERING')
check(Catalog.fromDefinition('emberroutes:group_discussion') == speech, 'fromDefinition maps speech')
check(Catalog.fromDefinition('UNKNOWN_DEF') == nil, 'fromDefinition returns nil for unknown')

-- 2. Attendance Reason & Badge Tests
local r1 = Presentation.attendanceReasonText('ACTIVITY_BOOK_RETURN')
check(type(r1) == 'string' and #r1 > 0, 'bookReturn reason localized')

local r2 = Presentation.attendanceReasonText('UNKNOWN_REASON_KEY_XYZ')
check(r2 == getText('IGUI_EmberRoutesProbe_Activity_statusChecking'), 'unknown reason safe fallback')

local b1 = Presentation.statusBadge('READY')
check(b1.badgeType == 'READY' and type(b1.text) == 'string', 'READY badge')

local b2 = Presentation.statusBadge('WAIT', 'ACTIVITY_NEEDS_CARE')
check(b2.badgeType == 'ALERT', 'needs care is marked as ALERT badge')

local b3 = Presentation.statusBadge('WAIT', 'ACTIVITY_HAUL_SETTLING')
check(b3.badgeType == 'WAIT', 'haul settling is marked as WAIT badge')

local b4 = Presentation.statusBadge('UNKNOWN', nil)
check(b4.badgeType == 'UNKNOWN', 'unknown state is marked as UNKNOWN badge')

-- 3. Benefit Three-Phase Tests
local preSpeech = Presentation.benefitText('leader_speech', 'PREVIEW')
check(type(preSpeech) == 'string' and #preSpeech > 0, 'Phase 1 preview text generated')

local runSpeech = Presentation.benefitText('leader_speech', 'RUNNING')
check(runSpeech == getText('IGUI_EmberRoutesProbe_Activity_benefitPendingSettlement'), 'Phase 2 running text strictly pending, no fake progress')

local postSpeechApplied = Presentation.benefitText('leader_speech', 'CLOSED', { state = 'APPLIED', hours = 1 })
check(type(postSpeechApplied) == 'string' and #postSpeechApplied > 0, 'Phase 3 applied text generated')

local postSpeechSkipped = Presentation.benefitText('leader_speech', 'CLOSED', { state = 'SKIPPED' })
check(postSpeechSkipped == getText('IGUI_EmberRoutesProbe_Activity_benefitSkipped'), 'Phase 3 skipped text generated')

-- 4. Debrief View-Model Test
local mockDetail = {
    name = 'My Assembly',
    definition = 'emberroutes:group_discussion',
    outcome = 'COMPLETED',
    counts = { invited = 3, arrived = 3, joined = 3, settled = 3 },
    roster = {
        ['bob'] = { joined = true, settled = true, participationHours = 1, relief = { state = 'APPLIED', hours = 1 } },
        ['alice'] = { joined = true, settled = true, participationHours = 0.5, relief = { state = 'APPLIED', hours = 0.5 } },
        ['charlie'] = { joined = true, settled = true, participationHours = 0, relief = { state = 'SKIPPED', reason = 'INELIGIBLE' } },
    }
}

local debrief = Presentation.debrief(mockDetail)
check(debrief.outcome == 'COMPLETED', 'debrief reflects outcome')
check(debrief.reliefCount == 2, 'debrief counts applied relief')
check(#debrief.members == 3, 'debrief includes all members')
check(debrief.members[1].id == 'bob', 'debrief sorts by participation hours')

print('activity-presentation-test: ' .. checks .. ' PASS (pure scenario catalog & presentation layer)')
