package emberroutes.probe;

public final class BodyAuthorityTest {
    public static void main(String[] args) {
        var a = new BodyAuthority();
        assert !a.saveIdle("a");
        assert a.legacyAllowed("a");
        assert a.lifecycleIdle("a") && !a.lifecycleIdle(null) && !a.lifecycleIdle("");
        assert a.acquire("a", "j", 0).isEmpty();
        String first = a.acquire("a", "j", 1);
        assert !first.isEmpty() && a.allows("a", first, false);
        assert !a.lifecycleIdle("a") && a.lifecycleIdle("b");
        assert !a.allows("b", first, false);
        assert !a.allows("a", "wrong", true);
        assert a.acquire("a", "other", 2).isEmpty();
        assert !a.release("a", first, false);
        a.freeze();
        assert !a.legacyAllowed("b");
        assert !a.saveIdle("a") && a.saveIdle("b") && !a.saveIdle(null) && !a.saveIdle("");
        assert !a.lifecycleIdle("b");
        assert !a.allows("a", first, false) && a.allows("a", first, true);
        assert !a.thaw() && a.acquire("b", "j", 1).isEmpty();
        assert a.release("a", first, true) && a.saveIdle("a") && a.thaw() && !a.saveIdle("a");
        assert a.lifecycleIdle("a");
        assert a.managed("a") && !a.allows("a", first, true);
        assert !a.legacyAllowed("a") && a.legacyAllowed("b");
        assert a.acquire("a", "j", 1).isEmpty();
        String next = a.acquire("a", "j2", 2);
        assert !next.isEmpty() && !a.release("a", first, true);
        a.retire();
        assert !a.saveIdle("b");
        assert !a.legacyAllowed("b");
        assert !a.lifecycleIdle("b");
        assert !a.allows("a", next, false) && !a.thaw();
        assert a.allows("a", next, true); // retirement still permits necessary stop
        assert a.release("a", next, true);
        assert a.acquire("b", "j", 3).isEmpty();
        var world = new BodyAuthority();
        assert !world.allows("a", next, true);
        System.out.println("PASS body authority ownership/generation/freeze/retirement; engine NOT RUN");
    }
}
