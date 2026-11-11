package emberroutes.probe.navharness;

import java.io.File;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Single entry point for the nav harness ("mini-Zomboid test build").
 *
 * <p>Runs every harness section in its own subprocess (each section builds
 * its own headless world, so isolation also keeps the global
 * {@code IsoWorld.instance} clean between sections) and prints a
 * PASS/FAIL summary. Exit code: 0 only when every selected section
 * passes; any FAIL (or a section that crashes / cannot start) exits
 * non-zero.
 *
 * <p>Sections:
 * <ul>
 *   <li>{@code world} — {@link SyntheticWorldTest}: 8x8 room + gapped wall
 *       + doors + window + fences + glass + upper floor.</li>
 *   <li>{@code pathfinder} — {@link PathfinderScenarios}: 6 PASS, 3 SKIP
 *       (broken glass / door-key / positive stairs are unbuildable
 *       headless).</li>
 *   <li>{@code motion} — {@link MotionDriver}: A REACHED 1.93s, B
 *       PATH_ENDED 1.88s, C REACHED 4.43s, D BLOCKED.</li>
 *   <li>{@code haul} — the Lua haul loop under lua5.4
 *       ({@code tests/navharness/run-haul-loop.sh}): 27 checks, 4
 *       scenarios (S1–S4).</li>
 * </ul>
 *
 * <p>Usage (normally via {@code tests/navharness/run.sh}, which compiles
 * production code + harness and passes the properties below):
 * {@code java -Dnavharness.root=<repo-root> -Dnavharness.gameroot=<game-root>
 *   -Dnavharness.classes=<compiled-classes-dir>
 *   emberroutes.probe.navharness.NavHarness [all|world|pathfinder|motion|haul ...]}
 * No arguments means {@code all}. Properties default to: root = current
 * working directory, gameroot = {@code $GAME_ROOT} or
 * {@code ~/workspace/game-root}, classes = the directory / jar this class
 * was loaded from.
 */
public final class NavHarness {

    private static final Map<String, String> JAVA_SECTIONS = Map.of(
            "world", "emberroutes.probe.navharness.SyntheticWorldTest",
            "pathfinder", "emberroutes.probe.navharness.PathfinderScenarios",
            "motion", "emberroutes.probe.navharness.MotionDriver");

    private static final List<String> ALL_SECTIONS = List.of("world", "pathfinder", "motion", "haul");

    private NavHarness() {}

    public static void main(String[] args) throws Exception {
        List<String> sections = new ArrayList<>();
        for (String arg : args) {
            if ("all".equals(arg)) {
                sections.addAll(ALL_SECTIONS);
            } else if (ALL_SECTIONS.contains(arg)) {
                if (!sections.contains(arg)) sections.add(arg);
            } else {
                System.out.println("NAVHARNESS: unknown section '" + arg + "', known: all "
                        + String.join(" ", ALL_SECTIONS));
                System.exit(2);
            }
        }
        if (sections.isEmpty()) sections.addAll(ALL_SECTIONS);

        String root = System.getProperty("navharness.root", System.getProperty("user.dir"));
        String gameRoot = System.getProperty("navharness.gameroot", defaultGameRoot());
        String classes = System.getProperty("navharness.classes", defaultClassesDir());
        String javaBin = System.getProperty("java.home") + File.separator + "bin"
                + File.separator + "java";

        System.out.println("NAVHARNESS: root=" + root + " gameroot=" + gameRoot);
        System.out.println("NAVHARNESS: sections=" + String.join(",", sections));

        Map<String, Boolean> results = new LinkedHashMap<>();
        for (String section : sections) {
            System.out.println("======================================================================");
            System.out.println("NAVHARNESS section: " + section);
            System.out.println("======================================================================");
            boolean ok = runSection(section, root, gameRoot, classes, javaBin);
            results.put(section, ok);
            System.out.println("NAVHARNESS section " + section + ": " + (ok ? "PASS" : "FAIL"));
        }

        System.out.println("======================================================================");
        System.out.println("NAVHARNESS SUMMARY");
        boolean allOk = true;
        for (Map.Entry<String, Boolean> e : results.entrySet()) {
            System.out.println("  " + String.format("%-10s", e.getKey()) + " " + (e.getValue() ? "PASS" : "FAIL"));
            allOk &= e.getValue();
        }
        if (allOk) {
            System.out.println("NAVHARNESS PASS -- all selected sections green");
        } else {
            System.out.println("NAVHARNESS FAIL -- at least one section failed (see above)");
            System.exit(1);
        }
    }

    private static boolean runSection(String section, String root, String gameRoot,
                                      String classes, String javaBin) {
        try {
            ProcessBuilder pb;
            if ("haul".equals(section)) {
                pb = new ProcessBuilder("sh",
                        root + "/tests/navharness/run-haul-loop.sh", root);
            } else {
                String cp = classes + File.pathSeparator + gameRoot + File.separator + "*";
                pb = new ProcessBuilder(javaBin, "-ea", "-cp", cp, JAVA_SECTIONS.get(section));
            }
            pb.inheritIO();
            pb.directory(new File(root));
            Process p = pb.start();
            int exit = p.waitFor();
            return exit == 0;
        } catch (Exception e) {
            System.out.println("NAVHARNESS section " + section + " could not run: " + e);
            return false;
        }
    }

    private static String defaultGameRoot() {
        String env = System.getenv("GAME_ROOT");
        if (env != null && !env.isBlank()) return env;
        return System.getProperty("user.home") + "/workspace/game-root";
    }

    private static String defaultClassesDir() {
        try {
            File codeSource = new File(NavHarness.class.getProtectionDomain()
                    .getCodeSource().getLocation().toURI());
            return codeSource.isFile() ? codeSource.getParent() : codeSource.getPath();
        } catch (Exception e) {
            return ".";
        }
    }
}
