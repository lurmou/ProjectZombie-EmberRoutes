# 载体探针 0.1.0 验证记录

> 日期：2026-10-19｜状态：本机构建/静态/纯逻辑检查完成；游戏实机未验证

## 交付内容

已独立实现临时 IsoPlayer 子类载体、稳定探针 ID、单对象会话、坐标规则、原版路径请求、停止/状态检查/清理、版本诊断、右键菜单、CN/EN 提示和构建打包脚本。见 [测试说明](../../testing/phase0-carrier.md) 和 [实施计划](../../superpowers/plans/2026-10-19-phase0-carrier-plan.md)。

产物：`build/packages/EmberRoutesProbe-0.1.0.zip`。实际构建的依赖、文件与产物哈希保存在 [机器可读验证记录](probe-0.1.0-verification.json)；原始构建报告为本地 `build/probe-build.json`。JAR 仅含 `emberroutes.probe` 和 manifest，不打包游戏、ZombieBuddy 或 NPCFW 类。

## 实际执行的检查

| 检查 | 结果 | 范围及限制 |
|---|---|---|
| JDK 25 javac 编译当前游戏/ZB 依赖 | 通过 | 输出目标 Java 17；不等于游戏加载成功 |
| 纯逻辑测试 | 29 项断言通过 | 非有限坐标、距离/楼层、命令名、SP/MP 门禁、重复创建/移除、构造失败、清理失败保留引用 |
| 初始失败验证 | 已执行 | 实现前测试因缺少 ProbeRules/ProbeSession 编译失败；随后补实现通过 |
| JAR 内容检查 | 通过 | 只允许 META-INF 与 emberroutes 路径 |
| CN/EN JSON 键集合比较 | 通过 | IG_UI、Sandbox 成对；未做游戏内排版验证 |
| preflight / Lua 语法 | 通过 | 4 个 Lua 文件，0 error / 0 warning |
| preflight / 结构与不变量 | 通过 | 结构规则、额外 prerender 规则和候选不变量无命中 |
| preflight / LuaLS | 通过 | 0 error / 0 warning；识别 1 个 Java 注入全局 |
| preflight / 索引新鲜度 | 通过 | 10 项通过；EOL 专属健康检查因非该架构按工具规则跳过 |
| modscan 实际模组根 | 未发现整文件替换冲突 | 扫 4 个 Lua；不等于所有运行时模组兼容 |
| 文档链接 | 见本轮 doclink 输出 | 显式指定本轮修改文档 |

首次 preflight 的 LuaLS 因沙箱不允许在共享 `.workbuddy/tools` 写临时配置而失败；通过系统审批重新执行后完整通过。未修改共享工具代码。

工具知识库仍报告原版 `shared/Fluids/ISFluidEmptyAction.lua` 含 `0.0f` 导致 1 个文件无法按标准 Lua 解析。本项目文件解析和检查通过，不将知识库覆盖率报告隐去。

原始输出：本地 `build/logs/build-probe.txt`、`logic-tests.txt`、`preflight.txt`、`doclink.txt`。

## 引擎接入依据

使用与前轮一致的游戏 JAR 新提取 `IsoPlayer`、`IsoGameCharacter`、`IsoMovingObject`、`AIComponent`，位于忽略目录 `build/reference/pz-current`；ZB 接入类新提取到 `build/reference/zb-current`。以下行号仅属于本次 CFR 输出：

- `IsoGameCharacter.java:774` 起的构造仅在非零坐标时自动加入 moving objects；因此先以零坐标构造、获取会话所有权，再显式设置出生位置与注册，降低半构造对象进入调度的风险。
- `IsoPlayer.java:2571` 的 setNpc 挂载 AIComponent；`AIComponent.java` 提供 justMoved/running/strafe 控制变量。
- `IsoGameCharacter.java:5923` 起的 CanUsePathfindState/pathToAux/pathToLocationF 是本包原版路径入口；不使用直接逐帧写坐标作为行走实现。
- `IsoPlayer.java:2048` 起的 updateInternal2 仍有本地假设；`:2178` 起包含专服断言、摄像机和实例赋值。因此 MP 入口未建立前拒绝实体创建；SP 用 finally 恢复实例与摄像机引用，副作用尚需实测。
- `IsoMovingObject.java:718` 起的 removeFromWorld 会处理调度和加入/移除集合；本包另显式清理自己持有的当前世界及方格引用，不清空集合。
- ZB `Loader.java:793` 起调用目标包 Main；`Exposer.java:71` 起提供命名类暴露。本包 Main 使用 Exposer 暴露 `EmberRoutesProbeJava`，Lua 先检查能力与版本再调用。

NPCFW 仅用于机制对照，见 [首轮参考评审](npcfw-reference-review.md)。本包没有复制其自理、驾驶、ASM、商业库存或生产实现。

## 明确未完成的验收

- SP 启动、外观、移动、绕障、镜头、停止/清理、保存退出：**未验证**。
- MP 载体模拟与创建/移动/销毁同步：**未实现**；本包只诊断并拒绝生成，不称作 MP 通过。
- 僵尸交互、战斗效果、三项动作白名单、完整状态恢复、强退防复制与负载预算：**未实现/未验证**。

临时实体没有持久化协议；保存回调只是辅助清理，测试者应先显式移除再退出。本轮没有启动游戏或专服，没有替用户修改安装目录和启动配置。
