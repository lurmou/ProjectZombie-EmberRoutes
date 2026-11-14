package emberroutes.probe;

import java.nio.file.*;
import java.security.MessageDigest;
import java.util.HexFormat;
import org.json.JSONObject;
import se.krka.kahlua.vm.*;

/** Explicit QA launch only. This bridge transports data, never executes commands. */
public final class QaBridge {
    private static QaFileProtocol files;
    private static Thread owner;
    private QaBridge() {}

    static boolean openConfigured() {
        String directory = System.getProperty("emberroutes.qa.root");
        if (directory == null) return false;
        try {
            Path jar = Path.of(ProbeRuntime.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            String hash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(jar)));
            files = new QaFileProtocol(Path.of(directory), BuildInfo.VERSION, hash);
            owner = null; // Bind at the first Lua callback, after extension loading.
            return true;
        } catch (Exception error) { throw new IllegalStateException("QA_START_REFUSED", error); }
    }

    public static double clockMs() { return System.nanoTime() / 1_000_000.0; }

    public static KahluaTable session() { check(); return table(files.session()); }

    public static KahluaTable menuRun() {
        check();
        try { return command(files.menuRun()); }
        catch (java.io.IOException error) { throw new IllegalStateException("QA_COMMAND_READ_FAILED", error); }
    }

    public static void reject(String reason) {
        check();
        try { files.rejected(reason); }
        catch (java.io.IOException error) { throw new IllegalStateException("QA_STATUS_WRITE_FAILED", error); }
    }

    public static KahluaTable poll() {
        check();
        try { return command(files.poll()); }
        catch (Exception error) {
            try { files.rejected(error.getMessage()); }
            catch (Exception output) { throw new IllegalStateException("QA_STATUS_WRITE_FAILED", output); }
            return null;
        }
    }

    public static void report(String state, String phase, double seq, KahluaTable evidence) {
        check();
        if (!Double.isFinite(seq) || seq != Math.floor(seq)) throw new IllegalArgumentException("QA_SEQUENCE_INVALID");
        try { files.report(state, phase, (long)seq, object(evidence, 0, new int[1])); }
        catch (java.io.IOException error) { throw new IllegalStateException("QA_RESULT_WRITE_FAILED", error); }
    }

    private static void check() {
        if (files == null) throw new IllegalStateException("QA_NOT_CONFIGURED");
        if (owner == null) owner = Thread.currentThread();
        if (Thread.currentThread() != owner) throw new IllegalStateException("QA_THREAD_REQUIRED");
    }

    private static KahluaTable command(QaFileProtocol.Command command) {
        if (command == null) return null;
        KahluaTable value = KernelValues.table();
        value.rawset("seq", (double)command.seq()); value.rawset("op", command.op()); value.rawset("caseId", command.caseId());
        return value;
    }

    private static KahluaTable table(JSONObject object) {
        KahluaTable value = KernelValues.table();
        for (String key : object.keySet()) {
            Object item = object.get(key);
            value.rawset(key, item instanceof Number n ? n.doubleValue() : item);
        }
        return value;
    }

    private static JSONObject object(KahluaTable value, int depth, int[] budget) {
        if (depth > 6) throw new IllegalArgumentException("QA_EVIDENCE_DEPTH");
        JSONObject result = new JSONObject();
        if (value == null) return result;
        KahluaTableIterator iterator = value.iterator();
        while (iterator.advance()) {
            if (++budget[0] > 512) throw new IllegalArgumentException("QA_EVIDENCE_LIMIT");
            Object key = iterator.getKey(), item = iterator.getValue();
            if (!(key instanceof String)) throw new IllegalArgumentException("QA_EVIDENCE_KEY");
            if (item instanceof KahluaTable child) item = object(child, depth + 1, budget);
            else if (!(item instanceof Boolean) && !(item instanceof String s && s.length() <= 4096)
                    && !(item instanceof Number n && Double.isFinite(n.doubleValue())))
                throw new IllegalArgumentException("QA_EVIDENCE_VALUE");
            result.put((String)key, item);
        }
        return result;
    }
}
