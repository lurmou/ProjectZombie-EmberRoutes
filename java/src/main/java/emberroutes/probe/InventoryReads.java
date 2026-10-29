package emberroutes.probe;

import java.util.ArrayList;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoGameCharacter;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;

/** Game-thread read helpers. No ownership, mutations, retained snapshots or worker threads. */
public final class InventoryReads {
    public static final int SLICE_LIMIT=32;
    private InventoryReads() {}
    static boolean truthy(Object value) { return value!=null && !Boolean.FALSE.equals(value); }
    private static final java.util.List<String> PROTECTED_KEYS=java.util.List.of(
        "EmberRoutesHaulFixture","EmberRoutesPersistenceSample","EmberRoutesProbeFixture");
    static boolean protectedData(KahluaTable data) {
        // Same short-circuit order as the original || chain: stops at the first truthy rawget.
        for (String key:PROTECTED_KEYS) if (truthy(data.rawget(key))) return true;
        return false;
    }
    public static Boolean eligible(InventoryItem item) {
        if (item==null || "Container".equals(item.getCategory()) || item.isEquipped() || item.isFavorite()) return false;
        KahluaTable data=item.getModData();
        // Preserve another mod's virtual ModData fields through the Lua path.
        if (data.getMetatable()!=null) return null;
        return !protectedData(data);
    }
    static double carry(double maximum,double weight,double free) {
        if (!Double.isFinite(maximum) || !Double.isFinite(weight) || maximum<0 || weight<0) return 0;
        return Math.max(0,Math.min(free,maximum-weight));
    }
    public static double freeCarry(IsoGameCharacter npc) {
        if (npc==null) return 0;
        double maximum=npc.getMaxWeight(),weight=npc.getInventoryWeight();
        if (!Double.isFinite(maximum) || !Double.isFinite(weight) || maximum<0 || weight<0) return 0;
        return carry(maximum,weight,npc.getInventory().getFreeCapacity(npc));
    }
    private static KahluaTable table() { return J2SEPlatform.getInstance().newTable(); }
    private static KahluaTable rejected(String reason) {
        KahluaTable result=table(); result.rawset("reason",reason); return result;
    }
    public static KahluaTable slice(ItemContainer container,ArrayList<InventoryItem> expected,
                                    int size,int offset,int limit) {
        if (container==null || expected==null || container.getItems()!=expected || expected.size()!=size)
            return rejected("INVENTORY_CHANGED");
        if (size>2000 || offset<0 || offset>size || limit<1 || limit>SLICE_LIMIT)
            return rejected("SCAN_RANGE_INVALID");
        KahluaTable result=table(),rows=table();
        int end=Math.min(size,offset+limit);
        for (int i=offset;i<end;i++) {
            InventoryItem item=expected.get(i);
            if (item==null || item.getContainer()!=container) return rejected("ITEM_LOCATION_CHANGED");
            int base=(i-offset)*3;
            rows.rawset(base+1,item); rows.rawset(base+2,Double.valueOf(item.getID())); rows.rawset(base+3,item.getFullType());
        }
        // Nothing above calls back into Lua. Never publish a partial/changed slice.
        if (container.getItems()!=expected || expected.size()!=size) return rejected("INVENTORY_CHANGED");
        result.rawset("rows",rows); return result;
    }
}
