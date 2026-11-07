package emberroutes.probe;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.scripting.objects.ItemTag;

/**
 * AE2-style layered warehouse index.
 *
 * <p>Layers, from the game outward:
 * <pre>
 *   L1  Lua read path        - only ever reads the published front snapshot
 *   L2  front snapshot       - immutable KahluaTable, atomically swapped on change
 *   L3  Aggregate/KeyCounter - incremental -old/+new over changed keys only
 *   L4  ContainerContribution- resident shell, slot-level fingerprint diff
 *   L5  ItemContainer        - the only place item rows are actually read
 * </pre>
 *
 * <p>A container change no longer recompiles the whole settlement: the
 * aggregate subtracts the old contribution and adds the new one, touching only
 * the fullType keys that actually changed. The KahluaTable itself is still
 * rebuilt on change (Lua consumers hold it directly), but that is a plain
 * serialization of already-computed values, not a re-aggregation.
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
        if (ft != null) CATEGORY_CACHE.put(ft, node);
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

    // ---------------------------------------------------------------- L4 shell

    /** Resident shell: one instance per container, refreshed in place. */
    static final class ContainerContribution {
        String containerId;
        WarehouseFingerprint fingerprint;
        int count;
        Map<String, Integer> typeCounts = Collections.emptyMap();
        Map<String, Integer> tagCounts = Collections.emptyMap();
        double capacity, usedWeight;
        String kind, displayType, customName;
        int x, y, z;
        String status;

        ContainerContribution(String containerId) {
            this.containerId = containerId;
        }

        void assign(WarehouseFingerprint fp, int count, Map<String, Integer> types,
                    Map<String, Integer> tags, double capacity, double usedWeight,
                    Desc d, String status) {
            this.fingerprint = fp;
            this.count = count;
            this.typeCounts = types;
            this.tagCounts = tags;
            this.capacity = capacity;
            this.usedWeight = usedWeight;
            this.kind = d.kind;
            this.displayType = d.displayType;
            this.customName = d.customName;
            this.x = d.x; this.y = d.y; this.z = d.z;
            this.status = status;
        }

        /** Descriptor-only refresh (labels or position moved, items untouched). */
        void describe(Desc d) {
            this.capacity = d.cap > 0 ? d.cap : this.capacity;
            this.usedWeight = d.used > 0 ? d.used : this.usedWeight;
            this.kind = d.kind;
            this.displayType = d.displayType;
            this.customName = d.customName;
            this.x = d.x; this.y = d.y; this.z = d.z;
        }
    }

    // ------------------------------------------------------------- L3 aggregate

    static final class Source {
        final String id, kind, displayType, customName;
        final int x, y, z, count;

        Source(ContainerContribution c, int count) {
            this.id = c.containerId;
            this.kind = c.kind;
            this.displayType = c.displayType;
            this.customName = c.customName;
            this.x = c.x; this.y = c.y; this.z = c.z;
            this.count = count;
        }
    }

    /** Incremental KeyCounter. Only keys present in a changed contribution move. */
    static final class Aggregate {
        final TreeMap<String, Integer> typeCounts = new TreeMap<>();
        final TreeMap<String, List<Source>> sourcesByType = new TreeMap<>();
        final TreeMap<String, Integer> tagCounts = new TreeMap<>();
        int loaded, unloaded, totalItems, fullCount;
        double totalCapacity, totalUsedWeight;

        private static void bump(TreeMap<String, Integer> map, String key, int delta) {
            Integer old = map.get(key);
            int next = (old == null ? 0 : old) + delta;
            if (next <= 0) map.remove(key);
            else map.put(key, next);
        }

        void subtract(ContainerContribution c) {
            if ("LOADED".equals(c.status)) {
                loaded--;
                totalItems -= c.count;
                totalCapacity -= c.capacity;
                totalUsedWeight -= c.usedWeight;
                if (c.capacity > 0 && c.usedWeight >= c.capacity * 0.9) fullCount--;
                for (Map.Entry<String, Integer> e : c.typeCounts.entrySet()) {
                    bump(typeCounts, e.getKey(), -e.getValue());
                    List<Source> list = sourcesByType.get(e.getKey());
                    if (list != null) {
                        list.removeIf(s -> c.containerId.equals(s.id));
                        if (list.isEmpty()) sourcesByType.remove(e.getKey());
                    }
                }
                for (Map.Entry<String, Integer> e : c.tagCounts.entrySet()) {
                    bump(tagCounts, e.getKey(), -e.getValue());
                }
            } else {
                unloaded--;
            }
        }

        void add(ContainerContribution c) {
            if ("LOADED".equals(c.status)) {
                loaded++;
                totalItems += c.count;
                totalCapacity += c.capacity;
                totalUsedWeight += c.usedWeight;
                if (c.capacity > 0 && c.usedWeight >= c.capacity * 0.9) fullCount++;
                for (Map.Entry<String, Integer> e : c.typeCounts.entrySet()) {
                    bump(typeCounts, e.getKey(), e.getValue());
                    sourcesByType.computeIfAbsent(e.getKey(), k -> new ArrayList<>())
                        .add(new Source(c, e.getValue()));
                }
                for (Map.Entry<String, Integer> e : c.tagCounts.entrySet()) {
                    bump(tagCounts, e.getKey(), e.getValue());
                }
            } else {
                unloaded++;
            }
        }
    }

    // ------------------------------------------------------------- L2 / state

    static final class SettlementState {
        final String settlementId;
        final Map<String, ContainerContribution> containers = new ConcurrentHashMap<>();
        final Aggregate aggregate = new Aggregate();
        /** Immutable published snapshot; Lua only ever sees this reference. */
        volatile KahluaTable front = null;
        long revision = 0;
        // URGENT / SLOWER: a container event resets the deadline, otherwise the
        // verification period backs off until the settlement is truly asleep.
        long nextDueAt = 0;
        long quietMs = 200;

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
        if (settlementId != null) SETTLEMENTS.remove(settlementId);
    }

    /** O(1) read path: no item rows, no aggregation, no allocation. */
    public static double typeCount(String settlementId, String fullType) {
        if (fullType == null) return 0;
        SettlementState s = SETTLEMENTS.get(settlementId);
        if (s == null) return 0;
        Integer n = s.aggregate.typeCounts.get(fullType);
        return n == null ? 0 : n.doubleValue();
    }

    public static boolean hasType(String settlementId, String fullType) {
        return typeCount(settlementId, fullType) > 0;
    }

    /**
     * URGENT exits immediately; a quiet settlement backs off 200ms -> 5s so
     * the Lua dispatcher stops paying O(containers) verify calls.
     */
    public static boolean tickDue(String settlementId, boolean urgent) {
        SettlementState s = SETTLEMENTS.get(settlementId);
        if (s == null) return true;
        long now = System.currentTimeMillis();
        if (urgent) {
            s.quietMs = 200;
            s.nextDueAt = 0;
        }
        if (now < s.nextDueAt) return false;
        s.quietMs = Math.min(5000, s.quietMs * 2);
        s.nextDueAt = now + s.quietMs;
        return true;
    }

    private static void markUrgent(SettlementState s) {
        s.quietMs = 200;
        s.nextDueAt = 0;
    }

    // ------------------------------------------------------------- descriptor

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

    /** Parsed container descriptor, reused as a resident shell (game thread only). */
    static final class Desc {
        String id;
        ItemContainer container;
        int x, y, z;
        double cap, used;
        String kind, displayType, customName;
    }

    private static final Desc DESC = new Desc();

    private static Desc readDesc(KahluaTable desc) {
        if (desc == null) return null;
        Object rawId = desc.rawget("id");
        if (!(rawId instanceof String cid)) return null;
        Object contObj = desc.rawget("container");
        DESC.id = cid;
        DESC.container = contObj instanceof ItemContainer ic ? ic : null;
        DESC.x = intVal(desc.rawget("x"), 0);
        DESC.y = intVal(desc.rawget("y"), 0);
        DESC.z = intVal(desc.rawget("z"), 0);
        DESC.cap = doubleVal(desc.rawget("capacity"), 0.0);
        DESC.used = doubleVal(desc.rawget("usedWeight"), 0.0);
        DESC.kind = strVal(desc.rawget("kind"), "container");
        DESC.displayType = strVal(desc.rawget("displayType"), null);
        DESC.customName = strVal(desc.rawget("customName"), null);
        return DESC;
    }

    private static boolean sameDescriptor(ContainerContribution a, Desc d) {
        return a.x == d.x && a.y == d.y && a.z == d.z
            && Double.compare(a.capacity, d.cap == 0 ? a.capacity : d.cap) == 0
            && Objects.equals(a.kind, d.kind)
            && Objects.equals(a.displayType, d.displayType)
            && Objects.equals(a.customName, d.customName);
    }

    // ----------------------------------------------------------------- L4 read

    private static ContainerContribution target(SettlementState s, String id) {
        ContainerContribution existing = s.containers.get(id);
        if (existing != null) {
            s.aggregate.subtract(existing);
            return existing;
        }
        ContainerContribution created = new ContainerContribution(id);
        s.containers.put(id, created);
        return created;
    }

    private static void commit(SettlementState s, ContainerContribution c) {
        s.aggregate.add(c);
        markUrgent(s);
    }

    private static ContainerContribution unloaded(SettlementState s, Desc d) {
        ContainerContribution c = target(s, d.id);
        c.assign(null, 0, Collections.emptyMap(), Collections.emptyMap(),
            d.cap, d.used, d, "CONTAINER_UNLOADED");
        commit(s, c);
        return c;
    }

    /** Reads one container into the resident shell. The only place item rows are touched. */
    private static ContainerContribution scanLoaded(SettlementState s, Desc d, WarehouseFingerprint fp) {
        ContainerContribution c = target(s, d.id);
        ArrayList<InventoryItem> items = d.container.getItems();
        Map<String, Integer> counts = new HashMap<>();
        Map<String, Integer> tags = new HashMap<>();
        int eligibleCount = 0;
        if (items != null) {
            int sz = items.size();
            for (int i = 0; i < sz; i++) {
                InventoryItem itm = items.get(i);
                if (itm == null) continue;
                if (!Boolean.TRUE.equals(InventoryReads.eligible(itm))) continue;
                String ft = itm.getFullType();
                if (ft != null) {
                    counts.put(ft, counts.getOrDefault(ft, 0) + 1);
                    eligibleCount++;
                    classifyItem(itm);
                }
                try {
                    Set<ItemTag> itemTags = itm.getTags();
                    if (itemTags != null && tags.size() < 256) {
                        for (ItemTag tag : itemTags) {
                            if (tag == null) continue;
                            String name = tag.toString();
                            if (name != null && !name.isEmpty()) {
                                tags.put(name, tags.getOrDefault(name, 0) + 1);
                            }
                        }
                    }
                } catch (RuntimeException ignored) {}
            }
        }
        double actualCap = d.cap > 0 ? d.cap : (double) d.container.getCapacity();
        double actualUsed = d.used > 0 ? d.used : (double) d.container.getContentsWeight();
        c.assign(fp, eligibleCount, counts, tags, actualCap, actualUsed, d, "LOADED");
        commit(s, c);
        return c;
    }

    private static void removeContainer(SettlementState s, String id) {
        ContainerContribution old = s.containers.remove(id);
        if (old != null) s.aggregate.subtract(old);
        markUrgent(s);
    }

    // --------------------------------------------------------------- L2 publish

    /** Builds the back buffer, then atomically publishes it as the new front. */
    private static KahluaTable publish(SettlementState s) {
        s.revision++;
        KahluaTable back = compileSnapshot(s);
        s.front = back;
        return back;
    }

    private static KahluaTable compileSnapshot(SettlementState s) {
        KahluaTable result = table();
        KahluaTable rowsTable = table();
        KahluaTable countsTable = table();
        KahluaTable containersTable = table();
        KahluaTable fullContainersList = table();
        Aggregate a = s.aggregate;

        int contIndex = 1;
        for (ContainerContribution c : s.containers.values()) {
            if (!"LOADED".equals(c.status)) continue;
            if (c.capacity > 0 && c.usedWeight >= c.capacity * 0.9 && fullContainersList.len() < 8) {
                KahluaTable fc = table();
                fc.rawset("name", c.customName != null ? c.customName : c.kind);
                fc.rawset("x", Double.valueOf(c.x));
                fc.rawset("y", Double.valueOf(c.y));
                fc.rawset("z", Double.valueOf(c.z));
                fc.rawset("capacity", Double.valueOf(c.capacity));
                fc.rawset("used", Double.valueOf(c.usedWeight));
                fullContainersList.rawset(Double.valueOf(fullContainersList.len() + 1), fc);
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
        }

        int rowIndex = 1;
        for (Map.Entry<String, Integer> e : a.typeCounts.entrySet()) {
            String ft = e.getKey();
            KahluaTable row = table();
            row.rawset("fullType", ft);
            row.rawset("count", Double.valueOf(e.getValue()));
            row.rawset("node", CATEGORY_CACHE.getOrDefault(ft, "other"));

            KahluaTable sources = table();
            List<Source> srcList = a.sourcesByType.get(ft);
            if (srcList != null) {
                for (int i = 0; i < srcList.size(); i++) {
                    Source src = srcList.get(i);
                    KahluaTable entry = table();
                    entry.rawset("id", src.id);
                    entry.rawset("count", Double.valueOf(src.count));
                    entry.rawset("x", Double.valueOf(src.x));
                    entry.rawset("y", Double.valueOf(src.y));
                    entry.rawset("z", Double.valueOf(src.z));
                    entry.rawset("kind", src.kind);
                    if (src.displayType != null) entry.rawset("displayType", src.displayType);
                    if (src.customName != null) entry.rawset("customName", src.customName);
                    sources.rawset(Double.valueOf(i + 1), entry);
                }
            }
            row.rawset("sources", sources);
            rowsTable.rawset(Double.valueOf(rowIndex++), row);
        }

        countsTable.rawset("loaded", Double.valueOf(a.loaded));
        countsTable.rawset("unloaded", Double.valueOf(a.unloaded));
        countsTable.rawset("private", Double.valueOf(0));
        countsTable.rawset("missing", Double.valueOf(0));
        countsTable.rawset("limited", Double.valueOf(0));
        countsTable.rawset("items", Double.valueOf(a.totalItems));
        countsTable.rawset("containers", Double.valueOf(s.containers.size()));
        countsTable.rawset("totalCapacity", Double.valueOf(a.totalCapacity));
        countsTable.rawset("usedWeight", Double.valueOf(a.totalUsedWeight));
        countsTable.rawset("fullCount", Double.valueOf(a.fullCount));
        countsTable.rawset("fullContainers", fullContainersList);

        KahluaTable tagsTable = table();
        int tagIndex = 1;
        for (Map.Entry<String, Integer> e : a.tagCounts.entrySet()) {
            KahluaTable tagRow = table();
            tagRow.rawset("tag", e.getKey());
            tagRow.rawset("count", Double.valueOf(e.getValue()));
            tagsTable.rawset(Double.valueOf(tagIndex++), tagRow);
        }

        result.rawset("state", "READY");
        result.rawset("rows", rowsTable);
        result.rawset("counts", countsTable);
        result.rawset("containers", containersTable);
        result.rawset("tags", tagsTable);
        result.rawset("revision", Double.valueOf(s.revision));
        return result;
    }

    // ------------------------------------------------------------ public mounts

    public static KahluaTable scanSettlement(String settlementId, KahluaTable containerList, boolean force) {
        if (settlementId == null || containerList == null) return null;
        SettlementState state = SETTLEMENTS.computeIfAbsent(settlementId, SettlementState::new);
        boolean dirty = force || state.front == null;
        Set<String> activeIds = new HashSet<>();

        var iter = containerList.iterator();
        while (iter.advance()) {
            if (!(iter.getValue() instanceof KahluaTable descTable)) continue;
            Desc d = readDesc(descTable);
            if (d == null) continue;
            activeIds.add(d.id);
            if (d.container == null) {
                ContainerContribution prev = state.containers.get(d.id);
                if (prev == null || !"CONTAINER_UNLOADED".equals(prev.status)) {
                    unloaded(state, d);
                    dirty = true;
                }
                continue;
            }
            WarehouseFingerprint fp = WarehouseFingerprint.of(d.container);
            ContainerContribution existing = state.containers.get(d.id);
            if (!dirty && !force && existing != null && "LOADED".equals(existing.status)
                    && fp != null && fp.matches(existing.fingerprint)) {
                continue;
            }
            scanLoaded(state, d, fp);
            dirty = true;
        }

        List<String> removed = new ArrayList<>();
        for (String id : state.containers.keySet()) {
            if (!activeIds.contains(id)) removed.add(id);
        }
        for (String id : removed) {
            removeContainer(state, id);
            dirty = true;
        }
        if (!dirty && state.front != null) return state.front;
        return publish(state);
    }

    /** Mounts the container set once; known containers keep their contribution. */
    public static KahluaTable mountSettlement(String settlementId, KahluaTable containerList) {
        if (settlementId == null || containerList == null) return null;
        SettlementState state = SETTLEMENTS.computeIfAbsent(settlementId, SettlementState::new);
        boolean dirty = state.front == null;
        Set<String> activeIds = new HashSet<>();

        var iter = containerList.iterator();
        while (iter.advance()) {
            if (!(iter.getValue() instanceof KahluaTable descTable)) continue;
            Desc d = readDesc(descTable);
            if (d == null) continue;
            activeIds.add(d.id);
            ContainerContribution existing = state.containers.get(d.id);
            if (existing == null) {
                if (d.container == null) unloaded(state, d);
                else scanLoaded(state, d, WarehouseFingerprint.of(d.container));
                dirty = true;
            } else if (!sameDescriptor(existing, d)) {
                state.aggregate.subtract(existing);
                existing.describe(d);
                state.aggregate.add(existing);
                dirty = true;
            }
        }
        List<String> removed = new ArrayList<>();
        for (String id : state.containers.keySet()) {
            if (!activeIds.contains(id)) removed.add(id);
        }
        for (String id : removed) {
            removeContainer(state, id);
            dirty = true;
        }
        return dirty ? publish(state) : state.front;
    }

    /** Refreshes exactly one container (AE2 ExternalInventoryCache.update). */
    public static KahluaTable applyContainer(String settlementId, KahluaTable descriptor) {
        if (settlementId == null || descriptor == null) return null;
        Desc d = readDesc(descriptor);
        if (d == null) return null;
        SettlementState state = SETTLEMENTS.computeIfAbsent(settlementId, SettlementState::new);
        ContainerContribution existing = state.containers.get(d.id);

        if (d.container == null) {
            if (existing != null && "CONTAINER_UNLOADED".equals(existing.status) && sameDescriptor(existing, d)) {
                return state.front;
            }
            unloaded(state, d);
            return publish(state);
        }

        WarehouseFingerprint fp = WarehouseFingerprint.of(d.container);
        if (existing != null && "LOADED".equals(existing.status) && fp != null
                && fp.matches(existing.fingerprint) && sameDescriptor(existing, d)) {
            // Zero-allocation fast path: same slots, same descriptor, same front.
            return state.front;
        }
        scanLoaded(state, d, fp);
        return publish(state);
    }

    /** Removes one container from the aggregate (AE2 unmount). */
    public static KahluaTable unmountContainer(String settlementId, String containerId) {
        SettlementState state = SETTLEMENTS.get(settlementId);
        if (state == null || containerId == null) return null;
        if (!state.containers.containsKey(containerId)) return state.front;
        removeContainer(state, containerId);
        return publish(state);
    }
}
