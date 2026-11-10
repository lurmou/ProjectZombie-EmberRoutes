package emberroutes.probe;

public final class DoorwayArbiterTest {
    public static void main(String[] args) {
        testCanonicalEdgeKey();
        testSingleNpcAcquireAndRelease();
        testMutualExclusionAndYielding();
        testTtlExpiryAndAutoRecovery();
        testAbortAndReleaseByNpc();
        testDirectionAwareClearance();
        System.out.println("PASS doorway arbiter token reservation, mutual exclusion, clearance and lifecycle cleanup");
    }

    private static void testCanonicalEdgeKey() {
        long key1 = DoorwayArbiter.coordKey(10, 20, 10, 21, 0);
        long key2 = DoorwayArbiter.coordKey(10, 21, 10, 20, 0);
        assert key1 == key2 : "Symmetric coordinates must produce identical canonical key";
        assert !DoorwayArbiter.edgeIsVertical(key1) : "Edge separating y=20 and y=21 must be horizontal";
        assert DoorwayArbiter.edgeMinX(key1) == 10 : "MinX should be 10";
        assert DoorwayArbiter.edgeMinY(key1) == 20 : "MinY should be 20";
        assert DoorwayArbiter.edgeZ(key1) == 0 : "Z should be 0";

        long vert1 = DoorwayArbiter.coordKey(15, 30, 16, 30, 1);
        long vert2 = DoorwayArbiter.coordKey(16, 30, 15, 30, 1);
        assert vert1 == vert2 : "Vertical edge must be canonical";
        assert DoorwayArbiter.edgeIsVertical(vert1) : "Edge separating x=15 and x=16 must be vertical";
        assert DoorwayArbiter.edgeMinX(vert1) == 15 : "MinX should be 15";
        assert DoorwayArbiter.edgeMinY(vert1) == 30 : "MinY should be 30";
        assert DoorwayArbiter.edgeZ(vert1) == 1 : "Z should be 1";

        assert key1 != vert1 : "Different doors must have different keys";
    }

    private static void testSingleNpcAcquireAndRelease() {
        DoorwayArbiter.reset();
        long doorKey = DoorwayArbiter.coordKey(10, 20, 10, 21, 0);
        long now = 1_000_000_000L;

        assert DoorwayArbiter.acquire(doorKey, "npc-A", now, 10.5f, 19.8f) : "First acquire should succeed";
        assert DoorwayArbiter.heldEdge("npc-A") == doorKey : "Held edge mapping must match";
        assert DoorwayArbiter.currentToken(doorKey, now) != null : "Token must exist";
        assert "npc-A".equals(DoorwayArbiter.currentToken(doorKey, now).npcId) : "Owner must be npc-A";

        // Re-acquiring from same NPC refreshes token
        assert DoorwayArbiter.acquire(doorKey, "npc-A", now + 100_000_000L, 10.5f, 20.2f) : "Re-acquire by owner should succeed";

        // Release
        assert DoorwayArbiter.release(doorKey, "npc-A") : "Release should succeed";
        assert DoorwayArbiter.heldEdge("npc-A") == null : "Held edge mapping should be cleared";
        assert DoorwayArbiter.currentToken(doorKey, now) == null : "Token should no longer exist";
    }

    private static void testMutualExclusionAndYielding() {
        DoorwayArbiter.reset();
        long doorKey = DoorwayArbiter.coordKey(10, 20, 10, 21, 0);
        long now = 1_000_000_000L;

        // NPC A approaches from (10.5, 19.8)
        assert DoorwayArbiter.acquire(doorKey, "npc-A", now, 10.5f, 19.8f) : "NPC A should acquire";

        // NPC B approaches from (10.5, 21.8) at the same time
        assert !DoorwayArbiter.acquire(doorKey, "npc-B", now + 10_000_000L, 10.5f, 21.8f) : "NPC B must be rejected while A holds the doorway";

        // NPC A finishes crossing to (10.5, 22.0)
        assert DoorwayArbiter.checkAndReleaseCleared("npc-A", 10.5f, 22.0f, now + 200_000_000L) : "NPC A should clear the doorway";

        // Now NPC B acquires
        assert DoorwayArbiter.acquire(doorKey, "npc-B", now + 500_000_000L, 10.5f, 21.8f) : "NPC B should acquire once A has cleared";
    }

    private static void testTtlExpiryAndAutoRecovery() {
        DoorwayArbiter.reset();
        long doorKey = DoorwayArbiter.coordKey(5, 5, 6, 5, 0);
        long now = 1_000_000_000L;
        long ttl = 500_000_000L; // 500ms

        assert DoorwayArbiter.acquire(doorKey, "npc-A", now, ttl, 4.8f, 5.5f) : "NPC A acquires with 500ms TTL";

        // 200ms later: still active
        assert !DoorwayArbiter.acquire(doorKey, "npc-B", now + 200_000_000L, ttl, 6.8f, 5.5f) : "NPC B rejected within TTL";

        // 600ms later: TTL expired, NPC B should automatically acquire
        assert DoorwayArbiter.acquire(doorKey, "npc-B", now + 600_000_000L, ttl, 6.8f, 5.5f) : "NPC B should acquire after TTL expiration";
        assert "npc-B".equals(DoorwayArbiter.currentToken(doorKey, now + 600_000_000L).npcId) : "New owner must be NPC B";
    }

    private static void testAbortAndReleaseByNpc() {
        DoorwayArbiter.reset();
        long doorKey1 = DoorwayArbiter.coordKey(10, 10, 10, 11, 0);
        long now = 1_000_000_000L;

        assert DoorwayArbiter.acquire(doorKey1, "npc-A", now, 10.5f, 9.8f) : "NPC A acquires";

        // NPC A gets interrupted (combat / sleep / player command)
        DoorwayArbiter.releaseByNpc("npc-A");
        assert DoorwayArbiter.heldEdge("npc-A") == null : "All held edges should be dropped";
        assert DoorwayArbiter.currentToken(doorKey1, now) == null : "Token should be dropped";

        // NPC B can immediately acquire without waiting for TTL
        assert DoorwayArbiter.acquire(doorKey1, "npc-B", now, 10.5f, 11.5f) : "NPC B can acquire immediately after abort";
    }

    private static void testDirectionAwareClearance() {
        DoorwayArbiter.reset();
        // Vertical door between x=10 and x=11 on y=5. Edge center is (11.0, 5.5).
        long doorKey = DoorwayArbiter.coordKey(10, 5, 11, 5, 0);
        long now = 1_000_000_000L;

        // NPC A approaches from x=9.8 (left side, approachSign = -1)
        DoorwayArbiter.acquire(doorKey, "npc-A", now, 9.8f, 5.5f);
        DoorwayArbiter.Token tok = DoorwayArbiter.currentToken(doorKey, now);
        assert tok != null && tok.approachSign == -1 : "Approach sign from x < 11.0 should be -1";

        // While stepping onto the threshold (x=10.5), it must NOT be considered cleared
        assert !DoorwayArbiter.checkAndReleaseCleared("npc-A", 10.5f, 5.5f, now + 100_000_000L) : "Threshold tile should not trigger clearance";
        assert DoorwayArbiter.heldEdge("npc-A") != null : "Token must still be held";

        // Moving to x=11.8 (on right side, >= 11.0 + 0.75) -> Cleared!
        assert DoorwayArbiter.checkAndReleaseCleared("npc-A", 11.8f, 5.5f, now + 200_000_000L) : "Reaching opposite side must trigger clearance";
        assert DoorwayArbiter.heldEdge("npc-A") == null : "Token should be released after clearance";

        // Reverse approach: NPC B approaches from x=12.2 (right side, approachSign = +1)
        DoorwayArbiter.acquire(doorKey, "npc-B", now, 12.2f, 5.5f);
        DoorwayArbiter.Token tokB = DoorwayArbiter.currentToken(doorKey, now);
        assert tokB != null && tokB.approachSign == 1 : "Approach sign from x > 11.0 should be +1";

        // NPC B steps to x=10.1 (on left side, <= 11.0 - 0.75) -> Cleared!
        assert DoorwayArbiter.checkAndReleaseCleared("npc-B", 10.1f, 5.5f, now + 300_000_000L) : "Crossing to left side must trigger clearance";
        assert DoorwayArbiter.heldEdge("npc-B") == null : "Token should be released";
    }
}
