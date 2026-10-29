-- Wall-clock observation/housekeeping periods, never native action durations.
-- Stop confirmation, save barriers and physical commit validation bypass these.
return {
    readMs=50, facilitiesMs=50, discoveryMs=500, precheckMs=50,
    memberIdleMs=1000, retirementMs=250, retirementFallbackMs=2000,
}
