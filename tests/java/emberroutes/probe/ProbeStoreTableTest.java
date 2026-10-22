package emberroutes.probe;

import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;

/** Actual Kahlua table migration contract. Does not initialize GlobalModData or load an NPC. */
class ProbeStoreTableTest {
    private static int count;
    public static void main(String[] args) {
        var platform=J2SEPlatform.getInstance(); var root=platform.newTable(); var legacy=platform.newTable();
        legacy.rawset("state","LIVE"); legacy.rawset("c0","original-serialized-envelope");
        var migrated=ProbePersistence.migrateRecords(root,legacy,platform);
        check(migrated.rawget("legacy")==legacy,"legacy record preserved by identity");
        check("original-serialized-envelope".equals(((KahluaTable)migrated.rawget("legacy")).rawget("c0")),"native envelope untouched by table migration");
        var second=platform.newTable(); migrated.rawset("second",second); migrated.rawset("legacy",null);
        var again=ProbePersistence.migrateRecords(root,legacy,platform);
        check(again==migrated && again.rawget("legacy")==null,"v1 cannot reappear after v2 record removal");
        check(again.rawget("second")==second,"additional NPC record survives repeated access");
        var empty=ProbePersistence.migrateRecords(platform.newTable(),null,platform);
        check(empty.isEmpty(),"empty world does not invent a checkpoint");
        var blocked=platform.newTable(); blocked.rawset("state","BLOCKED");
        check(ProbePersistence.migrateRecords(platform.newTable(),blocked,platform).rawget("legacy")==blocked,"blocked legacy gate preserved");
        for (Object bad:new Object[]{"corrupt",platform.newTable()}) {
            var invalid=platform.newTable(); invalid.rawset("snapshot",bad);
            rejects(()->ProbePersistence.migrateRecords(invalid,legacy,platform));
            check(invalid.rawget("snapshot")==bad,"invalid snapshot never overwritten by fresh migration");
        }
        var future=platform.newTable(); var snapshot=platform.newTable();
        snapshot.rawset("format",3.0); snapshot.rawset("records",platform.newTable()); future.rawset("snapshot",snapshot);
        rejects(()->ProbePersistence.migrateRecords(future,legacy,platform));
        System.out.println("PASS "+count+" actual Kahlua checkpoint table migration checks; native world/body save NOT RUN");
    }
    static void check(boolean value,String message) { count++; if (!value) throw new AssertionError(message); }
    static void rejects(Runnable task) {
        try { task.run(); } catch (IllegalStateException expected) { count++; return; }
        throw new AssertionError("unsupported store must be rejected");
    }
}
