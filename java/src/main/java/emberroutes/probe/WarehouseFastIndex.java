package emberroutes.probe;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;

/**
 * Three-tier high-performance warehouse index and caching system.
 * 1. Tier 1: In-memory compiled Kahlua snapshot cache for zero-latency UI read.
 * 2. Tier 2: Microsecond container fingerprint change detection (skips unchanged containers).
 * 3. Tier 3: Sub-millisecond Java-native container scan and aggregation.
 */
public final class WarehouseFastIndex {
    private WarehouseFastIndex() {}

    private static KahluaTable table() {
        return J2SEPlatform.getInstance().newTable();
    }

    private static final Map<String, String> CATEGORY_CACHE = new ConcurrentHashMap<>();

    public static String classifyItem(InventoryItem item) {
        if (item == null) return "other";
        String ft = item.getFullType();
        if (ft != null) {
            String cached = CATEGORY_CACHE.get(ft);
            if (cached != null) return cached;
        }

        String node = doClassify(item);
        if (ft != null) {
            CATEGORY_CACHE.put(ft, node);
        }
        return node;
    }

    private static String doClassify(InventoryItem item) {
        try {
            boolean food = item.isFood() || "Food".equalsIgnoreCase(item.getCategory());
            if (food) {
                return item.getOffAgeMax() < 1_000_000_000 ? "food.perishable" : "food.stable";
            }
            if (item instanceof zombie.inventory.types.HandWeapon hw && hw.isRanged()) {
                return "weapons.guns";
            }
            String cat = item.getCategory();
            String disp = item.getDisplayCategory();
            if ("Ammo".equalsIgnoreCase(cat) || "Ammo".equalsIgnoreCase(disp)) {
                return "weapons.ammo";
            }
            if ("Weapon".equalsIgnoreCase(cat) || "WeaponPart".equalsIgnoreCase(cat)) {
                return "weapons.other";
            }
            if ("Material".equalsIgnoreCase(cat) || "Clothing".equalsIgnoreCase(cat)) {
                return "materials";
            }
            String fullType = item.getFullType();
            if ("FirstAid".equalsIgnoreCase(cat) || "FirstAid".equalsIgnoreCase(disp) ||
                (fullType != null && (fullType.contains("Bandage") || fullType.contains("Pills")))) {
                return "medical";
            }
            if ("Tool".equalsIgnoreCase(cat) || "ToolWeapon".equalsIgnoreCase(cat) ||
                (fullType != null && (fullType.contains("Hammer") || fullType.contains("Saw") ||
                                      fullType.contains("Axe") || fullType.contains("Wrench") ||
                                      fullType.contains("Screwdriver")))) {
                return "tools";
            }
        } catch (RuntimeException ignored) {}
        return "other";
    }

    static final class ContainerContribution {
        final String containerId;
        final WarehouseFingerprint fingerprint;
        final int count;
        final Map<String, Integer> typeCounts;
        final double capacity;
        final double usedWeight;
        final String kind;
        final String displayType;
        final String customName;
        final int x, y, z;
        final String status;

        ContainerContribution(String containerId, WarehouseFingerprint fingerprint, int count,
                              Map<String, Integer> typeCounts, double capacity, double usedWeight,
                              String kind, String displayType, String customName, int x, int y, int z,
                              String status) {
            this.containerId = containerId;
            this.fingerprint = fingerprint;
            this.count = count;
            this.typeCounts = typeCounts;
            this.capacity = capacity;
            this.usedWeight = usedWeight;
            this.kind = kind;
            this.displayType = displayType;
            this.customName = customName;
            this.x = x;
            this.y = y;
            this.z = z;
            this.status = status;
        }
    }

    static final class SettlementState {
        final String settlementId;
        final Map<String, ContainerContribution> containers = new ConcurrentHashMap<>();
        KahluaTable compiledResult = null;
        long revision = 0;

        SettlementState(String settlementId) {
            this.settlementId = settlementId;
        }
    }

    private static final Map<String, SettlementState> SETTLEMENTS = new ConcurrentHashMap<>();

    public static void reset() {
        SETTLEMENTS.clear();
        CATEGORY_CACHE.clear();
    }

    public static void invalidateSettlement(String settlementId) {
        if (settlementId != null) {
            SETTLEMENTS.remove(settlementId);
        }
    }

    private static int intVal(Object o, int fallback) {
        if (o instanceof Number n) return n.intValue();
        return fallback;
    }

    private static double doubleVal(Object o, double fallback) {
        if (o instanceof Number n) return n.doubleValue();
        return fallback;
    }

    private static String strVal(Object o, String fallback) {
        if (o instanceof String s) return s;
        return fallback;
    }

    public static KahluaTable scanSettlement(String settlementId, KahluaTable containerList, boolean force) {
        if (settlementId == null || containerList == null) return null;
        SettlementState state = SETTLEMENTS.computeIfAbsent(settlementId, SettlementState::new);

        boolean dirty = force || state.compiledResult == null;
        Set<String> activeIds = new HashSet<>();

        var iter = containerList.iterator();
        while (iter.advance()) {
            if (!(iter.getValue() instanceof KahluaTable desc)) continue;
            String cid = (String) desc.rawget("id");
            if (cid == null) continue;
            activeIds.add(cid);

            ItemContainer container = null;
            Object contObj = desc.rawget("container");
            if (contObj instanceof ItemContainer ic) {
                container = ic;
            }

            int x = intVal(desc.rawget("x"), 0);
            int y = intVal(desc.rawget("y"), 0);
            int z = intVal(desc.rawget("z"), 0);
            double cap = doubleVal(desc.rawget("capacity"), 0.0);
            double used = doubleVal(desc.rawget("usedWeight"), 0.0);
            String kind = strVal(desc.rawget("kind"), "container");
            String disp = strVal(desc.rawget("displayType"), null);
            String custom = strVal(desc.rawget("customName"), null);

            if (container == null) {
                ContainerContribution prev = state.containers.get(cid);
                if (prev == null || !"CONTAINER_UNLOADED".equals(prev.status)) {
                    state.containers.put(cid, new ContainerContribution(cid, null, 0,
                        Collections.emptyMap(), cap, used, kind, disp, custom, x, y, z, "CONTAINER_UNLOADED"));
                    dirty = true;
                }
                continue;
            }

            WarehouseFingerprint fp = WarehouseFingerprint.of(container);
            ContainerContribution existing = state.containers.get(cid);

            if (!dirty && existing != null && "LOADED".equals(existing.status) && fp != null && fp.matches(existing.fingerprint)) {
                // Tier 2 check: Unchanged! Skip scanning.
                continue;
            }

            // Tier 3 scan: Scan container items in native Java
            ArrayList<InventoryItem> items = container.getItems();
            Map<String, Integer> counts = new HashMap<>();
            int eligibleCount = 0;
            if (items != null) {
                int sz = items.size();
                for (int i = 0; i < sz; i++) {
                    InventoryItem itm = items.get(i);
                    if (itm == null) continue;
                    if (!Boolean.TRUE.equals(InventoryReads.eligible(itm))) continue;
                    String ft = itm.getFullType();
                    if (ft == null) continue;
                    counts.put(ft, counts.getOrDefault(ft, 0) + 1);
                    eligibleCount++;
                    classifyItem(itm);
                }
            }

            double actualCap = cap > 0 ? cap : (double) container.getCapacity();
            double actualUsed = used > 0 ? used : (double) container.getContentsWeight();

            ContainerContribution contribution = new ContainerContribution(
                cid, fp, eligibleCount, counts, actualCap, actualUsed,
                kind, disp, custom, x, y, z, "LOADED"
            );
            state.containers.put(cid, contribution);
            dirty = true;
        }

        // Handle deleted / removed containers
        if (state.containers.keySet().removeIf(id -> !activeIds.contains(id))) {
            dirty = true;
        }

        if (!dirty && state.compiledResult != null) {
            // Tier 1 check: Instant return of compiled snapshot
            return state.compiledResult;
        }

        state.revision++;
        state.compiledResult = compileSnapshot(state);
        return state.compiledResult;
    }

    private static KahluaTable compileSnapshot(SettlementState state) {
        KahluaTable result = table();
        KahluaTable rowsTable = table();
        KahluaTable countsTable = table();
        KahluaTable containersTable = table();
        KahluaTable fullContainersList = table();

        int loadedCount = 0;
        int unloadedCount = 0;
        int totalItems = 0;
        double totalCapacity = 0;
        double totalUsedWeight = 0;
        int fullCount = 0;

        Map<String, Integer> totalCountsByType = new HashMap<>();
        Map<String, List<KahluaTable>> sourcesByType = new HashMap<>();

        int contIndex = 1;
        for (ContainerContribution c : state.containers.values()) {
            if ("LOADED".equals(c.status)) {
                loadedCount++;
                totalItems += c.count;
                totalCapacity += c.capacity;
                totalUsedWeight += c.usedWeight;

                boolean isFull = c.capacity > 0 && c.usedWeight >= c.capacity * 0.9;
                if (isFull) {
                    fullCount++;
                    if (fullContainersList.len() < 8) {
                        KahluaTable fc = table();
                        fc.rawset("name", c.customName != null ? c.customName : c.kind);
                        fc.rawset("x", Double.valueOf(c.x));
                        fc.rawset("y", Double.valueOf(c.y));
                        fc.rawset("z", Double.valueOf(c.z));
                        fc.rawset("capacity", Double.valueOf(c.capacity));
                        fc.rawset("used", Double.valueOf(c.usedWeight));
                        fullContainersList.rawset(Double.valueOf(fullContainersList.len() + 1), fc);
                    }
                }

                KahluaTable contEntry = table();
                contEntry.rawset("id", c.containerId);
                contEntry.rawset("x", Double.valueOf(c.x));
                contEntry.rawset("y", Double.valueOf(c.y));
                contEntry.rawset("z", Double.valueOf(c.z));
                contEntry.rawset("kind", c.kind);
                if (c.displayType != null) contEntry.rawset("displayType", c.displayType);
                if (c.customName != null) contEntry.rawset("customName", c.customName);
                contEntry.rawset("capacity", Double.valueOf(c.capacity));
                contEntry.rawset("usedWeight", Double.valueOf(c.usedWeight));
                contEntry.rawset("count", Double.valueOf(c.count));
                containersTable.rawset(Double.valueOf(contIndex++), contEntry);

                for (Map.Entry<String, Integer> entry : c.typeCounts.entrySet()) {
                    String ft = entry.getKey();
                    int qty = entry.getValue();
                    totalCountsByType.put(ft, totalCountsByType.getOrDefault(ft, 0) + qty);

                    KahluaTable src = table();
                    src.rawset("id", c.containerId);
                    src.rawset("count", Double.valueOf(qty));
                    src.rawset("x", Double.valueOf(c.x));
                    src.rawset("y", Double.valueOf(c.y));
                    src.rawset("z", Double.valueOf(c.z));
                    src.rawset("kind", c.kind);
                    if (c.displayType != null) src.rawset("displayType", c.displayType);
                    if (c.customName != null) src.rawset("customName", c.customName);

                    sourcesByType.computeIfAbsent(ft, k -> new ArrayList<>()).add(src);
                }
            } else {
                unloadedCount++;
            }
        }

        List<String> sortedTypes = new ArrayList<>(totalCountsByType.keySet());
        Collections.sort(sortedTypes);

        int rowIndex = 1;
        for (String ft : sortedTypes) {
            KahluaTable row = table();
            row.rawset("fullType", ft);
            row.rawset("count", Double.valueOf(totalCountsByType.get(ft)));
            row.rawset("node", CATEGORY_CACHE.getOrDefault(ft, "other"));

            KahluaTable sources = table();
            List<KahluaTable> srcList = sourcesByType.get(ft);
            if (srcList != null) {
                for (int s = 0; s < srcList.size(); s++) {
                    sources.rawset(Double.valueOf(s + 1), srcList.get(s));
                }
            }
            row.rawset("sources", sources);
            rowsTable.rawset(Double.valueOf(rowIndex++), row);
        }

        countsTable.rawset("loaded", Double.valueOf(loadedCount));
        countsTable.rawset("unloaded", Double.valueOf(unloadedCount));
        countsTable.rawset("private", Double.valueOf(0));
        countsTable.rawset("missing", Double.valueOf(0));
        countsTable.rawset("limited", Double.valueOf(0));
        countsTable.rawset("items", Double.valueOf(totalItems));
        countsTable.rawset("containers", Double.valueOf(state.containers.size()));
        countsTable.rawset("totalCapacity", Double.valueOf(totalCapacity));
        countsTable.rawset("usedWeight", Double.valueOf(totalUsedWeight));
        countsTable.rawset("fullCount", Double.valueOf(fullCount));
        countsTable.rawset("fullContainers", fullContainersList);

        result.rawset("state", "READY");
        result.rawset("rows", rowsTable);
        result.rawset("counts", countsTable);
        result.rawset("containers", containersTable);
        result.rawset("revision", Double.valueOf(state.revision));
        return result;
    }
}
