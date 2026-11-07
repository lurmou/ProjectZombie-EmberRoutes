package emberroutes.probe;

/** Geometry only, using installed engine types on the classpath without a world. */
public final class LeaderTrailTest {
    private static void near(float actual,float expected) {
        if (Math.abs(actual-expected)>0.0001f) throw new AssertionError(actual+" != "+expected);
    }
    public static void main(String[] args) {
        LeaderTrail t=new LeaderTrail();
        assert !t.sample(1.5f);
        for (int i=0;i<=16;i++) t.record(i*0.25f,0,0);
        assert t.sample(1.5f); near(t.outX,2.5f); near(t.outY,0); near(t.outDirX,1);
        // A corner follows walked distance, not the diagonal leader vector.
        for (int i=1;i<=8;i++) t.record(4,i*0.25f,0);
        assert t.sample(2.5f); near(t.outX,3.5f); near(t.outY,0);
        for (int i=7;i>=0;i--) t.record(4,i*0.25f,0);
        assert t.sample(1); near(t.outX,4); near(t.outY,1); near(t.outDirY,-1);
        t.record(4,0,1); assert !t.sample(0.25f); // floor change severs history
        t.record(20,0,1); assert !t.sample(0.25f); // large jump severs history
        t.reset();
        for (int i=0;i<200;i++) t.record(i*0.25f,0,0);
        assert t.sample(6.75f); near(t.outX,49.75f-6.75f);
        assert !t.sample(24); // 96 points contain 95 intervals, not 96
        // Stationary slots retain both rear and lateral offsets in either axis.
        for (int rank=0;rank<3;rank++) {
            near(CompanionNavigation.slotX(rank,10,1,0),8.5f);
            near(CompanionNavigation.slotY(rank,10,1,0),10+CompanionNavigation.slotSide(rank));
            near(CompanionNavigation.slotX(rank,10,0,1),10-CompanionNavigation.slotSide(rank));
            near(CompanionNavigation.slotY(rank,10,0,1),8.5f);
        }
        System.out.println("PASS trail corner/reversal/break/capacity and explicit slot geometry; game NOT RUN");
    }
}
