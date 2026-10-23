package emberroutes.probe;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.file.*;
import java.util.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import zombie.GameWindow;

/** Installed native table codec and actual global-moddata envelope, without a world. */
public final class ProbeSaveReceiptTest {
    private static int count;
    static void check(boolean value,String message) { count++; if (!value) throw new AssertionError(message); }
    static KahluaTable table() { return J2SEPlatform.getInstance().newTable(); }
    static ByteBuffer envelope(Map<String,KahluaTable> tables) throws Exception {
        ByteBuffer b=ByteBuffer.allocate(1024*1024); b.putInt(249).putInt(tables.size());
        for (var entry:tables.entrySet()) {
            int offset=b.position(); b.putInt(0); int start=b.position();
            GameWindow.WriteString(b,entry.getKey()); entry.getValue().save(b);
            b.putInt(offset,b.position()-start);
        }
        return b.flip();
    }
    public static void main(String[] args) throws Exception {
        KahluaTable work=table(),npc=table(),receipt=table(),claims=table();
        receipt.rawset("id","current-save"); receipt.rawset("state","CAPTURED");
        work.rawset("executionSave",receipt); work.rawset("claims",claims);
        claims.rawset(92.0,"original-job"); npc.rawset("c0","original-native-bytes");
        KahluaTable jobs=table(),byId=table(),job=table(),payload=table(),publicWork=table(),orders=table(),order=table();
        jobs.rawset("format",1.0); jobs.rawset("byId",byId); byId.rawset("job-1",job);
        job.rawset("id","job-1"); job.rawset("revision",2.0); job.rawset("payload",payload);
        payload.rawset("orderId","order-1"); payload.rawset("materialId",92.0);
        work.rawset("taskJobs",jobs); work.rawset("publicWork",publicWork);
        publicWork.rawset("orders",orders); orders.rawset("order-1",order);
        order.rawset("jobId","job-1"); order.rawset("npcId","npc-a");
        Path directory=Files.createTempDirectory("ember-save-receipt-"),file=directory.resolve("global_mod_data.bin");
        try {
            var proof=new ProbeSaveReceipt(file,work,npc);
            var tables=new LinkedHashMap<String,KahluaTable>();
            tables.put("other-mod",table()); tables.put(ProbeSaveReceipt.NPC,npc); tables.put(ProbeSaveReceipt.WORK,work);
            ByteBuffer current=envelope(tables);
            check(proof.matches(current.duplicate()),"own records match independently of table order/other mods");
            payload.rawset("materialId",93.0);
            check(!proof.matches(envelope(tables)),"nested independent Job original ID change is detected");
            payload.rawset("materialId",92.0); order.rawset("jobId","job-2");
            check(!proof.matches(envelope(tables)),"public Order claim-link change is detected");
            order.rawset("jobId","job-1");
            check(proof.matches(envelope(tables)),"nested Job and public Order survive installed codec round trip");
            Files.write(file,Arrays.copyOf(current.array(),current.limit()));
            check(proof.matches(file,work,npc),"normal save read-only file verification");
            check(!proof.matches(directory.resolve("another-world.bin"),work,npc),"world path cannot borrow receipt");
            receipt.rawset("id","old-save");
            check(!proof.matches(envelope(tables)),"old save nonce rejected");
            check(!proof.matches(file,work,npc),"live ledger changes after capture rejected");
            receipt.rawset("id","current-save"); claims.rawset(92.0,"other-job");
            check(!proof.matches(envelope(tables)),"same nonce with changed original ownership rejected");
            claims.rawset(92.0,"original-job");
            tables.remove(ProbeSaveReceipt.NPC);
            check(!proof.matches(envelope(tables)),"missing checkpoint table rejected");
            try { proof.matches(ByteBuffer.wrap(new byte[3])); throw new AssertionError("truncation accepted"); }
            catch (IOException expected) { count++; }
            ByteBuffer future=envelope(tables); future.putInt(0,250);
            try { proof.matches(future); throw new AssertionError("future format accepted"); }
            catch (IOException expected) { count++; }
            work.rawset("cycle",work);
            try { new ProbeSaveReceipt(file,work,npc); throw new AssertionError("cycle accepted"); }
            catch (IOException expected) { count++; }
        } finally { Files.deleteIfExists(file); Files.deleteIfExists(directory); }
        System.out.println("PASS "+count+" installed-codec save receipt checks; engine save/crash NOT RUN");
    }
}
