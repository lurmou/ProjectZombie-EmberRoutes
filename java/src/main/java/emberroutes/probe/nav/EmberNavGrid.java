package emberroutes.probe.nav;

import zombie.characters.IsoGameCharacter;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.IsoWorld;
import zombie.iso.SpriteDetails.IsoFlagType;
import zombie.iso.SpriteDetails.IsoObjectType;

/**
 * High-performance 3D discrete grid queries for Project Zomboid tiles.
 * Inspects floor walkability, diagonal corner clearances, fences, and multi-level stair links.
 */
public final class EmberNavGrid {

    public enum FenceKind {
        NONE,
        LOW,
        TALL
    }

    private EmberNavGrid() {}

    public static IsoGridSquare getSquare(int x, int y, int z) {
        IsoCell cell = IsoWorld.instance != null ? IsoWorld.instance.currentCell : null;
        return cell != null ? cell.getGridSquare(x, y, z) : null;
    }

    public static boolean isWalkable(IsoGridSquare sq) {
        if (sq == null) return false;
        if (sq.isSolid() || sq.isSolidTrans()) return false;
        if (sq.HasTree()) return false;
        if (sq.haveFire() || sq.hasFireObject() || sq.hasLitCampfire()) return false;
        return sq.TreatAsSolidFloor();
    }

    public static boolean isNavigationFloor(IsoGridSquare sq) {
        return isWalkable(sq) && !sq.HasStairs();
    }

    public static boolean sameSquare(IsoGridSquare a, IsoGridSquare b) {
        if (a == b) return true;
        if (a == null || b == null) return false;
        return a.getX() == b.getX() && a.getY() == b.getY() && a.getZ() == b.getZ();
    }

    public static FenceKind fenceEdgeKind(IsoGridSquare from, IsoGridSquare to) {
        if (from == null || to == null) return FenceKind.NONE;
        int dx = to.getX() - from.getX();
        int dy = to.getY() - from.getY();
        if (dx != 0 && dy != 0) return FenceKind.NONE; // Fences are orthogonal

        IsoGridSquare target;
        if (dy != 0) {
            target = dy > 0 ? to : from;
            if (target.getProperties() != null) {
                if (target.getProperties().has(IsoFlagType.HoppableN)) return FenceKind.LOW;
                if (target.getProperties().has(IsoFlagType.WallN)) return FenceKind.TALL;
            }
        } else {
            target = dx > 0 ? to : from;
            if (target.getProperties() != null) {
                if (target.getProperties().has(IsoFlagType.HoppableW)) return FenceKind.LOW;
                if (target.getProperties().has(IsoFlagType.WallW)) return FenceKind.TALL;
            }
        }
        return FenceKind.NONE;
    }

    public static int fenceEdgeCost(IsoGridSquare from, IsoGridSquare to) {
        FenceKind kind = fenceEdgeKind(from, to);
        if (kind == FenceKind.LOW) {
            return isUnsafeFenceDrop(from, to) ? NavCost.BLOCKED : NavCost.LOW_FENCE_VAULT;
        } else if (kind == FenceKind.TALL) {
            return isUnsafeFenceDrop(from, to) ? NavCost.BLOCKED : NavCost.TALL_FENCE_CLIMB;
        }
        return NavCost.CLEAR;
    }

    /**
     * Prevents jumping off ledges or fences into deadly mid-air / falls.
     */
    public static boolean isUnsafeFenceDrop(IsoGridSquare from, IsoGridSquare to) {
        if (from == null || to == null) return true;
        if (from.getZ() > 0 || to.getZ() > 0) {
            if (!to.TreatAsSolidFloor()) return true;
        }
        return false;
    }

    /**
     * Core step verification between two adjacent squares on the same Z level.
     */
    public static boolean canStep(IsoGameCharacter character, IsoGridSquare from, IsoGridSquare to) {
        if (from == null || to == null) return false;
        if (!isWalkable(to)) return false;
        if (from.getZ() != to.getZ()) return false;

        int dx = to.getX() - from.getX();
        int dy = to.getY() - from.getY();
        if (Math.abs(dx) > 1 || Math.abs(dy) > 1) return false;

        boolean hasDoor = from.getDoorTo(to) != null;
        boolean hasWindow = from.getWindowTo(to) != null;
        FenceKind fence = fenceEdgeKind(from, to);
        boolean hasSpecialEdge = hasDoor || hasWindow || fence != FenceKind.NONE;

        // Wall obstruction (if not passing through a doorway or window)
        if (!hasSpecialEdge && from.isWallTo(to)) {
            return false;
        }

        // Window blocked checks
        if (!hasWindow && from.isWindowBlockedTo(to)) {
            return false;
        }

        // Diagonal movement corner check (no cutting through closed corner walls)
        if (dx != 0 && dy != 0) {
            IsoGridSquare c1 = getSquare(from.getX() + dx, from.getY(), from.getZ());
            IsoGridSquare c2 = getSquare(from.getX(), from.getY() + dy, from.getZ());
            if (c1 == null || c2 == null) return false;
            if (!isWalkable(c1) && !isWalkable(c2)) return false;
            if (from.isWallTo(c1) || from.isWallTo(c2)) return false;
            if (c1.isWallTo(to) || c2.isWallTo(to)) return false;
        }

        return true;
    }

    // ==========================================
    // 3D Stair Linkage & Anchor Resolution
    // ==========================================

    public static IsoGridSquare stairBottomApproach(IsoGridSquare sq) {
        IsoGridSquare top = staircaseTop(sq);
        if (top == null) return null;
        IsoGridSquare approach;
        if (top.HasStairTopNorth()) {
            approach = getSquare(top.getX(), top.getY() + 3, top.getZ());
        } else if (top.HasStairTopWest()) {
            approach = getSquare(top.getX() + 3, top.getY(), top.getZ());
        } else {
            return null;
        }
        return isNavigationFloor(approach) ? approach : null;
    }

    public static IsoGridSquare stairUpperLanding(IsoGridSquare sq) {
        return stairUp(staircaseTop(sq));
    }

    public static IsoGridSquare stairLandingAbove(IsoGridSquare sq) {
        if (!isNavigationFloor(sq)) return null;
        IsoGridSquare north = getSquare(sq.getX(), sq.getY() - 1, sq.getZ());
        if (north != null && north.has(IsoObjectType.stairsBN)) {
            IsoGridSquare top = staircaseTop(north);
            if (sameSquare(sq, stairBottomApproach(top))) {
                return stairUp(top);
            }
        }
        IsoGridSquare west = getSquare(sq.getX() - 1, sq.getY(), sq.getZ());
        if (west != null && west.has(IsoObjectType.stairsBW)) {
            IsoGridSquare top = staircaseTop(west);
            if (sameSquare(sq, stairBottomApproach(top))) {
                return stairUp(top);
            }
        }
        return null;
    }

    public static IsoGridSquare stairApproachBelow(IsoGridSquare sq) {
        if (!isNavigationFloor(sq)) return null;
        IsoGridSquare down = stairDown(sq);
        return down != null ? stairBottomApproach(down) : null;
    }

    private static IsoGridSquare staircaseTop(IsoGridSquare sq) {
        if (sq == null || !sq.HasStairs()) return null;
        if (sq.HasStairTop()) return sq;
        IsoGridSquare top = null;
        if (sq.has(IsoObjectType.stairsMN)) {
            top = getSquare(sq.getX(), sq.getY() - 1, sq.getZ());
        } else if (sq.has(IsoObjectType.stairsBN)) {
            top = getSquare(sq.getX(), sq.getY() - 2, sq.getZ());
        } else if (sq.has(IsoObjectType.stairsMW)) {
            top = getSquare(sq.getX() - 1, sq.getY(), sq.getZ());
        } else if (sq.has(IsoObjectType.stairsBW)) {
            top = getSquare(sq.getX() - 2, sq.getY(), sq.getZ());
        }
        return top;
    }

    public static IsoGridSquare stairUp(IsoGridSquare top) {
        if (top == null) return null;
        IsoGridSquare dest;
        if (top.HasStairTopNorth()) {
            dest = getSquare(top.getX(), top.getY() - 1, top.getZ() + 1);
        } else if (top.HasStairTopWest()) {
            dest = getSquare(top.getX() - 1, top.getY(), top.getZ() + 1);
        } else {
            return null;
        }
        return isWalkable(dest) ? dest : null;
    }

    public static IsoGridSquare stairDown(IsoGridSquare landing) {
        if (landing == null) return null;
        IsoGridSquare north = getSquare(landing.getX(), landing.getY() + 1, landing.getZ() - 1);
        if (north != null && north.HasStairTopNorth()) return north;
        IsoGridSquare west = getSquare(landing.getX() + 1, landing.getY(), landing.getZ() - 1);
        if (west != null && west.HasStairTopWest()) return west;
        return null;
    }
}
