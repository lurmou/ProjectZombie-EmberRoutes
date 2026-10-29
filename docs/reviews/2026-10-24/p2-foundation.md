# P2基础接入与准确续接

日期：2026-10-24｜状态：基础代码已实现，生活运行闭环未接通。

用户已明确授权后续自主判断完成P2，不再重复询问实施批准；参照[唯一架构](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)及[实施计划](../../superpowers/plans/2026-10-24-p2-self-care.md)。当前仍为单人，未宣称联机、睡眠或P2玩法通过实机。

## 已实现

- TaskJobs：按Registry.data世界身份共用唯一JobStore运行实例。BusinessJobs改经该服务，加载/flush只处理CRAFT/HAUL，不替个人记录推导状态。
- JobStore：普通记录保留既有512条上限；SELF_CARE独立上限256，每NPC只允许一条持续自理例程。例程内用sequence/attemptId隔离尝试，平时挂起不占身体，不为每口食物新建Job。记录仍在唯一taskJobs根表，不创建公共Order，不删除劳动历史。PublicWork统计普通容量时排除个人例程。
- SelfCareRecord：初始封套、步骤/种类/声明列表验证；新尝试要求IDLE、效果已知、无未结义务或声明，不覆盖待核对消费。尚无自动创建或运行消费者。
- LaborStore：生活原件和设施稳定键共用已有claims，读档同轮重建；跨NPC争同原件拒绝，UNKNOWN/未结义务不得释放，token受世界/attempt代次隔离。
- BehaviorTree：记忆Sequence/Fallback/Condition/Action/Subtree、有界推进、非法结构/环/节点复用拒绝、清理等待和停止入口；完成叶缓存结果，清理等待不重复执行。
- NeedsPolicy：纯阈值/滞后、已知可执行候选及安全上下文过滤，原生需求满足判定；尚无游戏Stats观察消费者。

容量细化把自理定义为长期个人维护例程，具体吃喝为其执行尝试，不改变Job/Session/Claim分责。NPC退役前不终结后复活；未知attempt须先核对，不能推进sequence覆盖事实。不承诺每口食物永久审计，已有劳动历史原样保留。

## 实际验证

安装Kahlua新增p2-foundation-test.lua共34项针对存储共享、个人/普通容量、劳动投影、原件争用/释放及读档不复活、世界退役、树清理防重放、纯需求仲裁通过。日志build/logs/p2-foundation-kahlua.txt。受影响既有JobStore22、公共协调44、受控制作55、搬运控制21、保存编排61项通过；下层累计数字不能当P2实机数量。

初次preflight误用仓库根，扫描了build研究/测试夹具，因既有package全局替身报错失败；部署Lua结构和LuaLS（0错误/169信息警告）通过，未修改旧研究样本来掩盖结果。已按正确模组根重跑，日志build/logs/p2-foundation-mod-preflight.txt；最终结果以末尾及退出码确认，未完成不写通过。未运行游戏、磁盘故障或性能测试；未改Java、版本或发布包。并行UI/生产改动保留。

## 准确续接点

后续已推进停止回执、恢复/保存窗口、原生需求/资源观察及消费叶；以下原始续接点的最新状态以[本轮接线记录](p2-handoff-and-consumption.md)为准，勿重做已实现部分。

1. 核对模组preflight完成结果，当前统一执行session为15470，原始日志build/logs/p2-foundation-mod-preflight.txt；处理新增模块诊断，不重复无关历史全套。preflight启动后的TaskJobs根表替换检测、个人声明持久清除做了2文件静态lint及34项回归；最终交付门禁须覆盖最终文件。
2. 实现TaskResume持久REQUESTED→停稳回执→STOP_CONFIRMED→RESTORE_PENDING及显式命令epoch。TaskRuntime替换原因仍固定REPLACED，尚未接SELF_CARE；须覆盖pending被保存撤销窗口。
3. 接NeedsObserver低频Stats/安全观察、有界SelfCareResources，资源可执行候选形成后再中断；未知不派发。
4. 实现SelfCare和原版吃喝/耐力休息/睡眠适配、个人库存与仓储取用/归还，BT是唯一微观运行器。当前未实现，不能因BT文件存在标生活闭环完成。
5. 接TaskPersistence、Boot、个人义务移除门禁及监控；工作/随从回原Job/上下文，用户新命令作废旧恢复。
6. 睡眠核查授权和唤醒/姿态清理；现stopMask不含睡眠，不能充作完整停止证据。按改动构建/门禁并交付一份集中实机说明，未运行写未验证。

本聊天自动续接emberroutes-p2已启用，持续推进上述任务，只通知实质进展/失败/可验收交付；P2代码、检查和交付说明完成后停用，不归档聊天，不重复请求批准。
