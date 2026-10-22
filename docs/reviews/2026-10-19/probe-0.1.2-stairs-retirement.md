# 载体探针 0.1.2：跨楼层移动与攻击中退场

> 日期：2026-10-19｜状态：代码、构建及静态检查完成，修复后实机未验证

## 本轮关口

用户确认 0.1.1 已能移动；本机日志也有多条真实位置变化与 MOVE_REACHED。本轮继续 Phase 0 的基础交互/生命周期关口：处理上下楼请求和正在被僵尸攻击时的退场，不跳过这些故障直接宣称动作白名单或 MP 通过。

## 日志结论

- 上楼无响应：0.1.1 规则强制目标与角色同层，日志有 `INVALID_POINT finite same-floor point within 16 tiles required`。即使只放开该规则，原到达判定只有 XY，也可能在楼下误报抵达楼上。
- 删除后攻击报错：日志中 `REMOVED` 在 f:19375，f:19602 发生 `BodyDamage.UpdateBoredom` 的空方格异常。调用链为 `AttackState.triggerPlayerReaction → BodyDamage.Update`，中间可见 pzopt 的延迟动画处理。此证据支持“退场后仍有攻击引用”，不代表已证明 pzopt 本身有错。
- 同一次退出另有 `hs_err_pid18264.log`，报告 JVM `archiveHeapWriter.cpp:758` / AOT 归档错误；它是退出缓存创建阶段的另一条错误，不能和上述 Java 空引用合并归因。本轮不修改 JVM 或优化模组配置。

相关原文只截取必要部分，见 [本轮实机日志摘录](probe-0.1.1-stairs-removal-runtime.txt)。没有保存完整聊天或整份 JVM 环境转储。

## 当前引擎核查

游戏 JAR SHA-256 与前轮相同：`E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`。

从当前包提取 IsoZombie、AttackState、BaseGrappleable、IGrappleable，结合已有 IsoGameCharacter/PathFindBehavior2 核查：

- AttackState 的攻击动画事件读取 zombie.target，随后可能直接调用目标的 BodyDamage.Update；清空方格但未先解除目标并不安全。
- IsoZombie.setTarget(null) 是原版目标清理入口；啃食另有 setEatBodyTarget(null, false)，不能只处理 target。
- BaseGrappleable.LetGoOfGrappled 会通知另一方 GrapplerLetGo 并清理关联；使用原版已有的 Aborted 结果，而非直接私自清字段。
- removeFromWorld/removeFromSquare 负责对象与方格离场，但没有为模组自动建立“外部引用已经释放”的退场事务。

提取文件指纹、构建和产物哈希见 [机器记录](probe-0.1.2-verification.json)。

## 0.1.2 实现

### 三维移动

去掉同层硬限制，采用 16 格三维距离和有限整数目标高度检查；目标方格仍须已加载、存在地板且可用。原版路径行为负责寻找楼梯路线，不直接改 Z 值传送。

移动生命周期保存目标 Z；抵达要求距离、实际楼层和高度容差共同满足。在相同 XY 的楼下，或楼梯尚未到达平台时，不返回 REACHED。日志目标与剩余距离也包含 Z。

这只修复请求和到达逻辑，不证明所有原版/模组楼梯、翻越或跨楼层门窗都已兼容。

### 分阶段退场

1. 删除请求先标记 retiring，停止自主更新/移动，关闭本临时探针的可见性与碰撞并启用保护；继续保留原对象、方格和会话所有权。
2. 立即查找已加载角色中指向本 NPC 的追击、啃食、跟随、抓取关系，使用原版接口解除；不删除僵尸、不清空其他目标、不强制重置其状态机。
3. 只在退场期间每 100ms 核查一次。此前攻击者尚在相关攻击动画或仍有抓取关系时，继续等待；至少连续 3 次清净采样并满 500ms 后才允许物理移除。
4. 最多等待 5 秒；无法确认则返回 REMOVAL_BLOCKED、保留对象，不在超时后强行清空方格，也不无限自动重试。显式再次移除才开启新一轮等待。
5. 真正移除后才释放 probeId 和会话；期间重复生成返回已有对象，移动返回 CARRIER_RETIRING。

主要状态：`REMOVAL_PENDING` 表示已进入退场，`REMOVED` 才表示物理清理完成；`REMOVAL_BLOCKED` / `REMOVAL_FAILED` 均未完成清理。INSPECT 新增 retiring、退场阶段、已清引用数、关联攻击者数与身体健康值。

无新全局攻击补丁；未屏蔽普通玩家伤害或吞掉引擎空引用异常。其他模组可持有本轮未覆盖的私有引用，尤其带延迟动画/并行优化时，仍必须实机复测。若退出世界前退场未完成，可能保留旧会话并要求重启游戏；本包尚无完整世界卸载/存档恢复协议。

## 实际检查

- Java 构建及 61 项纯逻辑断言通过。覆盖三维距离、楼下不得到达、楼梯边界、路径结束错误楼层、攻击中等待、静默窗口被打断、超时保留、阻塞后不无限重试、显式重试和长暂停。
- 完整 preflight 通过，LuaLS 为 0 error / 0 warning；原版知识库仍有 1 个含 `0.0f` 的解析缺口，不属于本项目。
- 原始输出见 [构建/断言](probe-0.1.2-build.txt)、[preflight](probe-0.1.2-preflight.txt)。文档检查另存本地 `build/logs/0.1.2-doclink.txt`。
- 0.1.2 上下楼、攻击中移除与延迟动画兼容：**未实机验证**。MP、动作白名单、崩溃恢复和性能规模：**未验证/未实现**。

## 合并复测步骤

完整退出游戏，更新整包到 0.1.2 并确认 READY 的版本。

1. 重测空地移动；再在有正常楼梯的建筑中，分别从一楼到二楼、从二楼返回一楼。检查 MOVE_TARGET 的 Z：原版地面为 0，二楼为 1。
2. 将目标设在 NPC 正上方的另一层，确认不会在同 XY 的楼下直接报告到达。无路、未加载和超时应明确失败。
3. 分别在无人攻击、僵尸追击、正在啃咬时点击移除。观察先 PENDING 后 REMOVED；继续观察数秒，确认无攻击空方格报错。
4. PENDING 时再次生成不得出现第二个 NPC。若 BLOCKED，保留 INSPECT 和日志，不把隐藏状态当成已删除。
5. 保存/退出前等待 REMOVED，并检查 carrier=absent；本轮不承诺 JVM AOT 退出问题已解决。

通用安装和状态码说明见 [测试说明](../../testing/phase0-carrier.md)。下一个后续关口是原版吃喝/搬运动作白名单；它仍依赖本轮交互与退场复测结果。
