package emberroutes.probe;

/** Bounded quiescence gate, not a timer that blindly destroys an attacked body. */
public final class ProbeRetirement {
    public enum Result { IDLE, WAITING, READY, BLOCKED }
    public static final long SCAN_INTERVAL_NANOS = 100_000_000L;
    public static final long QUIET_NANOS = 500_000_000L;
    public static final long MAX_WAIT_NANOS = 5_000_000_000L;
    private Result result = Result.IDLE;
    private long startedAt, quietSince;
    private int quietSamples;

    public void begin(long now) {
        startedAt = now; quietSince = now; quietSamples = 0; result = Result.WAITING;
    }
    public Result poll(long now, boolean busy) {
        if (result != Result.WAITING) return result;
        if (now - startedAt >= MAX_WAIT_NANOS) return result = Result.BLOCKED;
        if (busy) { quietSamples = 0; quietSince = now; }
        else {
            if (quietSamples == 0) quietSince = now;
            quietSamples++;
            if (quietSamples >= 3 && now - quietSince >= QUIET_NANOS) return result = Result.READY;
        }
        return result;
    }
    public Result result() { return result; }
    public void clear() { result = Result.IDLE; quietSamples = 0; }
}
