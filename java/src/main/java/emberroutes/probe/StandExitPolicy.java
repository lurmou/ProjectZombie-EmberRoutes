package emberroutes.probe;

/** Retry only a stalled vanilla sit-to-stand request, never a pose in progress. */
final class StandExitPolicy {
    private StandExitPolicy() {}
    static boolean allows(boolean bed,boolean gettingUp,boolean corpse,boolean queueBusy,boolean alreadyRequested,boolean seatedReady) {
        return seatedReady && !bed && !gettingUp && !corpse && !queueBusy && !alreadyRequested;
    }
}
