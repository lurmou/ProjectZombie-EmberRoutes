# P2停止交接、观察与消费动作接入

日期：2026-10-24｜状态：协议及动作叶已接，自动生活主循环仍未实现，未交付实机包。

后续状态已推进：主循环、取还物与地面休息睡眠接线见[P2生活闭环](p2-living-loop.md)；下面保留本次协议接入时的历史边界，续接以新证据和BACKLOG为准。

继续依据[唯一架构v1.1](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)和[P2计划](../../superpowers/plans/2026-10-24-p2-self-care.md)。继承[基础实现](p2-foundation.md)，不重新选择架构，不把协议夹具视为完整NPC行为。

## 本轮完成

- TaskRuntime支持可选replaceReason，保持默认REPLACED；TaskController终结摘要保留KNOWN/UNKNOWN效果事实。世界Runtime只在身体控制已释放后发布停止回执，回执持久化失败则不推进后继。正常推进和保存收尾均覆盖，成功通知幂等。
- TaskResume先持久记录REQUESTED，核对原Job/停止原因/效果后绑定停后代次；恢复只提交原Job非抢占请求，不重新领取公共额度。QUEUED不等于恢复完成，直到实际start或有已启动任务的终结回执才确认。pending被保存取消后保留恢复义务。
- 显式命令epoch与Companion内部模式版本分离。客户端启动安装协议；跟随、人工制作/搬运、暂停/停止/移动等已接受指令作废旧恢复意图，非抢占自动恢复不递增epoch。
- TaskPersistence加载时恢复持久停止关系；保存事实包含实际started证据。LaborStore暴露真实读档代次增量，仅凭该证据重映射搬运恢复代次，不把任意新generation当合法。BLOCKED保存回执禁止自动自理申请/恢复。
- NeedsObserver只读原生HUNGER/THIRST/FATIGUE/ENDURANCE及有界可见危险；接口/数据缺失或观察超限为未知，可见近邻活僵尸、受攻击、着火和近期掉血阻止普通自理。尚未接自动采样循环。
- SelfCareResources支持个人主包/有界嵌套包和有权限的据点仓储增量查找，每步计入调用方预算；生产托管原件排除，恢复查找可指定自己的ownerId。拒绝危险食物、污水/混合流体、诊断夹具及需要额外点火物的候选；改变库存尺寸、目标未加载和无物资分别返回，不把未知当空。候选授权前须重验，个人包被移出NPC库存也不能继续使用。
- SelfCareActions提供原版ISEatFoodAction和ISDrinkFluidAction消费叶，按当前会话及attempt隔离每实例回调；派发/原生start前持久记事实，完成/中断后核对真实剩余量。重复完成、过期停止、不同attempt的旧证据、未知消费恢复均不能重复扣物。原生副产物按真实新ID观察，调用方未能接管声明就隔离为UNKNOWN，不按类型补造。

## 重要边界

本轮未实现SelfCare自动主循环、仓储取还原件叶、耐力休息及疲劳睡眠，也尚未接监控/个人义务移除门禁；现有NPC不会仅因这些模块存在而开始完整自主吃喝。消费叶当前只由宿主夹具调用，正式上下文仍需补齐。

正式上下文的sameAttempt负责world/job/attempt身份，valid负责执行权限，不能把预期的食物耗尽当作会话失效；persist必须保留当前已更新的恢复引用/命令epoch，不能用旧闭包payload覆盖用户新指令。claimOutputs须把原生新增实例声明并持久归账。主服务需在消费/取还物后明确释放、归还或保留义务，不能只让树返回Success。

原生接口核查使用当前安装Lua及JAR，JAR SHA256仍为`E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`。检索确认getSurroundingAttackingZombies重载、Food危险/腐败字段和原版消费生命周期；未改安装文件。不会把这些静态事实扩写成原生睡眠或完整自理已实机通过。

## 验证

- 安装Kahlua：运行服务48、个人恢复/命令/保存窗口23、观察/资源预算12、消费叶11项通过；消费/世界原生宿主为替身。日志build/logs/p2-task-runtime-test.lua.txt、p2-self-care-resume.txt、p2-self-care-observation.txt、p2-self-care-actions.txt。
- 受影响既有控制器28、保存61、启动30、随从20、制作55、搬运21项通过；基础34项仍通过。仅按相应夹具实际输出记账，不将下层累计断言当新P2用例。
- preflight本轮运行通过：137个部署Lua，解析/结构0错误，LuaLS0错误/172信息警告；日志build/logs/p2-handoff-preflight.txt。随后对最后修改的6文件以及消费叶执行单文件静态检查，0错误；最终整组交付门禁仍须覆盖届时全部最终文件。原版ISFluidEmptyAction.lua的0.0f语法覆盖缺口仍存在。
- 未运行游戏、未构建新包、未改Java或版本号；并行UI/生产改动保留。

## 准确续接点

1. 实现SelfCare主服务：低频/事件观察、共享扫描/节点预算、候选可执行后才中断、持久例程及prepare/confirm协议接Session；不要重新实现本轮模块。
2. 实现原件取还叶与副产物声明，原版转移须避免真实玩家槽UI访问，复用既有WorkTransfer已验证边界。挂起可保留义务而释放身体，不能永久冻结NPC。
3. 将消费叶串入小型BT并接TaskPersistence/Boot生命周期、个人义务删除门禁和可读监控。完成工作→吃喝→同Job/跟随恢复的实际业务夹具，再做耐力休息与原生睡眠。
4. 安装原生睡眠仍需独立核查受控入睡/醒来/姿态清理，不能用当前move/queue stopMask冒充；故障和未验证情况如实记录。最终交付一个集中实机版本，不逐模块要求用户测试。

自动续接保持启用，用户无须重复批准实施；代码、必要检查及交付完成后停用，不提前记P2完成。
