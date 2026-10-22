package emberroutes.probe;

public final class ProbeRules {
    public static final double MAX_DISTANCE = 16.0;
    private ProbeRules() {}

    /** This gate does not constitute a decision to abandon the MP product. */
    public static boolean canSimulate(boolean client, boolean server) {
        return !client && !server;
    }

    public static boolean allowedPoint(double ax, double ay, double az, double x, double y, double z) {
        return allowedPoint(ax,ay,az,x,y,z,MAX_DISTANCE);
    }
    public static boolean allowedWorkerPoint(double ax,double ay,double az,double x,double y,double z) {
        return allowedPoint(ax,ay,az,x,y,z,256);
    }
    private static boolean allowedPoint(double ax,double ay,double az,double x,double y,double z,double distance) {
        if (!Double.isFinite(ax) || !Double.isFinite(ay) || !Double.isFinite(az)
                || !Double.isFinite(x) || !Double.isFinite(y) || !Double.isFinite(z)) return false;
        if (z != Math.floor(z)) return false;
        double dx = ax - x, dy = ay - y, dz = az - z;
        return dx * dx + dy * dy + dz * dz <= distance * distance;
    }

    public static boolean isCommand(String command) {
        return "spawn".equals(command) || "move".equals(command) || "stop".equals(command)
                || "inspect".equals(command) || "remove".equals(command);
    }
}
