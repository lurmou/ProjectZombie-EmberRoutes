package emberroutes.probe.nav;

import java.util.ArrayList;
import java.util.List;
import zombie.iso.IsoGridSquare;
import zombie.pathfind.PolygonalMap2;

/**
 * Line-of-sight checking and adaptive checkpoint pruning.
 * Collapses long straight sequences of grid nodes into minimal waypoints
 * without cutting through walls, closed doors, fences, or across floors.
 */
public final class NavRaycast {
    public static final float MAX_ADAPTIVE_SPAN = 3.75f;

    public static final class Waypoint {
        public final float x;
        public final float y;
        public final int z;
        public final boolean isMandatory; // e.g. door, window, fence, or stair threshold

        public Waypoint(float x, float y, int z, boolean isMandatory) {
            this.x = x;
            this.y = y;
            this.z = z;
            this.isMandatory = isMandatory;
        }

        @Override
        public String toString() {
            return "(" + x + "," + y + "," + z + (isMandatory ? "*)" : ")");
        }
    }

    private NavRaycast() {}

    /**
     * Line-of-sight collision check on level z between (x1, y1) and (x2, y2).
     * Works both in-game via PolygonalMap2 and offline via grid stepping.
     */
    public static boolean lineWalkable(float x1, float y1, float x2, float y2, int z) {
        if (PolygonalMap2.instance != null) {
            try {
                // Returns true if clear (no collision)
                return !PolygonalMap2.instance.lineClearCollide(x1, y1, x2, y2, z, null, false, true);
            } catch (Throwable ignored) {
                // Fall back to discrete grid DDA
            }
        }
        return ddaLineWalkable(x1, y1, x2, y2, z);
    }

    /**
     * Robust Bresenham/DDA line clearance over EmberNavGrid.
     */
    public static boolean ddaLineWalkable(float x1, float y1, float x2, float y2, int z) {
        int x0 = (int) Math.floor(x1);
        int y0 = (int) Math.floor(y1);
        int xEnd = (int) Math.floor(x2);
        int yEnd = (int) Math.floor(y2);

        if (x0 == xEnd && y0 == yEnd) {
            IsoGridSquare sq = EmberNavGrid.getSquare(x0, y0, z);
            return sq == null || EmberNavGrid.isWalkable(sq);
        }

        int dx = Math.abs(xEnd - x0);
        int dy = Math.abs(yEnd - y0);
        int sx = x0 < xEnd ? 1 : -1;
        int sy = y0 < yEnd ? 1 : -1;
        int err = dx - dy;

        int curX = x0;
        int curY = y0;

        while (true) {
            IsoGridSquare cur = EmberNavGrid.getSquare(curX, curY, z);
            if (cur != null && !EmberNavGrid.isWalkable(cur)) {
                return false;
            }

            if (curX == xEnd && curY == yEnd) break;

            int e2 = 2 * err;
            int nextX = curX;
            int nextY = curY;

            if (e2 > -dy) {
                err -= dy;
                nextX += sx;
            }
            if (e2 < dx) {
                err += dx;
                nextY += sy;
            }

            IsoGridSquare nxt = EmberNavGrid.getSquare(nextX, nextY, z);
            if (cur != null && nxt != null && !EmberNavGrid.canStep(null, cur, nxt)) {
                return false;
            }

            curX = nextX;
            curY = nextY;
        }

        return true;
    }

    /**
     * Compresses a dense tile path into sparse, smooth waypoints.
     */
    public static List<Waypoint> pruneCheckpoints(List<Waypoint> raw) {
        if (raw == null || raw.size() <= 2) {
            return raw != null ? new ArrayList<>(raw) : new ArrayList<>();
        }

        List<Waypoint> pruned = new ArrayList<>();
        int count = raw.size();
        pruned.add(raw.get(0));

        int anchorIdx = 0;
        while (anchorIdx < count - 1) {
            int furthest = anchorIdx + 1;
            float accDist = 0.0f;

            for (int candidate = anchorIdx + 1; candidate < count; candidate++) {
                Waypoint prev = raw.get(candidate - 1);
                Waypoint curr = raw.get(candidate);

                // Multi-floor transitions cannot be skipped
                if (prev.z != curr.z) {
                    if (candidate == anchorIdx + 1) furthest = candidate;
                    break;
                }

                float segDist = (float) Math.hypot(curr.x - prev.x, curr.y - prev.y);
                accDist += segDist;

                // Stop if maximum straight span exceeded
                if (accDist > MAX_ADAPTIVE_SPAN) {
                    break;
                }

                Waypoint anchor = raw.get(anchorIdx);
                if (candidate != anchorIdx + 1 && !lineWalkable(anchor.x, anchor.y, curr.x, curr.y, anchor.z)) {
                    break;
                }

                furthest = candidate;
                if (curr.isMandatory) {
                    break;
                }
            }

            pruned.add(raw.get(furthest));
            anchorIdx = furthest;
        }

        return pruned;
    }
}
