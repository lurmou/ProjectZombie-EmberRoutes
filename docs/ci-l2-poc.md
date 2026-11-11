# CI POC：将 L2（Lua 逻辑测试）接入 CI

> 草案（Phase 1 / E）。本文件描述如何把 `tests/lua/*.lua` 经 `KahluaLaborTest.java` 接入 CI，
> 以及**必须先解决的一个落地障碍**。不要直接照抄末尾的 job 到 `ci.yml` 而不先做"修复 1"。

## 障碍：运行器写死了本机游戏 stdlib 路径

`tests/java/KahluaLaborTest.java:29`：
```java
run(thread,env,Path.of("D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/stdlib.lua"));
```
这是开发者机器的绝对路径。CI / 他人机器上不存在 → L2 无法复现。

### 修复 1（必做，约 3 行）：改为 `GAME_ROOT` 驱动 + 回退
将第 29 行替换为：
```java
String gameRoot = System.getenv().getOrDefault("GAME_ROOT", "game-root");
Path stdlib = Path.of(gameRoot, "stdlib.lua");
if (!Files.exists(stdlib))
    throw new IllegalStateException("EmberRoutes L2 tests need PZ stdlib.lua: set GAME_ROOT=<pz-install> or place stdlib.lua in game-root/ (looked at: " + stdlib + ")");
run(thread, env, stdlib);
```
- 本地：`GAME_ROOT=D:/Software/GameApp/steam/steamapps/common/ProjectZomboid` 即可，行为与改前一致。
- CI / 自托管：`GAME_ROOT` 指向含 `stdlib.lua` 的 `game-root/`（与 `jar-checks` 共用同一目录）。
- **shim（零游戏依赖的 `pz-stdlib-shim.lua`）暂缓，不纳入本次修复**——见文末"shim 为什么暂缓"。
- 这是让 L2 在"有游戏根目录"前提下可复现的关键；GitHub runner 仍跳过（与 jar-checks 一致）。

### 修复 2（建议）：新增 `lua-labor-tests` job
与 `jar-checks` 对称——有 `game-root/` 才跑，否则跳过（专有游戏文件不入库，GitHub runner 上跳过是预期行为，不是失败）。

```yaml
  lua-labor-tests:
    name: lua labor tests (Kahlua logic)
    runs-on: ubuntu-latest
    steps:
      - name: Check out
        uses: actions/checkout@v4

      - name: Set up Java 17 (Temurin)
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - name: Look for game jars / stdlib
        id: game
        shell: bash
        run: |
          if [ -f game-root/stdlib.lua ] && [ -f game-root/projectzomboid.jar ]; then
            echo "has_game=true" >> "$GITHUB_OUTPUT"
            echo "Game root found."
          else
            echo "has_game=false" >> "$GITHUB_OUTPUT"
            echo "game-root/ not present — lua labor tests will be skipped (see workflow header)."
          fi

      - name: Run lua labor tests
        if: steps.game.outputs.has_game == 'true'
        shell: bash
        env:
          GAME_ROOT: ${{ github.workspace }}/game-root
        run: |
          java -cp "game-root/*" tests/java/KahluaLaborTest.java --all --keep-going

      - name: Report skip
        if: steps.game.outputs.has_game != 'true'
        shell: bash
        run: |
          {
            echo "## lua-labor-tests skipped"
            echo ""
            echo "No \`game-root/stdlib.lua\` + \`game-root/projectzomboid.jar\` on this runner,"
            echo "so L2 Lua logic tests did not run. This is expected on GitHub-hosted runners"
            echo "(proprietary game files are never committed). Run them on a self-hosted runner"
            echo "with the game installed, or locally via GAME_ROOT=<pz-install>."
          } >> "$GITHUB_STEP_SUMMARY"
```

> 说明：`java tests/java/KahluaLaborTest.java` 走 JEP 330 单文件源启动（JDK 11+），
> `--all` 跑全部 `-test.lua`，`--keep-going` 汇总失败并以退出码 1 失败。无需构建步骤。

## 本地验证（在修复 1 之后）

```bash
# 在本机（有游戏安装）：
GAME_ROOT="D:/Software/GameApp/steam/steamapps/common/ProjectZomboid" \
  java -cp "game-root/*" tests/java/KahluaLaborTest.java --all --keep-going

# 在无游戏安装、且未提供 shim 的干净环境：
# L2 会直接报错退出（缺 stdlib.lua）——这符合预期（shim 暂缓）；
# 要跑 L2 必须提供 GAME_ROOT 或 game-root/stdlib.lua（与 jar-checks 一致）。
```

## 落地顺序建议
1. 先合入 D 修复（`tools/check-undeclared-globals.py` 已 `git add`，待提交）。
2. 做修复 1（stdlib 路径解耦，shim 暂缓）。
3. 先本地跑通 `--all --keep-going` 验证 285 个测试基线（记录通过/失败数）。
4. 再合入修复 2 的 `lua-labor-tests` job（自托管 runner 上生效，GitHub runner 安全跳过）。
5. 不要一次性把 285 个测试设为硬门禁——先以 `--keep-going` 汇总观察，稳定后再要求零失败。

## shim 为什么暂缓（本次不做）

`pz-stdlib-shim.lua`（零游戏依赖的最小 PZ 标准库替身）能让 L2 在 **GitHub 免费 runner** 上也跑，但它：
- 需要先做依赖发现：读游戏 `stdlib.lua` + grep `tests/lua/*.lua` 实际用到的 PZ 全局，才能写出"刚好够用"的替身；
- 必须随 PZ 版本演进维护（B42 改了某个全局签名，shim 也得跟着改），否则测试会静默误报。

而仓库现有策略就是"游戏文件不入库、GitHub runner 跳过 jar-checks"，所以方案 A（解耦 + `game-root/stdlib.lua` 门控）已足以让 L2 成为可复现的 CI 门禁（在自托管 runner 上）。shim 留作后续可选增强，不现在写。

## 注意
- 修复 1 后，L2 在 GitHub runner 上仍会"跳过"（缺 `game-root/`），这点与 `jar-checks` 一致，属预期。
- L2 绿 ≠ 游戏机制正确（见 `docs/VERIFICATION_MATRIX.md` 第 0 节）；实机层（L5/L6）不可替代。
- `java-version` 已与 `build-probe.ps1`（`--release 17`）对齐为 17（原 `ci.yml` 误写 25，已修）。
