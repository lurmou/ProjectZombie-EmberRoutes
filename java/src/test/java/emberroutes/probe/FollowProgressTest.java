package emberroutes.probe;

public final class FollowProgressTest {
    public static void main(String[] args) {
        FollowProgress p=new FollowProgress();
        assert p.canRequest(0);
        assert !p.stalled(0,0,0);
        p.requested(0);
        assert !p.canRequest(199_999_999);
        assert p.canRequest(200_000_000);
        // Replanning a moving target must not conceal a stuck NPC.
        for (long now=200_000_000;now<FollowProgress.STALL_NANOS;now+=200_000_000) {
            p.requested(now);
            assert !p.stalled(0,0,now);
        }
        assert p.stalled(0,0,FollowProgress.STALL_NANOS);
        assert !p.stalled(0.3f,0,FollowProgress.STALL_NANOS);
        p.pause(100_000_000_000L);
        assert !p.stalled(0.3f,0,100_000_000_001L);
        p.waiting(200_000_000_000L);
        assert !p.stalled(0.3f,0,300_000_000_000L);
        p.ended(false,0);
        assert !p.canRequest(FollowProgress.RETRY_NANOS-1);
        assert p.canRequest(FollowProgress.RETRY_NANOS);
        p.ended(false,2_000_000_000L); p.ended(false,4_000_000_000L);
        assert p.blocked() && !p.canRequest(Long.MAX_VALUE);
        p.ended(true,5_000_000_000L);
        assert !p.blocked();
        assert FollowProgress.distance2(1,2,4,6)==25;
        FollowProgress probe=new FollowProgress();
        assert !probe.probeDue(0,0,0);
        assert !probe.probeDue(0,0,FollowProgress.PROBE_NANOS-1);
        assert probe.probeDue(0,0,FollowProgress.PROBE_NANOS);
        assert !probe.probeDue(0.13f,0,FollowProgress.PROBE_NANOS+1);
        probe.pause(20_000_000_000L);
        assert !probe.probeDue(0.13f,0,20_100_000_000L);
        System.out.println("PASS follow replan/backoff/progress/pause boundaries; engine NOT simulated");
    }
}
