# 开发检查表：PZ 补丁后流程

> 日期：2026-11-11｜状态：active｜适用：Project Zomboid 本体补丁（或 `projectzomboid.jar` / `ZombieBuddy.jar` 变化）之后。
> 本表是补丁后流程的唯一落点；通用检查规则见 [development-rules.md](development-rules.md)（检查与交付），依赖哈希基线见 [tools/build-probe.ps1](../tools/build-probe.ps1)。

## 补丁后，先跑桥面测试

PZ 补丁后，任何其他测试、构建或实机之前，先跑 `ProbeBridgeSurfaceTest`（114 方法白名单）：白名单就是“桥还健在”的最快信号。桥面红了就停下来，先对白名单做 diff（缺了哪个方法、多出哪个方法），修桥或同步白名单并说明原因；不绕过、不跳过、不先跑别的测试。

仓库根目录一条命令（Linux/macOS；Windows 走 `tools/build-probe.ps1`，其桥面步骤与本命令等价）：

```sh
sh tools/run-bridge-surface.sh
```

通过输出：`PASS 114 public bridge methods; dynamic kernel entries retained; metadata only, game NOT RUN`

## 补丁后，其余顺序

1. 依赖哈希：`build-probe.ps1` 已 pin 两个 jar 的 SHA256；哈希变了是补丁的正常结果，先按脚本提示复核（re-review before updating the baseline），不要直接改期望哈希。`run-bridge-surface.sh` 只提示、不拦截。
2. 桥面测试绿了，再跑其余回归：Kahlua 全树编译、逻辑测试、完整构建（`build-probe.ps1`），按 `development-rules.md` 检查与交付。
3. 白名单变化：桥方法增减时同步改 `tests/java/emberroutes/probe/ProbeBridgeSurfaceTest.java` 的白名单，并在提交里说明原因；白名单与当前桥方法表必须一致。
