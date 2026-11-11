package emberroutes.probe.navharness;

import zombie.iso.IsoGridSquare;
import zombie.iso.SpriteDetails.IsoFlagType;

import emberroutes.probe.nav.EmberNavGrid;
import emberroutes.probe.nav.NavCost;

/**
 * Acceptance test for {@link SyntheticWorld} (nav-harness item 1).
 * Runnable entry point: builds an 8x8 room with a gapped wall, a closed and
 * an open door, a window, fences, broken glass and an upper floor, and
 * asserts getSquare round-trips plus walkability at every step.
 *
 * Run: javac against the game jars + java/src/main/java, then
 * {@code java -cp <classes>:<game-root>/* emberroutes.probe.navharness.SyntheticWorldTest}
 */
public final class SyntheticWorldTest {

    private SyntheticWorldTest() {}

    public static void main(String[] args) {
        SyntheticWorld world = SyntheticWorld.create();

        // 1. 8x8 room: every square round-trips and is walkable.
        world.room(8, 8);
        for (int x = 0; x < 8; x++) {
            for (int y = 0; y < 8; y++) {
                IsoGridSquare sq = world.getSquare(x, y, 0);
                check(sq != null, "room square missing at " + x + "," + y);
                check(world.getSquare(x, y, 0) == sq, "getSquare not stable at " + x + "," + y);
                check(world.isWalkable(x, y, 0), "room square not walkable at " + x + "," + y);
            }
        }
        check(world.getSquare(8, 0, 0) == null, "x=8 must be outside the single chunk");
        check(world.getSquare(0, 8, 0) == null, "y=8 must be outside the single chunk");

        // 2. Solid wall x=4 with a gap at y=3 (Spike2 case B).
        world.wallSegment(4, 0, 4, 2);
        world.wallSegment(4, 4, 4, 7);
        for (int y = 0; y < 8; y++) {
            if (y == 3) {
                check(world.isWalkable(4, y, 0), "gap at (4,3) must stay walkable");
            } else {
                check(!world.isWalkable(4, y, 0), "wall at (4," + y + ") must not be walkable");
            }
        }
        check(EmberNavGrid.canStep(null, world.getSquare(3, 3, 0), world.getSquare(4, 3, 0)),
                "step through gap (3,3)->(4,3) must be allowed");
        check(!EmberNavGrid.canStep(null, world.getSquare(3, 2, 0), world.getSquare(4, 2, 0)),
                "step into wall (3,2)->(4,2) must be refused");
        // Edge-wall flag: WallW on (4,1) also blocks entry from the west.
        IsoGridSquare edgeWall = world.getSquare(4, 1, 0);
        check(edgeWall.getProperties().has(IsoFlagType.solid), "wall square keeps solid flag");

        // 3. Doors: closed blocks, open passes.
        world.door(0, 3, SyntheticWorld.Edge.WEST, false);
        check(!world.isWalkable(0, 3, 0), "closed door must not be walkable");
        check(!EmberNavGrid.canStep(null, world.getSquare(1, 3, 0), world.getSquare(0, 3, 0)),
                "step into closed door must be refused");
        world.door(7, 3, SyntheticWorld.Edge.WEST, true);
        check(world.isWalkable(7, 3, 0), "open door must be walkable");
        check(EmberNavGrid.canStep(null, world.getSquare(6, 3, 0), world.getSquare(7, 3, 0)),
                "step through open door must be allowed");
        check(world.doors().size() == 2, "expected 2 recorded doors, got " + world.doors().size());

        // 4. Window: flag-level, does not block movement.
        world.window(2, 0, SyntheticWorld.Edge.NORTH);
        check(world.isWalkable(2, 0, 0), "window square must stay walkable");
        check(EmberNavGrid.canStep(null, world.getSquare(2, 1, 0), world.getSquare(2, 0, 0)),
                "step through flag window must be allowed");
        check(world.getSquare(2, 0, 0).getProperties().has(IsoFlagType.WindowN),
                "window square must carry WindowN flag");
        check(world.windows().size() == 1, "expected 1 recorded window");

        // 5. Fences: low (Hoppable) vs tall (TallHoppable) edge kinds.
        world.fence(5, 5, SyntheticWorld.Edge.NORTH, false);
        world.fence(6, 6, SyntheticWorld.Edge.WEST, true);
        check(EmberNavGrid.fenceEdgeKind(world.getSquare(5, 4, 0), world.getSquare(5, 5, 0))
                        == EmberNavGrid.FenceKind.LOW,
                "HoppableN must read as LOW fence");
        check(EmberNavGrid.fenceEdgeKind(world.getSquare(5, 6, 0), world.getSquare(6, 6, 0))
                        == EmberNavGrid.FenceKind.TALL,
                "TallHoppableW must read as TALL fence");
        check(world.fences().size() == 2, "expected 2 recorded fences");

        // 6. Broken glass: registry records it (real object needs game Rand, see class doc).
        world.brokenGlass(1, 1);
        check(world.hasBrokenGlass(1, 1, 0), "broken glass must be recorded at (1,1)");
        check(!world.hasBrokenGlass(1, 2, 0), "no broken glass at (1,2)");
        check(NavCost.groundHazardCost(null, world.getSquare(1, 1, 0)) == NavCost.CLEAR,
                "flag-only glass is CLEAR to NavCost until the real object exists (documented TODO)");

        // 7. Multi-floor: upper floor at z=1 round-trips and is walkable.
        world.upperFloor(8, 8);
        for (int x = 0; x < 8; x++) {
            for (int y = 0; y < 8; y++) {
                IsoGridSquare sq = world.getSquare(x, y, 1);
                check(sq != null, "upper square missing at " + x + "," + y + ",1");
                check(world.getSquare(x, y, 1) == sq, "z=1 getSquare not stable at " + x + "," + y);
                check(world.isWalkable(x, y, 1), "upper square not walkable at " + x + "," + y + ",1");
            }
        }
        SyntheticWorld.StairLink link = world.staircase(2, 2, 0, SyntheticWorld.Edge.NORTH);
        check(link.z0() == 0 && link.z1() == 1, "stair link must span z 0->1");
        check(world.stairLinks().size() == 1, "expected 1 recorded stair link");

        // 8. Bounds: the single chunk refuses coordinates outside 0..7.
        boolean threw = false;
        try {
            world.roomAt(0, 0, 9, 9, 0);
        } catch (IllegalArgumentException expected) {
            threw = true;
        }
        check(threw, "room(9,9) must throw IllegalArgumentException");

        System.out.println("PASS SyntheticWorld: 8x8 room + gapped wall + doors + window "
                + "+ fences + glass + upper floor, getSquare round-trip + isWalkable all green");
    }

    private static void check(boolean cond, String msg) {
        if (!cond) {
            throw new AssertionError("SyntheticWorldTest FAILED: " + msg);
        }
    }
}
