-- P1 pilot 3/15: utility steepening (Sims-inspired): EAT/DRINK scores in
-- Policy.choose are multiplied once the raw need passes a tier (hunger /
-- thirst > 0.50 x2, > 0.70 x3), so a very hungry/thirsty NPC outranks a
-- merely tired one. Only the ranking score changes: thresholds, the
-- candidate set, MEDICAL precedence, hysteresis, and SLEEP/REST scoring
-- are pinned unchanged below. choose() returns only the winning kind, so
-- every tier is pinned by ranking one need against another.
-- Run from the repo root: lua tests/lua/p1-pilot-utility-steepening-test.lua
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local checks=0
local function check(v,s) checks=checks+1 assert(v,s) end

local Policy=require 'EmberRoutesProbe/SelfCare/NeedsPolicy'
local safe={safe=true}
local function sample(hunger,thirst,fatigue,endurance)
    return {hunger=hunger,thirst=thirst,fatigue=fatigue,endurance=endurance}
end
local EAT_SLEEP={EAT=true,SLEEP=true}
local DRINK_SLEEP={DRINK=true,SLEEP=true}

-- ---- Steepening constants live in the NeedsPolicy table, not scattered ----
check(Policy.STEEPENING.TIER1==0.50,'steepening tier 1 threshold pinned at 0.50')
check(Policy.STEEPENING.TIER2==0.70,'steepening tier 2 threshold pinned at 0.70')
check(Policy.STEEPENING.TIER1_MULT==2,'steepening tier 1 multiplier pinned at x2')
check(Policy.STEEPENING.TIER2_MULT==3,'steepening tier 2 multiplier pinned at x3')

-- ---- EAT: three tiers, ranked against linear SLEEP (fatigue) ----
-- Note: SLEEP only competes above its enter threshold (fatigue > 0.70),
-- so every fatigue competitor here is 0.75 or higher.
check(Policy.choose(sample(0.40,0.05,0.75,0.90),nil,safe,EAT_SLEEP)=='SLEEP',
    'hunger 0.40 below tier 1 scores x1 and loses to fatigue 0.75')
check(Policy.choose(sample(0.49,0.05,0.75,0.90),nil,safe,EAT_SLEEP)=='SLEEP',
    'hunger 0.49 just below tier 1 still scores x1 and loses to fatigue 0.75')
check(Policy.choose(sample(0.50,0.05,0.75,0.90),nil,safe,EAT_SLEEP)=='SLEEP',
    'hunger exactly 0.50 is not above tier 1, scores x1 and loses to fatigue 0.75')
check(Policy.choose(sample(0.60,0.05,0.90,0.90),nil,safe,EAT_SLEEP)=='EAT',
    'hunger 0.60 in tier 1 scores x2 (1.20) and beats fatigue 0.90')
check(Policy.choose(sample(0.70,0.05,0.95,0.90),nil,safe,EAT_SLEEP)=='EAT',
    'hunger exactly 0.70 is not above tier 2, scores x2 (1.40) and beats fatigue 0.95')
check(Policy.choose(sample(0.80,0.05,0.95,0.90),nil,safe,EAT_SLEEP)=='EAT',
    'hunger 0.80 in tier 2 scores x3 (2.40) and beats fatigue 0.95')
-- The 0.70 boundary itself: hunger 0.69 x2 (1.38) loses to thirst 0.70 x2
-- (1.40), while hunger 0.71 x3 (2.13) beats thirst 0.705 x3 (2.115).
-- Either side steepened wrongly flips one of these two rankings.
check(Policy.choose(sample(0.69,0.70,0.10,0.90),nil,safe,{EAT=true,DRINK=true})=='DRINK',
    'hunger 0.69 scores x2 and loses to thirst 0.70 x2')
check(Policy.choose(sample(0.71,0.705,0.10,0.90),nil,safe,{EAT=true,DRINK=true})=='EAT',
    'hunger 0.71 scores x3 and beats thirst 0.705 x3')
-- A single eligible need still wins whatever its tier: steepening only
-- re-ranks, it never creates or removes a candidate.
check(Policy.choose(sample(0.80,0.05,0.10,0.90),nil,safe,{EAT=true})=='EAT',
    'steepened hunger alone still chooses EAT')
check(Policy.choose(sample(0.30,0.05,0.10,0.90),nil,safe,{EAT=true})=='EAT',
    'unsteepened hunger alone still chooses EAT')

-- ---- DRINK: same function, same tiers (verified shared scoring path) ----
check(Policy.choose(sample(0.05,0.40,0.75,0.90),nil,safe,DRINK_SLEEP)=='SLEEP',
    'thirst 0.40 below tier 1 scores x1 and loses to fatigue 0.75')
check(Policy.choose(sample(0.05,0.50,0.75,0.90),nil,safe,DRINK_SLEEP)=='SLEEP',
    'thirst exactly 0.50 is not above tier 1, scores x1 and loses to fatigue 0.75')
check(Policy.choose(sample(0.05,0.60,0.90,0.90),nil,safe,DRINK_SLEEP)=='DRINK',
    'thirst 0.60 in tier 1 scores x2 (1.20) and beats fatigue 0.90')
check(Policy.choose(sample(0.05,0.80,0.95,0.90),nil,safe,DRINK_SLEEP)=='DRINK',
    'thirst 0.80 in tier 2 scores x3 (2.40) and beats fatigue 0.95')
check(Policy.choose(sample(0.40,0.60,0.10,0.90),nil,safe,{EAT=true,DRINK=true})=='DRINK',
    'thirst 0.60 x2 beats hunger 0.40 x1 head to head')

-- ---- SLEEP/REST scoring is completely unchanged (linear, unsteepened) ----
check(Policy.choose(sample(0.65,0.05,0.75,0.90),nil,safe,EAT_SLEEP)=='EAT',
    'fatigue 0.75 stays linear: hunger 0.65 x2 (1.30) beats it, a steepened SLEEP (2.25) would not lose')
check(Policy.choose(sample(0.30,0.05,0.80,0.90),nil,safe,EAT_SLEEP)=='SLEEP',
    'fatigue 0.80 still beats hunger 0.30 with no steepening on either side')
check(Policy.choose(sample(0.65,0.05,0.10,0.20),nil,safe,{EAT=true,REST=true})=='EAT',
    'endurance 0.20 (REST 0.80) stays linear: hunger 0.65 x2 (1.30) beats it, a steepened REST (1.60) would not lose')
check(Policy.choose(sample(0.30,0.05,0.10,0.05),nil,safe,{EAT=true,REST=true})=='REST',
    'endurance 0.05 (REST 0.95) still beats hunger 0.30')

-- ---- Thresholds and candidate set unchanged: only the score moved ----
check(Policy.choose(sample(0.26,0.05,0.10,0.90),nil,safe,{EAT=true})=='EAT',
    'EAT enter threshold still 0.25: hunger 0.26 is eligible')
check(Policy.choose(sample(0.25,0.05,0.10,0.90),nil,safe,{EAT=true})==nil,
    'EAT enter threshold still strict: hunger exactly 0.25 is not eligible')
check(Policy.choose(sample(0.40,0.05,0.10,0.90),nil,{safe=true,isWorking=true},{EAT=true})==nil,
    'EAT workEnter threshold still 0.50: working hunger 0.40 is not eligible')
check(Policy.choose(sample(0.30,0.05,0.10,0.90),nil,safe,{SLEEP=true})==nil,
    'unoffered EAT is never chosen and low fatigue alone chooses nothing')

-- ---- Hysteresis still applies after steepening, tiers judged on raw v ----
check(Policy.choose(sample(0.49,0.05,0.90,0.90),'EAT',safe,EAT_SLEEP)=='SLEEP',
    'active hunger 0.49 stays tier 1 (0.49 x1 + 0.15 = 0.64) and loses to fatigue 0.90')
-- Fatigue cannot pin the small hysteresis win (it only competes above
-- 0.70), so DRINK at exactly tier 1 (thirst 0.50 scores x1 = 0.50) is the
-- competitor: hunger 0.40 + 0.15 = 0.55 beats it, bare 0.40 would not.
check(Policy.choose(sample(0.40,0.50,0.10,0.90),'EAT',safe,{EAT=true,DRINK=true})=='EAT',
    'hysteresis still holds the active need: hunger 0.40 + 0.15 beats thirst 0.50')

-- ---- MEDICAL precedence untouched by steepening ----
local medicalSample=sample(0.90,0.05,0.10,0.90)
medicalSample.medical={needsCare=true}
check(Policy.choose(medicalSample,nil,safe,{MEDICAL=true,EAT=true})=='MEDICAL',
    'MEDICAL still wins over steepened hunger 0.90 when care is needed')
print('PASS '..checks..' utility steepening checks; thresholds, SLEEP/REST, MEDICAL unchanged')
