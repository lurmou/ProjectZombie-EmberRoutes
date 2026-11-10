-- Central constants and native dimension table. Single source of truth for
-- numbers that more than one module reads, or that encode a native range
-- assumption a reader cannot see from the call site. Follow the JobState
-- registry pattern: one vocabulary, one read path; adding a value touches
-- this file only, and callers never restate the literal.
--
-- What lives here, and what does not:
-- * Stat: the native dimension table (0-1 vs 0-100) plus the normalize
--   helpers. Evidence, all read from this repo, not from memory:
--   ActivityRelief.lua's write guard (BOREDOM/UNHAPPINESS <=100, STRESS <=1);
--   LeisureService.sample (/100 for PAIN/BOREDOM, none for STRESS);
--   NpcDebugMenu slider steps (1 for PAIN/PANIC/BOREDOM/UNHAPPINESS,
--   default 0.01 for HUNGER/THIRST/FATIGUE/ENDURANCE/MORALE/STRESS) with
--   min/max taken from the native enum itself. MORALE and PANIC have no
--   in-repo reader/writer that uses their range, so their rows rest on the
--   slider steps only: UNVERIFIED against the jar, do not treat as proof.
-- * Health/Threat/Needs/Supply/Priority: cross-module values that used to
--   be restated as bare literals in two or more files. Same value with a
--   different meaning is deliberately NOT merged (see the inventory doc):
--   e.g. the 15000ms backoff cap and the 15000ms reservation expiry are
--   separate names in TickConfig, and leisure gates stay in LeisureConfig.
-- * Domain-local tuning stays in its owning table (LeisureConfig,
--   NeedsPolicy rules); this file never duplicates those numbers.
-- * Lua/Java dual implementation (threat rule) cannot share one table:
--   ObserverReads.java names the same values and its header points back
--   here. Change one side, grep the other by name.
local Constants={}

-- Native stat ranges. Every range is {min=0, max=N}; HEALTH is the body
-- health 0-100 scale, not a CharacterStat.
Constants.Stat={
    NATIVE_MAX={HUNGER=1,THIRST=1,FATIGUE=1,ENDURANCE=1,STRESS=1,MORALE=1,
        BOREDOM=100,UNHAPPINESS=100,PAIN=100,PANIC=100,HEALTH=100},
    -- Write-back tolerances, split by scale: 0-100 stats tolerate 1e-4,
    -- 0-1 stats tolerate 1e-6 (ActivityRelief write confirmation).
    TOLERANCE_CENT=0.0001,
    TOLERANCE_UNIT=0.000001,
}
local Stat=Constants.Stat
local function finite01(v) return type(v)=='number' and v==v and v>=0 and v<=1 end
-- 0-1 scale check (was NeedsObserver's local number()).
function Stat.isUnit(v) return finite01(v) end
-- Native-scale check for one stat: 0 <= v <= NATIVE_MAX[stat].
function Stat.isNative(stat,v)
    local max=Stat.NATIVE_MAX[stat]
    return type(v)=='number' and v==v and max~=nil and v>=0 and v<=max
end
-- Native value -> 0-1 unit value. 0-1 stats pass through unchanged;
-- 0-100 stats divide by 100. Unknown stats pass through: only the ten
-- listed stats are normalized, anything else is a caller bug, not a
-- dimension this table knows.
function Stat.toUnit(stat,v)
    local max=Stat.NATIVE_MAX[stat]
    if max==nil then return v end
    return v/max
end
-- getHungerChange() dimension heuristic, kept behavior-identical: a value
-- above 1 is read as a 0-100 percentage, otherwise as 0-1. The native
-- return dimension itself is UNVERIFIED against the jar; this only names
-- the assumption instead of restating `val>1 and val/100 or val`.
function Stat.normalizeHungerChange(v) return v>1 and v/100 or v end

-- Health bars. WORK_MIN is the shared "fit for strenuous activity" gate
-- (haul acceptance, cleanup orders, FITNESS); STROLL_MIN is the lighter
-- walking gate. The 75 leisure gate stays in LeisureConfig: different
-- meaning (leisure admission, not strenuous work).
Constants.Health={
    WORK_MIN=95,
    STROLL_MIN=85,
    -- Personnel page mental warning: UNHAPPINESS is native 0-100, STRESS
    -- is native 0-1. The expression is correct; the names carry the scales
    -- so the next reader does not have to know both native ranges.
    MENTAL_UNHAPPINESS_WARN=80,
    MENTAL_STRESS_WARN=0.8,
    CACHE_MS=1000,
}

-- Threat rule, shared with ObserverReads.java (SPOTTED_LIMIT there, plus
-- THREAT_RADIUS/THREAT_Z_MAX). RADIUS is stored once; call sites compare
-- squared distance against RADIUS*RADIUS so no second squared value can
-- drift. Z_MAX is a strict bound on the Lua side (`< Z_MAX`) and the
-- matching skip (`>= Z_MAX`) on the Java side.
Constants.Threat={
    SPOTTED_LIMIT=64,
    RADIUS=10,
    Z_MAX=1,
}

-- Needs observation: recent-damage grace after a health drop, and the two
-- single-threshold gates whose meaning belongs with the needs dimensions.
Constants.Observer={
    DAMAGE_DROP=0.01,
    DAMAGE_GRACE_MS=3000,
}
Constants.Needs={
    -- SLEEP needs the NPC not too hungry/thirsty first. Deliberately NOT
    -- derived from the EAT/DRINK enter thresholds: no stated relation.
    SLEEP_MAX_HUNGER=0.5,
    SLEEP_MAX_THIRST=0.5,
    -- Field work refuses below this endurance; unrelated to the REST
    -- enter threshold (0.25) and the FITNESS endurance line (0.65).
    FIELD_MIN_ENDURANCE=0.4,
}

-- Supply macro estimation. DAILY_FOOD/WATER_PER_PERSON stay in
-- SupplyEstimate (P0 unified them there); only the status days and the
-- resolveHunger fallbacks move here.
Constants.Supply={
    STATUS_CRITICAL_DAYS=2.0,
    STATUS_WARNING_DAYS=5.0,
    HUNGER_MEALS=0.35,
    HUNGER_STABLE=0.25,
    HUNGER_DEFAULT=0.15,
}

-- Work priority range, validated in PublicWork (setPriorities/setPriority)
-- and in OrderStore's saved-format check. 0 is a valid stored value
-- (disabled); WorkSelector's `p>=1` filter is a different predicate and
-- intentionally does not use these.
Constants.Priority={
    MIN=0,
    MAX=4,
}

return Constants
