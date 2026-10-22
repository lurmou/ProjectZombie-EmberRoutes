# 0.2.0 原版动作批量探针记录

> 日期：2026-10-19｜状态：本地检查通过，实机未验证

## 来源与基线

沿用本项目独立载体代码，没有迁入 CommunityTrade 或 NPCFW 类。游戏与 ZombieBuddy 哈希由构建脚本复核，与 [基线](baseline.json) 相同。参考原版安装目录的 `ISBaseTimedAction.lua`、`ISTimedActionQueue.lua`、`ISEatFoodAction.lua`、`ISDrinkFluidAction.lua`、`ISInventoryTransferAction.lua`、`ISTransferAction.lua` 与当前 JAR 中的 `IsoGameCharacter`、`LuaTimedActionNew`。

原版执行链先 perform 再 complete；吃喝实际效果不能仅以 Lua 队列清空判定。吃饭取消经 serverStop/eat 部分结算，喝水随 update 渐进结算，因此中断验证保留部分消耗。搬运验证原对象、ID、耐久、ModData 和唯一所在容器。本包只使用 NPC 内部容器，避免 selectedContainer 分支访问真实玩家槽位的 loot UI，并关闭本动作的玩家进度条；未全局替换原版动作。

原版 SP autoDrink 不受 IsoPlayer.autoDrink 字段控制；仅覆写探针的 autoDrink 以隔离测量。移动、停止、退场同步停止原版队列，Lua 保存前也取消批次；随后清理本次夹具及队列引用。未知容器或混入物资阻塞夹具删除。

## 当前用户证据与黄色圈

用户对 0.1.2 反馈“可以了”，但未提供逐项楼梯/攻击退场验收表。本轮不扩张为完整生命周期通过。

读取本次 console.txt 可见 0.1.2 BOOT、READY 和 NPCFW “Injected 247 global functions. Framework READY.”；外部代理仍然加载。源码扫描本包未发现圈/标记绘制。当前 JAR 的 IsoZombie.renderDebug 中，zombieRenderViewDistance 的目标状态可画黄色圈；本机 debug-options.ini 对应值为 false，故这仅是可辨识的原版候选，不能认定为当前圈来源。本包未改变游戏调试选项或启动配置。

## 检查与交付

实现 [设计](../../superpowers/specs/2026-10-19-phase0-actions-design.md) 和 [计划](../../superpowers/plans/2026-10-19-phase0-actions-plan.md)；使用方法见 [集中测试说明](../../testing/phase0-actions.md)。原始输出与产物哈希随本记录保存；检查结果以 `probe-0.2.0-verification.json` 为准。

当前游戏中的动画、实际动作效果、攻击中断与本包联动：未实机验证。专服与双客户端：未实现/未验证。本轮交付是动作白名单验证包，不能当作经营系统或整个 Phase 0 已完成。

本地结果：Java 构建及 61 项断言；Lua 批次策略 16 项、替身调度/清理边界 14 项，合计 91 项；preflight 通过（LuaLS 0 error / 0 warning）；8 份 Markdown 的 doclink 为 0 错误 / 0 提示。原版知识库仍有一个 `0.0f` 语法解析缺口，未将该工具盲区当作本包通过证据。

复跑：`./tools/build-probe.ps1`；使用本机 Lua 5.1 分别执行 `tests/lua/batch-test.lua`、`tests/lua/actions-test.lua`；`node ../.workbuddy/tools/pz.mjs preflight Contents/mods/EmberRoutesProbe`。32 位 Lua 在沙盒内报系统 DLL 重定位错误，获工具审批后直接运行成功；没有更改系统配置或解释器。替身测试仅检查我们的调度，不模拟原版效果。
