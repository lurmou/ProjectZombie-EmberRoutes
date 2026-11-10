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
    -- Wake cadence: the wake-revision poll and the fast re-decide after a
    -- care wake share one 50ms pass with precheckMs above.
    wakeMs=50,
    -- Discovery pass leaves dirty wakes usable again after this delay.
    discoveryWakeMs=100,
    -- Housekeeping cadences. Same value, different jobs: keep separate.
    reconcileMs=1000, stockMs=1000,
    -- Consecutive-failure backoff ladder for one worker's decide period.
    -- Index by min(backoff,3): 1 -> 2000, 2 -> 5000, 3+ -> 15000.
    backoffMs={2000,5000,15000},
    -- Pending-claim expiry. Same 15000 as the backoff cap by coincidence
    -- only: a reservation expiring is not a backoff, so it has its own name.
    reservationExpiryMs=15000,
    -- Leisure/social churn round: PublicWork throttles leisure-ready
    -- notifications and LeisureService groups social invites to this round.
    socialRoundMs=1500,
    -- TaskRuntime business pacing between an attached task's spec.tick
    -- pairs, and its idle poll when no task is attached.
    businessPaceMs=18, businessIdleMs=50,
}
