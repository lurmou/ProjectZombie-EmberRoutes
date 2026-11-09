package emberroutes.probe;

import java.lang.ref.WeakReference;
import java.util.ArrayDeque;
import java.util.WeakHashMap;
import zombie.characters.IsoPlayer;

/**
 * Single-frame path search arbiter & failed query cache.
 * Inspired by ProjectRemnants (NavMover & NPCPathfinder).
 *
 * 1. Enforces a 16ms single-frame window: only 1 NPC can trigger native A* search
 *    (pathToLocationF) per 16ms window. Other NPCs are enqueued in FIFO order.
 * 2. 500ms failed query cache: prevents immediate repath storms when a target
 *    is unreachable, eliminating main thread frame drops.
 */
public final class PathSearchArbiter {
    public static final long SEARCH_WINDOW_NANOS = 16_000_000L; // 16ms ~ 1 standard 60fps frame
    public static final long FAILED_QUERY_TTL_NANOS = 500_000_000L; // 500ms cooldown

    private static long currentWindow = Long.MIN_VALUE;
    private static boolean slotUsed = false;

    private static final class Waiter {
        final WeakReference<IsoPlayer> actor;
        long window;
        Waiter(IsoPlayer player, long window) {
            this.actor = new WeakReference<>(player);
            this.window = window;
        }
    }

    private static final ArrayDeque<Waiter> WAITERS = new ArrayDeque<>();
    private static final WeakHashMap<IsoPlayer, Waiter> WAITER_MAP = new WeakHashMap<>();

    private static final class FailedQuery {
        final int targetX, targetY, targetZ;
        final long recordedAtNanos;
        FailedQuery(int x, int y, int z, long now) {
            this.targetX = x; this.targetY = y; this.targetZ = z;
            this.recordedAtNanos = now;
        }
    }

    private static final WeakHashMap<IsoPlayer, FailedQuery> FAILED_QUERIES = new WeakHashMap<>();

    private PathSearchArbiter() {}

    /**
     * Attempts to acquire the single A* pathfinding slot for the current 16ms frame window.
     * @param player The requesting character
     * @return true if the character is granted permission to start pathfinding this frame;
     *         false if the slot is occupied or another character is ahead in the queue.
     */
    public static synchronized boolean reserveSearchSlot(IsoPlayer player) {
        long now = System.nanoTime();
        long window = now / SEARCH_WINDOW_NANOS;
        if (window != currentWindow) {
            currentWindow = window;
            slotUsed = false;
        }

        if (player != null) {
            Waiter waiter = WAITER_MAP.get(player);
            if (waiter == null) {
                waiter = new Waiter(player, window);
                WAITER_MAP.put(player, waiter);
                WAITERS.addLast(waiter);
            } else {
                waiter.window = window;
            }
        }

        pruneWaiters(window);

        if (slotUsed) {
            return false;
        }

        if (player == null && !WAITERS.isEmpty()) {
            return false;
        }

        if (player != null) {
            Waiter head = WAITERS.peekFirst();
            if (head == null || head.actor.get() != player) {
                return false;
            }
            WAITERS.removeFirst();
            WAITER_MAP.remove(player);
        }

        slotUsed = true;
        return true;
    }

    private static void pruneWaiters(long currentWindow) {
        while (!WAITERS.isEmpty()) {
            Waiter head = WAITERS.peekFirst();
            IsoPlayer actor = head.actor.get();
            if (actor != null && !actor.isDead() && head.window >= currentWindow - 2L) {
                return;
            }
            WAITERS.removeFirst();
            if (actor != null && WAITER_MAP.get(actor) == head) {
                WAITER_MAP.remove(actor);
            }
        }
    }

    /**
     * Checks if a query to (targetX, targetY, targetZ) has recently failed for this character.
     */
    public static synchronized boolean isRecentlyFailed(IsoPlayer player, int targetX, int targetY, int targetZ) {
        if (player == null) return false;
        FailedQuery q = FAILED_QUERIES.get(player);
        if (q == null) return false;
        long now = System.nanoTime();
        if (now - q.recordedAtNanos >= FAILED_QUERY_TTL_NANOS) {
            FAILED_QUERIES.remove(player);
            return false;
        }
        return q.targetX == targetX && q.targetY == targetY && q.targetZ == targetZ;
    }

    /**
     * Records a failed path search to suppress repeated A* spam.
     */
    public static synchronized void recordFailure(IsoPlayer player, int targetX, int targetY, int targetZ) {
        if (player == null) return;
        FAILED_QUERIES.put(player, new FailedQuery(targetX, targetY, targetZ, System.nanoTime()));
    }

    /**
     * Clears pending queue and failure state for the given character.
     */
    public static synchronized void clearFor(IsoPlayer player) {
        if (player == null) return;
        Waiter w = WAITER_MAP.remove(player);
        if (w != null) WAITERS.remove(w);
        FAILED_QUERIES.remove(player);
    }

    public static synchronized void reset() {
        currentWindow = Long.MIN_VALUE;
        slotUsed = false;
        WAITERS.clear();
        WAITER_MAP.clear();
        FAILED_QUERIES.clear();
    }
}
