-- Experience-balance values for the leisure pipeline. Tuning happens here;
-- protocol/budget constants (timeouts, scan caps, distance and occupancy
-- checks) stay at their call sites because they encode performance promises.
local C={
    gates={health=75,hunger=0.25,thirst=0.20,fatigue=0.70,endurance=0.25},
    fitness={fatigue=0.38,endurance=0.65,pain=0.18},
    fitnessExit={endurance=0.40,hunger=0.25,thirst=0.20,fatigue=0.5},
    stroll={fatigue=0.5,endurance=0.55,pain=0.18},
    cooldownHours={FITNESS=12,SOCIAL=2.5,SMOKE=0.5,READING=0.1,STROLL=0.5,default=0,failed=0.03},
    repeatWeightFactor=0.15,
    socialChance={from=18,to=21,evening=0.7,other=0.25},
    weights={OBSERVE=1,FITNESS=0.8,STROLL=0.25,SITE_OBSERVE=0.4,READING=1.3,SMOKE=1,SIT=1.2,PUBLIC_LIFE=0.9},
    fitnessMinutes=60,sitMinutes=60,readingMinutes=60,observeMinutes=1,briefMinutes=0.5,strollMinutes=2,
    seatRetryMs=60000,
    movementIntervalHours=0.25,
    readingSeatRetries=2,readingSeatRetryMs=1000,decisionPauseMin=1,decisionPauseMax=4,lookIntervalMs=3000,
    failedTargetMs=15000,workStopDebounceMs=10000,
    lifecycle={SIT={mode='continuous',minimumMs=45000,reviewMs=10000},
        OBSERVE={mode='bounded'},STROLL={mode='bounded'},
        FITNESS={mode='bounded'},SOCIAL={mode='finite'},READING={mode='finite'},SMOKE={mode='finite'}},
    switchMargin=0.35,switchMoveCost=0.25,habituationMs=600000,
}
return C
