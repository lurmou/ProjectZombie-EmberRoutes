package emberroutes.probe;

import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.CharacterStat;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;

/**
 * Game-thread need/safety observation batch. One call replaces the per-NPC Lua
 * bridge chain (stats x5, body damage, fire flag, attacking count, spotted-list
 * instanceof scan). Read-only; no state, no retention, no side effects.
 * Returns null on any guard failure so Lua can fall back to its own path.
 */
public final class ObserverReads {
    /** Lua NeedsObserver caps the spotted scan at this size before reporting UNKNOWN. */
    private static final int SPOTTED_LIMIT = 64;
    private ObserverReads() {}

    private static KahluaTable table() { return J2SEPlatform.getInstance().newTable(); }

    public static KahluaTable sample(IsoPlayer npc) {
        if (npc == null || npc.isDead() || npc.getCurrentSquare() == null) return null;
        KahluaTable result = table();
        try {
            zombie.characters.Stats stats = npc.getStats();
            result.rawset("hunger", Double.valueOf(stats.get(CharacterStat.HUNGER)));
            result.rawset("thirst", Double.valueOf(stats.get(CharacterStat.THIRST)));
            result.rawset("fatigue", Double.valueOf(stats.get(CharacterStat.FATIGUE)));
            result.rawset("endurance", Double.valueOf(stats.get(CharacterStat.ENDURANCE)));
            result.rawset("pain", Double.valueOf(stats.get(CharacterStat.PAIN)));
            result.rawset("health", Double.valueOf(npc.getBodyDamage().getOverallBodyHealth()));
        } catch (RuntimeException error) {
            return null;
        }
        result.rawset("onFire", Boolean.valueOf(npc.isOnFire()));
        result.rawset("attacking", Double.valueOf(npc.getSurroundingAttackingZombies(false)));
        // spottedThreat: omitted key means UNKNOWN (list unavailable or oversized),
        // TRUE means a live zombie within the Lua threat rule, FALSE means clear.
        try {
            java.util.Stack<?> seen = npc.getSpottedList();
            if (seen != null && seen.size() <= SPOTTED_LIMIT) {
                boolean threat = false;
                double x = npc.getX(), y = npc.getY(), z = npc.getZ();
                for (Object value : seen) {
                    if (!(value instanceof IsoZombie zombie) || zombie.isDead()) continue;
                    if (Math.abs(zombie.getZ() - z) >= 1) continue;
                    double dx = zombie.getX() - x, dy = zombie.getY() - y;
                    if (dx * dx + dy * dy <= 100) { threat = true; break; }
                }
                result.rawset("spottedThreat", Boolean.valueOf(threat));
            }
        } catch (RuntimeException ignored) {
            // Key stays absent; Lua maps that to UNKNOWN exactly like the guard path.
        }
        return result;
    }
}
