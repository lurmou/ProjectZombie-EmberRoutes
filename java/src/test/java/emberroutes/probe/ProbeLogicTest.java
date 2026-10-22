package emberroutes.probe;

import java.util.concurrent.atomic.AtomicInteger;

/** No game/native classes: exercises ownership, failure and input boundaries. */
public final class ProbeLogicTest {
    private static int assertions;

    public static void main(String[] args) {
        check(ProbeRules.canSimulate(false, false), "SP accepted");
        check(!ProbeRules.canSimulate(true, false), "MP client rejected");
        check(!ProbeRules.canSimulate(false, true), "dedicated server rejected");
        check(!ProbeRules.canSimulate(true, true), "host rejected until server driver exists");
        check(ProbeRules.allowedPoint(0, 0, 0, 16, 0, 0), "distance boundary accepted");
        check(!ProbeRules.allowedPoint(0, 0, 0, 16.01, 0, 0), "too far rejected");
        check(ProbeRules.allowedPoint(0, 0, 0, 0, 0, 1), "loaded upper floor can be requested");
        check(!ProbeRules.allowedPoint(0, 0, 0, 0, 0, 17), "vertical distance bounded");
        check(ProbeRules.allowedPoint(0, 0, 0.5, 0, 0, 1), "actor on stair can request upper landing");
        for (double bad : new double[] {Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY}) {
            check(!ProbeRules.allowedPoint(0, 0, 0, bad, 0, 0), "bad x rejected");
            check(!ProbeRules.allowedPoint(0, 0, 0, 0, bad, 0), "bad y rejected");
            check(!ProbeRules.allowedPoint(0, 0, 0, 0, 0, bad), "bad z rejected");
        }
        check(!ProbeRules.allowedPoint(0, 0, 0, 0, 0, 0.1), "fractional floor rejected");
        check(ProbeRules.isCommand("inspect"), "known command accepted");
        check(!ProbeRules.isCommand("Spawn"), "case mismatch rejected");
        check(!ProbeRules.isCommand(null), "null command rejected");

        ProbeSession<Object> session = new ProbeSession<>();
        AtomicInteger creations = new AtomicInteger();
        Object first = session.spawn(() -> { creations.incrementAndGet(); return new Object(); });
        check(session.spawn(() -> { throw new AssertionError("second construction"); }) == first,
                "repeated spawn returns existing object");
        check(creations.get() == 1, "one construction");
        try {
            session.remove(value -> { throw new IllegalStateException("injected cleanup failure"); });
            throw new AssertionError("cleanup should fail");
        } catch (IllegalStateException expected) {
            check(session.get() == first, "cleanup failure retains ownership for retry");
        }
        AtomicInteger removals = new AtomicInteger();
        check(session.remove(value -> removals.incrementAndGet()), "remove existing");
        check(!session.remove(value -> { throw new AssertionError("second cleanup"); }), "remove absent is harmless");
        check(removals.get() == 1 && session.get() == null, "one cleanup and no retained object");
        try {
            session.spawn(() -> { throw new IllegalArgumentException("injected construction failure"); });
            throw new AssertionError("factory should fail");
        } catch (IllegalArgumentException expected) {
            check(session.get() == null, "failed factory does not poison session");
        }
        try {
            session.spawn(() -> null);
            throw new AssertionError("null result should fail");
        } catch (NullPointerException expected) {
            check(session.get() == null, "null factory result not retained");
        }
        check(session.spawn(Object::new) != null, "retry after construction failure");
        movementRegression();
        retirementRegression();
        System.out.println(BuildInfo.PREFIX + " PASS " + assertions + " assertions");
    }

    private static void movementRegression() {
        ProbeMovement move = new ProbeMovement();
        AtomicInteger advances = new AtomicInteger();
        java.util.function.Supplier<ProbeMovement.PathResult> step = () -> {
            advances.incrementAndGet();
            return ProbeMovement.PathResult.WORKING;
        };
        check(move.tick(step, 0, 0, 0, 0) == ProbeMovement.Outcome.IDLE, "idle does not poll path");
        check(advances.get() == 0, "no spontaneous movement");
        move.begin(0, 5, 0, 0);
        check(move.tick(step, 0, 0, 0, 1) == ProbeMovement.Outcome.MOVING, "new target polls path");
        check(advances.get() == 1, "one path step per tick");
        move.tick(step, 0, 1, 0, 2);
        check(advances.get() == 2, "path must advance again after initial request");
        check(move.distance(0, 1, 0) == 4, "distance uses target not actor facing");
        check(move.tick(step, 0, 5, 0, 3) == ProbeMovement.Outcome.REACHED, "real target reached");
        check(advances.get() == 2 && !move.active(), "arrival stops before another displacement");
        move.tick(step, 0, 5, 0, 4);
        check(advances.get() == 2, "finished movement does not resume");
        move.begin(0, -5, 0, 10);
        check(move.targetY() == -5 && move.active(), "replacement target behind accepted");
        check(move.tick(() -> ProbeMovement.PathResult.FAILED, 0, 5, 0, 11) == ProbeMovement.Outcome.FAILED,
                "path failure terminates instead of walking forward");
        check(!move.active(), "failed movement inactive");
        move.begin(6, 6, 0, 20);
        check(move.tick(() -> ProbeMovement.PathResult.SUCCEEDED, 0, 0, 0, 21) == ProbeMovement.Outcome.PATH_ENDED,
                "native success away from requested target is not arrival");
        move.begin(6, 6, 0, 30);
        check(move.tick(step, 0, 0, 0, 30 + ProbeMovement.TIMEOUT_NANOS) == ProbeMovement.Outcome.TIMEOUT,
                "deadline terminates without another path step");
        move.begin(-5, 0, 0, 40);
        move.cancel();
        check(move.tick(step, 0, 0, 0, 41) == ProbeMovement.Outcome.IDLE, "explicit stop cancels driver");
        move.begin(0, 0, 1, 50);
        check(move.tick(step, 0, 0, 0, 51) == ProbeMovement.Outcome.MOVING,
                "same XY on downstairs floor is not arrival");
        check(move.tick(step, 0, 0, 0.9, 52) == ProbeMovement.Outcome.MOVING,
                "stair approach below requested floor is not arrival");
        check(move.tick(step, 0, 0, 1, 53) == ProbeMovement.Outcome.REACHED, "upper floor reached");
        move.begin(0, 0, 1, 60);
        check(move.tick(() -> ProbeMovement.PathResult.SUCCEEDED, 0, 0, 0, 61)
                == ProbeMovement.Outcome.PATH_ENDED, "path ending downstairs does not report success");
    }

    private static void retirementRegression() {
        ProbeMovement pausedMove = new ProbeMovement();
        pausedMove.begin(5, 0, 0, 0);
        pausedMove.pause(1_000_000_000L);
        pausedMove.pause(50_000_000_000L);
        check(pausedMove.tick(() -> ProbeMovement.PathResult.WORKING, 0, 0, 0, 100_000_000_000L)
                == ProbeMovement.Outcome.MOVING, "long pause excludes elapsed wall time without advancing path");
        check(pausedMove.steps() == 1, "paused callback never advances movement");
        check(pausedMove.tick(() -> ProbeMovement.PathResult.WORKING, 0, 0, 0, 120_000_000_000L)
                == ProbeMovement.Outcome.TIMEOUT, "resumed path retains bounded active-time deadline");
        pausedMove.begin(5, 0, 0, 0);
        pausedMove.pause(1);
        pausedMove.cancel();
        check(pausedMove.tick(() -> { throw new AssertionError("paused cancelled path restarted"); }, 0, 0, 0, 100)
                == ProbeMovement.Outcome.IDLE, "cancel clears paused path ownership");
        ProbeRetirement retirement = new ProbeRetirement();
        check(retirement.poll(0, false) == ProbeRetirement.Result.IDLE, "absent retirement has no work");
        retirement.begin(0);
        check(retirement.poll(0, true) == ProbeRetirement.Result.WAITING, "active bite delays detach");
        check(retirement.poll(100_000_000L, false) == ProbeRetirement.Result.WAITING, "first clear sample insufficient");
        check(retirement.poll(400_000_000L, false) == ProbeRetirement.Result.WAITING, "quiet interval not elapsed");
        check(retirement.poll(600_000_000L, false) == ProbeRetirement.Result.READY, "sustained quiescence permits detach");
        retirement.begin(0);
        retirement.poll(0, false);
        retirement.poll(300_000_000L, false);
        retirement.poll(400_000_000L, true);
        check(retirement.poll(600_000_000L, false) == ProbeRetirement.Result.WAITING, "renewed bite restarts quiet window");
        check(retirement.poll(ProbeRetirement.MAX_WAIT_NANOS, true) == ProbeRetirement.Result.BLOCKED,
                "timeout retains body instead of destroying attacked target");
        check(retirement.poll(ProbeRetirement.MAX_WAIT_NANOS + 1, false) == ProbeRetirement.Result.BLOCKED,
                "blocked retirement does not retry forever");
        retirement.begin(10_000_000_000L);
        check(retirement.result() == ProbeRetirement.Result.WAITING, "explicit retry reopens bounded retirement");
        retirement.clear();
        check(retirement.result() == ProbeRetirement.Result.IDLE, "completed cleanup resets gate");
        retirement.begin(0);
        retirement.poll(0, false);
        retirement.poll(100_000_000L, false);
        check(retirement.poll(ProbeRetirement.MAX_WAIT_NANOS, false) == ProbeRetirement.Result.BLOCKED,
                "long pause cannot turn expired quiet samples into deletion permission");
    }

    private static void check(boolean condition, String message) {
        assertions++;
        if (!condition) throw new AssertionError(message);
    }
}
