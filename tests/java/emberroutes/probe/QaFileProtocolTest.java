package emberroutes.probe;

import java.nio.file.*;
import java.nio.file.attribute.FileTime;
import java.util.UUID;
import org.json.JSONObject;

/** Real temporary files, no game startup or native world. */
public final class QaFileProtocolTest {
    private static int assertions;
    private static long stamp = System.currentTimeMillis();
    private static final String HASH = "A".repeat(64);
    private static void check(boolean value, String message) {
        assertions++; if (!value) throw new AssertionError(message);
    }
    private static void write(Path root, String file, String text) throws Exception {
        Path path = root.resolve(file); Files.writeString(path, text);
        Files.setLastModifiedTime(path, FileTime.fromMillis(++stamp));
    }
    private static JSONObject session(String id) {
        return new JSONObject().put("format", 1).put("runId", id).put("version", "test")
                .put("jarSha256", HASH).put("sourceHash", HASH).put("saveName", "ERQA_Test").put("autoStart", true);
    }
    private static JSONObject command(String id, long seq, String op) {
        return new JSONObject().put("format", 1).put("runId", id).put("seq", seq).put("op", op).put("caseId", "smoke");
    }
    @FunctionalInterface interface Checked { void run() throws Exception; }
    private static void rejects(Checked action, String label) throws Exception {
        try { action.run(); throw new AssertionError("accepted " + label); }
        catch (IllegalArgumentException | org.json.JSONException expected) { assertions++; }
    }
    public static void main(String[] args) throws Exception {
        Path root = Files.createTempDirectory("emberroutes-qa-protocol-");
        String id = UUID.randomUUID().toString();
        write(root, "session.json", session(id).toString());
        QaFileProtocol mailbox = new QaFileProtocol(root, "test", HASH);
        check(mailbox.poll() == null, "missing command does nothing");
        write(root, "command.json", command(id, 1, "run").toString());
        check(mailbox.poll().seq() == 1, "first request accepted");
        check(mailbox.poll() == null, "unchanged file does not replay");
        write(root, "command.json", command(id, 1, "run").toString());
        check(mailbox.poll() == null, "rewritten duplicate does not replay");
        write(root, "command.json", command(id, 1, "cancel").toString());
        rejects(mailbox::poll, "conflicting same-sequence operation");
        write(root, "command.json", command(UUID.randomUUID().toString(), 2, "run").toString());
        rejects(mailbox::poll, "different run identity");
        write(root, "command.json", command(id, 2, "executeLua").toString());
        rejects(mailbox::poll, "unregistered operation");
        write(root, "command.json", command(id, 2, "run").put("caseId", "unknown").toString());
        rejects(mailbox::poll, "unregistered scene");
        write(root, "command.json", command(id, 2, "run").put("path", "outside").toString());
        rejects(mailbox::poll, "extra path field");
        write(root, "command.json", command(id, 2, "run").put("seq", "2").toString());
        rejects(mailbox::poll, "string sequence");
        write(root, "command.json", command(id, 2, "run").put("format", 1.5).toString());
        rejects(mailbox::poll, "fractional format");
        write(root, "command.json", "{"); rejects(mailbox::poll, "partial JSON");
        write(root, "command.json", " ".repeat(8193)); rejects(mailbox::poll, "oversize input");
        write(root, "command.json", command(id, 2, "run").toString());
        check(mailbox.poll().seq() == 2, "rejected input does not consume the next sequence");
        mailbox.report("PASS", "COMPLETE", 2, new JSONObject().put("native", true));
        JSONObject result = new JSONObject(Files.readString(root.resolve("result.json")));
        check(result.getString("runId").equals(id) && result.getLong("seq") == 2
                && result.getString("jarSha256").equals(HASH) && result.getJSONObject("evidence").getBoolean("native"), "result retains identity and evidence");
        check(!Files.exists(root.resolve("result.json.tmp")), "atomic publication leaves no pending file");
        rejects(() -> mailbox.report("SUCCESS", "COMPLETE", 2, new JSONObject()), "unknown terminal spelling");
        write(root, "command.json", command(id, 1, "run").toString()); rejects(mailbox::poll, "older command");
        rejects(() -> new QaFileProtocol(root, "wrong-version", HASH), "mismatched version");
        rejects(() -> new QaFileProtocol(root, "test", "B".repeat(64)), "mismatched JAR");
        write(root, "session.json", session(id).put("saveName", "PersonalSave").toString());
        rejects(() -> new QaFileProtocol(root, "test", HASH), "non-QA world name");
        System.out.println("PASS " + assertions + " QA mailbox file/identity/replay/result checks; game NOT RUN");
    }
}
