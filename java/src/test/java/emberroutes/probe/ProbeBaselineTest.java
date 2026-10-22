package emberroutes.probe;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/** Reads the actual installed files. Does not fake IsoPlayer or start the game engine. */
public final class ProbeBaselineTest {
    public static void main(String[] args) throws Exception {
        Path root = Path.of(args[0]);
        String expected = args[1];
        var baseline = ProbeBaseline.check(root, expected);
        if (!baseline.matches()) throw new AssertionError("installed game differs from pinned baseline");
        if (!baseline.gameJar().toRealPath().equals(root.resolve("projectzomboid.jar").toRealPath()))
            throw new AssertionError("wrong game jar selected");
        if (ProbeBaseline.check(root, "0".repeat(64)).matches()) throw new AssertionError("changed hash must block");
        Path override = root.resolve("pzopt/aot/pzopt.jar");
        if (Files.isRegularFile(override) && Files.isSameFile(baseline.gameJar(), override))
            throw new AssertionError("class override must never substitute for installation baseline");
        try {
            ProbeBaseline.check(root.resolve("pzopt/aot"), expected);
            throw new AssertionError("missing game jar must not silently select pzopt.jar");
        } catch (IOException expectedMissing) { /* no arbitrary fallback */ }
        if (args.length > 2 && args[2].equals("--class-origin")) {
            // Resolve class metadata with the real override-first classpath, without initializing IsoPlayer.
            Class<?> player = Class.forName("zombie.characters.IsoPlayer", false, ClassLoader.getSystemClassLoader());
            Path actualSource = Path.of(player.getProtectionDomain().getCodeSource().getLocation().toURI());
            if (!Files.isSameFile(actualSource, override)) throw new AssertionError("expected pzopt class origin: " + actualSource);
            if (Files.isSameFile(actualSource, baseline.gameJar())) throw new AssertionError("class source confused with installation jar");
            System.out.println("PASS real override-first class loading: IsoPlayerCodeSource=" + actualSource
                    + "; installation baseline remains accepted; IsoPlayer NOT initialized");
        }
        System.out.println("PASS installed-file baseline regression: exact game JAR, strict hash, no override fallback");
        System.out.println("gameJar=" + baseline.gameJar() + " sha256=" + baseline.hash()
                + " overridePresent=" + Files.isRegularFile(override) + "; PZ engine NOT RUN");
    }
}
