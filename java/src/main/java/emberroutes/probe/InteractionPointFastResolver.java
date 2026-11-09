package emberroutes.probe;

import java.util.HashSet;
import java.util.Set;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaTableIterator;
import zombie.characters.IsoPlayer;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;

/**
 * Fast native adjacent standable interaction point resolver.
 * Inspired by ProjectRemnants (NPCMoveTargets.resolveInteractionPoint).
 * Bypasses Lua AdjacentFreeTileFinder 8-iteration JNI loops entirely.
 */
public final class InteractionPointFastResolver {
    private static final int[][] ADJACENT_OFFSETS = {
        {0, -1}, {1, 0}, {0, 1}, {-1, 0},
        {1, -1}, {1, 1}, {-1, 1}, {-1, -1}
    };

    private InteractionPointFastResolver() {}

    private static boolean isWalkableFloor(IsoGridSquare sq) {
        if (sq == null) return false;
        if (sq.isSolid() || sq.isSolidTrans()) return false;
        if (sq.HasTree()) return false;
        return sq.TreatAsSolidFloor();
    }

    private static boolean canStandAt(IsoGridSquare sq, IsoPlayer npc) {
        if (sq == null) return false;
        if (!isWalkableFloor(sq)) return false;
        if (npc != null) {
            try {
                if (npc.canStandAt(sq.getX() + 0.5f, sq.getY() + 0.5f, sq.getZ())) return true;
            } catch (Throwable ignored) {}
        }
        return sq.isFree(true);
    }

    /**
     * Resolves the closest reachable, standable adjacent square to the target.
     * @param targetSquare The target interaction square (e.g. container / workstation)
     * @param npc The acting NPC
     * @param excludedSquares Optional Lua table of already tried/excluded squares
     * @return KahluaTable with {x, y, z, square} or null if no walkable tile exists.
     */
    public static KahluaTable resolveAdjacentTile(IsoGridSquare targetSquare, IsoPlayer npc, KahluaTable excludedSquares) {
        if (targetSquare == null) return null;
        IsoCell cell = targetSquare.getCell();
        if (cell == null) {
            cell = IsoWorld.instance != null ? IsoWorld.instance.currentCell : null;
            if (cell == null) return null;
        }

        Set<IsoGridSquare> excluded = null;
        if (excludedSquares != null) {
            excluded = new HashSet<>();
            KahluaTableIterator it = excludedSquares.iterator();
            while (it.advance()) {
                Object val = it.getValue();
                if (val instanceof IsoGridSquare sq) excluded.add(sq);
            }
        }

        int targetX = targetSquare.getX();
        int targetY = targetSquare.getY();
        int targetZ = targetSquare.getZ();

        float npcX = npc != null ? npc.getX() : targetX + 0.5f;
        float npcY = npc != null ? npc.getY() : targetY + 0.5f;

        IsoGridSquare best = null;
        float bestDistSq = Float.MAX_VALUE;

        for (int[] offset : ADJACENT_OFFSETS) {
            int cx = targetX + offset[0];
            int cy = targetY + offset[1];
            IsoGridSquare cand = cell.getGridSquare(cx, cy, targetZ);
            if (cand == null) continue;
            if (excluded != null && excluded.contains(cand)) continue;

            if (canStandAt(cand, npc)) {
                // Check reachability between candidate and target
                try {
                    if (!cand.canReachTo(targetSquare) && !targetSquare.canReachTo(cand)) {
                        continue;
                    }
                } catch (Throwable ignored) {}

                float dx = (cx + 0.5f) - npcX;
                float dy = (cy + 0.5f) - npcY;
                float distSq = dx * dx + dy * dy;
                if (distSq < bestDistSq) {
                    bestDistSq = distSq;
                    best = cand;
                }
            }
        }

        if (best == null) return null;

        KahluaTable result = J2SEPlatform.getInstance().newTable();
        result.rawset("x", (double) best.getX() + 0.5);
        result.rawset("y", (double) best.getY() + 0.5);
        result.rawset("z", (double) best.getZ());
        result.rawset("square", best);
        return result;
    }
}
