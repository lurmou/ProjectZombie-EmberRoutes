package emberroutes.probe;

/** Transient interpolation owned by one ProbeNpc body, never a task/claim owner. */
final class BedPoseMotion {
    static float[] bedOffset(float x,float y,int minX,int minY,int maxX,int maxY,String facing) {
        boolean alongX="E".equals(facing) || "W".equals(facing);
        if (!alongX && !("N".equals(facing) || "S".equals(facing))) return null;
        if (minX>maxX || minY>maxY || (alongX ? maxX-minX : maxY-minY)<1) return null;
        float targetX=alongX ? (minX+maxX+1)/2f : Math.max(minX+0.5f,Math.min(maxX+0.5f,x));
        float targetY=alongX ? Math.max(minY+0.5f,Math.min(maxY+0.5f,y)) : (minY+maxY+1)/2f;
        return new float[]{targetX-x,targetY-y};
    }
    enum Phase { AWAKE, ENTER, LYING, EXIT, SEATED }
    final float anchorX,anchorY,z,offsetX,offsetY;
    Phase phase=Phase.AWAKE;
    private boolean exitRequested;
    private long since;
    private float exitX,exitY;
    BedPoseMotion(float x,float y,float z,float dx,float dy,long now) {
        anchorX=x; anchorY=y; this.z=z; offsetX=dx; offsetY=dy; since=now;
    }
    private float progress(long now) {
        double duration=phase==Phase.ENTER ? 1_200_000_000.0 : 1_167_000_000.0;
        float p=(float)Math.max(0,Math.min(1,(now-since)/duration));
        return p*p*(3-2*p);
    }
    float x(long now) {
        return switch(phase) {
            case AWAKE -> anchorX;
            case ENTER -> anchorX+offsetX*progress(now);
            case LYING -> anchorX+offsetX;
            case EXIT -> exitX+(anchorX-exitX)*progress(now);
            case SEATED -> anchorX;
        };
    }
    float y(long now) {
        return switch(phase) {
            case AWAKE -> anchorY;
            case ENTER -> anchorY+offsetY*progress(now);
            case LYING -> anchorY+offsetY;
            case EXIT -> exitY+(anchorY-exitY)*progress(now);
            case SEATED -> anchorY;
        };
    }
    void exit(long now) {
        if (phase==Phase.AWAKE) { phase=Phase.SEATED; return; }
        if (phase==Phase.ENTER) { exitRequested=true; return; }
        if (phase==Phase.EXIT || phase==Phase.SEATED) return;
        exitX=x(now); exitY=y(now); phase=Phase.EXIT; since=now;
    }
    void advance(long now) {
        advance(now,true);
    }
    void advance(long now,boolean nativeReady) {
        if (phase==Phase.AWAKE && nativeReady && now-since>=100_000_000L) { phase=Phase.ENTER; since=now; }
        else if (phase==Phase.ENTER && now-since>=1_200_000_000L && (nativeReady || now-since>=3_000_000_000L)) {
            phase=Phase.LYING;
            if (exitRequested) exit(now);
        }
        else if (phase==Phase.EXIT && now-since>=1_167_000_000L && (nativeReady || now-since>=3_000_000_000L)) phase=Phase.SEATED;
    }
    float directionBlend(long now) {
        return switch(phase) {
            case AWAKE, SEATED -> 0;
            case ENTER -> progress(now);
            case LYING -> 1;
            case EXIT -> 1-progress(now);
        };
    }
}
