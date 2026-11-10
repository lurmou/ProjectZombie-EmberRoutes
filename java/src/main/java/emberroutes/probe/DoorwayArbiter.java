package emberroutes.probe;

import java.util.Iterator;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import zombie.characters.IsoPlayer;

/**
 * The Sims-style exclusive doorway passage coordinator:
 * 1. Coordinates single-file passage through 1-tile doors / thresholds.
 * 2. Direction-aware clearance verification ensures tokens are never prematurely released.
 * 3. 1500ms soft TTL ensures an interrupted or deceased NPC automatically releases the token.
 * 4. 2500ms route-failure timeout provides graceful fallback if the doorway remains contested.
 * 5. Symmetric 64-bit canonical edge key guarantees consistent lookup regardless of approach direction.
 */
public final class DoorwayArbiter {
    public static final long DEFAULT_TTL_NANOS = 1_500_000_000L; // 1.5 seconds lease
    public static final long ROUTE_FAILURE_NANOS = 2_500_000_000L; // 2.5 seconds fallback
    public static final float CLEARANCE_SPAN = 0.75f;
    public static final float ABANDON_SPAN = 1.50f;

    public static final class Token {
        public final String npcId;
        public final long grantedAtNanos;
        public final long expiresAtNanos;
        public final int approachSign; // -1 if approaching from negative side, +1 if from positive side

        public Token(String npcId, long now, long ttlNanos, int approachSign) {
            this.npcId = npcId;
            this.grantedAtNanos = now;
            this.expiresAtNanos = now + ttlNanos;
            this.approachSign = approachSign;
        }

        public boolean isValid(long now) {
            return now < expiresAtNanos;
        }
    }

    private static final ConcurrentHashMap<Long, Token> TOKENS = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, Long> NPC_HELD_EDGES = new ConcurrentHashMap<>();

    private DoorwayArbiter() {}

    /**
     * Encodes an undirected edge between two adjacent tiles (x1, y1) and (x2, y2) on floor z
     * into a canonical 64-bit integer.
     */
    public static long coordKey(int x1, int y1, int x2, int y2, int z) {
        int minX = Math.min(x1, x2);
        int minY = Math.min(y1, y2);
        long isVertical = (x1 != x2) ? 1L : 0L;

        return (((long) z & 0xFFL) << 56)
                | (((long) (minX & 0xFFFF)) << 40)
                | (((long) (minY & 0xFFFF)) << 24)
                | isVertical;
    }

    public static int edgeMinX(long key) { return (int) ((key >>> 40) & 0xFFFFL); }
    public static int edgeMinY(long key) { return (int) ((key >>> 24) & 0xFFFFL); }
    public static int edgeZ(long key) { return (int) ((key >>> 56) & 0xFFL); }
    public static boolean edgeIsVertical(long key) { return (key & 1L) == 1L; }

    public static float edgeCenterX(long key) {
        return edgeIsVertical(key) ? edgeMinX(key) + 1.0f : edgeMinX(key) + 0.5f;
    }

    public static float edgeCenterY(long key) {
        return edgeIsVertical(key) ? edgeMinY(key) + 0.5f : edgeMinY(key) + 1.0f;
    }

    /**
     * Resolves a stable string identifier for an NPC / player.
     */
    public static String resolveNpcId(IsoPlayer player) {
        if (player == null) return "";
        try {
            String cid = ProbeRuntime.carrierId(player);
            if (cid != null && !cid.isEmpty()) return cid;
        } catch (Throwable ignored) {}
        return "player-" + player.hashCode();
    }

    /**
     * Calculates the approach sign (-1 or +1) based on current position relative to the door edge.
     */
    public static int calculateApproachSign(long edgeKey, float curX, float curY) {
        boolean vert = edgeIsVertical(edgeKey);
        if (vert) {
            float midX = edgeMinX(edgeKey) + 1.0f;
            return curX < midX ? -1 : 1;
        } else {
            float midY = edgeMinY(edgeKey) + 1.0f;
            return curY < midY ? -1 : 1;
        }
    }

    /**
     * Attempts to acquire the exclusive doorway passage token.
     * @param edgeKey The canonical door edge key
     * @param npcId The requesting NPC's stable identifier
     * @param now Current System.nanoTime()
     * @param ttlNanos Token lease duration
     * @param curX NPC's current X coordinate
     * @param curY NPC's current Y coordinate
     * @return true if acquired or already owned by npcId; false if held by another NPC.
     */
    public static synchronized boolean acquire(long edgeKey, String npcId, long now, long ttlNanos, float curX, float curY) {
        if (npcId == null || npcId.isEmpty()) return true;

        Token existing = TOKENS.get(edgeKey);
        int sign = calculateApproachSign(edgeKey, curX, curY);

        if (existing == null || !existing.isValid(now)) {
            Token token = new Token(npcId, now, ttlNanos, sign);
            TOKENS.put(edgeKey, token);
            NPC_HELD_EDGES.put(npcId, edgeKey);
            return true;
        }

        if (npcId.equals(existing.npcId)) {
            // Refresh lease while navigating the threshold
            Token refreshed = new Token(npcId, now, ttlNanos, existing.approachSign);
            TOKENS.put(edgeKey, refreshed);
            NPC_HELD_EDGES.put(npcId, edgeKey);
            return true;
        }

        return false;
    }

    public static boolean acquire(long edgeKey, String npcId, long now, float curX, float curY) {
        return acquire(edgeKey, npcId, now, DEFAULT_TTL_NANOS, curX, curY);
    }

    /**
     * Releases the token held by npcId on the given doorway.
     */
    public static synchronized boolean release(long edgeKey, String npcId) {
        if (npcId == null || npcId.isEmpty()) return false;
        Token existing = TOKENS.get(edgeKey);
        if (existing != null && npcId.equals(existing.npcId)) {
            TOKENS.remove(edgeKey);
            NPC_HELD_EDGES.remove(npcId);
            return true;
        }
        return false;
    }

    /**
     * Releases all tokens currently held by the specified NPC (used upon interruption, sleep, death).
     */
    public static synchronized void releaseByNpc(String npcId) {
        if (npcId == null || npcId.isEmpty()) return;
        NPC_HELD_EDGES.remove(npcId);
        Iterator<Map.Entry<Long, Token>> it = TOKENS.entrySet().iterator();
        while (it.hasNext()) {
            Map.Entry<Long, Token> entry = it.next();
            if (npcId.equals(entry.getValue().npcId)) {
                it.remove();
            }
        }
    }

    /**
     * Checks if the character has moved past the doorway to the opposite side, or backed far away.
     */
    public static boolean hasCleared(Token token, long edgeKey, float curX, float curY) {
        if (token == null) return true;
        boolean vert = edgeIsVertical(edgeKey);
        if (vert) {
            float midX = edgeMinX(edgeKey) + 1.0f;
            float midY = edgeMinY(edgeKey) + 0.5f;
            float dist = (float) Math.hypot(curX - midX, curY - midY);
            if (dist >= ABANDON_SPAN) return true; // Walked away without crossing

            if (token.approachSign < 0) {
                return curX >= midX + CLEARANCE_SPAN;
            } else {
                return curX <= midX - CLEARANCE_SPAN;
            }
        } else {
            float midX = edgeMinX(edgeKey) + 0.5f;
            float midY = edgeMinY(edgeKey) + 1.0f;
            float dist = (float) Math.hypot(curX - midX, curY - midY);
            if (dist >= ABANDON_SPAN) return true; // Walked away without crossing

            if (token.approachSign < 0) {
                return curY >= midY + CLEARANCE_SPAN;
            } else {
                return curY <= midY - CLEARANCE_SPAN;
            }
        }
    }

    /**
     * Periodic check to release any doorway token if the character has cleared the threshold.
     */
    public static synchronized boolean checkAndReleaseCleared(String npcId, float curX, float curY, long now) {
        if (npcId == null || npcId.isEmpty()) return false;
        Long heldKey = NPC_HELD_EDGES.get(npcId);
        if (heldKey != null) {
            Token token = TOKENS.get(heldKey);
            if (token == null || !token.isValid(now) || hasCleared(token, heldKey, curX, curY)) {
                release(heldKey, npcId);
                return true;
            }
        }
        return false;
    }

    public static boolean checkAndReleaseCleared(String npcId, float curX, float curY) {
        return checkAndReleaseCleared(npcId, curX, curY, System.nanoTime());
    }

    /**
     * Returns the current valid owner of the door, or null if unowned / expired.
     */
    public static Token currentToken(long edgeKey, long now) {
        Token token = TOKENS.get(edgeKey);
        if (token != null && token.isValid(now)) {
            return token;
        }
        return null;
    }

    public static Long heldEdge(String npcId) {
        return NPC_HELD_EDGES.get(npcId);
    }

    /**
     * Clears all tokens (for world tear-down or test reset).
     */
    public static synchronized void reset() {
        TOKENS.clear();
        NPC_HELD_EDGES.clear();
    }
}
