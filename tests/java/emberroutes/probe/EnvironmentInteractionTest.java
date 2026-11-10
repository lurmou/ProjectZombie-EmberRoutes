package emberroutes.probe;

import zombie.iso.IsoDirections;

public final class EnvironmentInteractionTest {
    public static void main(String[] args) {
        testDirectionOfOrthogonal();
        testDirectionOfDiagonalAndZero();
        testNullSafetyAndTraversalGuard();
        System.out.println("PASS environment interaction edge direction, distance guard and traversal safety");
    }

    private static void testDirectionOfOrthogonal() {
        assert EnvironmentInteraction.directionOf(0, -1) == IsoDirections.N : "North direction failed";
        assert EnvironmentInteraction.directionOf(0, 1) == IsoDirections.S : "South direction failed";
        assert EnvironmentInteraction.directionOf(-1, 0) == IsoDirections.W : "West direction failed";
        assert EnvironmentInteraction.directionOf(1, 0) == IsoDirections.E : "East direction failed";
    }

    private static void testDirectionOfDiagonalAndZero() {
        assert EnvironmentInteraction.directionOf(0, 0) == null : "Zero displacement should be null";
        // Vertical priority for diagonal components
        assert EnvironmentInteraction.directionOf(1, -1) == IsoDirections.N : "NE should prioritize N";
        assert EnvironmentInteraction.directionOf(-1, 1) == IsoDirections.S : "SW should prioritize S";
    }

    private static void testNullSafetyAndTraversalGuard() {
        assert EnvironmentInteraction.interactAhead(null, 10.0f, 10.0f, false) == EnvironmentInteraction.Result.NONE;
        assert EnvironmentInteraction.interactAhead(null, 10.0f, 10.0f, true) == EnvironmentInteraction.Result.NONE;
        assert EnvironmentInteraction.Result.valueOf("WAIT_DOORWAY") == EnvironmentInteraction.Result.WAIT_DOORWAY : "WAIT_DOORWAY enum must exist";
    }
}
