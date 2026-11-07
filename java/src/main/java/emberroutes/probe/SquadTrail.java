package emberroutes.probe;

import zombie.characters.IsoPlayer;

/** Squad-shared leader trails. One entry per leader, released by the last follower;
 * bounded so a broken lifecycle cannot accumulate geometry for dead leaders. */
final class SquadTrail {
    private static final int MAX = 4;
    private static final IsoPlayer[] leaders = new IsoPlayer[MAX];
    private static final LeaderTrail[] trails = new LeaderTrail[MAX];
    private static final int[] refs = new int[MAX];

    private SquadTrail() { }

    /** Returns null when all entries are held; the caller then plans without a trail. */
    static LeaderTrail acquire(IsoPlayer leader) {
        if (leader == null) return null;
        for (int i = 0; i < MAX; i++)
            if (leaders[i] == leader) { refs[i]++; return trails[i]; }
        for (int i = 0; i < MAX; i++) {
            if (leaders[i] == null || refs[i] <= 0) {
                leaders[i] = leader;
                if (trails[i] == null) trails[i] = new LeaderTrail();
                else trails[i].reset();
                refs[i] = 1;
                return trails[i];
            }
        }
        ProbeRuntime.log("SQUAD_TRAIL_FULL leaders=" + count());
        return null;
    }

    static void release(IsoPlayer leader, LeaderTrail trail) {
        if (leader == null) return;
        for (int i = 0; i < MAX; i++) {
            if (leaders[i] != leader || trails[i] != trail) continue;
            if (--refs[i] <= 0) { refs[i] = 0; leaders[i] = null; trails[i].reset(); }
            return;
        }
    }

    /** World replacement invalidates all stored geometry; no per-leader cleanup. */
    static void clear() {
        for (int i = 0; i < MAX; i++) {
            if (trails[i] != null) trails[i].reset();
            leaders[i] = null;
            refs[i] = 0;
        }
    }

    private static int count() {
        int total = 0;
        for (int i = 0; i < MAX; i++) total += refs[i] > 0 ? 1 : 0;
        return total;
    }
}
