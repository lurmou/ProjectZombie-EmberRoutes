# P1旧制作与草稿执行接线（0.22.10）

状态：完成旧CraftProbe格式2执行/恢复、格式1原件归还及规划草稿的TaskRuntime接线。迁移总门闩仍关闭，诊断写入口及统一保存尚未完成，P1未通过。

依据：[唯一架构v1.1](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)、[P1计划](../../superpowers/plans/2026-10-23-p1-runtime-integration.md)。延续[正式制作与搬运接线](p1-labor-runtime.md)，未增加调度器、行为树框架或新的工单存储。

## 实现

- 旧run/resume/return先只读核验，再申请身体；获授后才建立执行上下文、生成台面标识并按原业务认领原件。保持原格式及Job ID；新单不接触玩家背包，格式1只归还原借用品。
- 草稿尚未进入持久记录时也有可捕获的停止适配；已存工单在恢复规划期间仍核对原件。完成、暂停与规划草稿分别保留准确代次，停止重试不重复递增。
- 移动、入队及清理使用票据body；迟到的start/动画/perform/stop不能操作继任队列。正常结束先核对交付并释放声明，再移除业务上下文，捕获的适配继续确认身体关闭。
- 停止核对复用InventoryView，在NPC、原来源和目标容器中检查唯一原件；搬运回调异常时不能只相信位置缓存。原件缺失或制作提交未知保留声明与uncertain，不自动重做。无原件效果的未发布草稿可安全退出。
- 旧自动续工改为非抢占申请，不在保存回调中启动；保留草稿/原工单Job ID，不抢新人工跟随。这里验证的是旧续工入口适配，**不是任务4统一保存屏障、读档或落盘成功证明**。

## 检查

- 安装Kahlua定向42项通过：格式2完成/暂停/同Job恢复、规划草稿中断及交接、自动续工、格式1原件归还、旧回调隔离、未知提交和原件缺失。复用的旧制作652项通过。
- 正式制作接线28项、业务停止14项、未知搬运保护及依赖的多NPC48项/动作16项/搬运54及69项通过。原生角色、库存、移动和保存仍由替身提供，不能代替实机。
- preflight通过：107个Lua文件语法/结构检查无问题，LuaLS为0错误、72条既有信息性告警，分布与上轮明细一致。原版ISFluidEmptyAction.lua的`0.0f`仍为知识库解析缺口，不产出该文件结论。
- 0.22.10构建与安装JAR基线检查通过；release-check为0错误、54条既有提示。ZIP中的9个关键Lua/JAR/mod.info文件逐一SHA256匹配工作区；version.txt、Build.lua、mod.info均为0.22.10。5份本轮文档链接无断链，定向diff空白检查通过。
- 日志：`build/logs/p1-legacy-craft-tests.txt`、`p1-legacy-craft-preflight.txt`、`p1-legacy-craft-release.txt`。新路径实机、统一保存/读档及性能未验证。

## 续接

继续P1任务3的Actions/Haul/NpcCommands/Persistence样本等诊断写入口及控制旁路清单；随后任务4统一保存、退出和StockService恢复。不得重复搭建已有Runtime或重新迁移本轮旧制作路径；不得先打开Boot.controlledExecution。

用户本轮确定：界面视觉最后以低思考处理，当前先完成底层框架。复用已有UI的Layout/State/CachedList/PageLifecycle；后续页面读取业务投影、通过同一业务命令提交，不能在页面实现NPC选择、资产结算或另建任务状态。
