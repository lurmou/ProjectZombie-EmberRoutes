package emberroutes.probe;

import me.zed_0xff.zombie_buddy.Exposer;

public final class Main {
    public static void main(String[] args) {
        Exposer.exposeClass(ProbeRuntime.class, "EmberRoutesProbeJava");
        Exposer.exposeClass(ProbeNpc.class, "EmberRoutesProbeCarrier");
        ProbeRuntime.log("BOOT jar loaded; Lua API registered; runtime tests NOT RUN");
    }
}
