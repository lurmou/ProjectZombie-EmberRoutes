#!/bin/sh
# One-click entry point for the nav harness ("mini-Zomboid test build").
#
# Compiles the production tree + harness together with javac, then runs
# every harness section (world, pathfinder, motion, haul loop under
# lua5.4) and prints a PASS/FAIL summary.
#
#   tests/navharness/run.sh [all|world|pathfinder|motion|haul ...]
#   tests/navharness/run.sh motion        # only the motion driver
#
# Exit code: 0 only when every selected section passes; any FAIL (or a
# failed compile / missing prerequisite) exits non-zero.
#
# Prerequisites (see tests/navharness/README.md):
#   - JDK 25: $JDK_BIN/java, or $JAVA_HOME/bin/java, or ~/workspace/jdk-25/bin/java
#   - Game jars: $GAME_ROOT/projectzomboid.jar + ZombieBuddy.jar
#     (default ~/workspace/game-root; jars stay OUT of the repo)
#   - lua5.4 on PATH (haul loop only)
#
# BuildInfo stub: the production tree references emberroutes.probe.BuildInfo,
# which build-probe.ps1 normally generates. This script generates the same
# stub from the same template fields (VERSION from version.txt, PREFIX
# derived from it, GAME_SHA256 = sha256 of projectzomboid.jar) into a
# scratch directory under /tmp on every run. It is never written into
# java/src or Contents/, and never committed.
set -u
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

# ---- locate JDK 25 ------------------------------------------------------
if [ -n "${JDK_BIN:-}" ]; then
    JAVA="$JDK_BIN/java"
    JAVAC="$JDK_BIN/javac"
elif [ -n "${JAVA_HOME:-}" ]; then
    JAVA="$JAVA_HOME/bin/java"
    JAVAC="$JAVA_HOME/bin/javac"
else
    JAVA="$HOME/workspace/jdk-25/bin/java"
    JAVAC="$HOME/workspace/jdk-25/bin/javac"
fi
if [ ! -x "$JAVA" ] || [ ! -x "$JAVAC" ]; then
    echo "NAVHARNESS: JDK 25 not found (looked for $JAVA). Set JDK_BIN or JAVA_HOME." >&2
    exit 2
fi
JAVA_VER=$("$JAVA" -version 2>&1 | head -1)
case "$JAVA_VER" in
    *'"25'*) ;;
    *) echo "NAVHARNESS: expected JDK 25, got: $JAVA_VER" >&2; exit 2 ;;
esac

# ---- locate game jars ---------------------------------------------------
GAME_ROOT=${GAME_ROOT:-"$HOME/workspace/game-root"}
if [ ! -f "$GAME_ROOT/projectzomboid.jar" ] || [ ! -f "$GAME_ROOT/ZombieBuddy.jar" ]; then
    echo "NAVHARNESS: game jars missing in $GAME_ROOT (need projectzomboid.jar + ZombieBuddy.jar)." >&2
    echo "NAVHARNESS: jars are classpath-only and must never be copied into the repo." >&2
    exit 2
fi

# ---- lua5.4 (haul loop) ---------------------------------------------------
if ! command -v lua5.4 >/dev/null 2>&1; then
    echo "NAVHARNESS: lua5.4 not found on PATH (needed by the haul-loop section)." >&2
    exit 2
fi

# ---- build dirs (scratch, under /tmp) ------------------------------------
BUILD_DIR=${NAVHARNESS_BUILD_DIR:-"/tmp/navharness-build"}
CLASSES="$BUILD_DIR/classes"
GENERATED="$BUILD_DIR/generated/emberroutes/probe"
mkdir -p "$CLASSES" "$GENERATED"

# ---- BuildInfo stub, same template fields as tools/build-probe.ps1 -------
VERSION=$(cat "$ROOT/version.txt")
GAME_SHA=$(sha256sum "$GAME_ROOT/projectzomboid.jar" | cut -d' ' -f1)
cat > "$GENERATED/BuildInfo.java" <<EOF
package emberroutes.probe;

public final class BuildInfo {

    public static final String VERSION = "$VERSION";

    public static final String PREFIX = "[EmberRoutes v" + VERSION + "]";

    public static final String GAME_SHA256 = "$GAME_SHA";

    private BuildInfo() {}

}
EOF

# ---- compile: production tree + generated stub + harness -----------------
# Production sources: everything under java/src/main/java.
# Harness sources: the navharness test package (SyntheticWorld,
# SyntheticWorldTest, PathfinderScenarios, MotionDriver, NavHarness).
echo "NAVHARNESS: compiling production + harness (JDK 25, version $VERSION)..."
# shellcheck disable=SC2046
"$JAVAC" -cp "$GAME_ROOT/*" -d "$CLASSES" \
    $(find "$ROOT/java/src/main/java" -name '*.java') \
    "$GENERATED/BuildInfo.java" \
    "$ROOT/tests/java/emberroutes/probe/navharness/"*.java
COMPILE_STATUS=$?
if [ "$COMPILE_STATUS" -ne 0 ]; then
    echo "NAVHARNESS: compile FAILED (exit $COMPILE_STATUS)." >&2
    exit "$COMPILE_STATUS"
fi
echo "NAVHARNESS: compile OK."

# ---- run -----------------------------------------------------------------
exec "$JAVA" \
    -Dnavharness.root="$ROOT" \
    -Dnavharness.gameroot="$GAME_ROOT" \
    -Dnavharness.classes="$CLASSES" \
    -cp "$CLASSES:$GAME_ROOT/*" \
    emberroutes.probe.navharness.NavHarness "$@"
