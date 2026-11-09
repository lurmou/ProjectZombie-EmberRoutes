package emberroutes.probe;

public final class LocomotionSteeringTest {
    public static void main(String[] args) {
        testStraightApproach();
        testRightAngleCornerCutting();
        testOvershootEliminatesOrbiting();
        testBackwardDraggingGuard();
        testNativeTraversalGuard();
        testTerminalArrivalDeceleration();
        System.out.println("PASS locomotion steering lookahead, overshoot elimination, corner dampening and guard invariants");
    }

    private static void testStraightApproach() {
        // Character moving north from (0, 0) toward w0 (0, 5) with facing (0, 1)
        LocomotionSteering.Plan plan = LocomotionSteering.compute(
                0.0f, 0.0f,
                0.0f, 1.0f,
                0.0f, 5.0f,
                true, 0.0f, 10.0f,
                0.65f, false, false);

        assert Math.abs(plan.targetX - 0.0f) < 0.001f;
        assert Math.abs(plan.targetY - 5.0f) < 0.001f;
        assert Math.abs(plan.dirX - 0.0f) < 0.001f;
        assert Math.abs(plan.dirY - 1.0f) < 0.001f;
        assert Math.abs(plan.speedScale - 1.0f) < 0.001f : "straight aligned movement should have speedScale=1.0";
        assert !plan.advanceWaypoint;
    }

    private static void testRightAngleCornerCutting() {
        // 1. Entering lookahead zone at (0, 4.6), w0 is at (0, 5.0) [0.4m away], w1 is at (5.0, 5.0) [90 deg turn east]
        // Facing is still North (0, 1)
        LocomotionSteering.Plan planEntry = LocomotionSteering.compute(
                0.0f, 4.6f,
                0.0f, 1.0f,
                0.0f, 5.0f,
                true, 5.0f, 5.0f,
                0.65f, false, false);

        // Remaining lookahead: 0.65 - 0.40 = 0.25 along segment (0, 5) -> (5, 5)
        assert Math.abs(planEntry.targetX - 0.25f) < 0.01f : "targetX should cut into next segment: " + planEntry.targetX;
        assert Math.abs(planEntry.targetY - 5.00f) < 0.01f : "targetY should be 5.0: " + planEntry.targetY;
        assert planEntry.dirX > 0.0f : "should steer east: " + planEntry.dirX;
        assert planEntry.dirY > 0.0f : "should steer north: " + planEntry.dirY;
        assert planEntry.speedScale < 0.95f : "entry into corner should start dampening speed: " + planEntry.speedScale;

        // 2. Deep into corner apex at (0, 4.95), facing North (0, 1) while turning East
        LocomotionSteering.Plan planApex = LocomotionSteering.compute(
                0.0f, 4.95f,
                0.0f, 1.0f,
                0.0f, 5.0f,
                true, 5.0f, 5.0f,
                0.65f, false, false);

        assert planApex.speedScale < 0.60f : "apex of 90 deg corner must strongly dampen speed: " + planApex.speedScale;
        assert planApex.speedScale >= LocomotionSteering.MIN_SPEED_SCALE : "speedScale should respect minimum: " + planApex.speedScale;
        assert !planApex.advanceWaypoint;
    }

    private static void testOvershootEliminatesOrbiting() {
        // Character at (0.2, 5.0), past w0 (0.0, 5.0) along segment w0->w1 (5.0, 5.0)
        // Progress is +0.2 > 0.05
        LocomotionSteering.Plan plan = LocomotionSteering.compute(
                0.2f, 5.0f,
                1.0f, 0.0f,
                0.0f, 5.0f,
                true, 5.0f, 5.0f,
                0.65f, false, false);

        assert plan.advanceWaypoint : "overshoot past w0 must trigger advanceWaypoint to prevent orbiting";
        // Target should be ahead along w1, never behind at w0!
        assert plan.targetX > 0.2f : "target must lie ahead in the corridor, not behind: " + plan.targetX;
        assert plan.dirX > 0.99f : "input must drive forward toward w1, not pull back toward w0";
    }

    private static void testBackwardDraggingGuard() {
        // Character dragging corpse backwards: facing South (0, -1), moving toward w0 (0, 5)
        LocomotionSteering.Plan plan = LocomotionSteering.compute(
                0.0f, 4.6f,
                0.0f, -1.0f,
                0.0f, 5.0f,
                true, 5.0f, 5.0f,
                0.65f, true, false);

        // Must directly target w0, speedScale=1.0, advanceWaypoint=false
        assert Math.abs(plan.targetX - 0.0f) < 0.001f;
        assert Math.abs(plan.targetY - 5.0f) < 0.001f;
        assert Math.abs(plan.speedScale - 1.0f) < 0.001f : "backward drag must not be dampened: " + plan.speedScale;
        assert !plan.advanceWaypoint;
    }

    private static void testNativeTraversalGuard() {
        LocomotionSteering.Plan plan = LocomotionSteering.compute(
                0.0f, 4.6f,
                0.0f, 1.0f,
                0.0f, 5.0f,
                true, 5.0f, 5.0f,
                0.65f, false, true);

        assert Math.abs(plan.speedScale - 1.0f) < 0.001f;
        assert !plan.advanceWaypoint;
    }

    private static void testTerminalArrivalDeceleration() {
        // Approaching terminal goal (no w1) at distance 0.15m (< 0.35m)
        LocomotionSteering.Plan plan = LocomotionSteering.compute(
                0.0f, 4.85f,
                0.0f, 1.0f,
                0.0f, 5.0f,
                false, 0.0f, 0.0f,
                0.65f, false, false);

        assert Math.abs(plan.targetX - 0.0f) < 0.001f;
        assert Math.abs(plan.targetY - 5.0f) < 0.001f;
        assert plan.speedScale < 0.60f : "terminal approach must smoothly brake: " + plan.speedScale;
    }
}
