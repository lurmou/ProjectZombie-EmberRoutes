package emberroutes.probe.navharness;

import java.util.ArrayList;
import java.util.List;
import zombie.iso.IsoCell;
import zombie.iso.IsoChunk;
import zombie.iso.IsoChunkMap;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;
import zombie.iso.SliceY;
import zombie.iso.SpriteDetails.IsoFlagType;
import emberroutes.probe.nav.EmberNavGrid;
import emberroutes.probe.nav.EmberPathfinder;
import emberroutes.probe.nav.NavCost;
import emberroutes.probe.nav.NavRaycast;

/**
 * Pathfinder scenario set for the Ember Routes nav harness ("mini-Zomboid test build").
 *
 * Organized from the verified feasibility spikes Spike2.java / Spike2b.java
 * (8x8 room, wall-with-gap -> through gap; sealed wall -> null; flag-only
 * wall -> detour / costly crossing; isWallTo false for flag-only squares).
 * Each scenario asserts route / no-route / cost against the real production
 * classes (EmberPathfinder, EmberNavGrid, NavCost) and prints the waypoint
 * list of every route it finds.
 *
 * Run (from the repo root, JDK 25, game jars on the classpath only):
 *   javac -cp "$GAME_ROOT/*" -d /tmp/navharness-classes \
 *       java/src/main/java/emberroutes/probe/nav/*.java
 *   javac -ea -cp "/tmp/navharness-classes:$GAME_ROOT/*" -d /tmp/navharness-classes \
 *       tests/java/emberroutes/probe/navharness/PathfinderScenarios.java
 *   java -ea -cp "/tmp/navharness-classes:$GAME_ROOT/*" \
 *       emberroutes.probe.navharness.PathfinderScenarios
 *
 * Scenarios that cannot run headless are recorded with skip() + the verified
 * cause instead of being faked: broken glass, locked-door-with-key, and
 * positive stair traversal (see each method).
 */
public final class PathfinderScenarios {

    // ------------------------------------------------------------------
    // World builder.
    // vendored from Spike1c, consolidate into SyntheticWorld in harness-entry.
    // (Copied here so this scenario set does not block on item 1; the
    // harness entry point, item 7, will converge on one shared builder.)
    // ------------------------------------------------------------------
    static IsoCell cell;
    static IsoChunkMap cm;
    static SliceY slice;

    static void buildWorld() {
        IsoWorld world = new IsoWorld();
        IsoWorld.instance = world;
        cell = new IsoCell(30, 30);
        world.currentCell = cell;
        cm = cell.getChunkMap(0);
        cm.setInitialPos(0, 0);
        IsoChunk chunk = new IsoChunk(cell);
        chunk.wx = 0;
        chunk.wy = 0;
        chunk.refs.add(cm);
        cm.setChunkDirect(chunk, false);
        slice = new SliceY();
    }

    static IsoGridSquare floor(int x, int y) {
        return floor(x, y, 0);
    }

    static IsoGridSquare floor(int x, int y, int z) {
        IsoGridSquare sq = new IsoGridSquare(cell, slice, x, y, z);
        sq.getProperties().set(IsoFlagType.solidfloor);
        cm.setGridSquare(sq, x, y, z);
        return sq;
    }

    static void room(int size) {
        for (int x = 0; x < size; x++) {
            for (int y = 0; y < size; y++) floor(x, y);
        }
    }

    static IsoGridSquare solidWall(int x, int y) {
        IsoGridSquare sq = new IsoGridSquare(cell, slice, x, y, 0);
        sq.getProperties().set(IsoFlagType.solid);
        sq.getProperties().set(IsoFlagType.solidfloor);
        cm.setGridSquare(sq, x, y, 0);
        return sq;
    }

    static IsoGridSquare flagWall(int x, int y, IsoFlagType flag) {
        IsoGridSquare sq = new IsoGridSquare(cell, slice, x, y, 0);
        sq.getProperties().set(IsoFlagType.solidfloor);
        sq.getProperties().set(flag);
        cm.setGridSquare(sq, x, y, 0);
        return sq;
    }

    // ------------------------------------------------------------------
    // Reporting / assertions.
    // ------------------------------------------------------------------
    static int passed = 0;
    static final List<String> skipped = new ArrayList<>();

    static void pass(String name) {
        passed++;
        System.out.println("PASS " + name);
    }

    static void skip(String name, String reason) {
        skipped.add(name + ": " + reason);
        System.out.println("SKIP " + name + ": " + reason);
    }

    static String printPath(String name, List<NavRaycast.Waypoint> path) {
        if (path == null) {
            System.out.println("  " + name + ": null (no path)");
            return name + ": null";
        }
        StringBuilder sb = new StringBuilder("  " + name + ": " + path.size() + " waypoints:");
        for (NavRaycast.Waypoint w : path) {
            sb.append(String.format(" (%.1f,%.1f,%d%s)", w.x, w.y, w.z, w.isMandatory ? ",M" : ""));
        }
        System.out.println(sb);
        return sb.toString();
    }

    static int tileX(NavRaycast.Waypoint w) { return (int) Math.floor(w.x); }
    static int tileY(NavRaycast.Waypoint w) { return (int) Math.floor(w.y); }

    static void check(boolean cond, String msg) {
        if (!cond) throw new AssertionError(msg);
    }

    static void checkEndpoints(List<NavRaycast.Waypoint> path, int sx, int sy, int tx, int ty) {
        check(path != null && !path.isEmpty(), "expected a path");
        check(tileX(path.get(0)) == sx && tileY(path.get(0)) == sy,
                "path must start at (" + sx + "," + sy + "), got (" + tileX(path.get(0)) + "," + tileY(path.get(0)) + ")");
        NavRaycast.Waypoint last = path.get(path.size() - 1);
        check(tileX(last) == tx && tileY(last) == ty,
                "path must end at (" + tx + "," + ty + "), got (" + tileX(last) + "," + tileY(last) + ")");
    }

    // ------------------------------------------------------------------
    // Scenarios.
    // ------------------------------------------------------------------

    /** Open 8x8 room: a route must exist from corner to corner. */
    static void scenarioOpenRoom() {
        buildWorld();
        room(8);
        List<NavRaycast.Waypoint> path = EmberPathfinder.findPath(null, 1, 1, 0, 6, 6, 0, 2000);
        printPath("open (1,1)->(6,6)", path);
        checkEndpoints(path, 1, 1, 6, 6);
        for (NavRaycast.Waypoint w : path) {
            check(w.z == 0, "open-room path must stay on z=0");
            check(tileX(w) >= 0 && tileX(w) < 8 && tileY(w) >= 0 && tileY(w) < 8,
                    "open-room waypoint outside room: " + w);
        }
        pass("open-room");
    }

    /** Solid wall x=4 with a gap at y=3: the route must go through the gap. */
    static void scenarioWallGap() {
        buildWorld();
        room(8);
        for (int y = 0; y < 8; y++) {
            if (y != 3) solidWall(4, y);
        }
        List<NavRaycast.Waypoint> path = EmberPathfinder.findPath(null, 1, 3, 0, 6, 3, 0, 2000);
        printPath("wall-gap (1,3)->(6,3)", path);
        checkEndpoints(path, 1, 3, 6, 3);
        boolean throughGap = false;
        for (NavRaycast.Waypoint w : path) {
            if (tileX(w) == 4) {
                check(tileY(w) == 3, "path must not cross the solid wall outside the gap, at (" + tileX(w) + "," + tileY(w) + ")");
                throughGap = true;
            }
        }
        check(throughGap, "path must pass through the gap tile (4,3)");
        pass("wall-gap");
    }

    /** Solid wall x=4 with no gap: no route. */
    static void scenarioSealedWall() {
        buildWorld();
        room(8);
        for (int y = 0; y < 8; y++) solidWall(4, y);
        List<NavRaycast.Waypoint> path = EmberPathfinder.findPath(null, 1, 3, 0, 6, 3, 0, 2000);
        printPath("sealed-wall (1,3)->(6,3)", path);
        check(path == null, "sealed wall must yield no path, got " + (path == null ? "null" : path.size() + " waypoints"));
        pass("sealed-wall");
    }

    /**
     * Flag-only wall (WallW, not solid) on x=4: isWallTo() returns false for
     * flag-only squares (verified Spike2b), so the wall does not block — but
     * fenceEdgeKind() reads the flag as TALL on ORTHOGONAL steps, so an
     * orthogonal crossing costs NavCost.TALL_FENCE_CLIMB. Note the A* route
     * found here crosses the column diagonally, and fenceEdgeKind() returns
     * NONE for diagonal steps, so the diagonal crossing pays no fence cost
     * and its waypoint is not mandatory — that is real production behavior,
     * asserted explicitly below, not assumed.
     */
    static void scenarioFlagWall() {
        buildWorld();
        room(8);
        for (int y = 0; y < 8; y++) flagWall(4, y, IsoFlagType.WallW);
        List<NavRaycast.Waypoint> path = EmberPathfinder.findPath(null, 1, 3, 0, 6, 3, 0, 2000);
        printPath("flag-wall WallW (1,3)->(6,3)", path);
        checkEndpoints(path, 1, 3, 6, 3);
        int crossings = 0;
        for (NavRaycast.Waypoint w : path) {
            if (tileX(w) == 4) crossings++;
        }
        check(crossings == 1, "flag-wall path must cross the flagged column exactly once, crossed " + crossings + " times");
        // Diagonal steps pay no fence cost: fenceEdgeKind() is NONE off-axis.
        check(EmberNavGrid.fenceEdgeKind(cm.getGridSquare(3, 3, 0), cm.getGridSquare(4, 4, 0)) == EmberNavGrid.FenceKind.NONE,
                "diagonal step across a WallW column must be NONE fence kind (no fence cost)");

        // Spike2b matrix: a flag-only square is no wall in any direction.
        buildWorld();
        IsoGridSquare center = flagWall(1, 1, IsoFlagType.WallW);
        IsoGridSquare west = floor(0, 1);
        IsoGridSquare east = floor(2, 1);
        IsoGridSquare north = floor(1, 0);
        IsoGridSquare south = floor(1, 2);
        IsoGridSquare[][] pairs = {{west, center}, {east, center}, {north, center},
                {south, center}, {center, west}, {center, east}};
        for (IsoGridSquare[] p : pairs) {
            check(!p[0].isWallTo(p[1]), "isWallTo must be false for flag-only WallW square");
            check(EmberNavGrid.canStep(null, p[0], p[1]), "canStep must be true for flag-only WallW square");
        }
        IsoGridSquare centerN = flagWall(1, 1, IsoFlagType.WallN);
        check(!north.isWallTo(centerN) && EmberNavGrid.canStep(null, north, centerN), "WallN: north->center must not be a wall");
        check(!south.isWallTo(centerN) && EmberNavGrid.canStep(null, south, centerN), "WallN: south->center must not be a wall");
        check(!west.isWallTo(centerN) && EmberNavGrid.canStep(null, west, centerN), "WallN: west->center must not be a wall");

        // Fence edge costs follow the real NavCost constants, not invented numbers.
        check(EmberNavGrid.fenceEdgeKind(west, center) == EmberNavGrid.FenceKind.TALL, "WallW edge must be TALL fence");
        check(EmberNavGrid.fenceEdgeCost(west, center) == NavCost.TALL_FENCE_CLIMB, "TALL fence cost must be NavCost.TALL_FENCE_CLIMB");
        IsoGridSquare hopW = flagWall(1, 1, IsoFlagType.HoppableW);
        check(EmberNavGrid.fenceEdgeKind(west, hopW) == EmberNavGrid.FenceKind.LOW, "HoppableW edge must be LOW fence");
        check(EmberNavGrid.fenceEdgeCost(west, hopW) == NavCost.LOW_FENCE_VAULT, "LOW fence cost must be NavCost.LOW_FENCE_VAULT");
        IsoGridSquare hopN = flagWall(1, 1, IsoFlagType.HoppableN);
        check(EmberNavGrid.fenceEdgeKind(north, hopN) == EmberNavGrid.FenceKind.LOW, "HoppableN edge must be LOW fence");
        check(EmberNavGrid.fenceEdgeCost(floor(0, 1), floor(2, 1)) == NavCost.CLEAR, "plain edge must be CLEAR");
        pass("flag-wall");
    }

    /**
     * Broken glass: SKIPPED headless (verified, not assumed).
     * NavCost.groundHazardCost reads sq.getBrokenGlass(): null character
     * counts as shod -> BROKEN_GLASS_SHOD_PENALTY, barefoot -> BLOCKED.
     * But no broken-glass square can be built headless on this VM:
     * IsoGridSquare.addBrokenGlass() and direct `new IsoBrokenGlass(cell)`
     * both throw NPE because the engine RNG (`randomizer`) is null outside
     * game init, and `new IsoPlayer(cell)` (needed for the barefoot case)
     * fails at GameClient static init for the same reason. Three approaches
     * tried (direct add / direct attach / RandStandard init — its ctor is
     * protected); stopped per the anti-rabbit-hole rule. Needs a game-init
     * harness (item 7) or in-game run to cover.
     * Runnable control kept: a clean square costs CLEAR.
     */
    static void scenarioBrokenGlass() {
        buildWorld();
        room(8);
        IsoGridSquare clean = cm.getGridSquare(2, 2, 0);
        check(NavCost.groundHazardCost(null, clean) == NavCost.CLEAR,
                "clean square must cost CLEAR, got " + NavCost.groundHazardCost(null, clean));
        check(NavCost.BROKEN_GLASS_SHOD_PENALTY == 50, "shod glass penalty constant changed, check NavCost");
        skip("broken-glass detour/cost",
                "no broken-glass square constructible headless: addBrokenGlass()/new IsoBrokenGlass(cell) NPE on null engine RNG; IsoPlayer (barefoot case) fails at GameClient static init for the same reason");
        pass("broken-glass-control");
    }

    /**
     * Locked door + key: SKIPPED headless (verified, not assumed).
     * NavCost.doorEdgeCost needs a real door object discoverable via
     * from.getDoorTo(to). Headless that is impossible on this VM:
     * the sprite-name IsoDoor ctor NPEs (no sprite data without a game
     * install: validSprite null); a bare-ctor door attached by hand is
     * invisible to getDoorTo (verified false from both sides); and the
     * IsoSprite-ctor path pulls LuaManager/SandboxOptions/ZomboidFileSystem
     * static init, which needs a game install root. A key-holding character
     * would also need IsoPlayer, blocked as in scenarioBrokenGlass.
     * The no-door guard (CLEAR) is already covered by NavPathfinderTest.
     */
    static void scenarioDoorKey() {
        skip("door-key",
                "no real IsoDoor constructible headless: sprite ctor NPEs (validSprite null), bare-ctor door invisible to getDoorTo, IsoSprite ctor pulls LuaManager/ZomboidFileSystem init needing a game install; IsoPlayer also blocked");
    }

    /**
     * Stairs up/down: positive traversal SKIPPED; negative linkage asserted.
     * Positive traversal needs real stair objects: an IsoObject with a
     * hand-made IsoSprite reports HasStairs=false (no sprite data headless),
     * so EmberNavGrid.staircaseTop / stair anchors can never resolve and
     * the A* stair relaxation never fires. A multi-level synthetic world is
     * buildable in principle (z=1 floor squares below), but without stair
     * objects it proves nothing beyond the negative assertions kept here:
     * with a real z=1 floor present and no stairs, the z=0 -> z=1 route
     * must still be null and all stair lookups must return null.
     */
    static void scenarioStairs() {
        buildWorld();
        room(8);
        for (int x = 0; x < 8; x++) {
            for (int y = 0; y < 8; y++) floor(x, y, 1);
        }
        IsoGridSquare ground = cm.getGridSquare(1, 1, 0);
        check(cm.getGridSquare(1, 1, 1) != null, "z=1 floor square must exist (multi-level world built)");
        check(EmberNavGrid.stairLandingAbove(ground) == null, "plain floor must have no stair landing above");
        check(EmberNavGrid.stairApproachBelow(cm.getGridSquare(1, 1, 1)) == null, "plain upper floor must have no stair approach below");
        check(EmberNavGrid.stairBottomApproach(ground) == null, "plain floor must have no stair bottom approach");
        check(EmberNavGrid.stairUpperLanding(ground) == null, "plain floor must have no stair upper landing");
        List<NavRaycast.Waypoint> up = EmberPathfinder.findPath(null, 1, 1, 0, 6, 6, 1, 2000);
        printPath("stairs up (1,1,0)->(6,6,1) no stairs", up);
        check(up == null, "z=0 -> z=1 with no stair link must yield no path");
        List<NavRaycast.Waypoint> down = EmberPathfinder.findPath(null, 6, 6, 1, 1, 1, 0, 2000);
        printPath("stairs down (6,6,1)->(1,1,0) no stairs", down);
        check(down == null, "z=1 -> z=0 with no stair link must yield no path");
        pass("stairs-negative");
        skip("stairs up/down traversal",
                "no real stair objects headless: IsoObject with hand-made IsoSprite reports HasStairs=false; real stair sprites need IsoSpriteManager asset data from a game install");
    }

    public static void main(String[] args) {
        scenarioOpenRoom();
        scenarioWallGap();
        scenarioSealedWall();
        scenarioFlagWall();
        scenarioBrokenGlass();
        scenarioDoorKey();
        scenarioStairs();
        System.out.println("PATHFINDER-SCENARIOS: " + passed + " passed, " + skipped.size() + " skipped");
        for (String s : skipped) System.out.println("  skipped: " + s);
        System.out.println("PASS pathfinder scenarios (open/wall-gap/sealed/flag-wall/glass-control/stairs-negative)");
    }
}
