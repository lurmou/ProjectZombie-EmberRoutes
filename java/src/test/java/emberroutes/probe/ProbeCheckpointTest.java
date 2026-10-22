package emberroutes.probe;

import java.io.IOException;
import java.util.*;

/** Corruption and identity tests; does not pretend to exercise native PZ serialization. */
public final class ProbeCheckpointTest {
    private static int assertions;
    private static final String HASH = "a".repeat(64), WORLD = "C:/test/save";
    private static final String ID = "12345678-1234-1234-1234-123456789abc";
    private static ProbeCheckpoint.Data data(byte[] bytes, List<ProbeCheckpoint.Item> items, Map<String, Integer> equipment) {
        return new ProbeCheckpoint.Data(WORLD, HASH, 249, ID, 12.5f, 18.5f, 1.02f,
                "FOLLOW", true, 10.5f, 17.5f, 1, items, equipment, bytes);
    }
    public static void main(String[] args) throws Exception {
        var items = List.of(new ProbeCheckpoint.Item(12, 0, "Base.Bag", 90),
                new ProbeCheckpoint.Item(22, 12, "Base.Pencil", 5));
        byte[] bytes = new byte[128 * 1024]; new Random(7).nextBytes(bytes);
        String encoded = ProbeCheckpoint.encode(data(bytes, items, Map.of("attached:Back", 12)));
        var restored = ProbeCheckpoint.decode(encoded, WORLD, HASH, 249);
        check(restored.npcId().equals(ID) && restored.world().equals(WORLD), "world and stable UUID survive");
        check(restored.mode().equals("FOLLOW") && restored.homeZ() == 1 && restored.z() == 1.02f,
                "intent, home and native fractional Z preserved");
        check(restored.items().equals(items) && restored.equipment().get("attached:Back") == 12,
                "nested item parent, condition and attachment ID preserved");
        check(Arrays.equals(restored.nativeBytes(), bytes), "large binary payload round-trips exactly");
        check(encoded.length() > 32767, "fixture exceeds native signed-short string limit");
        var chunks = ProbeCheckpoint.split(encoded);
        check(chunks.stream().allMatch(part -> part.length() <= 16000), "all strings fit native signed-short length");
        check(ProbeCheckpoint.join(chunks).equals(encoded), "chunked world-table payload is exact");
        rejects(() -> ProbeCheckpoint.join(List.of()), "missing chunks refused");
        rejects(() -> ProbeCheckpoint.join(List.of("short", "tail")), "short interior chunk refused");
        rejects(() -> ProbeCheckpoint.join(List.of("x".repeat(16001))), "oversized table string refused");
        List<String> swapped = new ArrayList<>(chunks); Collections.swap(swapped, 0, 1);
        rejects(() -> ProbeCheckpoint.decode(ProbeCheckpoint.join(swapped), WORLD, HASH, 249), "reordered complete chunks fail checksum");
        List<String> missing = chunks.subList(0, chunks.size() - 1);
        rejects(() -> ProbeCheckpoint.decode(ProbeCheckpoint.join(missing), WORLD, HASH, 249), "missing final chunk cannot restore prefix");
        rejects(() -> ProbeCheckpoint.decode(encoded, WORLD + "other", HASH, 249), "foreign world refused");
        rejects(() -> ProbeCheckpoint.decode(encoded, WORLD, "b".repeat(64), 249), "changed JAR refused");
        rejects(() -> ProbeCheckpoint.decode(encoded, WORLD, HASH, 250), "changed world format refused");
        byte[] corrupt = Base64.getDecoder().decode(encoded); corrupt[24] ^= 1;
        String badMetadata = Base64.getEncoder().encodeToString(corrupt);
        rejects(() -> ProbeCheckpoint.decode(badMetadata, WORLD, HASH, 249),
                "metadata corruption fails checksum");
        corrupt = Base64.getDecoder().decode(encoded); corrupt[corrupt.length - 64] ^= 1;
        String badBody = Base64.getEncoder().encodeToString(corrupt);
        rejects(() -> ProbeCheckpoint.decode(badBody, WORLD, HASH, 249), "native corruption fails checksum");
        rejects(() -> ProbeCheckpoint.decode(encoded.substring(0, encoded.length() - 12), WORLD, HASH, 249), "truncation refused");
        rejects(() -> ProbeCheckpoint.decode("!!", WORLD, HASH, 249), "invalid base64 refused");
        rejects(() -> ProbeCheckpoint.decode("", WORLD, HASH, 249), "empty envelope refused");
        rejects(() -> ProbeCheckpoint.encode(data(new byte[0], items, Map.of())), "empty body refused");
        rejects(() -> ProbeCheckpoint.encode(data(new byte[ProbeCheckpoint.MAX_NATIVE + 1], items, Map.of())), "oversized body refused");
        rejects(() -> ProbeCheckpoint.encode(data(bytes, List.of(items.get(0), items.get(0)), Map.of())), "duplicate item ID refused");
        rejects(() -> ProbeCheckpoint.encode(data(bytes, List.of(items.get(1)), Map.of())), "orphan nested item refused");
        rejects(() -> ProbeCheckpoint.encode(data(bytes, List.of(new ProbeCheckpoint.Item(12, 12, "Base.Bag", 2)), Map.of())), "self container refused");
        rejects(() -> ProbeCheckpoint.encode(data(bytes, List.of(new ProbeCheckpoint.Item(12, 22, "Base.Bag", 2),
                new ProbeCheckpoint.Item(22, 12, "Base.Bag", 2)), Map.of())), "container cycle refused");
        rejects(() -> ProbeCheckpoint.encode(data(bytes, items, Map.of("primary", 99))), "equipment cannot point outside inventory");
        rejects(() -> ProbeCheckpoint.encode(data(bytes, items, Map.of("unknown", 12))), "unknown equipment slot refused");
        var invalid = new ProbeCheckpoint.Data(WORLD, HASH, 249, ID, Float.NaN, 0, 0, "HOLD", false,
                0, 0, 0, items, Map.of(), bytes);
        rejects(() -> ProbeCheckpoint.encode(invalid), "NaN coordinate refused");
        var returning = new ProbeCheckpoint.Data(WORLD, HASH, 249, ID, 0, 0, 0, "RETURNING", false,
                0, 0, 0, items, Map.of(), bytes);
        rejects(() -> ProbeCheckpoint.encode(returning), "return without home refused");
        ProbeRestoreGate gate = new ProbeRestoreGate();
        check(gate.canRestore(false) && gate.canSpawn(false, false), "new world permits first creation");
        check(!gate.canSpawn(false, true), "saved checkpoint prevents alternate spawn");
        check(!gate.canRestore(true) && !gate.canSpawn(true, false), "existing body prevents duplicate ownership");
        gate.attached();
        check(!gate.canRestore(false) && !gate.canSpawn(false, false), "consumed record cannot revive a disappeared body");
        gate.lost();
        check(gate.state() == ProbeRestoreGate.State.LOST && !gate.canRestore(false), "unexpected loss blocks old replay");
        gate.removed();
        check(!gate.canRestore(false) && gate.canSpawn(false, true), "explicit removal allows replacement but not old restore");
        gate.lost();
        check(gate.state() == ProbeRestoreGate.State.REMOVED, "late cleanup does not undo explicit deletion");
        gate.reset();
        check(gate.canRestore(false) && !gate.canSpawn(false, true), "new world resets consume gate but respects record");
        check(!ProbeRestoreGate.mayReleaseDisposedWorld(false, true, true), "empty live cell is not disposal permission");
        check(!ProbeRestoreGate.mayReleaseDisposedWorld(true, false, true), "world replacement alone cannot discard owned objects");
        check(!ProbeRestoreGate.mayReleaseDisposedWorld(true, true, false), "chunk workers must have completed disposal");
        check(ProbeRestoreGate.mayReleaseDisposedWorld(true, true, true), "only complete engine disposal releases stale session");
        System.out.println("PASS " + assertions + " checkpoint/gate assertions; native PZ serialization NOT RUN");
    }
    private interface Action { void run() throws IOException; }
    private static void rejects(Action action, String message) throws IOException {
        try { action.run(); } catch (IOException expected) { check(true, message); return; }
        throw new AssertionError(message);
    }
    private static void check(boolean ok, String message) { assertions++; if (!ok) throw new AssertionError(message); }
}
