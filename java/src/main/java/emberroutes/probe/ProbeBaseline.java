package emberroutes.probe;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

/** Installation identity is independent of the source of an overridden game class. */
public final class ProbeBaseline {
    public record Check(Path gameJar, String hash, boolean matches) { }
    private ProbeBaseline() { }

    public static Check check(Path installationRoot, String expectedHash) throws IOException {
        Path jar = installationRoot.toAbsolutePath().normalize().resolve("projectzomboid.jar");
        if (!Files.isRegularFile(jar)) throw new IOException("GAME_JAR_UNAVAILABLE " + jar);
        final MessageDigest digest;
        try { digest = MessageDigest.getInstance("SHA-256"); }
        catch (NoSuchAlgorithmException error) { throw new AssertionError(error); }
        try (var input = Files.newInputStream(jar)) {
            byte[] buffer = new byte[65536]; int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        String hash = HexFormat.of().withUpperCase().formatHex(digest.digest());
        return new Check(jar, hash, hash.equalsIgnoreCase(expectedHash));
    }
}
