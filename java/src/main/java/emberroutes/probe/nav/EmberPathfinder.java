package emberroutes.probe.nav;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import zombie.characters.IsoGameCharacter;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;

/**
 * High-performance 3D discrete grid A* pathfinder.
 * Features:
 * 1. Zero-GC search context reuse via ThreadLocal pool and binary min-heap.
 * 2. Dynamic multi-factor edge cost: doors (with key check), windows (glass check), ground hazards (glass/fire), stairs.
 * 3. Staircase anchor relaxation for multi-floor navigation.
 * 4. Adaptive checkpoint pruning via NavRaycast.
 */
public final class EmberPathfinder {
    public static final int DEFAULT_MAX_NODES = 2000;
    public static final int MAX_NODE_BUDGET = 8000;

    private static final int[] DX = {1, -1, 0, 0, 1, 1, -1, -1};
    private static final int[] DY = {0, 0, 1, -1, 1, -1, 1, -1};

    public static final class Node {
        public int x, y, z;
        public int g, h, f;
        public boolean closed;
        public boolean mandatory;
        public Node parent;

        public void reset(int x, int y, int z, int g, int h, Node parent, boolean mandatory) {
            this.x = x;
            this.y = y;
            this.z = z;
            this.g = g;
            this.h = h;
            this.f = g + h;
            this.closed = false;
            this.mandatory = mandatory;
            this.parent = parent;
        }
    }

    private static final class SearchContext {
        private Node[] pool = new Node[4096];
        private int poolSize = 0;

        private Node[] heap = new Node[4096];
        private int heapSize = 0;

        private final HashMap<Long, Node> map = new HashMap<>(4096);

        SearchContext() {
            for (int i = 0; i < pool.length; i++) {
                pool[i] = new Node();
            }
        }

        void clear() {
            poolSize = 0;
            heapSize = 0;
            map.clear();
        }

        Node allocate(int x, int y, int z, int g, int h, Node parent, boolean mandatory) {
            if (poolSize >= pool.length) {
                Node[] next = new Node[pool.length * 2];
                System.arraycopy(pool, 0, next, 0, pool.length);
                for (int i = pool.length; i < next.length; i++) {
                    next[i] = new Node();
                }
                pool = next;
            }
            Node n = pool[poolSize++];
            n.reset(x, y, z, g, h, parent, mandatory);
            return n;
        }

        void pushHeap(Node n) {
            if (heapSize >= heap.length) {
                Node[] next = new Node[heap.length * 2];
                System.arraycopy(heap, 0, next, 0, heap.length);
                heap = next;
            }
            heap[heapSize] = n;
            siftUp(heapSize++);
        }

        Node popHeap() {
            if (heapSize == 0) return null;
            Node result = heap[0];
            heapSize--;
            if (heapSize > 0) {
                heap[0] = heap[heapSize];
                siftDown(0);
            }
            return result;
        }

        private void siftUp(int idx) {
            Node target = heap[idx];
            while (idx > 0) {
                int parentIdx = (idx - 1) >>> 1;
                Node parent = heap[parentIdx];
                if (target.f >= parent.f) break;
                heap[idx] = parent;
                idx = parentIdx;
            }
            heap[idx] = target;
        }

        private void siftDown(int idx) {
            Node target = heap[idx];
            int half = heapSize >>> 1;
            while (idx < half) {
                int child = (idx << 1) + 1;
                Node cNode = heap[child];
                int right = child + 1;
                if (right < heapSize && heap[right].f < cNode.f) {
                    child = right;
                    cNode = heap[right];
                }
                if (target.f <= cNode.f) break;
                heap[idx] = cNode;
                idx = child;
            }
            heap[idx] = target;
        }
    }

    private static final ThreadLocal<SearchContext> CONTEXT = ThreadLocal.withInitial(SearchContext::new);

    private EmberPathfinder() {}

    private static long coordKey(int x, int y, int z) {
        return (((long) z & 0xFFFFL) << 48) | (((long) x & 0xFFFFFFL) << 24) | ((long) y & 0xFFFFFFL);
    }

    /**
     * 3D octile distance heuristic.
     */
    public static int heuristic(int x1, int y1, int z1, int x2, int y2, int z2) {
        int dx = Math.abs(x1 - x2);
        int dy = Math.abs(y1 - y2);
        int dz = Math.abs(z1 - z2);
        int minD = Math.min(dx, dy);
        int maxD = Math.max(dx, dy);
        // Octile 2D + vertical staircase penalty
        return minD * NavCost.DIAGONAL_COST + (maxD - minD) * NavCost.CARDINAL_COST + dz * NavCost.STAIR_COST;
    }

    /**
     * Public search entry point.
     */
    public static List<NavRaycast.Waypoint> findPath(
            IsoGameCharacter character,
            int startX, int startY, int startZ,
            int targetX, int targetY, int targetZ,
            int maxNodes) {

        if (IsoWorld.instance != null && IsoWorld.instance.currentCell != null) {
            IsoGridSquare startSq = EmberNavGrid.getSquare(startX, startY, startZ);
            IsoGridSquare targetSq = EmberNavGrid.getSquare(targetX, targetY, targetZ);
            if (startSq == null || targetSq == null) return null;
        }

        if (startX == targetX && startY == targetY && startZ == targetZ) {
            List<NavRaycast.Waypoint> single = new ArrayList<>();
            single.add(new NavRaycast.Waypoint(targetX + 0.5f, targetY + 0.5f, targetZ, true));
            return single;
        }

        SearchContext ctx = CONTEXT.get();
        ctx.clear();

        int budget = maxNodes > 0 ? Math.min(maxNodes, MAX_NODE_BUDGET) : DEFAULT_MAX_NODES;

        Node startNode = ctx.allocate(startX, startY, startZ, 0, heuristic(startX, startY, startZ, targetX, targetY, targetZ), null, false);
        ctx.map.put(coordKey(startX, startY, startZ), startNode);
        ctx.pushHeap(startNode);

        int expansions = 0;

        while (ctx.heapSize > 0) {
            if (++expansions > budget) {
                return null; // Budget exhausted
            }

            Node current = ctx.popHeap();
            if (current.closed) continue;
            current.closed = true;

            if (current.x == targetX && current.y == targetY && current.z == targetZ) {
                return buildRoute(current);
            }

            IsoGridSquare curSq = EmberNavGrid.getSquare(current.x, current.y, current.z);
            if (curSq == null) continue;

            // Staircase vertical traversal
            if (curSq.HasStairs()) {
                relaxStairAnchor(ctx, current, EmberNavGrid.stairBottomApproach(curSq), targetX, targetY, targetZ);
                relaxStairAnchor(ctx, current, EmberNavGrid.stairUpperLanding(curSq), targetX, targetY, targetZ);
            } else {
                // 8 horizontal neighbors
                for (int i = 0; i < 8; i++) {
                    int nx = current.x + DX[i];
                    int ny = current.y + DY[i];
                    IsoGridSquare nxtSq = EmberNavGrid.getSquare(nx, ny, current.z);
                    if (nxtSq == null || !EmberNavGrid.isNavigationFloor(nxtSq)) continue;

                    if (!EmberNavGrid.canStep(character, curSq, nxtSq)) continue;

                    int doorCost = NavCost.doorEdgeCost(character, curSq, nxtSq);
                    if (doorCost == NavCost.BLOCKED) continue;

                    int windowCost = NavCost.windowEdgeCost(character, curSq, nxtSq);
                    if (windowCost == NavCost.BLOCKED) continue;

                    int fenceCost = EmberNavGrid.fenceEdgeCost(curSq, nxtSq);
                    if (fenceCost == NavCost.BLOCKED) continue;

                    int groundCost = NavCost.groundHazardCost(character, nxtSq);
                    if (groundCost == NavCost.BLOCKED) continue;

                    boolean isDiagonal = (DX[i] != 0 && DY[i] != 0);
                    int baseStep = isDiagonal ? NavCost.DIAGONAL_COST : NavCost.CARDINAL_COST;
                    int stepCost = baseStep + doorCost + windowCost + fenceCost + groundCost;
                    boolean mandatory = (doorCost > 0 || windowCost > 0 || fenceCost > 0);

                    relaxNode(ctx, current, nx, ny, current.z, stepCost, targetX, targetY, targetZ, mandatory);
                }

                // Stairs nearby that can lead above or below
                IsoGridSquare aboveLanding = EmberNavGrid.stairLandingAbove(curSq);
                if (aboveLanding != null) {
                    relaxStairAnchor(ctx, current, aboveLanding, targetX, targetY, targetZ);
                }
                IsoGridSquare belowApproach = EmberNavGrid.stairApproachBelow(curSq);
                if (belowApproach != null) {
                    relaxStairAnchor(ctx, current, belowApproach, targetX, targetY, targetZ);
                }
            }
        }

        return null; // No path found
    }

    private static void relaxNode(
            SearchContext ctx, Node current,
            int nx, int ny, int nz, int edgeCost,
            int tx, int ty, int tz, boolean mandatory) {

        long key = coordKey(nx, ny, nz);
        Node existing = ctx.map.get(key);
        int newG = current.g + edgeCost;

        if (existing == null) {
            int h = heuristic(nx, ny, nz, tx, ty, tz);
            Node neighbor = ctx.allocate(nx, ny, nz, newG, h, current, mandatory);
            ctx.map.put(key, neighbor);
            ctx.pushHeap(neighbor);
        } else if (newG < existing.g && !existing.closed) {
            existing.g = newG;
            existing.f = newG + existing.h;
            existing.parent = current;
            existing.mandatory = existing.mandatory || mandatory;
            ctx.pushHeap(existing); // Re-insert with updated lower f
        }
    }

    private static void relaxStairAnchor(
            SearchContext ctx, Node current, IsoGridSquare anchor,
            int tx, int ty, int tz) {
        if (anchor == null) return;
        relaxNode(ctx, current, anchor.getX(), anchor.getY(), anchor.getZ(), NavCost.STAIR_COST, tx, ty, tz, true);
    }

    private static List<NavRaycast.Waypoint> buildRoute(Node goalNode) {
        List<NavRaycast.Waypoint> raw = new ArrayList<>();
        Node curr = goalNode;
        while (curr != null) {
            raw.add(new NavRaycast.Waypoint(curr.x + 0.5f, curr.y + 0.5f, curr.z, curr.mandatory));
            curr = curr.parent;
        }
        Collections.reverse(raw);
        return NavRaycast.pruneCheckpoints(raw);
    }
}
