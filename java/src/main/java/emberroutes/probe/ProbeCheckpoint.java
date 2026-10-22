package emberroutes.probe;

import java.io.*;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.*;

/** Engine-free, bounded envelope. The checksum covers metadata as well as native bytes. */
public final class ProbeCheckpoint {
    public static final int MAX_NATIVE = 4 * 1024 * 1024;
    public static final int MAX_ITEMS = 4096;
    public static final int CHUNK_SIZE = 16000, MAX_CHUNKS = 440;
    private static final int MAX_ENVELOPE = MAX_NATIVE + 1024 * 1024;
    private static final int MAGIC = 0x45524E50, FORMAT = 1;
    public record Item(int id, int parent, String type, int condition) { }
    public record Data(String world, String gameHash, int worldVersion, String npcId,
                       float x, float y, float z, String mode, boolean hasHome,
                       float homeX, float homeY, float homeZ, List<Item> items,
                       Map<String, Integer> equipment, byte[] nativeBytes) { }

    private ProbeCheckpoint() { }

    /** GameWindow.StringUTF stores a signed short byte length. ASCII chunks stay below that limit. */
    public static List<String> split(String encoded) throws IOException {
        if (encoded.isEmpty() || encoded.length() > (long)CHUNK_SIZE * MAX_CHUNKS) throw new IOException("INVALID_CHUNK_COUNT");
        List<String> chunks = new ArrayList<>();
        for (int i = 0; i < encoded.length(); i += CHUNK_SIZE)
            chunks.add(encoded.substring(i, Math.min(encoded.length(), i + CHUNK_SIZE)));
        return List.copyOf(chunks);
    }

    public static String join(List<String> chunks) throws IOException {
        if (chunks.isEmpty() || chunks.size() > MAX_CHUNKS) throw new IOException("INVALID_CHUNK_COUNT");
        StringBuilder encoded = new StringBuilder();
        for (int i = 0; i < chunks.size(); i++) {
            String chunk = chunks.get(i);
            if (chunk == null || chunk.isEmpty() || chunk.length() > CHUNK_SIZE
                    || (i < chunks.size() - 1 && chunk.length() != CHUNK_SIZE)) throw new IOException("INVALID_CHUNK");
            encoded.append(chunk);
        }
        return encoded.toString();
    }

    public static String encode(Data data) throws IOException {
        validate(data);
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (DataOutputStream out = new DataOutputStream(buffer)) {
            out.writeInt(MAGIC); out.writeInt(FORMAT);
            out.writeUTF(data.world); out.writeUTF(data.gameHash); out.writeInt(data.worldVersion);
            out.writeUTF(data.npcId); out.writeFloat(data.x); out.writeFloat(data.y); out.writeFloat(data.z);
            out.writeUTF(data.mode); out.writeBoolean(data.hasHome);
            out.writeFloat(data.homeX); out.writeFloat(data.homeY); out.writeFloat(data.homeZ);
            out.writeInt(data.items.size());
            for (Item item : data.items) {
                out.writeInt(item.id); out.writeInt(item.parent); out.writeUTF(item.type); out.writeInt(item.condition);
            }
            out.writeInt(data.equipment.size());
            for (var item : new TreeMap<>(data.equipment).entrySet()) {
                out.writeUTF(item.getKey()); out.writeInt(item.getValue());
            }
            out.writeInt(data.nativeBytes.length); out.write(data.nativeBytes);
        }
        if (buffer.size() > MAX_ENVELOPE) throw new IOException("ENVELOPE_TOO_LARGE");
        byte[] content = buffer.toByteArray();
        buffer.write(digest(content));
        return Base64.getEncoder().encodeToString(buffer.toByteArray());
    }

    public static Data decode(String encoded, String world, String hash, int worldVersion) throws IOException {
        if (encoded == null || encoded.length() > (MAX_ENVELOPE + 32L) * 4 / 3 + 4)
            throw new IOException("ENVELOPE_TOO_LARGE");
        final byte[] bytes;
        try { bytes = Base64.getDecoder().decode(encoded); }
        catch (IllegalArgumentException error) { throw new IOException("INVALID_BASE64", error); }
        if (bytes.length < 40 || bytes.length > MAX_ENVELOPE + 32) throw new IOException("INVALID_LENGTH");
        byte[] content = Arrays.copyOf(bytes, bytes.length - 32);
        if (!MessageDigest.isEqual(digest(content), Arrays.copyOfRange(bytes, content.length, bytes.length)))
            throw new IOException("CHECKSUM_MISMATCH");
        try (DataInputStream in = new DataInputStream(new ByteArrayInputStream(content))) {
            if (in.readInt() != MAGIC || in.readInt() != FORMAT) throw new IOException("FORMAT_MISMATCH");
            String savedWorld = in.readUTF(), savedHash = in.readUTF();
            int savedVersion = in.readInt();
            if (!world.equals(savedWorld) || !hash.equals(savedHash) || worldVersion != savedVersion)
                throw new IOException("BASELINE_OR_WORLD_MISMATCH");
            String id = in.readUTF();
            float x = in.readFloat(), y = in.readFloat(), z = in.readFloat();
            String mode = in.readUTF(); boolean home = in.readBoolean();
            float hx = in.readFloat(), hy = in.readFloat(), hz = in.readFloat();
            int count = bounded(in.readInt(), MAX_ITEMS);
            List<Item> items = new ArrayList<>();
            for (int i = 0; i < count; i++) items.add(new Item(in.readInt(), in.readInt(), in.readUTF(), in.readInt()));
            count = bounded(in.readInt(), 256);
            Map<String, Integer> equipment = new TreeMap<>();
            for (int i = 0; i < count; i++) {
                if (equipment.put(in.readUTF(), in.readInt()) != null) throw new IOException("DUPLICATE_EQUIPMENT");
            }
            int size = bounded(in.readInt(), MAX_NATIVE);
            if (size == 0 || size != in.available()) throw new IOException("NATIVE_LENGTH_MISMATCH");
            Data data = new Data(savedWorld, savedHash, savedVersion, id, x, y, z, mode, home, hx, hy, hz,
                    List.copyOf(items), Map.copyOf(equipment), in.readNBytes(size));
            validate(data);
            return data;
        }
    }

    private static int bounded(int size, int max) throws IOException {
        if (size < 0 || size > max) throw new IOException("COUNT_OUT_OF_BOUNDS");
        return size;
    }

    private static void point(float x, float y, float z) throws IOException {
        if (!Float.isFinite(x) || !Float.isFinite(y) || !Float.isFinite(z)
                || Math.abs(x) > 10_000_000 || Math.abs(y) > 10_000_000 || z < -32 || z > 31)
            throw new IOException("INVALID_COORDINATES");
    }

    private static void validate(Data data) throws IOException {
        try { UUID.fromString(data.npcId); }
        catch (IllegalArgumentException error) { throw new IOException("INVALID_NPC_ID", error); }
        if (data.world.isEmpty() || data.world.length() > 2048 || data.gameHash.length() != 64
                || data.worldVersion != 249) throw new IOException("INVALID_BASELINE");
        point(data.x, data.y, data.z);
        if (!Set.of("HOLD", "FOLLOW", "RETURNING").contains(data.mode)) throw new IOException("INVALID_ORDER");
        if (data.hasHome) {
            point(data.homeX, data.homeY, data.homeZ);
            if (data.homeZ != Math.floor(data.homeZ)) throw new IOException("INVALID_HOME_FLOOR");
        } else if (data.mode.equals("RETURNING")) throw new IOException("HOME_REQUIRED");
        bounded(data.items.size(), MAX_ITEMS); bounded(data.equipment.size(), 256);
        if (data.nativeBytes.length == 0 || data.nativeBytes.length > MAX_NATIVE) throw new IOException("NATIVE_TOO_LARGE");
        Map<Integer, Item> byId = new HashMap<>();
        for (Item item : data.items) {
            if (item.id == 0 || item.type.isEmpty() || item.type.length() > 512 || item.id == item.parent
                    || byId.put(item.id, item) != null) throw new IOException("INVALID_ITEM_IDENTITY");
        }
        for (Item item : data.items) {
            int parent = item.parent, depth = 0;
            while (parent != 0) {
                Item ancestor = byId.get(parent);
                if (ancestor == null || ++depth > 16) throw new IOException("INVALID_ITEM_TREE");
                parent = ancestor.parent;
            }
        }
        for (var item : data.equipment.entrySet()) {
            String slot = item.getKey();
            if ((!slot.equals("primary") && !slot.equals("secondary") && !slot.startsWith("worn:")
                    && !slot.startsWith("attached:")) || slot.length() > 512 || !byId.containsKey(item.getValue()))
                throw new IOException("INVALID_EQUIPMENT");
        }
    }

    private static byte[] digest(byte[] bytes) {
        try { return MessageDigest.getInstance("SHA-256").digest(bytes); }
        catch (NoSuchAlgorithmException error) { throw new AssertionError(error); }
    }
}
