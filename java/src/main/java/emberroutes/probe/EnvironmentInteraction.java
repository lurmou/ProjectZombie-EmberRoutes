package emberroutes.probe;

import zombie.characters.IsoPlayer;
import zombie.iso.IsoDirections;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.SpriteDetails.IsoFlagType;
import zombie.iso.objects.IsoDoor;
import zombie.iso.objects.IsoThumpable;
import zombie.iso.objects.IsoWindow;

/**
 * Proactive environmental obstacle interaction pipeline:
 * Interacts with closed doors, low/tall fences, and windows ahead of character movement.
 */
public final class EnvironmentInteraction {
    public static final float LOOKAHEAD_STEP = 0.85f;
    public static final float MAX_INTERACTION_DIST = 1.35f;

    public enum Result {
        NONE,
        INTERACTED,
        CLIMBING,
        BLOCKED
    }

    private EnvironmentInteraction() {}

    /**
     * Inspects the edge leading into the next square along the movement heading.
     */
    public static Result interactAhead(IsoPlayer player, float nextX, float nextY, boolean nativeTraversal) {
        if (player == null || nativeTraversal) return Result.NONE;
        IsoGridSquare curSq = player.getCurrentSquare();
        if (curSq == null) return Result.NONE;

        float dirX = nextX - player.getX();
        float dirY = nextY - player.getY();
        float dist = (float) Math.hypot(dirX, dirY);
        if (dist <= 0.001f) return Result.NONE;

        dirX /= dist;
        dirY /= dist;

        int targetX = (int) Math.floor(player.getX() + dirX * LOOKAHEAD_STEP);
        int targetY = (int) Math.floor(player.getY() + dirY * LOOKAHEAD_STEP);
        int targetZ = (int) player.getZ();

        if (targetX == curSq.getX() && targetY == curSq.getY()) {
            return Result.NONE;
        }

        IsoGridSquare targetSq = player.getCell() != null
                ? player.getCell().getGridSquare(targetX, targetY, targetZ) : null;
        if (targetSq == null) return Result.NONE;

        int dx = targetX - curSq.getX();
        int dy = targetY - curSq.getY();

        // 1. Direct orthogonal step
        if (dx == 0 || dy == 0) {
            return checkEdge(player, curSq, targetSq, dx, dy);
        }

        // 2. Diagonal step: decompose into primary and secondary orthogonal edges
        if (player.getCell() != null) {
            IsoGridSquare xSq = player.getCell().getGridSquare(curSq.getX() + dx, curSq.getY(), targetZ);
            if (xSq != null) {
                Result r = checkEdge(player, curSq, xSq, dx, 0);
                if (r != Result.NONE) return r;
            }

            IsoGridSquare ySq = player.getCell().getGridSquare(curSq.getX(), curSq.getY() + dy, targetZ);
            if (ySq != null) {
                return checkEdge(player, curSq, ySq, 0, dy);
            }
        }

        return Result.NONE;
    }

    public static Result checkEdge(IsoPlayer player, IsoGridSquare curSq, IsoGridSquare nextSq, int dx, int dy) {
        if (curSq == null || nextSq == null) return Result.NONE;

        float edgeCenterX = curSq.getX() + 0.5f + dx * 0.5f;
        float edgeCenterY = curSq.getY() + 0.5f + dy * 0.5f;
        float distToEdge = (float) Math.hypot(player.getX() - edgeCenterX, player.getY() - edgeCenterY);
        if (distToEdge > MAX_INTERACTION_DIST) {
            return Result.NONE;
        }

        // 1. Door check (native IsoDoor and thumpable wooden doors)
        IsoObject doorObj = curSq.getDoorTo(nextSq);
        if (doorObj instanceof IsoDoor) {
            IsoDoor door = (IsoDoor) doorObj;
            if (!door.IsOpen()) {
                if (door.couldBeOpen(player)) {
                    door.ToggleDoor(player);
                    return door.IsOpen() ? Result.INTERACTED : Result.BLOCKED;
                }
                return Result.BLOCKED;
            }
            return Result.NONE;
        } else if (doorObj instanceof IsoThumpable) {
            IsoThumpable thump = (IsoThumpable) doorObj;
            if (thump.isDoor() && !thump.IsOpen()) {
                if (thump.couldBeOpen(player)) {
                    thump.ToggleDoor(player);
                    return thump.IsOpen() ? Result.INTERACTED : Result.BLOCKED;
                }
                return Result.BLOCKED;
            }
            return Result.NONE;
        }

        // 2. Window check
        IsoWindow window = curSq.getWindowTo(nextSq);
        if (window != null) {
            if (window.canClimbThrough(player) && (!window.isSmashed() || window.isGlassRemoved())) {
                player.climbThroughWindow(window);
                return Result.CLIMBING;
            } else if (window.IsOpen()) {
                player.climbThroughWindow(window);
                return Result.CLIMBING;
            } else if (!window.isBarricaded() && !window.isPermaLocked()) {
                window.ToggleWindow(player);
                if (window.IsOpen() || window.canClimbThrough(player)) {
                    player.climbThroughWindow(window);
                    return Result.CLIMBING;
                }
            }
            return Result.BLOCKED;
        }

        // 3. Fence / Wall check
        IsoDirections dir = directionOf(dx, dy);
        if (dir != null && curSq.getProperties() != null) {
            IsoGridSquare edgeSq = (dy != 0) ? (dy > 0 ? nextSq : curSq) : (dx > 0 ? nextSq : curSq);
            if (edgeSq.getProperties() != null) {
                IsoFlagType hopFlag = (dy != 0) ? IsoFlagType.HoppableN : IsoFlagType.HoppableW;
                IsoFlagType tallFlag = (dy != 0) ? IsoFlagType.TallHoppableN : IsoFlagType.TallHoppableW;

                if (edgeSq.getProperties().has(hopFlag)) {
                    player.climbOverFence(dir);
                    return Result.CLIMBING;
                } else if (edgeSq.getProperties().has(tallFlag)) {
                    if (player.climbOverWall(dir)) {
                        return Result.CLIMBING;
                    }
                    return Result.BLOCKED;
                }
            }
        }

        return Result.NONE;
    }

    public static IsoDirections directionOf(int dx, int dy) {
        if (dy < 0) return IsoDirections.N;
        if (dy > 0) return IsoDirections.S;
        if (dx < 0) return IsoDirections.W;
        if (dx > 0) return IsoDirections.E;
        return null;
    }
}
