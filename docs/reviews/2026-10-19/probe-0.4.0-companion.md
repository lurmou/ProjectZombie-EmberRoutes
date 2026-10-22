# 0.4.0 单人随从与暂停退场

> 日期：2026-10-19｜状态：实现与本地检查，实机未验证

本轮按用户 [单人优先决定](../../decisions/2026-10-19-sp-first.md) 实施，见 [设计](../../superpowers/specs/2026-10-19-sp-companion-design.md)、[计划](../../superpowers/plans/2026-10-19-sp-companion-plan.md) 与 [集中测试说明](../../testing/single-player-companion.md)。当前 JAR 哈希与前述基线一致。

## 实现事实

- 新增本地 Driver，按稳定 NPC UUID 绑定意图和标量快照；声明 SINGLE_PLAYER / multiplayer=false，陈旧绑定拒绝执行。旧动作/搬运接口不冒充已网络化。
- 随从控制器不直接读取载体 userdata，驻点也通过 Driver 的标量快照取得，避免未来适配层仍被原生对象访问穿透。
- FollowPolicy 提供起停滞回、有限重规划与三次失败预算；Companion 管理 FOLLOW/HOLD/RETURNING/BLOCKED，驻点绑定 NPC UUID。工作与随从交接共享 cancelAll；停用控制器每秒检查并释放失效对象引用。
- Java 增加受限 controlledCarrier / carrierId，保留原有 SP、线程、存活及距离校验；follow 移动仍由原版路径驱动，不新增第二个运动执行者。
- 当前 JAR 经 CFR 0.152 重新提取 GameWindow 与 LuaEventManager：前者在 doUpdate=false 且游戏内触发 OnTickEvenPaused，后者注册该事件。旧退场只有普通 OnTick，因此暂停时不继续检查。
- 新增暂停回调仅运行 retirementTick：退场继续关系解除/静默门控，非退场 NPC 只记录路径暂停时钟；不调用 update、不推进三个工作执行者。ProbeMovement 恢复时扣除已观察到的暂停时段，仍保留20秒有效运行上限。

## 验证边界

纯回归覆盖跟随重规划、滞回、跨层、无效坐标、失效人物、稳定 ID 替换、驻点返回/失败、工作交接、三次失败终止、暂停事件隔离和超时钟。替身不验证真实绕障、动画、楼梯、攻击关系或事件时序；需用户运行新包。

原有 0.2.0/0.3.0 SP 实机结果保留。本轮不将完整持久化、战斗、联机或规模性能标为已实现。检查输出和哈希见同目录 `probe-0.4.0-*` 文件。

版本日志统一经原版 DebugLog.log 输出，签名由当前 JAR javap 及原版 ISAdminPowerUI 的调用核对；保留原版本和分类前缀，不关闭测试日志。最终本地检查合计208项：Java65、跟随策略29、随从/Driver28、暂停回调8、批次16、旧动作14、世界搬运42、实际控制器交接6；重复嵌套运行的旧套件不重复计数。

最终 preflight 通过，LuaLS 为0 error / 0 warning；release-check 为0 error / 0提示；13份文档 doclink 为0错误 / 0提示。工具原版知识库仍有一个 `0.0f` 解析缺口，未据此证明那份原版文件正确。所有新增实机结果仍记为未验证。
