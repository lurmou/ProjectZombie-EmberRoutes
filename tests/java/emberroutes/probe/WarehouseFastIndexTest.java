package emberroutes.probe;

import java.util.ArrayList;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;

/**
 * Unit test for Three-Tier WarehouseFastIndex and WarehouseFingerprint.
 */
public final class WarehouseFastIndexTest {
    private static int checks;
    private static void check(boolean value, String why) {
        checks++;
        if (!value) throw new AssertionError(why);
    }

    private static InventoryItem makeItem(String module, String type, int id) {
        var itm = new InventoryItem(module, type, type, new zombie.scripting.objects.Item());
        itm.setID(id);
        return itm;
    }

    public static void main(String[] args) {
        WarehouseFastIndex.reset();

        // 1. Test WarehouseFingerprint
        var cont1 = new ItemContainer();
        cont1.setCapacity(50);
        cont1.getItems().add(makeItem("Base", "Log", 101));
        cont1.getItems().add(makeItem("Base", "Log", 102));

        var fp1 = WarehouseFingerprint.of(cont1);
        var fp2 = WarehouseFingerprint.of(cont1);
        check(fp1 != null && fp2 != null, "Fingerprints created");
        check(fp1.matches(fp2), "Same container produces matching fingerprints");

        cont1.getItems().add(makeItem("Base", "Log", 103));
        var fp3 = WarehouseFingerprint.of(cont1);
        check(!fp1.matches(fp3), "Adding item changes fingerprint");

        // 2. Test Settlement scan with 2 containers
        var platform = J2SEPlatform.getInstance();
        var containerList = platform.newTable();

        var desc1 = platform.newTable();
        desc1.rawset("id", "crate_1");
        desc1.rawset("container", cont1);
        desc1.rawset("x", 10.0); desc1.rawset("y", 20.0); desc1.rawset("z", 0.0);
        desc1.rawset("kind", "crate");
        desc1.rawset("customName", "Wood Storage");
        desc1.rawset("capacity", 50.0);
        desc1.rawset("usedWeight", 27.0);

        var cont2 = new ItemContainer();
        cont2.setCapacity(30);
        cont2.getItems().add(makeItem("Base", "Apple", 201));
        cont2.getItems().add(makeItem("Base", "Apple", 202));
        cont2.getItems().add(makeItem("Base", "Axe", 203));

        var desc2 = platform.newTable();
        desc2.rawset("id", "fridge_1");
        desc2.rawset("container", cont2);
        desc2.rawset("x", 15.0); desc2.rawset("y", 25.0); desc2.rawset("z", 0.0);
        desc2.rawset("kind", "fridge");
        desc2.rawset("customName", "Kitchen Fridge");
        desc2.rawset("capacity", 30.0);
        desc2.rawset("usedWeight", 6.0);

        containerList.rawset(1.0, desc1);
        containerList.rawset(2.0, desc2);

        // Initial scan
        KahluaTable result = WarehouseFastIndex.scanSettlement("settlement_one", containerList, false);
        check(result != null, "Scan result returned");
        check("READY".equals(result.rawget("state")), "Result state is READY");

        KahluaTable counts = (KahluaTable) result.rawget("counts");
        check(counts != null, "Counts table present");
        check(Double.valueOf(6.0).equals(counts.rawget("items")), "Total items count is 6 (3 logs, 2 apples, 1 axe)");
        check(Double.valueOf(2.0).equals(counts.rawget("loaded")), "2 containers loaded");
        check(Double.valueOf(80.0).equals(counts.rawget("totalCapacity")), "Total capacity is 50 + 30 = 80");

        KahluaTable rows = (KahluaTable) result.rawget("rows");
        check(rows != null, "Rows table present");
        check(rows.len() == 3, "3 distinct fullTypes found");

        // Verify sorted order: Base.Apple, Base.Axe, Base.Log
        KahluaTable r1 = (KahluaTable) rows.rawget(1.0);
        KahluaTable r2 = (KahluaTable) rows.rawget(2.0);
        KahluaTable r3 = (KahluaTable) rows.rawget(3.0);
        check("Base.Apple".equals(r1.rawget("fullType")), "First sorted type is Base.Apple");
        check(Double.valueOf(2.0).equals(r1.rawget("count")), "Apple count is 2");
        check("Base.Axe".equals(r2.rawget("fullType")), "Second sorted type is Base.Axe");
        check(Double.valueOf(1.0).equals(r2.rawget("count")), "Axe count is 1");
        check("tools".equals(r2.rawget("node")), "Axe categorized as tools");
        check("Base.Log".equals(r3.rawget("fullType")), "Third sorted type is Base.Log");
        check(Double.valueOf(3.0).equals(r3.rawget("count")), "Log count is 3");

        // Verify sources list for Log
        KahluaTable logSources = (KahluaTable) r3.rawget("sources");
        check(logSources.len() == 1, "Log has 1 source container");
        KahluaTable src1 = (KahluaTable) logSources.rawget(1.0);
        check("crate_1".equals(src1.rawget("id")), "Log source is crate_1");
        check(Double.valueOf(3.0).equals(src1.rawget("count")), "Log source count is 3");

        // 3. Test Tier 1 & Tier 2 Cache Hit (Zero-rescan)
        KahluaTable cachedResult = WarehouseFastIndex.scanSettlement("settlement_one", containerList, false);
        check(cachedResult == result, "Unchanged scan returns identical cached snapshot instance");

        // 4. Test Incremental Dirty Rescan
        cont2.getItems().add(makeItem("Base", "Apple", 204));
        KahluaTable updatedResult = WarehouseFastIndex.scanSettlement("settlement_one", containerList, false);
        check(updatedResult != result, "Dirty container triggers recompile");
        KahluaTable updatedCounts = (KahluaTable) updatedResult.rawget("counts");
        check(Double.valueOf(7.0).equals(updatedCounts.rawget("items")), "Updated total items is 7");

        KahluaTable updatedRows = (KahluaTable) updatedResult.rawget("rows");
        KahluaTable updatedR1 = (KahluaTable) updatedRows.rawget(1.0);
        check("Base.Apple".equals(updatedR1.rawget("fullType")), "Apple still first");
        check(Double.valueOf(3.0).equals(updatedR1.rawget("count")), "Apple count incremented to 3");

        // 5. Test Cache Reset
        WarehouseFastIndex.reset();
        KahluaTable afterReset = WarehouseFastIndex.scanSettlement("settlement_one", containerList, false);
        check(afterReset != updatedResult, "After reset, a new snapshot is generated");

        System.out.println("PASS " + checks + " WarehouseFastIndex & WarehouseFingerprint assertions cleanly!");
    }
}
