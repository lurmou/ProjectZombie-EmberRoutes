#!/bin/sh
# ProbeBridgeSurfaceTest — PZ 补丁后第一步：先跑桥面测试，再跑别的。
# 与 tools/build-probe.ps1 的桥面步骤等价（Windows 用 build-probe.ps1；本脚本供 Linux/macOS）。
# 用法（仓库根目录）：sh tools/run-bridge-surface.sh
# 环境：GAME_ROOT 未设时默认 $HOME/workspace/game-root（须含 projectzomboid.jar 与 ZombieBuddy.jar）；
#       JDK 未设时依次用 $HOME/workspace/jdk-25/bin、PATH 上的 javac/java（须为 Java 25）。
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GAME_ROOT=${GAME_ROOT:-"$HOME/workspace/game-root"}
JDK_BIN=${JDK_BIN:-"$HOME/workspace/jdk-25/bin"}
if [ -x "$JDK_BIN/javac" ]; then
    JAVAC="$JDK_BIN/javac"; JAVA="$JDK_BIN/java"
else
    JAVAC=javac; JAVA=java
fi

for jar in projectzomboid.jar ZombieBuddy.jar; do
    [ -f "$GAME_ROOT/$jar" ] || { echo "missing dependency: $GAME_ROOT/$jar" >&2; exit 1; }
done

# 依赖哈希只提示、不拦截：PZ 补丁后哈希变了是正常结果，复核与更新基线按 build-probe.ps1 的提示走。
# 期望哈希的唯一事实源是 tools/build-probe.ps1 的 $expected，本处只读它，不另存一份。
PZ_SHA=$(sha256sum "$GAME_ROOT/projectzomboid.jar" | cut -d' ' -f1)
BUDDY_SHA=$(sha256sum "$GAME_ROOT/ZombieBuddy.jar" | cut -d' ' -f1)
EXPECTED_PZ=$(sed -n "s/^[[:space:]]*'projectzomboid\.jar'[[:space:]]*=[[:space:]]*'\([0-9A-F]*\)'.*/\1/p" "$ROOT/tools/build-probe.ps1" | tr 'A-F' 'a-f')
EXPECTED_BUDDY=$(sed -n "s/^[[:space:]]*'ZombieBuddy\.jar'[[:space:]]*=[[:space:]]*'\([0-9A-F]*\)'.*/\1/p" "$ROOT/tools/build-probe.ps1" | tr 'A-F' 'a-f')
[ -n "$EXPECTED_PZ" ] && [ "$PZ_SHA" != "$EXPECTED_PZ" ] && echo "NOTE: projectzomboid.jar hash changed (patch expected) — re-review before updating the baseline in tools/build-probe.ps1" >&2
[ -n "$EXPECTED_BUDDY" ] && [ "$BUDDY_SHA" != "$EXPECTED_BUDDY" ] && echo "NOTE: ZombieBuddy.jar hash changed — re-review before updating the baseline in tools/build-probe.ps1" >&2

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT INT TERM
CLASSES="$STAGE/classes"; GENERATED="$STAGE/generated/emberroutes/probe"
mkdir -p "$CLASSES" "$GENERATED"

# BuildInfo 由构建生成（见 build-probe.ps1）；本处用等价桩：VERSION 取 version.txt，GAME_SHA256 取当前 jar 实测哈希。
VERSION=$(tr -d '[:space:]' < "$ROOT/version.txt")
cat > "$GENERATED/BuildInfo.java" <<EOF
package emberroutes.probe;

public final class BuildInfo {

    public static final String VERSION = "$VERSION";

    public static final String PREFIX = "[EmberRoutes v" + VERSION + "]";

    public static final String GAME_SHA256 = "$PZ_SHA";

    private BuildInfo() {}
}
EOF

# shellcheck disable=SC2046
"$JAVAC" -J-Duser.language=en --release 25 -encoding UTF-8 -cp "$GAME_ROOT/*" -d "$CLASSES" \
    $(find "$ROOT/java/src/main/java" -name '*.java') "$GENERATED/BuildInfo.java"
"$JAVA" -ea -cp "$CLASSES:$GAME_ROOT/*" "$ROOT/tests/java/emberroutes/probe/ProbeBridgeSurfaceTest.java"
