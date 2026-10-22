package emberroutes.probe;

import java.util.Objects;
import java.util.function.Supplier;

/** Engine-independent movement lifecycle; the supplied step is the native path follower. */
public final class ProbeMovement {
    public static final long TIMEOUT_NANOS = 20_000_000_000L;
    private static final double ARRIVAL_DISTANCE = 0.4;
    public enum PathResult { WORKING, SUCCEEDED, FAILED }
    public enum Outcome { IDLE, MOVING, REACHED, FAILED, PATH_ENDED, TIMEOUT }
    private boolean active;
    private double targetX, targetY, targetZ;
    private long startedAt;
    private long timeoutNanos=TIMEOUT_NANOS;
    private long steps;
    private boolean paused;
    private long pausedAt;

    public void begin(double x, double y, double z, long now) {
        begin(x,y,z,now,TIMEOUT_NANOS);
    }
    public void begin(double x,double y,double z,long now,long timeout) {
        if (!Double.isFinite(x) || !Double.isFinite(y) || !Double.isFinite(z))
            throw new IllegalArgumentException("non-finite target");
        targetX = x; targetY = y; targetZ = z; startedAt = now; steps = 0; active = true; paused = false;
        timeoutNanos=Math.max(TIMEOUT_NANOS,Math.min(180_000_000_000L,timeout));
    }

    public void pause(long now) {
        if (active && !paused) { paused = true; pausedAt = now; }
    }

    public Outcome tick(Supplier<PathResult> advance, double x, double y, double z, long now) {
        if (!active) return Outcome.IDLE;
        if (paused) { startedAt += Math.max(0, now - pausedAt); paused = false; }
        Outcome result;
        if (distance(x, y, z) <= ARRIVAL_DISTANCE && Math.abs(z - targetZ) <= 0.2
                && Math.floor(z + 0.001) == targetZ) result = Outcome.REACHED;
        else if (now - startedAt >= timeoutNanos) result = Outcome.TIMEOUT;
        else {
            PathResult path = Objects.requireNonNull(advance.get(), "native path result");
            steps++;
            if (path == PathResult.FAILED) result = Outcome.FAILED;
            else if (path == PathResult.SUCCEEDED) result = Outcome.PATH_ENDED;
            else return Outcome.MOVING;
        }
        active = false;
        return result;
    }

    public boolean active() { return active; }
    public long steps() { return steps; }
    public double targetX() { return targetX; }
    public double targetY() { return targetY; }
    public double targetZ() { return targetZ; }
    public double distance(double x, double y, double z) {
        return Math.hypot(Math.hypot(targetX - x, targetY - y), targetZ - z);
    }
    public void cancel() { active = false; paused = false; }
}
