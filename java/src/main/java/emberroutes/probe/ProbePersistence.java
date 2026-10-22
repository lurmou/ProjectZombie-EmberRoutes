package emberroutes.probe;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.file.Path;
import java.util.*;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.InventoryContainer;
import zombie.iso.IsoWorld;
import zombie.world.moddata.GlobalModData;

/** Only publishes into the current world's normal save. Never calls player file/DB save APIs. */
final class ProbePersistence {
    private static final String KEY = "EmberRoutes/NpcCheckpoint/v1";
    private static KahluaTable verifiedRecords;
    private static long revision,verifiedRevision=-1;
    private static Map<String,String> verifiedIds=Map.of();
    private final String slot;
    ProbePersistence(String slot) { this.slot = slot; }

    static ProbeBaseline.Check runtimeBaseline() throws IOException {
        // Current ZomboidFileSystem.init sets base to ./ and workdir to ./media.
        // IsoPlayer.CodeSource can instead be pzopt/aot/pzopt.jar; never hash it as the game JAR.
        var base = ZomboidFileSystem.instance.base.canonicalFile;
        if (base == null) throw new IOException("GAME_BASE_UNAVAILABLE");
        return ProbeBaseline.check(base.toPath(), BuildInfo.GAME_SHA256);
    }

    private static KahluaTable records() {
        KahluaTable root = GlobalModData.instance.getOrCreate("EmberRoutes/NpcCheckpoints/v2");
        Object legacy=root.rawget("snapshot")==null ? GlobalModData.instance.getOrCreate(KEY).rawget("record") : null;
        return migrateRecords(root,legacy,LuaManager.platform);
    }
    // Table/version contract is testable in the installed VM without initializing the world.
    static KahluaTable migrateRecords(KahluaTable root,Object legacy,se.krka.kahlua.vm.Platform platform) {
        Object value = root.rawget("snapshot");
        if (value == null) {
            KahluaTable snapshot = platform.newTable();
            KahluaTable records = platform.newTable();
            if (legacy != null) records.rawset("legacy", legacy);
            snapshot.rawset("format", 2.0); snapshot.rawset("records", records);
            root.rawset("snapshot", snapshot); // Publish migration once, never consult v1 again.
            return records;
        }
        if (!(value instanceof KahluaTable snapshot) || !Double.valueOf(2).equals(snapshot.rawget("format"))
                || !(snapshot.rawget("records") instanceof KahluaTable))
            throw new IllegalStateException("NPC_STORE_FORMAT_UNSUPPORTED");
        return (KahluaTable)snapshot.rawget("records");
    }
    static List<String> slots() {
        List<String> result = new ArrayList<>();
        var iterator = records().iterator();
        while (iterator.advance()) {
            if (!(iterator.getKey() instanceof String key)) throw new IllegalStateException("INVALID_NPC_SLOT");
            result.add(key);
        }
        Collections.sort(result);
        return result;
    }
    static void verifyStore() throws IOException {
        KahluaTable current=records();
        if (current==verifiedRecords && revision==verifiedRevision) return;
        var ownership=new CheckpointOwnership();
        Map<String,String> identities=new HashMap<>();
        for (String slot:slots()) {
            var saved=new ProbePersistence(slot);
            if (!saved.state().equals("LIVE")) continue;
            var data=saved.read(); ownership.accept(slot,data); identities.put(slot,data.npcId());
        }
        verifiedIds=Map.copyOf(identities);
        verifiedRecords=current; verifiedRevision=revision;
    }
    static String savedId(String slot) { return verifiedIds.get(slot); }
    static void invalidateVerification() { verifiedRecords=null; verifiedRevision=-1; verifiedIds=Map.of(); }
    private static String world() {
        return Path.of(ZomboidFileSystem.instance.getCurrentSaveDir()).toAbsolutePath().normalize().toString();
    }
    String state() throws IOException {
        Object value = records().rawget(slot);
        if (value == null) return "EMPTY";
        if (!(value instanceof KahluaTable record)) throw new IOException("INVALID_RECORD");
        Object state = record.rawget("state");
        if (!(state instanceof String text) || !Set.of("LIVE", "EMPTY", "BLOCKED").contains(text))
            throw new IOException("INVALID_RECORD_STATE");
        return text;
    }
    void empty() { publish("EMPTY", List.of(), null); }
    void block(String reason) { publish("BLOCKED", List.of(), reason); }
    void write(ProbeCheckpoint.Data data) throws IOException {
        publish("LIVE", ProbeCheckpoint.split(ProbeCheckpoint.encode(data)), null);
    }
    private void publish(String state, List<String> chunks, String reason) {
        KahluaTable record = LuaManager.platform.newTable();
        record.rawset("state", state);
        if (reason != null) record.rawset("reason", reason.substring(0, Math.min(reason.length(), 512)));
        if (!chunks.isEmpty()) {
            record.rawset("chunks", (double)chunks.size());
            for (int i = 0; i < chunks.size(); i++) record.rawset("c" + i, chunks.get(i));
        }
        // One publication point: no partially replaced record if encoding throws.
        records().rawset(slot, record);
        revision++;
    }
    ProbeCheckpoint.Data read() throws IOException {
        if (!state().equals("LIVE")) throw new IOException("NO_LIVE_CHECKPOINT state=" + state());
        KahluaTable record = (KahluaTable)records().rawget(slot);
        Object value = record.rawget("chunks");
        if (!(value instanceof Double count) || count < 1 || count > ProbeCheckpoint.MAX_CHUNKS || count != Math.floor(count))
            throw new IOException("INVALID_CHUNK_COUNT");
        List<String> chunks = new ArrayList<>();
        for (int i = 0; i < count.intValue(); i++) {
            Object part = record.rawget("c" + i);
            if (!(part instanceof String chunk)) throw new IOException("INVALID_CHUNK");
            chunks.add(chunk);
        }
        return ProbeCheckpoint.decode(ProbeCheckpoint.join(chunks), world(), BuildInfo.GAME_SHA256, IsoWorld.WorldVersion);
    }

    static ProbeCheckpoint.Data capture(ProbeNpc npc, String id, String mode, boolean home, float hx, float hy, float hz)
            throws IOException {
        if (npc.isDead() || npc.getVehicle() != null || npc.isOnFire()) throw new IOException("UNSUPPORTED_BODY_STATE");
        List<ProbeCheckpoint.Item> manifest = inventory(npc);
        Map<String, Integer> equipment = equipment(npc);
        ByteBuffer bytes = ByteBuffer.allocate(ProbeCheckpoint.MAX_NATIVE);
        npc.getModData().rawset("EmberRoutesNpcId", id);
        npc.save(bytes, false);
        if (!manifest.equals(inventory(npc)) || !equipment.equals(equipment(npc)))
            throw new IOException("SAVE_CHANGED_INVENTORY");
        byte[] nativeBytes = Arrays.copyOf(bytes.array(), bytes.position());
        return new ProbeCheckpoint.Data(world(), BuildInfo.GAME_SHA256, IsoWorld.WorldVersion, id,
                npc.getX(), npc.getY(), npc.getZ(), mode, home, hx, hy, hz, manifest, equipment, nativeBytes);
    }

    static void load(ProbeNpc npc, ProbeCheckpoint.Data data) throws IOException {
        npc.getInventory().clear();
        npc.getWornItems().clear(); npc.getAttachedItems().clear();
        npc.setPrimaryHandItem(null); npc.setSecondaryHandItem(null);
        ByteBuffer bytes = ByteBuffer.wrap(data.nativeBytes());
        npc.load(bytes, data.worldVersion(), false);
        if (bytes.hasRemaining() || npc.isDead() || npc.getVehicle() != null || npc.isOnFire()
                || !data.npcId().equals(npc.getModData().rawget("EmberRoutesNpcId")))
            throw new IOException("NATIVE_BODY_MISMATCH");
        if (!inventory(npc).equals(data.items())) throw new IOException("INVENTORY_IDENTITY_MISMATCH");
        Map<Integer, InventoryItem> items = new HashMap<>();
        index(npc.getInventory(), items, 0);
        for (var entry : data.equipment().entrySet()) {
            if (entry.getKey().startsWith("attached:"))
                npc.getAttachedItems().setItem(entry.getKey().substring(9), items.get(entry.getValue()));
        }
        if (!equipment(npc).equals(data.equipment())) throw new IOException("EQUIPMENT_IDENTITY_MISMATCH");
        // Native file loads may apply the real player's map offset. The envelope stores absolute world coordinates.
        npc.setNpc(true); npc.setGhostMode(false); npc.setGodMod(false); npc.setInvisible(false);
        npc.setNoDamage(false); npc.setCollidable(true);
        npc.stopProbe();
    }

    static List<ProbeCheckpoint.Item> inventory(IsoPlayer npc) throws IOException {
        List<ProbeCheckpoint.Item> list = new ArrayList<>();
        walk(npc.getInventory(), 0, 0, new HashSet<>(), list);
        list.sort(Comparator.comparingInt(ProbeCheckpoint.Item::id));
        return List.copyOf(list);
    }
    private static void walk(ItemContainer bag, int parent, int depth, Set<Integer> seen,
                             List<ProbeCheckpoint.Item> out) throws IOException {
        if (depth > 16) throw new IOException("INVENTORY_TOO_DEEP");
        for (InventoryItem item : bag.getItems()) {
            if (item.getID() == 0 || !seen.add(item.getID()) || out.size() >= ProbeCheckpoint.MAX_ITEMS)
                throw new IOException("INVALID_INVENTORY_IDENTITY");
            out.add(new ProbeCheckpoint.Item(item.getID(), parent, item.getFullType(), item.getCondition()));
            if (item instanceof InventoryContainer container) walk(container.getInventory(), item.getID(), depth + 1, seen, out);
        }
    }
    private static void index(ItemContainer bag, Map<Integer, InventoryItem> out, int depth) throws IOException {
        if (depth > 16) throw new IOException("INVENTORY_TOO_DEEP");
        for (InventoryItem item : bag.getItems()) {
            out.put(item.getID(), item);
            if (item instanceof InventoryContainer container) index(container.getInventory(), out, depth + 1);
        }
    }
    private static Map<String, Integer> equipment(IsoPlayer npc) {
        Map<String, Integer> equipment = new TreeMap<>();
        if (npc.getPrimaryHandItem() != null) equipment.put("primary", npc.getPrimaryHandItem().getID());
        if (npc.getSecondaryHandItem() != null) equipment.put("secondary", npc.getSecondaryHandItem().getID());
        for (int i = 0; i < npc.getWornItems().size(); i++) {
            var worn = npc.getWornItems().get(i);
            equipment.put("worn:" + worn.getLocation(), worn.getItem().getID());
        }
        for (int i = 0; i < npc.getAttachedItems().size(); i++) {
            var attached = npc.getAttachedItems().get(i);
            equipment.put("attached:" + attached.getLocation(), attached.getItem().getID());
        }
        return Map.copyOf(equipment);
    }
}
