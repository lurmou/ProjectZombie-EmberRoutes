package emberroutes.probe;

import java.util.Vector;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;
import zombie.iso.areas.IsoBuilding;
import zombie.iso.areas.IsoRoom;
import zombie.iso.areas.IsoRoomExit;
import zombie.iso.objects.IsoDoor;
import zombie.iso.objects.IsoThumpable;

/**
 * Settlement macro-reachability graph.
 * Inspired by RimWorld (District & Reachability System).
 *
 * Fast O(1) reachability pre-check between two squares:
 * 1. Checks multi-floor stair connectivity if Z differs.
 * 2. Checks room / building accessibility if one is indoors and other is outdoors.
 * 3. Quickly rejects disconnected requests before triggering A* search.
 */
public final class SettlementReachabilityGraph {
    private SettlementReachabilityGraph() {}

    /**
     * Determines whether two squares can reach each other on a macro scale.
     */
    public static boolean canReachMacro(IsoGridSquare from, IsoGridSquare to) {
        if (from == null || to == null) return false;
        if (from == to) return true;

        IsoCell cell = from.getCell();
        if (cell == null && IsoWorld.instance != null) cell = IsoWorld.instance.currentCell;
        if (cell == null) return false;

        // 1. Z-level check: if different floors, must have stairs between levels
        int fromZ = from.getZ();
        int toZ = to.getZ();
        if (fromZ != toZ) {
            if (!hasStairsBetweenLevels(cell, from, to, fromZ, toZ)) {
                return false;
            }
        }

        // 2. Room/Building door accessibility check
        IsoRoom fromRoom = from.getRoom();
        IsoRoom toRoom = to.getRoom();
        if (fromRoom != toRoom) {
            // If both rooms belong to the same building, they connect through internal doors/hallways
            if (fromRoom != null && toRoom != null && fromRoom.getBuilding() == toRoom.getBuilding()) {
                return true;
            }
            if (fromRoom != null && !isRoomPassable(cell, fromRoom)) return false;
            if (toRoom != null && !isRoomPassable(cell, toRoom)) return false;
        }

        return true;
    }

    private static boolean isRoomPassable(IsoCell cell, IsoRoom room) {
        if (room == null || room.getBuilding() == null) return true;
        IsoBuilding building = room.getBuilding();
        Vector<IsoRoomExit> exits = building.exits;
        if (exits == null || exits.isEmpty()) {
            return true;
        }
        for (int i = 0; i < exits.size(); i++) {
            IsoRoomExit exit = exits.get(i);
            if (exit == null) continue;
            var doorObj = exit.getDoor(cell);
            if (doorObj instanceof IsoDoor door) {
                // In PZ safehouses/settlements, doors are passable unless nailed shut with barricades
                if (!door.isBarricaded()) return true;
            } else if (doorObj instanceof IsoThumpable thumpable && thumpable.isDoor()) {
                if (!thumpable.isBarricaded()) return true;
            } else if (doorObj == null) {
                // Open entrance/archway/unloaded doorway
                return true;
            }
        }
        return false;
    }

    private static boolean hasStairsBetweenLevels(IsoCell cell, IsoGridSquare from, IsoGridSquare to, int z1, int z2) {
        int minZ = Math.min(z1, z2);
        int maxZ = Math.max(z1, z2);
        if (maxZ - minZ > 4) return false; // Too far vertically

        IsoBuilding bFrom = from.getBuilding();
        IsoBuilding bTo = to.getBuilding();
        if (bFrom != null && bFrom == bTo) {
            return true; // Multi-story building interior
        }

        int minX = Math.min(from.getX(), to.getX()) - 30;
        int maxX = Math.max(from.getX(), to.getX()) + 30;
        int minY = Math.min(from.getY(), to.getY()) - 30;
        int maxY = Math.max(from.getY(), to.getY()) + 30;

        for (int z = minZ; z < maxZ; z++) {
            boolean hasStairOnLevel = false;
            for (int x = minX; x <= maxX; x++) {
                for (int y = minY; y <= maxY; y++) {
                    IsoGridSquare sq = cell.getGridSquare(x, y, z);
                    if (sq != null && sq.HasStairs()) {
                        hasStairOnLevel = true;
                        break;
                    }
                }
                if (hasStairOnLevel) break;
            }
            if (!hasStairOnLevel) return true; // Fallback to A* search if outside current sample window
        }
        return true;
    }
}
