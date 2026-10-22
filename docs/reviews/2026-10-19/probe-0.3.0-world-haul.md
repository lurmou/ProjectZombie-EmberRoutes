# 0.3.0 真实容器搬运探针

> 日期：2026-10-19｜状态：实现与本地检查，待实机

前置结果：[0.2.0 实机记录](probe-0.2.0-runtime.md) 确认十项 SP 动作通过。新增 [设计](../../superpowers/specs/2026-10-19-phase0-world-haul-design.md)、[计划](../../superpowers/plans/2026-10-19-phase0-world-haul-plan.md) 和 [集中测试说明](../../testing/phase0-world-haul.md)。

## 契约与实现

- 基线：构建复核游戏和 ZombieBuddy JAR 哈希不变，见验证 JSON。
- 参考当前原版 `luautils.walkAdj`、`walkAdjObject`：使用 getCorrectSquareForWall、AdjacentFreeTileFinder.Find 和 canReachTo；不凭距离判断能隔墙拿取。
- `ProbeRuntime.carrierPresent` 与 `carrierActive` 区分存活和空闲，避免路径执行过程中误判 NPC 不可用；motionResult 只读返回真实移动终态。stopCarrier 只对当前持有的同一 SP 载体生效，可在指挥玩家死亡时停止工作，不伪造用户身份。
- 原版 ISInventoryTransferAction 对世界容器设置 selectedContainer，update/perform 会访问真实玩家的 loot UI。本包只在该动作实例的 startActionAnim 后清除此引用，保留原版动画、合法性、转移和声音；update 保留朝向目标容器，不全局替换动作类。
- 每步验证实际对象、ID、耐久、名称与 ModData；异常停止并保留实际位置，不删除再造。不检查或搬运未指定容器中的正式物资。
- 在原版 isValid 和 perform 效果边界再次检查标签、可触及性、实例状态和原版合法性，覆盖最近一次 Lua tick 后的撤权/变动；不是只在任务开始检查一次。
- getRandomUUID 在当前原版 Foraging 有真实调用，旧静态 lint 全局清单遗漏；通过 `_G` 获取并做存在性守卫，没有自创不稳定 ID 或修改共享工具。
- 取消、外部移动、停止、保存和退场协调两个测试执行者；世界搬运与旧吃喝批次互斥。生命周期仍需人工在保存前等待完整退场。

## 检查边界

Lua 回归覆盖 17 步往返、重复请求、执行互斥、原有资产保留、取消、容量不足、标签撤销、拆除、载体失效、原状态被修改、清理阻塞与原生路径失败。替身只检验调度和保护，不能证明原版寻路、世界容器 UI 适配及实际转移效果；这些必须由新包实机验证。

原始检查输出、源文件哈希、产物哈希与检查结果保存在本目录 `probe-0.3.0-*` 文件中。未运行专服、双客户端、故障恢复或性能测试，未把世界容器探针记作正式经营功能。

最终本地检查：Java 构建与 61 项断言；Lua 批次 16 项、旧动作调度 14 项、世界搬运 42 项，合计 133 项；preflight 通过，LuaLS 0 error / 0 warning；10 份 Markdown 的 doclink 为 0 错误 / 0 提示。世界容器新包实机未运行。
