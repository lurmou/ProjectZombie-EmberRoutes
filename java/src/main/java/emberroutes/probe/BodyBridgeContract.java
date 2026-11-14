package emberroutes.probe;

/** Current Lua body protocol. Internal types never cross the public Java bridge.
 * Owns protocol types only; tokens match exactly, without normalization. */
final class BodyBridgeContract {
    private BodyBridgeContract() {}

    static final int STOPPED = 0;
    static final int STOP_UNAVAILABLE = -1;

    enum ReposeKind {
        REST, SLEEP;

        static ReposeKind fromLua(String value) {
            if (value == null) return null;
            return switch (value) {
                case "REST" -> REST;
                case "SLEEP" -> SLEEP;
                default -> null;
            };
        }
    }

    enum FurniturePhase {
        FLOOR, PREPARE, STAND_TARGET, ALIGN_BED, LIE;

        static FurniturePhase fromLua(String value) {
            if (value == null) return null;
            return switch (value) {
                case "FLOOR" -> FLOOR;
                case "PREPARE" -> PREPARE;
                case "STAND_TARGET" -> STAND_TARGET;
                case "ALIGN_BED" -> ALIGN_BED;
                case "LIE" -> LIE;
                default -> null;
            };
        }
    }

    enum StopSignal {
        MOVEMENT(1), MOVING_FLAG(2), TIMED_ACTION(4), PATH(8), PATH_GOAL(16),
        PATH_NEXT(32), ASLEEP(64), RESTING(128), BED(256), FITNESS(512),
        EMOTE(1024), POSTURE(2048), CORPSE(4096), FOLLOW(8192);

        final int mask;
        StopSignal(int mask) { this.mask = mask; }
    }
}
