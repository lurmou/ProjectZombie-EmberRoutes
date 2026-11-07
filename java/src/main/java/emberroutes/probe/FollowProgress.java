package emberroutes.probe;

/** Session-local pacing, not an asset ledger. All clocks use monotonic nanos. */
final class FollowProgress {
    static final long REPLAN_NANOS=200_000_000L;
    static final long RETRY_NANOS=1_500_000_000L;
    static final long STALL_NANOS=8_000_000_000L;
    /** A doorway block must be answered in about a second, not after eight. */
    static final long PROBE_NANOS=1_200_000_000L;
    static final float PROBE_DISTANCE_SQ=0.0144f;
    private long nextRequest,progressAt;
    private float progressX,progressY;
    private boolean observed;
    private int failures;

    boolean stalled(float x,float y,long now) {
        if (!observed || distance2(x,y,progressX,progressY)>=0.04f) {
            observed=true; progressX=x; progressY=y; progressAt=now;
        }
        return now-progressAt>=STALL_NANOS;
    }
    /** True once the body has moved less than 0.12 tiles for 1.2s. Shares the
     * same progress clock as stalled(), so it never extends a real stall. */
    boolean probeDue(float x,float y,long now) {
        if (!observed || distance2(x,y,progressX,progressY)>=PROBE_DISTANCE_SQ) {
            observed=true; progressX=x; progressY=y; progressAt=now;
        }
        return now-progressAt>=PROBE_NANOS;
    }
    void waiting(long now) { progressAt=now; observed=false; }
    void pause(long now) { progressAt=now; }
    boolean canRequest(long now) { return failures<3 && now>=nextRequest; }
    void requested(long now) { nextRequest=now+REPLAN_NANOS; }
    void ended(boolean success,long now) {
        if (success) failures=0;
        else { failures++; nextRequest=now+RETRY_NANOS; }
    }
    boolean blocked() { return failures>=3; }
    static float distance2(float x,float y,float tx,float ty) {
        float dx=x-tx,dy=y-ty; return dx*dx+dy*dy;
    }
}
