package emberroutes.probe;

import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;

/** Actual Kahlua v2 checkpoint table contract. Does not initialize GlobalModData or load an NPC. No v1 migration: a fresh root gets an empty format-2 snapshot, anything else is rejected. */
class ProbeStoreTableTest {
    private static int count;
    public static void main(String[] args) {
        var platform=J2SEPlatform.getInstance(); var root=platform.newTable();
        var records=ProbePersistence.ensureRecords(root,platform);
        check(records.isEmpty(),"empty world does not invent a checkpoint");
        check(Double.valueOf(2).equals(((KahluaTable)root.rawget("snapshot")).rawget("format")),"fresh root publishes format-2 snapshot");
        var second=platform.newTable(); records.rawset("second",second);
        var again=ProbePersistence.ensureRecords(root,platform);
        check(again==records && again.rawget("second")==second,"additional NPC record survives repeated access");
        for (Object bad:new Object[]{"corrupt",platform.newTable()}) {
            var invalid=platform.newTable(); invalid.rawset("snapshot",bad);
            rejects(()->ProbePersistence.ensureRecords(invalid,platform));
            check(invalid.rawget("snapshot")==bad,"invalid snapshot never overwritten");
        }
        var future=platform.newTable(); var snapshot=platform.newTable();
        snapshot.rawset("format",3.0); snapshot.rawset("records",platform.newTable()); future.rawset("snapshot",snapshot);
        rejects(()->ProbePersistence.ensureRecords(future,platform));
        System.out.println("PASS "+count+" actual Kahlua checkpoint table checks; native world/body save NOT RUN");
    }
    static void check(boolean value,String message) { count++; if (!value) throw new AssertionError(message); }
    static void rejects(Runnable task) {
        try { task.run(); } catch (IllegalStateException expected) { count++; return; }
        throw new AssertionError("unsupported store must be rejected");
    }
}
