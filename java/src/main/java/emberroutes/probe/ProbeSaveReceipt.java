package emberroutes.probe;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.*;
import se.krka.kahlua.vm.KahluaTable;
import zombie.GameWindow;
import zombie.Lua.LuaManager;

/** Read-only check of our records in the pinned engine's global_mod_data.bin.
 * No replacement save format, GlobalModData.load(), filesystem write or durability claim.
 */
final class ProbeSaveReceipt {
    static final String WORK="EmberRoutes/Work/v1", NPC="EmberRoutes/NpcCheckpoints/v2";
    private static final int MAX_BYTES=64*1024*1024, MAX_ENTRIES=1_000_000;
    private final Path file;
    private final Map<String,Object> expected;
    ProbeSaveReceipt(Path file,KahluaTable work,KahluaTable npc) throws IOException {
        this.file=file.toAbsolutePath().normalize();
        expected=Map.of(WORK,snapshot(work),NPC,snapshot(npc));
    }
    boolean matches(Path current,KahluaTable work,KahluaTable npc) throws IOException {
        if (!file.equals(current.toAbsolutePath().normalize())
                || !expected.get(WORK).equals(snapshot(work)) || !expected.get(NPC).equals(snapshot(npc))) return false;
        try (var channel=FileChannel.open(file,StandardOpenOption.READ)) {
            long size=channel.size();
            if (size<8 || size>MAX_BYTES) throw new IOException("SAVE_RECEIPT_SIZE_LIMIT");
            ByteBuffer bytes=ByteBuffer.allocate((int)size);
            while (bytes.hasRemaining()) if (channel.read(bytes)<0) throw new IOException("SAVE_RECEIPT_TRUNCATED");
            bytes.flip();
            return matches(bytes);
        }
    }
    boolean matches(ByteBuffer bytes) throws IOException {
        try {
            // GlobalModData.save/load, installed 42.21.0: version, table count,
            // then (block size, GameWindow string key, native table payload).
            if (bytes.getInt()!=249) throw new IOException("SAVE_RECEIPT_VERSION_UNSUPPORTED");
            int count=bytes.getInt();
            if (count<0 || count>32768) throw new IOException("SAVE_RECEIPT_TABLE_LIMIT");
            Set<String> found=new HashSet<>();
            for (int i=0;i<count;i++) {
                int size=bytes.getInt();
                if (size<2 || size>bytes.remaining()) throw new IOException("SAVE_RECEIPT_BAD_BLOCK");
                int end=bytes.position()+size;
                ByteBuffer block=bytes.slice(); block.limit(size);
                String key=GameWindow.ReadString(block);
                if (expected.containsKey(key)) {
                    if (!found.add(key)) throw new IOException("SAVE_RECEIPT_DUPLICATE");
                    KahluaTable table=LuaManager.platform.newTable();
                    table.load(block,249);
                    if (block.hasRemaining() || !expected.get(key).equals(snapshot(table))) return false;
                }
                bytes.position(end);
            }
            return !bytes.hasRemaining() && found.size()==expected.size();
        } catch (RuntimeException error) { throw new IOException("SAVE_RECEIPT_INVALID",error); }
    }
    private static Object snapshot(KahluaTable table) throws IOException {
        return snapshot(table,new IdentityHashMap<>(),new int[]{0},0);
    }
    private static Object snapshot(Object value,IdentityHashMap<KahluaTable,Boolean> path,int[] count,int depth) throws IOException {
        if (value instanceof KahluaTable table) {
            if (depth>32 || path.put(table,true)!=null) throw new IOException("SAVE_RECEIPT_TABLE_CYCLE");
            Map<Object,Object> copy=new HashMap<>();
            var iterator=table.iterator();
            while (iterator.advance()) {
                if (++count[0]>MAX_ENTRIES) throw new IOException("SAVE_RECEIPT_ENTRY_LIMIT");
                Object key=iterator.getKey();
                if (!(key instanceof String || key instanceof Double)) throw new IOException("SAVE_RECEIPT_KEY_INVALID");
                copy.put(key,snapshot(iterator.getValue(),path,count,depth+1));
            }
            path.remove(table); return copy;
        }
        if (value instanceof String || value instanceof Boolean || value instanceof Double number && Double.isFinite(number)) return value;
        throw new IOException("SAVE_RECEIPT_NON_SCALAR");
    }
}
