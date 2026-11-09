package emberroutes.probe;

/**
 * Pure geometric locomotion steering:
 * 1. Pure pursuit lookahead sampling along path segments (smooth corner cutting).
 * 2. Overshoot detection to prevent waypoint orbiting / reverse circling.
 * 3. Facing-angle deviation dampening to prevent sliding / model clipping into walls.
 */
public final class LocomotionSteering {
    public static final float DEFAULT_LOOKAHEAD = 0.65f;
    public static final float MIN_SPEED_SCALE = 0.40f;
    public static final float OVERSHOOT_EPSILON = 0.05f;

    public static final class Plan {
        public final float targetX;
        public final float targetY;
        public final float dirX;
        public final float dirY;
        public final float speedScale;
        public final boolean advanceWaypoint;

        public Plan(float targetX, float targetY, float dirX, float dirY, float speedScale, boolean advanceWaypoint) {
            this.targetX = targetX;
            this.targetY = targetY;
            this.dirX = dirX;
            this.dirY = dirY;
            this.speedScale = speedScale;
            this.advanceWaypoint = advanceWaypoint;
        }
    }

    private LocomotionSteering() {}

    public static Plan compute(
            float curX, float curY,
            float forwardX, float forwardY,
            float w0X, float w0Y,
            boolean hasW1, float w1X, float w1Y,
            float lookahead,
            boolean isBackwards,
            boolean nativeTraversal) {

        if (!Float.isFinite(curX) || !Float.isFinite(curY)
                || !Float.isFinite(w0X) || !Float.isFinite(w0Y)) {
            return new Plan(w0X, w0Y, 0.0f, 0.0f, 1.0f, false);
        }

        float R = (lookahead > 0.01f && Float.isFinite(lookahead)) ? lookahead : DEFAULT_LOOKAHEAD;

        // Invariant guard: backward dragging and native traversal bypass forward lookahead steering.
        if (isBackwards || nativeTraversal) {
            float dx = w0X - curX, dy = w0Y - curY;
            float dist = (float) Math.hypot(dx, dy);
            float dirX = dist > 0.001f ? dx / dist : 0.0f;
            float dirY = dist > 0.001f ? dy / dist : 0.0f;
            return new Plan(w0X, w0Y, dirX, dirY, 1.0f, false);
        }

        boolean advanceWaypoint = false;
        float targetX = w0X;
        float targetY = w0Y;

        if (hasW1 && Float.isFinite(w1X) && Float.isFinite(w1Y)) {
            float segX = w1X - w0X, segY = w1Y - w0Y;
            float segLen = (float) Math.hypot(segX, segY);

            if (segLen > 0.001f) {
                float normSegX = segX / segLen;
                float normSegY = segY / segLen;

                // Overshoot check: project (current - w0) along segment (w0 -> w1)
                float toCurX = curX - w0X;
                float toCurY = curY - w0Y;
                float progress = toCurX * normSegX + toCurY * normSegY;

                if (progress > OVERSHOOT_EPSILON) {
                    // Body has crossed the normal plane through w0 into the next corridor.
                    // Advance past w0 to eliminate waypoint orbiting.
                    advanceWaypoint = true;
                    float remAlongSeg = Math.min(segLen, progress + R);
                    targetX = w0X + normSegX * remAlongSeg;
                    targetY = w0Y + normSegY * remAlongSeg;
                } else {
                    float distToW0 = (float) Math.hypot(toCurX, toCurY);
                    if (distToW0 <= R) {
                        // Smooth corner cutting: interpolate target ahead onto the next segment
                        float rem = R - distToW0;
                        float alongSeg = Math.min(segLen, rem);
                        targetX = w0X + normSegX * alongSeg;
                        targetY = w0Y + normSegY * alongSeg;
                    }
                }
            }
        }

        float toTargetX = targetX - curX;
        float toTargetY = targetY - curY;
        float targetDist = (float) Math.hypot(toTargetX, toTargetY);
        float dirX = targetDist > 0.001f ? toTargetX / targetDist : 0.0f;
        float dirY = targetDist > 0.001f ? toTargetY / targetDist : 0.0f;

        // Facing deviation dampening (speedScale)
        float speedScale = 1.0f;
        float forwardLen = (float) Math.hypot(forwardX, forwardY);
        if (forwardLen > 0.001f && targetDist > 0.001f) {
            float cosTheta = (forwardX * dirX + forwardY * dirY) / forwardLen;
            cosTheta = Math.max(-1.0f, Math.min(1.0f, cosTheta));
            // When cosTheta == 1.0 (aligned), scale = 1.0;
            // When cosTheta == 0.0 (90 deg turn), scale = 0.5;
            // Clamped at MIN_SPEED_SCALE (0.40)
            speedScale = Math.max(MIN_SPEED_SCALE, (1.0f + cosTheta) * 0.5f);
        }

        // Terminal arrival deceleration if approaching the final goal without next segment
        if (!hasW1 && targetDist < 0.35f) {
            speedScale = Math.min(speedScale, Math.max(0.25f, targetDist / 0.35f));
        }

        return new Plan(targetX, targetY, dirX, dirY, speedScale, advanceWaypoint);
    }
}
