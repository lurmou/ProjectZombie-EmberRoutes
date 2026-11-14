# 开发检查表：PZ 补丁后流程

> 日期：2026-11-11｜状态：active｜适用：Project Zomboid 本体补丁（或 `projectzomboid.jar` / `ZombieBuddy.jar` 变化）之后。
> 本表是补丁后流程的唯一落点；通用检查规则见 [development-rules.md](development-rules.md)（检查与交付），依赖哈希基线见 [tools/build-probe.ps1](../tools/build-probe.ps1)。

## 补丁后，先跑桥面测试

PZ 补丁后，任何其他测试、构建或实机之前，先跑 `ProbeBridgeSurfaceTest`（119 个入口的完整签名白名单）：白名单就是“桥还健在”的最快信号。桥面红了就停下来，先对白名单做 diff（缺了哪个方法、多出哪个方法、返回类型或参数类型变了哪一项），修桥或同步白名单并说明原因；不绕过、不跳过、不先跑别的测试。

仓库根目录一条命令（Linux/macOS；Windows 走 `tools/build-probe.ps1`，其桥面步骤与本命令等价）：

```sh
sh tools/run-bridge-surface.sh
```

通过输出：`PASS 119 complete Lua bridge signatures; metadata only, game NOT RUN`

## 补丁后，其余顺序

1. 依赖哈希：`build-probe.ps1` 已 pin 两个 jar 的 SHA256；哈希变了是补丁的正常结果，先按脚本提示复核（re-review before updating the baseline），不要直接改期望哈希。`run-bridge-surface.sh` 只提示、不拦截。
2. 桥面测试绿了，再跑其余回归：Kahlua 全树编译、逻辑测试、完整构建（`build-probe.ps1`），按 `development-rules.md` 检查与交付。
3. 白名单变化：桥方法或其返回/参数类型增减时同步改 `tests/java/emberroutes/probe/ProbeBridgeSurfaceTest.java` 的签名白名单，并在提交里说明原因；白名单必须与 ProbeRuntime 的公开静态入口表完全一致。

## 热重载陷阱：改了什么 → 要不要重启

> 口号修正：不是“只改函数体就能热重载”，而是“只改函数体、且函数走 Probe 分发表、且赋值在定义文件顶层，才可能热重载”。下表按代码判定。
> 前提：所谓热重载，指改动的文件在同一 Lua state 内被重执行。仓库内没有重执行入口（生产代码无 `dofile`/`loadfile`；`package.loaded` 只出现在测试桩里），具体用哪个游戏内入口重执行文件尚未实机验证。拿不准时一律重启——重启永远是对的，重执行不一定。

| 改了什么 | 要不要重启 | 为什么（代码依据） |
|---|---|---|
| Boot.lua 任何行为改动：顶层 require、tickHooks 表、Probe.begin / tick / reset / beforeSave 函数体、底部事件接线 | 必须重启 | 三重锁死：①顶层 require 命中缓存（Boot.lua:1-4；模块身份一会话内不变，Persistence.lua:13-16）；②重执行造出全新的局部 Probe 表（Boot.lua:14），旧表仍被 require 缓存与已注册回调持有；③subscribeOnce 先到先得（EventBus.lua:19-30），新注册被丢弃、旧闭包继续跑。连“只改 Probe.begin 函数体”也不生效。 |
| 经 EventBus.subscribeOnce 的事件订阅：新增 / 删除 / 改回调 | 必须重启 | 首次注册获胜：重执行不重复注册（EventBus.lua:19-30）；EventBus 没有注销 API，源码里删了订阅、运行中已注册的回调也不会注销；改回调体时旧闭包继续触发。引擎本身从不去重（EventBus.lua:3-8）。同理，EventBus.runOnce（Boot.lua:320 退休接线）也是首次执行获胜。 |
| 直接 Events.X.Add 的订阅点，如 EmberRoutesActivities.lua:4、NpcMedical.lua:274、VanillaCraftingHook.lua:101 | 必须重启 | 无去重守卫：重执行会把同一回调再加一遍，触发两次；删改同样不生效、不注销。 |
| 新增 / 删除 Lua 文件 | 必须重启 | 加载集在启动时定死：入口文件顶层 require 链一次性拉起全图（EmberRoutesProbe.lua:1-40）；新增文件没有任何 require 指向它；已删文件仍活在 require 缓存与已注册回调里。Kahlua 全树编译（tests/java/KahluaCompileTest.java）同样是加载时一次跑完。 |
| ActivityRegistry 定义改动：新增 / 改值 / 删定义 | 必须重启 | freeze 后 register 直接拒绝（ActivityRegistry.lua:29,65）；freeze 在 OnGameStart（EmberRoutesActivities.lua:4）与 ActivityService.load / preview（ActivityService.lua:15,59）触发；get 返回的是拷贝（ActivityRegistry.lua:66），改源码不影响内存中已冻结的副本。 |
| Constants.lua 改值 | 必须重启 | 文件重执行造出全新表（Constants.lua:27），各模块加载时持有的是旧表引用，调用时读的仍是旧表字段（如 Actions.lua:355）；威胁规则等值在 Java 侧有同名实现（ObserverReads.java），只改一边会两边不一致（Constants.lua:21-23 头注）。 |
| Java 桥改动：java/src 任一文件；或只改 Build.lua 的 version | 必须重启（重编 + 重启） | 类随 jar 在 JVM 启动时加载；Boot.begin 有版本门：EmberRoutesProbeJava.version() 与 build.version 不一致即 VERSION_MISMATCH、拒绝启动（Boot.lua:117；version() 返回 BuildInfo.VERSION，CarrierRuntime.java:37，BuildInfo 由 tools/build-probe.ps1 的 `$buildInfo` 块生成）。只改 Lua 侧 version 不同步 Java，同样触发 mismatch。 |
| 只改函数体，且函数经 Probe 分发表调用（Probe.tickX），赋值在定义文件顶层，如 Work.lua:195、Actions.lua:418、Haul.lua:417、ActivityService.lua:345 | 可重执行，不必重启 | Boot 每 tick 现查 Probe[hook.key]（Boot.lua:204）；重执行定义文件会把新闭包重新赋到共享 Probe 表上，下个 tick 即调用新体。条件：不动 tickHooks 表（Boot.lua:170，加载时建一次）、不新增 hook key、不改签名。 |
| 只改函数体，但赋值在 install() 里（SelfCare.lua:627、MembershipRuntime.lua:197、TaskRetirement.lua:33），或赋值与定义跨文件（Companion.lua:171 赋 TaskRuntime.lua:350 的 Runtime.tick） | 必须重启 | 重执行文件本身不调 install()，Probe 字段仍指向旧闭包；跨文件链须按顺序重执行定义文件与赋值文件，缺一环旧体继续跑。 |
| 纯注释 / 空白改动 | 不用重启 | 无行为变化。 |
