# P2实施计划深度评审

日期：2026-10-24｜状态：原稿需修改；不涉及总体架构重新选型。

评审对象：[P2实施计划](../../superpowers/plans/2026-10-24-p2-self-care.md)修订前稿（Task1～5）。原稿只读副本为`build/research/p2-plan-before-review.md`，SHA256为`007FE87BEB3058AC0E71372E0FE56EC66099B1A44445DF98868EAD0816130DDB`。本轮仅评审及修订计划。依据仍为[唯一架构v1.1](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)及其[统一任务细化](../../superpowers/specs/2026-10-23-unified-task-dispatch-design.md)。

## 结论

总体分层和“自理不建公共Order”正确，原实施计划尚不能直接照写。发现六项P1实施风险和一项P2问题；修订计划应把共享账本单实例、历史容量、持久交接、睡眠能力、原件生命周期及自理准入写成具体契约。不是要求建设另一个调度框架。

## Findings

### R1 [P1] 必须共用一个JobStore运行实例，不能仅共用根表

原Task1只规定SELF_CARE封套，没有规定SelfCare和BusinessJobs如何获得同一个存储实例。当前JobStore.open每次创建私有count/byNpc，BusinessJobs长期缓存自己的store。如果自理另外open同根表，新增Job不会进入另一个实例的索引和计数，可能超限写入、下次读档直接拒绝。

已在安装Kahlua实测：两个实例先后打开空根，第一个创建记录后第二个forNpc仍为空；第一个达到512条后第二个仍可写第513条，随后open返回JOB_LIMIT。证据脚本为`build/research/p2-plan-review-probe.lua`。修订：增加世界级TaskJobs访问服务，所有正式消费者从同一实例create/get/update/forNpc；不能只把BusinessJobs的类型检查删除。

### R2 [P1] 每次自理新增永久历史会耗尽生存行为的准入容量

原Global Constraints明确不删历史、512满后拒绝，同时Task1/4按一次自理建Job。当前JobStore把DONE/CANCELLED计入count且终态不可复用。已实测512条DONE、无任何未结义务后，第513次自理仍被JOB_LIMIT拒绝。不是仅工作列表变长，而是随后喝水、休息也无法启动。

修订：历史容量策略提升为Task0门禁。必须明确是否拆分活动容量与保留历史，或采用经明确批准的有限历史策略；不能在实现中偷删记录、复活终态Job、抬高常数或换平行账本绕过。当前尚无长期容量方案的批准依据，本轮不能宣布此项解决。

### R3 [P1] 恢复引用必须覆盖中断尚未完成就发生保存的窗口

原Task3只有capture/resume两个接口，却要求“停止后的业务代次”。当前Production.pause会增加generation，Work暂停也更新声明代次；Companion的intentRevision随运行模式变化，exportState不导出该值，不能直接当持久玩家命令版本。TaskRuntime.submit入pending后立即请求停止旧流程，beginSave又会撤销pending。若恢复引用仅放pending或到自理start才保存，旧工作已暂停而生活任务未启动时保存，就可能丢失续工义务。

修订：中断申请前持久写REQUESTED及原身份；停稳/效果保存回执后写STOP_CONFIRMED和停后代次，再授予生活Session。取消候选、准备失败和保存要保留这条关系。单独维护显式命令epoch，用户暂停/取消/跟随/停止/移动覆盖旧恢复意图；不能每次setMode都递增此epoch。恢复始终非抢占、同Job、不重新认领公共额度。

### R4 [P1] 睡眠不能只复用现有move/stop与动作队列停止证据

原Task4把原生睡眠查证排在已有三项任务之后，修改范围却只写Boot和必要时ProbeNpc。当前ProbeNpc.stopMask只含移动/路径/原生动作队列，不含isAsleep、isResting、家具状态；stopProbe未显式唤醒。原版ISTimedActionQueue.add对isAsleep角色直接返回。按现有“队列空且移动停止”判定交接，可能给仍睡着的NPC授予制作Session，随后原生动作根本不入队。

修订：睡眠原型移到Task0，明确带授权的入睡/唤醒路径和动作类别停止证据，必要时修改Driver、TaskController、Java受控API及ProbeNpc，而非只改叶子。普通睡眠期间isAsleep是预期运行状态；交出身体前则必须确认清醒及原生姿态可以启动后继动作。仅扩大通用stopMask而不处理睡眠主动状态，也会让睡眠自身被误判故障。

安装JAR进一步确认SleepingEvent.wakeUp的玩家淡入/加速/保存分支受isLocalPlayer守卫；当前ProbeNpc覆写为false。这比“一切原生唤醒都不可用”的推断更准确，但仍不证明完整NPC睡眠已实机可用。不得自行重写固定疲劳结算代替原生机制。

### R5 [P1] 生活原件的终结、移除与故障恢复必须接入已有生命周期

原Task4只有泛称“收尾”，没有说明从箱子借出的半份食物、剩水瓶、消费产生的空容器由谁保管、什么时候释放声明。原Task5也没有新增NPC移除门禁。当前NpcCommands移除主要依赖Work.prepareRemoval和诊断恢复记录；自理停稳后若携有待归还物或UNKNOWN，仅身体空闲不足以批准移除。

修订：每次取物前写原件来源、已接管状态及处置策略；保留/归还/转交逐项核验，未归还可保留独立义务并释放身体，但不能静默丢掉声明。把自理义务接入NPC移除、死亡/失联、world reset及保存恢复。玩家或其他模组已改变原件时记录事实，不能按类型补造；不以永久冻结整个NPC作为唯一故障处理。

### R6 [P1] 个人候选应先有可执行依据，再中断工作，并明确安全观察来源

原Task2只列四项Stats，NeedsPolicy却接context过滤安全；安全事实、时效和动作中重新失效均未定义。原Task4又把找资源放在树里，而树须先申请替换身体：如果无食物、资源未加载或被别人认领，就可能先打断生产再找不到资源，反复中断/恢复。只写“安全食物/水”也不足以约束原生动作的附带输入，例如ISEatFoodAction.start可能消耗点火物。

修订：只读、有界发现先形成允许/拒绝/未知及候选版本，确认至少一个可用目标后才提出普通自理中断；身体授予后再权威重验并声明。明确可观察危险、安全快照时效、跟随允许范围、期间安全失效的停止路径；安全未知不启动低优先级生活动作。明确食品/流体白名单、所需附带物和每次消费量，首版可拒绝需额外开封/点火的物品，不能自动借用托管工具。无资源时等待条件变化，不循环抢身体。

### R7 [P2] 树结构非法与预算耗尽不能统一返回Running

原Task2把“深度/推进预算耗尽保持Running”合在同一用例。深度超过固定上限属于结构无效，下轮仍无解；持续Running会永久占身体。另有每次16节点/32物品的预算，但未定义跨全部NPC的合计上限；若各执行器各拿一份预算，就与唯一架构要求的全局有界工作不同。

修订：树构建时验证深度/环/节点类型，非法树拒绝准入或经安全停止终结；只有本轮可恢复的时间/步数预算用尽才返回Running。明确观察使用现实时间节流、Stats随游戏时间自然变化；预算不足不推进失败冷却，不调用Fallback，不提前释放声明。全局扫描/节点/寻路分别共用计数，记录最坏轮转等待而不宣称支持某NPC规模。

## 验证边界

- 当前安装JAR SHA256仍为`E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`。
- 本轮重新读取在线需求文本，SHA256仍为`1E802DFE03A43437C77DC8EF5D04A2E38EC9AE9970A71D349B302B9EFE2EFB08`。只读缓存为`build/research/requirements-2026-10-24-review.txt`。
- 存储两项问题通过实际JobStore模块与安装Kahlua复现；没有使用原生身体或磁盘保存。
- 原版Lua核对了ISEatFoodAction、ISDrinkFluidAction、ISRestAction、ISTimedActionQueue；SleepingEvent新增javap输出在`build/research/p2-SleepingEvent-javap.txt`。
- 未修改运行源码，未构建、未运行游戏，未重跑无关全历史夹具。当前并行UI/生产改动原样保留。

## 收口要求

已修订实施计划，添加Task0原生能力及历史容量门禁，并把R1/R3/R5/R6/R7的接口和定向用例加入对应任务。R2仍需明确容量政策、R4仍需原生原型证据；修改计划不能自动把这两项写成已验证。总体架构保持v1.1，自理不进入公共工单池的决定不变。BACKLOG中已有并行UI优先事项保持原记录，本次计划评审不等于启动P2运行实施或改变其他工作的交付顺序。
