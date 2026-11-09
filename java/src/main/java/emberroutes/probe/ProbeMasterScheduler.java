package emberroutes.probe;

/**
 * Unified master cadence scheduler.
 * Implements tiered cadence execution with real monotonic clock to prevent high-refresh spikes:
 * - 60Hz: Locomotion, direct actions & task session execution (~16ms)
 * - 15Hz: Body authority and state checks (~66ms)
 * - 5Hz: Task dispatch & self-care polling (~200ms)
 * - 1Hz: Maintenance, incremental cache sweeping & retirement (~1000ms)
 */
public final class ProbeMasterScheduler {
    private static int tickCount = 0;
    private static long last60Nanos = 0;
    private static long last15Nanos = 0;
    private static long last5Nanos = 0;
    private static long last1Nanos = 0;

    private static boolean due60 = true;
    private static boolean due15 = true;
    private static boolean due5 = true;
    private static boolean due1 = true;

    private ProbeMasterScheduler() {}

    public static void tick() {
        tickCount++;
        long now = System.nanoTime();

        // 60Hz tier: 16ms = 16,000,000 ns
        due60 = (now - last60Nanos) >= 16_000_000L;
        if (due60) {
            last60Nanos = now;
            NativeActionSystem.tick();
        }

        // 15Hz tier: 66ms = 66,000,000 ns
        due15 = (now - last15Nanos) >= 66_000_000L;
        if (due15) {
            last15Nanos = now;
            ProbeRuntime.advanceRetirement();
        }

        // 5Hz tier: 200ms = 200,000,000 ns
        due5 = (now - last5Nanos) >= 200_000_000L;
        if (due5) {
            last5Nanos = now;
        }

        // 1Hz tier: 1000ms = 1,000,000,000 ns
        due1 = (now - last1Nanos) >= 1_000_000_000L;
        if (due1) {
            last1Nanos = now;
        }
    }

    public static int tickCount() {
        return tickCount;
    }

    public static boolean is60Hz() {
        return due60;
    }

    public static boolean is15Hz() {
        return due15;
    }

    public static boolean is5Hz() {
        return due5;
    }

    public static boolean is1Hz() {
        return due1;
    }

    public static void reset() {
        tickCount = 0;
        last60Nanos = 0;
        last15Nanos = 0;
        last5Nanos = 0;
        last1Nanos = 0;
        due60 = true;
        due15 = true;
        due5 = true;
        due1 = true;
        NativeActionSystem.reset();
    }
}
