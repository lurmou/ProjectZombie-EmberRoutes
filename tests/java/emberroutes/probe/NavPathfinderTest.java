package emberroutes.probe;

import java.util.ArrayList;
import java.util.List;
import emberroutes.probe.nav.EmberPathfinder;
import emberroutes.probe.nav.NavCost;
import emberroutes.probe.nav.NavRaycast;

public final class NavPathfinderTest {
    public static void main(String[] args) {
        testNavCostBasics();
        testHeuristicCalculations();
        testWaypointPruningAndMandatoryAnchors();
        testSinglePointSearch();
        System.out.println("PASS emberroutes custom 3D grid pathfinder, dynamic costs and checkpoint pruning");
    }

    private static void testNavCostBasics() {
        assert NavCost.hasKey(null, 123) == false : "null character has no keys";
        assert NavCost.hasKey(null, -1) == false;
        assert NavCost.isBarefoot(null) == false;

        assert NavCost.doorEdgeCost(null, null, null) == NavCost.CLEAR;
        assert NavCost.windowEdgeCost(null, null, null) == NavCost.CLEAR;
        assert NavCost.groundHazardCost(null, null) == NavCost.CLEAR;
    }

    private static void testHeuristicCalculations() {
        // Straight cardinal distance 5 tiles along X: 5 * CARDINAL_COST = 50
        int hCardinal = EmberPathfinder.heuristic(0, 0, 0, 5, 0, 0);
        assert hCardinal == 50 : "cardinal heuristic expected 50, got " + hCardinal;

        // Diagonal distance (3, 3): 3 * DIAGONAL_COST = 42
        int hDiagonal = EmberPathfinder.heuristic(0, 0, 0, 3, 3, 0);
        assert hDiagonal == 42 : "diagonal heuristic expected 42, got " + hDiagonal;

        // Mixed 2D (4, 2): 2 diagonal (28) + 2 cardinal (20) = 48
        int hMixed = EmberPathfinder.heuristic(0, 0, 0, 4, 2, 0);
        assert hMixed == 48 : "mixed heuristic expected 48, got " + hMixed;

        // Multi-floor vertical step: (0, 0, 0) to (0, 0, 2): 2 * STAIR_COST = 100
        int hVertical = EmberPathfinder.heuristic(0, 0, 0, 0, 0, 2);
        assert hVertical == 100 : "vertical stair heuristic expected 100, got " + hVertical;
    }

    private static void testWaypointPruningAndMandatoryAnchors() {
        List<NavRaycast.Waypoint> raw = new ArrayList<>();
        // Generate a straight line of 10 nodes along Y from y=0 to y=9
        for (int y = 0; y < 10; y++) {
            boolean mandatory = (y == 5); // Node 5 is a mandatory door / window
            raw.add(new NavRaycast.Waypoint(0.5f, y + 0.5f, 0, mandatory));
        }

        List<NavRaycast.Waypoint> pruned = NavRaycast.pruneCheckpoints(raw);

        // Pruning should significantly reduce the 10 nodes
        assert pruned.size() < 10 : "pruning should reduce node count, got " + pruned.size();

        // Start (y=0.5) and End (y=9.5) must be preserved
        assert Math.abs(pruned.get(0).y - 0.5f) < 0.001f : "start must be preserved";
        assert Math.abs(pruned.get(pruned.size() - 1).y - 9.5f) < 0.001f : "goal must be preserved";

        // Node 5 (mandatory door) must NOT be skipped!
        boolean hasMandatoryAnchor = false;
        for (NavRaycast.Waypoint wp : pruned) {
            if (wp.isMandatory && Math.abs(wp.y - 5.5f) < 0.001f) {
                hasMandatoryAnchor = true;
                break;
            }
        }
        assert hasMandatoryAnchor : "mandatory interaction anchor at y=5.5 must be retained in pruned path";
    }

    private static void testSinglePointSearch() {
        // Start and target are identical
        List<NavRaycast.Waypoint> path = EmberPathfinder.findPath(null, 10, 20, 0, 10, 20, 0, 100);
        assert path != null : "single point search should return path";
        assert path.size() == 1 : "expected 1 waypoint";
        assert Math.abs(path.get(0).x - 10.5f) < 0.001f;
        assert Math.abs(path.get(0).y - 20.5f) < 0.001f;
        assert path.get(0).z == 0;
    }
}
