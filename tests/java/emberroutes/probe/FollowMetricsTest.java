package emberroutes.probe;

/** Actual Kahlua snapshot; no world or native character is initialized. */
public final class FollowMetricsTest {
    private static double number(se.krka.kahlua.vm.KahluaTable table,String key) {
        return ((Number)table.rawget(key)).doubleValue();
    }
    public static void main(String[] args) {
        FollowMetrics.clear();
        FollowMetrics.sample(1_000_000_000L,"FOLLOW_ACTIVE",true);
        FollowMetrics.sample(1_000_000_000L,"FOLLOW_QUEUED",false);
        FollowMetrics.sample(1_000_000_000L,"FOLLOW_YIELD_BACK",false);
        FollowMetrics.sample(9_000_000_000L,"FOLLOW_WAITING",false);
        FollowMetrics.sample(9_000_000_000L,"FOLLOW_WAIT_VEHICLE",false);
        FollowMetrics.submitted(); FollowMetrics.submitted();
        var snapshot=FollowMetrics.snapshot();
        assert number(snapshot,"segmentSubmissions")==2;
        assert number(snapshot,"activeSeconds")==3;
        assert number(snapshot,"blockedSeconds")==2;
        assert Math.abs(number(snapshot,"blockedRatio")-2d/3)<1e-10;
        assert number(snapshot,"queueWaitSeconds")==1;
        assert number(snapshot,"searchWaitSeconds")==1;
        FollowMetrics.clear();
        assert number(FollowMetrics.snapshot(),"blockedRatio")==0;
        assert number(snapshot,"segmentSubmissions")==2 : "snapshot must be detached";
        System.out.println("PASS world follow metrics units, inactive exclusion and detached snapshot; game NOT RUN");
    }
}
