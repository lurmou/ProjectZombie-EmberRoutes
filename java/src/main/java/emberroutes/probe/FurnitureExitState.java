package emberroutes.probe;

/** Physical exit remains owned after logical state/refs disappear. No game APIs. */
final class FurnitureExitState {
    private boolean active,exiting,sawPose;
    private long quietSince=-1;
    boolean active() { return active; }
    boolean exiting() { return exiting; }
    void begin() { active=true; exiting=false; sawPose=false; quietSince=-1; }
    void request() { if (active) exiting=true; }
    void observe(boolean nativePose,boolean rootTrack,long now) {
        if (!active) return;
        if (nativePose || rootTrack) { sawPose=true; quietSince=-1; }
        else {
            if (sawPose) exiting=true;
            if (exiting && quietSince<0) quietSince=now;
        }
    }
    boolean settled(long now) { return active && exiting && quietSince>=0 && now-quietSince>=200_000_000L; }
    void finish() { active=false; exiting=false; sawPose=false; quietSince=-1; }
}
