package emberroutes.probe;

/** Session-local native posture policy. Does not submit direction or displacement. */
final class FollowLocomotion {
    private static final long TURN_HOLD_NANOS = 650_000_000L;
    private boolean catchingUp, hasDirection;
    private float previousX, previousY;
    private long walkUntil;

    boolean running(float distanceSquared, boolean leaderFast, boolean sneaking,
                    boolean precision, float dirX, float dirY, long now) {
        if (!Float.isFinite(distanceSquared) || distanceSquared < 0
                || !Float.isFinite(dirX) || !Float.isFinite(dirY)) return false;
        catchingUp = distanceSquared > (catchingUp ? 36f : 64f);
        float length = (float)Math.hypot(dirX, dirY);
        if (length < 0.001f) return false;
        dirX /= length; dirY /= length;
        if (hasDirection && previousX * dirX + previousY * dirY < 0.82f)
            walkUntil = now + TURN_HOLD_NANOS;
        previousX = dirX; previousY = dirY; hasDirection = true;
        return !sneaking && !precision && now >= walkUntil && (catchingUp || leaderFast);
    }

    void pause() { hasDirection = false; walkUntil = 0; }
}
