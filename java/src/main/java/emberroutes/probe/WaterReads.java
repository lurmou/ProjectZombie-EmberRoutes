package emberroutes.probe;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import zombie.iso.IsoObject;

/** Pinned-engine plumbing observation only. Never searches, pins or drains a source. */
public final class WaterReads {
    private static final Field BACKING;
    private static final Method INFINITE;
    static {
        Field backing = null;
        Method infinite = null;
        try {
            backing = IsoObject.class.getDeclaredField("externalWaterSource");
            infinite = IsoObject.class.getDeclaredMethod("isWaterInfinite");
            backing.setAccessible(true);
            infinite.setAccessible(true);
        } catch (ReflectiveOperationException | RuntimeException unavailable) {
            backing = null;
            infinite = null;
        }
        BACKING = backing;
        INFINITE = infinite;
    }
    private WaterReads() {}

    /** Call after the ordinary native amount observation refreshed its own cache. */
    public static KahluaTable backing(IsoObject tap) {
        KahluaTable result = J2SEPlatform.getInstance().newTable();
        if (tap == null || BACKING == null || INFINITE == null) {
            result.rawset("reason", "WATER_BACKING_UNAVAILABLE");
            return result;
        }
        try {
            if (Boolean.TRUE.equals(INFINITE.invoke(tap))) {
                result.rawset("mode", "NATIVE_WATER");
            } else if (tap.getUsesExternalWaterSource()) {
                Object source = BACKING.get(tap);
                if (source instanceof IsoObject object && object != tap) {
                    result.rawset("mode", "PLUMBED");
                    result.rawset("object", object);
                } else result.rawset("reason", "WATER_SOURCE_EMPTY");
            } else result.rawset("reason", "WATER_SOURCE_UNSUPPORTED");
        } catch (ReflectiveOperationException | RuntimeException unavailable) {
            result.rawset("reason", "WATER_BACKING_UNAVAILABLE");
        }
        return result;
    }
}
