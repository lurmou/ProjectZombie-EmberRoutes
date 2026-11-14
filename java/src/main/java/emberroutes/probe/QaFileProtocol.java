package emberroutes.probe;

import java.io.IOException;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.time.Instant;
import java.util.*;
import org.json.JSONObject;

/** Bounded, process-local QA mailbox. Contains no engine or body operations. */
final class QaFileProtocol {
    record Command(long seq, String op, String caseId) {}
    private static final Set<String> OPS = Set.of("run", "status", "cancel", "quit");
    private static final Set<String> CASES = Set.of("smoke", "actions");
    private static final Set<String> STATES = Set.of("MENU_READY", "LOADING", "PREPARING", "RUNNING",
            "STOPPING", "PASS", "FAIL", "BLOCKED", "CANCELLED");
    private static final Set<String> TERMINAL = Set.of("PASS", "FAIL", "BLOCKED", "CANCELLED");
    private final Path root;
    private final JSONObject session;
    private long stamp = -1, size = -1, sequence;
    private Command last;
    private JSONObject latest;

    QaFileProtocol(Path root, String version, String actualJarHash) throws IOException {
        this.root = root.toAbsolutePath().normalize();
        session = read(this.root.resolve("session.json"));
        exactFields(session, Set.of("format", "runId", "version", "jarSha256", "sourceHash", "saveName", "autoStart"));
        if (!(session.get("format") instanceof Number f && f.doubleValue() == 1) || !version.equals(session.getString("version"))
                || !actualJarHash.equalsIgnoreCase(session.getString("jarSha256"))
                || !session.getString("sourceHash").matches("[A-Fa-f0-9]{64}")
                || !session.getString("saveName").matches("ERQA_[A-Za-z0-9_-]{1,64}"))
            throw new IllegalArgumentException("QA_SESSION_MISMATCH");
        UUID.fromString(session.getString("runId"));
        if (!(session.get("autoStart") instanceof Boolean)) throw new IllegalArgumentException("QA_SESSION_AUTOSTART_INVALID");
        latest = envelope(0).put("state", "MENU_READY").put("phase", "BRIDGE_READY");
        write("status.json", latest);
    }

    JSONObject session() {
        return new JSONObject(session.toString()).put("cacheDir", root.resolve("cache").toString());
    }

    Command menuRun() throws IOException {
        Command pending = poll();
        if (pending != null && pending.op.equals("run")) return pending;
        last = new Command(++sequence, "run", "smoke");
        return last;
    }

    Command poll() throws IOException {
        Path file = root.resolve("command.json");
        if (!Files.isRegularFile(file)) return null;
        BasicFileAttributes info = Files.readAttributes(file, BasicFileAttributes.class);
        long modified = info.lastModifiedTime().toMillis();
        if (modified == stamp && info.size() == size) return null;
        stamp = modified; size = info.size();
        JSONObject input = read(file);
        exactFields(input, Set.of("format", "runId", "seq", "op", "caseId"));
        if (!(input.get("seq") instanceof Number numeric)) throw new IllegalArgumentException("QA_SEQUENCE_TYPE");
        double number = numeric.doubleValue();
        if (!(input.get("format") instanceof Number f && f.doubleValue() == 1) || !session.getString("runId").equals(input.getString("runId"))
                || !Double.isFinite(number) || number < 1 || number > 9007199254740991d || number != Math.floor(number))
            throw new IllegalArgumentException("QA_COMMAND_IDENTITY_INVALID");
        Command command = new Command((long)number, input.getString("op"), input.getString("caseId"));
        if (!OPS.contains(command.op) || !CASES.contains(command.caseId))
            throw new IllegalArgumentException("QA_COMMAND_UNSUPPORTED");
        if (command.seq < sequence) throw new IllegalArgumentException("QA_COMMAND_STALE");
        if (command.seq == sequence) {
            if (!command.equals(last)) throw new IllegalArgumentException("QA_COMMAND_SEQUENCE_CONFLICT");
            return null;
        }
        sequence = command.seq; last = command;
        return command;
    }

    void rejected(String reason) throws IOException {
        latest.put("commandError", reason);
        write("status.json", latest);
    }

    void report(String state, String phase, long seq, JSONObject evidence) throws IOException {
        if (!STATES.contains(state) || phase == null || phase.length() > 128 || seq < 0 || seq > sequence)
            throw new IllegalArgumentException("QA_REPORT_INVALID");
        latest = envelope(seq).put("state", state).put("phase", phase).put("evidence", evidence);
        write("status.json", latest);
        if (TERMINAL.contains(state)) write("result.json", latest);
    }

    private JSONObject envelope(long seq) {
        return new JSONObject().put("format", 1).put("runId", session.getString("runId"))
                .put("version", session.getString("version")).put("jarSha256", session.getString("jarSha256"))
                .put("sourceHash", session.getString("sourceHash")).put("seq", seq);
    }

    private void write(String name, JSONObject data) throws IOException {
        data.put("updatedAt", Instant.now().toString());
        Path temporary = root.resolve(name + ".tmp");
        Files.writeString(temporary, data.toString(2));
        Files.move(temporary, root.resolve(name), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
    }

    private static JSONObject read(Path path) throws IOException {
        byte[] data;
        try (var input = Files.newInputStream(path)) { data = input.readNBytes(8193); }
        if (data.length > 8192) throw new IllegalArgumentException("QA_FILE_TOO_LARGE");
        String text = new String(data, java.nio.charset.StandardCharsets.UTF_8);
        return new JSONObject(text.startsWith("\uFEFF") ? text.substring(1) : text);
    }

    private static void exactFields(JSONObject object, Set<String> fields) {
        if (!object.keySet().equals(fields)) throw new IllegalArgumentException("QA_FIELDS_INVALID");
    }
}
