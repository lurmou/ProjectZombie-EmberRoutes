-- Wall-clock observation/housekeeping periods, never native action durations.
-- Stop confirmation, save barriers and physical commit validation bypass these.
return {
    readMs=50, facilitiesMs=50, discoveryMs=500, precheckMs=50,
    -- Idle discovery stretches to this period; any decision or live precheck
    -- returns the dispatcher to discoveryMs. New demand still wakes the
    -- dispatcher through the dirty path, so a longer idle period never delays it.
    discoveryIdleMs=1000,
    -- Carriers beyond this radius decide on the slower period. Distance is a
    -- pacing signal only: they keep working, unlike a phase-out design.
    workerRemoteRadius=48, workerRemoteMs=2000,
    memberIdleMs=1000, retirementMs=250, retirementFallbackMs=2000,
}
