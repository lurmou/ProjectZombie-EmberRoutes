package emberroutes.probe;

/** Local steering geometry only. The carrier still owns movement and world checks.
 * Reference: NPCFW's corridor/side-hold/static-pass approach; no player slots. */
final class CrowdAvoidance {
    static final float LOOK_AHEAD=1.45f, CLEARANCE=0.48f, PROBE=0.95f;
    static boolean blocks(float x,float y,float dx,float dy) {
        float forward=x*dx+y*dy;
        return x*x+y*y<=LOOK_AHEAD*LOOK_AHEAD && forward>=-0.05f
                && forward<=LOOK_AHEAD && Math.abs(x*dy-y*dx)<=0.62f;
    }
    static boolean passed(float x,float y,float dx,float dy) { return x*dx+y*dy>=0.62f; }
    static void detour(float x,float y,float dx,float dy,int side,float[] result) {
        float distance=(float)Math.hypot(x,y);
        float pressure=Math.max(0,Math.min(1,(LOOK_AHEAD-distance)/0.97f));
        float lateral=0.35f+0.55f*pressure,away=0.25f*pressure;
        float ax=distance>0.001f ? -x/distance : -dy*side;
        float ay=distance>0.001f ? -y/distance : dx*side;
        float sx=dx*0.85f-dy*side*lateral+ax*away;
        float sy=dy*0.85f+dx*side*lateral+ay*away;
        float length=(float)Math.hypot(sx,sy);
        result[0]=sx/length; result[1]=sy/length;
    }
    static boolean clears(float x,float y,float dx,float dy,float length) {
        float before=x*x+y*y,ex=dx*length,ey=dy*length;
        float after=(x-ex)*(x-ex)+(y-ey)*(y-ey);
        if (before<CLEARANCE*CLEARANCE) return x*dx+y*dy<=0 && after>before+0.02f;
        float t=Math.max(0,Math.min(1,(x*ex+y*ey)/(length*length)));
        float px=x-ex*t,py=y-ey*t;
        return px*px+py*py>=CLEARANCE*CLEARANCE;
    }
}
