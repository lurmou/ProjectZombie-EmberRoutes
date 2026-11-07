package emberroutes.probe;

/** Production posture decisions only; native animation and speed are not simulated. */
public final class FollowLocomotionTest {
    public static void main(String[] args) {
        FollowLocomotion policy = new FollowLocomotion();
        assert !policy.running(64,false,false,false,1,0,0);
        assert policy.running(65,false,false,false,1,0,1);
        assert policy.running(49,false,false,false,1,0,2);
        assert !policy.running(36,false,false,false,1,0,3);
        assert !policy.running(49,false,false,false,1,0,4);
        assert policy.running(4,true,false,false,1,0,5);
        assert !policy.running(100,true,true,false,1,0,6); // Sneaking outranks catch-up.
        assert policy.running(49,false,false,false,1,0,7); // Catch-up remains latched.
        assert !policy.running(49,true,false,true,1,0,8); // Recovery/stairs/search cannot run.
        assert !policy.running(49,true,false,false,0,1,10);
        assert !policy.running(49,true,false,false,0,1,650_000_009L);
        assert policy.running(49,true,false,false,0,1,650_000_010L);
        assert !policy.running(49,true,false,false,0,-1,700_000_000L);
        policy.pause();
        assert policy.running(49,true,false,false,0,-1,800_000_000L);
        assert !policy.running(49,true,false,false,0,0,800_000_001L);
        assert !policy.running(Float.NaN,true,false,false,1,0,800_000_002L);
        assert !policy.running(49,true,false,false,Float.NaN,0,800_000_003L);
        System.out.println("PASS follow catch-up hysteresis, sneak, precision, turn hold and pause; native movement NOT RUN");
    }
}
