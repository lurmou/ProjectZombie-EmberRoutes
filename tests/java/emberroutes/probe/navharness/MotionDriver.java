package emberroutes.probe.navharness;

import java.util.ArrayList;
import java.util.List;
import emberroutes.probe.ProbeMovement;
import emberroutes.probe.nav.EmberPathfinder;
import emberroutes.probe.nav.NavRaycast;

/**
 * 60fps motion driver for the nav harness (mini vanilla test build).
 *
 * <p>Drives a headless NPC with the REAL production classes only:
 * {@link EmberPathfinder} finds the path and {@link ProbeMovement} owns the
 * movement lifecycle (begin / pause / tick). The per-frame advance walks the
 * waypoints at vanilla walk speed (2.4 tiles/s, 60fps); the motion string it
 * emits is the same string Haul.lua polls each frame. Four model scenarios:
 *
 * <ul>
 *   <li>A clean walk through a doorway gap -&gt; REACHED ~1.93s.</li>
 *   <li>B MODEL root-motion clip: the path ends 0.5 tiles short of the final
 *       waypoint -&gt; PATH_ENDED ~1.88s.</li>
 *   <li>C MODEL doorway WAIT: the body freezes 2.5s mid-path, then clears
 *       -&gt; REACHED ~4.43s.</li>
 *   <li>D sealed wall: moveTo refuses -&gt; BLOCKED.</li>
 * </ul>
 *
 * <p>Scenarios B and C are MODELS of vanilla-follower behaviour, not engine
 * evidence: the headless driver cannot get root-motion shortening or the
 * doorway WAIT_DOORWAY hold from the engine, so the driver models them
 * (clip the final segment / freeze frames) and labels them as such. The
 * motion strings themselves come from real {@link ProbeMovement} logic.
 *
 * <p>Run via the harness entry point (tests/navharness/run.sh), which
 * compiles production code + harness together and runs every section.
 * Standalone, with the production classes already compiled:
 * {@code java -cp "<classes>:<game-root>/*" emberroutes.probe.navharness.MotionDriver}
 * Exits non-zero when any scenario misses its expected outcome or time
 * (tolerance +/-0.15s, frame-quantised).
 */
public final class MotionDriver {
    public static final double WALK_SPEED = 2.4; // tiles/sec, vanilla walk
    public static final double DT = 1.0 / 60.0;  // 60 fps
    public static final double TIME_TOLERANCE_S = 0.15;

    /** One finished scenario: terminal motion, wall time and frame count. */
    public record ScenarioResult(String name, String outcome, double seconds, int frames) {}

    /** Scenario definition: which vanilla-follower model to apply, if any. */
    private record Scenario(String name, boolean clipFinal, int doorWaitFrames,
                            String expectedOutcome, double expectedSeconds) {}

    private static final List<Scenario> SCENARIOS = List.of(
            new Scenario("A clean walk through doorway gap (1.5,3.5)->(6.5,3.5)",
                    false, 0, "REACHED", 1.93),
            new Scenario("B MODEL root-motion clip: path ends 0.5 short",
                    true, 0, "PATH_ENDED", 1.88),
            new Scenario("C MODEL doorway WAIT 2.5s mid-path then clear",
                    false, 150, "REACHED", 4.43),
            new Scenario("D sealed wall: moveTo must refuse",
                    false, 0, "BLOCKED", 0.0));

    // ---- Synthetic world -------------------------------------------------
    // The shared SyntheticWorld (harness item 1). This file previously
    // vendored its own copy of the Spike1c builder; harness-entry converged
    // it onto SyntheticWorld — one builder only. The room is an 8x8 floor
    // with a solid wall at x=4 and a doorway gap at y=3.
    static final class Room {
        final SyntheticWorld world;

        Room() {
            world = SyntheticWorld.create();
            world.room(8, 8);
            world.wallSegment(4, 0, 4, 2);
            world.wallSegment(4, 4, 4, 7);
        }

        /** Seal the doorway gap: scenario D runs after A-C on the same room. */
        void sealDoorway() {
            world.wall(4, 3);
        }
    }

    // ---- 60fps driver ----------------------------------------------------
    /** The ProbeNpc.moveTo + per-frame advancePath roles, headless. */
    static final class Driver {
        final ProbeMovement movement = new ProbeMovement();
        List<NavRaycast.Waypoint> path;
        int wpIndex;
        double px, py, pz;
        long nowNanos;
        boolean clipFinal;   // MODEL: stop 0.5 short of final waypoint, then SUCCEEDED
        int doorWaitFrames;  // MODEL: freeze this many frames mid-path (doorway WAIT)
        int waitAtFrame = 60; // MODEL: doorway reached at this frame
        int framesRun;
        String lastOutcome = "IDLE";

        String moveTo(double tx, double ty, double tz) {
            path = EmberPathfinder.findPath(null, (int) px, (int) py, (int) pz,
                    (int) tx, (int) ty, (int) tz, 2000);
            if (path == null) {
                return "BLOCKED";
            }
            movement.begin(tx, ty, tz, nowNanos, Math.min(180_000_000_000L,
                    10_000_000_000L + (long) (3_000_000_000L * Math.hypot(tx - px, ty - py))));
            wpIndex = 0;
            framesRun = 0;
            return "MOVE_REQUESTED";
        }

        ProbeMovement.PathResult advance() {
            if (doorWaitFrames > 0 && framesRun >= waitAtFrame) {
                doorWaitFrames--;
                return ProbeMovement.PathResult.WORKING; // body frozen, path not advancing
            }
            if (wpIndex >= path.size()) {
                return ProbeMovement.PathResult.SUCCEEDED;
            }
            NavRaycast.Waypoint w = path.get(wpIndex);
            double dx = w.x - px, dy = w.y - py;
            double dist = Math.hypot(dx, dy);
            double step = WALK_SPEED * DT;
            boolean isFinal = (wpIndex == path.size() - 1);
            if (clipFinal && isFinal && dist <= 0.5 + step) {
                // Stop 0.5 short of the final waypoint, then report the path done.
                double keep = 0.5;
                if (dist > keep) {
                    px += dx / dist * (dist - keep);
                    py += dy / dist * (dist - keep);
                }
                wpIndex++;
                return ProbeMovement.PathResult.SUCCEEDED;
            }
            if (dist <= step) {
                px = w.x;
                py = w.y;
                wpIndex++;
                return wpIndex >= path.size() ? ProbeMovement.PathResult.SUCCEEDED
                        : ProbeMovement.PathResult.WORKING;
            }
            px += dx / dist * step;
            py += dy / dist * step;
            return ProbeMovement.PathResult.WORKING;
        }

        /** One 60fps frame. Returns the motionResult string Haul.lua polls. */
        String frame() {
            framesRun++;
            if (doorWaitFrames > 0 && framesRun >= waitAtFrame) {
                movement.pause(nowNanos); // production: WAIT_DOORWAY pauses the movement clock
            }
            ProbeMovement.Outcome o = movement.tick(this::advance, px, py, pz, nowNanos);
            nowNanos += (long) (DT * 1e9);
            lastOutcome = o.name();
            return lastOutcome;
        }
    }

    // ---- Scenario runner -------------------------------------------------
    /** Runs one scenario, printing the timestamped motion sequence. */
    static ScenarioResult runScenario(Scenario s, Room room, double tx, double ty) {
        System.out.println("--- " + s.name() + " ---");
        Driver d = new Driver();
        d.px = 1.5;
        d.py = 3.5;
        d.pz = 0;
        d.clipFinal = s.clipFinal();
        d.doorWaitFrames = s.doorWaitFrames();
        String requested = d.moveTo(tx, ty, 0);
        System.out.println("moveTo -> " + requested);
        if ("BLOCKED".equals(requested)) {
            System.out.println("terminal motion=BLOCKED after 0.00s (0 frames), "
                    + "final pos=(1.50,3.50) target=(" + tx + "," + ty + ")");
            return new ScenarioResult(s.name(), "BLOCKED", 0.0, 0);
        }
        String prev = "";
        int maxFrames = 60 * 30;
        for (int i = 0; i < maxFrames; i++) {
            String o = d.frame();
            if (!o.equals(prev)) {
                System.out.println("frame " + i + " t=" + String.format("%.2f", i * DT) + "s motion=" + o
                        + " pos=(" + String.format("%.2f", d.px) + "," + String.format("%.2f", d.py) + ")");
                prev = o;
            }
            if (!"MOVING".equals(o) && !"IDLE".equals(o)) {
                System.out.println("terminal motion=" + o + " after " + String.format("%.2f", i * DT)
                        + "s (" + i + " frames), final pos=(" + String.format("%.2f", d.px)
                        + "," + String.format("%.2f", d.py) + ") target=(" + tx + "," + ty + ")");
                return new ScenarioResult(s.name(), o, i * DT, i);
            }
        }
        System.out.println("no terminal outcome within " + maxFrames + " frames, last=" + prev);
        return new ScenarioResult(s.name(), prev, maxFrames * DT, maxFrames);
    }

    /** Runs all four scenarios on one shared room; D seals the doorway first. */
    public static List<ScenarioResult> runAll() {
        Room room = new Room();
        List<ScenarioResult> results = new ArrayList<>();
        for (Scenario s : SCENARIOS) {
            if (s.name().startsWith("D ")) {
                room.sealDoorway();
            }
            results.add(runScenario(s, room, 6.5, 3.5));
        }
        return results;
    }

    /** Checks one result against its expected outcome and time. */
    static boolean check(ScenarioResult r, Scenario s) {
        if (!r.outcome().equals(s.expectedOutcome())) {
            System.out.println("FAIL " + s.name() + ": expected " + s.expectedOutcome()
                    + " got " + r.outcome());
            return false;
        }
        if (!"BLOCKED".equals(s.expectedOutcome())
                && Math.abs(r.seconds() - s.expectedSeconds()) > TIME_TOLERANCE_S) {
            System.out.println("FAIL " + s.name() + ": expected ~" + s.expectedSeconds()
                    + "s got " + String.format("%.2f", r.seconds()) + "s");
            return false;
        }
        System.out.println("PASS " + s.name() + ": " + r.outcome()
                + " " + String.format("%.2f", r.seconds()) + "s (" + r.frames() + " frames)");
        return true;
    }

    public static void main(String[] args) {
        try {
            List<ScenarioResult> results = runAll();
            boolean ok = true;
            for (int i = 0; i < SCENARIOS.size(); i++) {
                ok &= check(results.get(i), SCENARIOS.get(i));
            }
            if (ok) {
                System.out.println("MOTION-DRIVER PASS");
            } else {
                System.out.println("MOTION-DRIVER FAIL");
                System.exit(1);
            }
        } catch (Throwable t) {
            System.out.println("MOTION-DRIVER FAILED: " + t);
            t.printStackTrace(System.out);
            System.exit(1);
        }
    }
}
