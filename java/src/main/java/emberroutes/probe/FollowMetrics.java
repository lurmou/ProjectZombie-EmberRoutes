package emberroutes.probe;

import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;

/** World-local diagnostic counters; no task, inventory or recovery authority. */
final class FollowMetrics {
    private static long segments,active,blocked,queued,search;
    private FollowMetrics() { }
    static void clear() { segments=active=blocked=queued=search=0; }
    static void submitted() { segments++; }
    static void sample(long elapsed,String status,boolean searching) {
        if (elapsed<=0 || "FOLLOW_WAITING".equals(status) || "FOLLOW_WAIT_VEHICLE".equals(status)) return;
        active+=elapsed;
        boolean queue="FOLLOW_QUEUED".equals(status);
        if (queue) queued+=elapsed;
        if (searching) search+=elapsed;
        if (queue || "FOLLOW_YIELD_SIDE".equals(status) || "FOLLOW_YIELD_BACK".equals(status)
                || "FOLLOW_PATH_FAILED".equals(status) || "FOLLOW_TIMEOUT".equals(status)
                || "FOLLOW_PATH_BLOCKED".equals(status) || "FOLLOW_STALLED".equals(status)
                || "FOLLOW_BLOCKED".equals(status)) blocked+=elapsed;
    }
    static KahluaTable snapshot() {
        KahluaTable out=J2SEPlatform.getInstance().newTable();
        out.rawset("segmentSubmissions",(double)segments);
        out.rawset("activeSeconds",active/1e9);
        out.rawset("blockedSeconds",blocked/1e9);
        out.rawset("blockedRatio",active==0 ? 0d : (double)blocked/active);
        out.rawset("queueWaitSeconds",queued/1e9);
        out.rawset("searchWaitSeconds",search/1e9);
        return out;
    }
}
