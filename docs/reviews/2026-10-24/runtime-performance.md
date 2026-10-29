# 0.24.4 常驻运行性能改进

## 基线及目标

用户截图 ZBLuaPerfMon 标头为 `last 1s`。EmberRoutes 的 Boot 入口累计分别为 189.3ms/104 次和 136.7ms/168 次；这是整个回调的累计墙钟时间，不能据入口行号归因给保存模块，也不能当成每帧 150ms。用户反馈只有一个 NPC、未开 UI，卡顿持续。验收目标：同一场景、同一监测工具的 Boot 一秒累计低于 50ms，当前尚未实测。

沿用[唯一架构](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)，[实施计划](../../superpowers/plans/2026-10-24-runtime-performance.md)。本轮在线需求重新导出 SHA256 为 `1E802DFE03A43437C77DC8EF5D04A2E38EC9AE9970A71D349B302B9EFE2EFB08`，与架构审查快照相同。安装基线：PZ 42.21.0、ZombieBuddy 2.3.4，构建校验当前 JAR 哈希，见 build/probe-build.json。

## 已确认的重复工作与修正

- Boot.hasJava 原来每次访问完整的原生扩展接口集合。现在成功启动后复用验证结果；每次 begin 强制重验，桥接对象替换或 controlledExecution 改变不会复用不相符的结果。没有缓存失败或缓存身体/库存事实。
- Persistence 原来无保存、无恢复时仍查询玩家、死亡状态及所在格。现在只在有待核对保存结果、恢复队列或旧恢复工作时进入；真实保存后的下一 tick 仍核对落盘回执，未降低保存检查频率。
- PublicWork 的 200ms 门限原来位于世界、运行器、玩家查询之后。现在没有在途预检时先判断时间；有在途请求仍逐 tick 切片。空 PrecheckQueue 不分配检查表、不读时钟。
- SelfCare 只在候选发现到期后查询世界与运行器；执行用的节点/扫描/路径共享预算仍每 tick 重置，避免慢发现拖慢动作树。复用预算表减少垃圾分配。
- TaskRetirement 提前判断 200ms 门限，保留原件、效果、停止与声明的所有结清条件。
- 公共物流原来空搜索结束后，下次普通决策再次构建扫描。现在空结果最多 2 秒重试，容器配置/据点变更和库存通知清除等待；运行中的扫描仍正常推进。外部模组或原版未发通知的变化靠有限重试发现。无观察者脏数据时不执行旧物流更新准备；未打开配方浏览/预览时不进入后台读服务。

这些是源码确认的无效工作；各项实际耗时比例仍待游戏分项采样，不能把任何一项直接宣称为 150ms 的主因。本轮未改 NPC 原生世界更新，也未改其他模组。

## 游戏内分项采样

完全退出游戏并加载 0.24.4。在原版 Debug 右键菜单的余烬商路诊断子菜单点击“后台性能采样（20秒，结果写入日志）”。采样默认关闭，20 秒自动结束，固定大小记录，无每帧打印。关闭 UI 并保持原测试的 NPC 状态，让 ZBLuaPerfMon 同时保留一秒窗口。

console.txt 中搜索 `RUNTIME_PERF`：输出 Boot 的 `Boot_ms_per_second`、最大单次 `max_tick_ms`，以及 Persistence/SelfCare/Tasks/Crafting/Actions/Haul/Work/Companion/Logistics/PublicWork/Retirement/CraftView/Java 的累计每秒耗时和单次最大值。`peak_tick_window_ms` 是以 tick 为边界、跨度至少一秒的累计峰值，遇长帧会超过一秒，不等同于监测器的精确滑窗。分项包含其下游调用，不能与 Boot 相加。计时开销包含在 Boot 内，默认关闭时不调用高精度时钟。

先用同工具判断是否低于 50ms；分项日志用于决定下一项优化。平均值不证明每个窗口达标，也不能证明整个游戏已消除卡顿。

## 验证

- 安装版 Kahlua：新空闲路径/能力缓存/替换重验/采样结束/服务顺序/保存唤醒测试通过；启动、暂停、保存恢复、结清删除、自理、公共派工、预检预算与多角色等待相关回归通过。原生世界和时钟边界仍为替身。
- 物流定向验证：空结果不反复重建、在途切片正常、库存事件立即唤醒、外部变化有限重试通过。既有物流进度测试把 Registry.data 替换为每调用都创建不同表，与真实世界契约不符；改为固定替代世界，保留跨世界隔离断言后通过。
- 0.24.4 构建通过；modscan 无文件替换冲突；release-check 为 0 错误、77 条现有 UI 硬编码中文提示；5 个相关 Markdown 文档 doclink 为 0 断链。完整 preflight 全部通过（152 个 Lua；原版 ISFluidEmptyAction 的 0.0f 解析缺口仍由工具明确列出，不属于本模组）。
- 最终 10 组相关 Lua 回归全部通过，见 build/logs/runtime-performance-regression.log。归档与源码逐文件 SHA256 比对 159 文件一致；ZIP SHA256 `83D48936516060A4B6B312B5A8162182ED50B1D6E474DDBA1697681E101BF40A`。
- **游戏、真实 CPU/GC 和低于 50ms 目标未验证。** 当前游戏未运行，不用离线断言推算加速百分比。

原始输出：build/logs/runtime-performance-regression.log、runtime-performance-tests.log、runtime-performance-tests-final.log（包含旧物流世界夹具失败）、runtime-performance-tests-extra.log、runtime-performance-tests-safety.log（修正后通过）、runtime-performance-preflight.log、runtime-performance-build.log、runtime-performance-release.log、runtime-performance-doclink.log。
