# P1任务3第一部分：业务停止适配

2026-10-23，0.22.7。已加入业务stopAdapter工厂和停止/效果保护，尚未加入统一启动服务；不是任务3全部完成，不是正式业务已切换managed控制。

## 新增职责

client/EmberRoutesProbe/TaskBusinessStop.lua复用TaskController协议：仅持有匹配npcId/jobId的STOPPING票据且可观察当前身体的适配器可以调用业务暂停；暂停先使业务效果闭包失效，再请求受控原生停止。observeStop同时检查nativeStopped与原版ISTimedActionQueue.queues[npc]的queue/current；队列服务缺失视为未知，不把缺数据当作空队列。效果由业务提供，持久事实/义务写入明确成功后才允许Controller释放Java授权。

已读取当前安装原版client/TimedActions/ISTimedActionQueue.lua：addToQueue在首项加入时立即begin，因此不允许在旧停止回调栈中授予新任务。新适配器自身防同步停止重入；Record/world/generation变化时拒绝旧暂停及效果写入。

业务接点：

- Production.stopAdapter(id,controller,ticketGetter)：捕获当前context/record/world，调用现有pause使代次/回调失效；保留COMMITTING/uncertain，UNKNOWN写RECONCILE_REQUIRED，保留原件与已确认产物。
- CraftProbe.stopAdapter：format3委托Production；旧持久制作单走自己的暂停协议；没有持久record的草稿不获得伪恢复权。
- Work.stopAdapter→WorkAgent.stopAdapter：停止后重验源/目标端点，使用现有InventoryView在源箱/NPC/目标箱定位全部原件ID；缺失/观察不完整写controlUncertain和RECONCILE_REQUIRED，launch拒绝该记录续工。既有原件Claims保留，不能伪造交付数量或释放找不到的物品。该状态未提供自动清除捷径。
- Companion.stopAdapter(id,controller,ticketGetter,persistIntent,jobId)→CompanionAgent.stopAdapter：先捕获标量恢复意图，取消策略并停身体；调用方必须提供persistIntent，明确记录成功才释放，不把HOLD状态当成原跟随意图。intentRevision隔离迟到回调。

这些工厂无自动调用者；当前启动/推进仍是旧流程。不得在启动适配、动作入队授权、自动续工及保存恢复尚未收敛前，自动给现有业务授予managed身体许可。旧pause中的直接队列操作仅在未来适配器确认拥有STOPPING上下文时可使用；普通旧入口的旁路收敛尚未完成。

## 检查与边界

task-business-stop-test.lua 14项覆盖所有权、fence先于stop、Lua队列/current与native状态联合观察、UNKNOWN义务、过期记录、观测缺失、部分停止异常。task-transfer-uncertain-test.lua验证真实WorkAgent.resume拒绝controlUncertain记录。

安装Kahlua同时通过控制器28项、Driver桥接、随从36项、多NPC48项及制作累计652项相关回归；原生身体、读取接口和保存仍使用宿主替身。原始输出build/logs/p1-business-stop-tests.txt；未知搬运保护另有独立命令输出。构建0.22.7及发布检查通过（0错误/54条既有提示）；preflight日志build/logs/p1-business-stop-preflight.txt，preflight全部通过（LuaLS 0错误/72条信息性警告），不宣称零警告。最终压缩包8个相关Lua模块哈希与源码一致。

用户本轮提供的[原版机制对齐记录](vanilla-engine-interface-alignment.md)已读取。医疗两阶段及其他业务决定用于后续P2/P4/P5，不在本轮顺带实现；记录中的接口、绝对时间及碰撞策略并不因设计获认可而成为已实测证据。

## 续接位置

[P1计划任务3](../../superpowers/plans/2026-10-23-p1-runtime-integration.md)尚需：世界级运行服务、各业务启动/推进的申请及dispatch、动作入队/清队列上下文、Debug旁路、自动续工候选。再完成任务4保存恢复后，才可启用全员managed与集中实机测试。本轮没有公共任务池或新医疗行为。
