-- Pure, stateless presentation layer for EmberRoutes Activity UI.
-- Translates raw engine facts, attendance reasons and relief records into
-- truthful, non-medicalized player view-models. Does not invent fake ETAs or progress.

local Catalog = require 'EmberRoutesProbe/ActivityScenarioCatalog'

local P = {}

local function getTextOr(key, fallback)
    local s = _G.getTextOrNull and _G.getTextOrNull(key)
    return s or fallback or key
end

local function t(key, ...)
    if _G.getText then
        return _G.getText('IGUI_EmberRoutesProbe_Activity_' .. key, ...)
    end
    return key
end

-- Exact whitelist mapping as mandated by SPEC §1.3
local REASON_KEYS = {
    ACTIVITY_BOOK_RETURN = 'IGUI_EmberRoutesProbe_Activity_reason_bookReturn',
    ACTIVITY_HAUL_SETTLING = 'IGUI_EmberRoutesProbe_Activity_reason_haulSettling',
    ACTIVITY_CRAFT_SETTLING = 'IGUI_EmberRoutesProbe_Activity_reason_craftSettling',
    ACTIVITY_COOKING_SETTLING = 'IGUI_EmberRoutesProbe_Activity_reason_cookingSettling',
    ACTIVITY_PERSONAL_SETTLING = 'IGUI_EmberRoutesProbe_Activity_reason_personalSettling',
    ACTIVITY_BODY_BUSY = 'IGUI_EmberRoutesProbe_Activity_reason_bodyBusy',
    ACTIVITY_CARGO_RETAINED = 'IGUI_EmberRoutesProbe_Activity_reason_cargoRetained',
    ACTIVITY_NEEDS_CARE = 'IGUI_EmberRoutesProbe_Activity_reason_needsCare',
    ACTIVITY_CARRIER_UNAVAILABLE = 'IGUI_EmberRoutesProbe_Activity_reason_carrierUnavailable',
    ACTIVITY_OBLIGATIONS_PENDING = 'IGUI_EmberRoutesProbe_Activity_reason_obligationsPending',
    ACTIVITY_PREDECESSOR_PENDING = 'IGUI_EmberRoutesProbe_Activity_reason_predecessorPending',
    ACTIVITY_OTHER_JOB_RETAINED = 'IGUI_EmberRoutesProbe_Activity_reason_otherJobRetained',
    ACTIVITY_EFFECTS_UNKNOWN = 'IGUI_EmberRoutesProbe_Activity_reason_effectsUnknown',
    ACTIVITY_NATIVE_ACTION_BUSY = 'IGUI_EmberRoutesProbe_Activity_reason_bodyBusy',
    ADMISSION_CLOSED = 'IGUI_EmberRoutesProbe_Activity_reason_admissionClosed',
    LATE_ARRIVAL = 'IGUI_EmberRoutesProbe_Activity_reason_lateArrival',
    ACTIVITY_MEMBERSHIP_CHANGED = 'IGUI_EmberRoutesProbe_Activity_ACTIVITY_MEMBERSHIP_CHANGED',
    ACTIVITY_ROSTER_REMOVED = 'IGUI_EmberRoutesProbe_Activity_ACTIVITY_ROSTER_REMOVED',
    ACTIVITY_REINVITE_UNAVAILABLE = 'IGUI_EmberRoutesProbe_Activity_ACTIVITY_REINVITE_UNAVAILABLE',
    QUORUM_NOT_MET = 'IGUI_EmberRoutesProbe_Activity_reason_quorumNotMet',
    REQUIRED_ROLE_LEFT = 'IGUI_EmberRoutesProbe_Activity_reason_requiredRoleLeft',
    LOAD_INTERRUPTED = 'IGUI_EmberRoutesProbe_Activity_reason_loadInterrupted',
    SAVE_INTERRUPTED = 'IGUI_EmberRoutesProbe_Activity_reason_saveInterrupted',
}

function P.attendanceReasonText(reason)
    if not reason then return '' end
    local key = REASON_KEYS[reason]
    if key then
        return getTextOr(key, t('statusChecking'))
    end
    -- Fallback to existing probe localization if present, or safe fallback
    return getTextOrNull('IGUI_EmberRoutesProbe_Activity_' .. reason)
        or getTextOrNull('IGUI_EmberRoutesProbe_Leisure_' .. reason)
        or t('statusChecking')
end

function P.statusBadge(state, reason)
    if state == 'READY' then
        return {
            text = t('badge_ready'),
            badgeType = 'READY',
            desc = t('badge_ready_desc'),
        }
    elseif state == 'TRAVELLING' then
        return {
            text = t('badge_travelling'),
            badgeType = 'TRAVELLING',
            desc = t('badge_travelling_desc'),
        }
    elseif state == 'ADMITTED' then
        return {
            text = t('badge_admitted'),
            badgeType = 'ADMITTED',
            desc = t('badge_admitted_desc'),
        }
    elseif state == 'WAIT' then
        local detail = P.attendanceReasonText(reason)
        local isAlert = reason == 'ACTIVITY_NEEDS_CARE' or reason == 'ACTIVITY_CARRIER_UNAVAILABLE'
        return {
            text = isAlert and t('badge_alert') or t('badge_wait'),
            badgeType = isAlert and 'ALERT' or 'WAIT',
            desc = detail,
        }
    elseif state == 'REJECTED' then
        return {
            text = t('badge_rejected'),
            badgeType = 'ALERT',
            desc = P.attendanceReasonText(reason),
        }
    elseif state == 'SETTLED' then
        return {
            text = t('badge_settled'),
            badgeType = 'SETTLED',
            desc = t('badge_settled_desc'),
        }
    else
        return {
            text = t('statusChecking'),
            badgeType = 'UNKNOWN',
            desc = P.attendanceReasonText(reason),
        }
    end
end

function P.phaseText(phase, stage)
    if phase == 'GATHERING' then
        return t('phaseGathering')
    elseif phase == 'RUNNING' then
        if stage and stage.id then
            local subKey = 'phase_' .. tostring(stage.id)
            local subText = getTextOrNull('IGUI_EmberRoutesProbe_Activity_' .. subKey)
            if subText then return subText end
        end
        return t('phaseRunning')
    elseif phase == 'WINDING_DOWN' or phase == 'SETTLING' then
        return t('phaseSettling')
    elseif phase == 'CLOSED' then
        return t('phaseClosed')
    end
    return t('statusChecking')
end

function P.outcomeText(outcome)
    if outcome == 'COMPLETED' then
        return t('outcomeCompleted')
    elseif outcome == 'CANCELLED' then
        return t('outcomeCancelled')
    elseif outcome == 'INCOMPLETE' then
        return t('outcomeIncomplete')
    end
    return ''
end

-- Strictly implements the 3-phase psychological benefit presentation rule
function P.benefitText(scenarioId, phase, memberRelief)
    local scenario = Catalog.get(scenarioId)
    if phase == 'PREVIEW' or phase == 'SETUP' then
        -- Phase 1: Pre-launch expected benefits
        if scenario and scenario.benefits then
            return getTextOr(scenario.benefits.summaryKey, t('expectedBenefitDefault'))
        end
        return t('expectedBenefitDefault')
    elseif phase == 'GATHERING' or phase == 'RUNNING' or phase == 'WINDING_DOWN' then
        -- Phase 2: Ongoing, pending settlement.
        -- Strictly prohibits fake continuous progress (e.g. "50% 心理减压")
        return t('benefitPendingSettlement')
    elseif phase == 'SETTLED' or phase == 'CLOSED' then
        -- Phase 3: Post-activity real settlement debrief
        if memberRelief then
            local state = memberRelief.state
            if state == 'APPLIED' then
                local hours = memberRelief.hours or 1
                local b = math.floor(6 * hours + 0.5)
                local u = math.floor(3 * hours + 0.5)
                local s = math.floor(2 * hours + 0.5)
                return t('benefitAppliedValues', b, u, s)
            elseif state == 'SKIPPED' then
                return t('benefitSkipped')
            elseif state == 'PREPARED' or state == 'APPLYING' then
                return t('benefitPendingFinalize')
            elseif state == 'UNKNOWN' then
                return t('benefitUnknown')
            end
        end
        return t('benefitNoReliefRecorded')
    end
    return ''
end

function P.formatMinutes(hours)
    return tostring(math.floor((hours or 0) * 60 + 0.5))
end

-- Generates a clean, factual debrief view-model after an activity closes
function P.debrief(detail)
    if not detail then return nil end
    local scenario = Catalog.fromDefinition(detail.definition)
    local title = scenario and getTextOr(scenario.titleKey, detail.name) or detail.name
    local counts = detail.counts or {}
    local members = {}
    local totalReliefCount = 0

    for npcId, m in pairs(detail.roster or {}) do
        local r = m.relief
        local gotRelief = r and r.state == 'APPLIED'
        if gotRelief then totalReliefCount = totalReliefCount + 1 end
        members[#members + 1] = {
            id = npcId,
            joined = m.joined == true,
            settled = m.settled == true,
            withdrawn = m.withdrawn == true,
            hours = m.participationHours or 0,
            gotRelief = gotRelief,
            reliefState = r and r.state,
            reliefReason = r and r.reason,
            reason = m.reason,
        }
    end

    table.sort(members, function(a, b) return (a.hours or 0) > (b.hours or 0) end)

    return {
        title = title,
        outcome = detail.outcome or 'INCOMPLETE',
        outcomeText = P.outcomeText(detail.outcome),
        reason = detail.reason,
        reasonText = P.attendanceReasonText(detail.reason),
        invited = counts.invited or 0,
        arrived = counts.arrived or 0,
        joined = counts.joined or 0,
        settled = counts.settled or 0,
        reliefCount = totalReliefCount,
        members = members,
    }
end

return P
