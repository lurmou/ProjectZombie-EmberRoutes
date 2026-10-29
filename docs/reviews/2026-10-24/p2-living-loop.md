# P2 自动生活闭环接线

日期：2026-10-24｜版本：0.24.0候选｜状态：运行代码已接，整组游戏验收未运行。

依据[唯一架构v1.1](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)及[P2计划](../../superpowers/plans/2026-10-24-p2-self-care.md)，接续[停止交接及消费基础](p2-handoff-and-consumption.md)。个人自理没有公共Order；持续例程及其attempt仍保存在唯一JobStore，真实原件仍由LaborStore裁决。

## 实现

- SelfCare在Boot的Runtime推进前采样/仲裁，随后公共派工才运行。每200ms轮转最多4人，每人需求采样至少间隔1000ms；每游戏tick共用16节点、32扫描、1新寻路预算。跟随时仅找个人物资，可短暂恢复耐力；长睡眠只在HOLD上下文提供。工作暂停后的跟随上下文取持久恢复引用，不能因内部HOLD误回仓库。没有合适水时冷却该候选，可评估已有食物。
- 有可用原件才持久准备中断与声明，随后提交同一TaskRuntime。停止回执核对后才授予生活身体，临时树串取物、原版吃喝、效果核对和归还；未开始的拒绝/取消释放未生效声明，保留真正已停原工作的关系。连续吃喝不会清掉原任务引用；恢复只重启同一Job/跟随意图，不重新领公共额度。
- SelfCareCustody复用WorkTransfer原版转移动作和寻路叶；个人嵌套包转入主包有单独的所有权条件。公用物资剩余、原版产生的空容器按原ID归还；原箱过滤/容量不适合时，复用CraftSupply/SortPolicy选择同据点适合仓储，并先持久记录实际目标。不能归还时留待归还义务、释放身体、允许原工作恢复，阻止另领普通工作或删除载体。本人已有物资仍由本人保管。
- 原生消费前后核对原件数量，并记录需求前后快照；渐进饮用及停止时的部分消费都不回滚。两次原生回调之间的外部数量改变进入UNKNOWN，不把它归因为本次吃喝；原生EAT的部分停止效果也受此隔离。消费已知完成后，合法归还到箱子不会被错判为“物品不在背包”。未知效果不重放。
- SelfCareRepose只观察原生ENDURANCE/FATIGUE。Driver→TaskController的身体能力→Java reposeWithControl控制入睡、休息和退出；不直接写固定恢复量。当前实现为**地面回退**，拒绝车辆内/已坐家具的载体；未实现寻找床/沙发及家具占位。保留将来设施能力接口，不把此项写成已完成。最多8游戏小时无达标即停并冷却，不无限持有身体。
- ProbeNpc停止位图增加睡眠64、休息128。睡眠自身保持合法当前Session；交接、保存、退役必须实际醒来、清休息及床引用，不能凭移动/动作队列为空释放。调用原版SleepingEvent的初始化/醒来部分，跳过玩家菜单回调；不在本模块调用UI淡入淡出、全局加速或自动保存。
- 已接Boot/reset、TaskPersistence恢复链、Work移除门禁和普通工作禁领。当前睡眠/吃喝的停止事实与挂起劳动同根保存；ACTING却没有已停事实的读档记录隔离为UNKNOWN。另修Runtime同步capture：身体已关闭而回执尚未持久化时，在本次保存栈补齐，不等保存后的tick。人员与原劳动监控显示自理状态/暂停原因，CN/EN成对；没有新增自理工单卡。

## 原生依据

当前安装PZ42.21.0 JAR SHA256仍为`E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`；ZombieBuddy2.3.4。ISEatFoodAction、ISDrinkFluidAction及ISInventoryTransferAction直接核查安装Lua。ISRestAction的开工/退出使用isResting及bed字段，但nil家具路径还含面朝对象调用；本次地面耐力休息使用其底层受控原语，未将坐下动画当耐力完成。

JAR的IsoGameCharacter.calculateStats调用原生睡/醒统计分支，IsoPlayer.updateStats_Sleeping处理疲劳恢复；SleepingEvent.wakeUp的UI/速度/自动保存分支受isLocalPlayer保护，ProbeNpc恒为false。安装的PZ Optimization覆盖JAR SHA256为`BCE7EA210FC5C5392CA691A14345D90131B1D664D4D8A1876600A1AC46FD1D3D`，其updateStats_Sleeping去除常量池编号后的javap方法与游戏JAR相同；输出在build/research/p2-sleep-override-comparison.json。这些属于源码/字节码证据，**不是无玩家槽位NPC睡眠实机原型通过**。

## 验证与交付

最终原始输出位于build/logs/p2-delivery-regressions.txt、p2-delivery-preflight.txt、p2-delivery-release.txt、p2-0.24.0-build.txt及p2-0.24.0-doclink.txt。宿主测试的世界、库存及原生动作使用替身，不能据此宣称睡眠、原版保存或性能实机通过。

已完成的定向结果：个人树/取还/真实Runtime交接20项，自动仲裁9项，休息睡眠10项，消费叶13项，恢复协议23项；运行/保存窗口55项及既有保存61、控制器28、启动31、生命周期15项通过。原件归还失败、空容器、替代分类仓储、原任务恢复、玩家覆盖、部分消费、睡眠旧回调与保存收尾均有对应宿主覆盖。基础34、观察/授权前包归属15、公共派工44及监控22项通过；受影响制作55和分类路由20项通过，不将旧夹具下层累计断言重复当作新P2覆盖。

0.24.0 Java构建及构建脚本内相关逻辑/基线/编解码测试通过；release-check为0错误/44条既有中文提示，文档链接6文件0断链。**最终preflight通过**：部署141个Lua，解析/结构0错误，LuaLS0阻塞错误/181信息性警告；原版ISFluidEmptyAction.lua的0.0f解析覆盖缺口仍如实保留。最终源码已冻结并与候选包逐项核对。

候选包build/packages/EmberRoutesProbe-0.24.0.zip的SHA256为`E9C175B3F88F93B22EC86C274214E6989C5947C7766DBB268DBD063966FD3BB2`，JAR为`4F374B150296BE3C11D6A59B4EA4F6B7FDBA375D92B7DC0D563DE30FFC26DB78`。独立逐项核对归档148个文件与当前部署原件，0不一致；摘要在build/research/p2-package-content-check.json，不以仅有压缩包文件名作为交付证据。

集中游戏步骤仅维护[一份P2验收说明](../../testing/p2-runtime-acceptance.md)。需要完整重启加载新Java接口；不按内部模块分别发测试包。暂不提交混有并行UI修改的整体Git提交，未发布工坊。

本轮代码、必要检查与交付说明已完成；自动续接按原约定停用，等待集中游戏结果，不自行扩展下一阶段或把未测原型登记成通过。

**未验证/未实现边界：**游戏里的完整工作→吃喝→恢复、无槽位睡眠疲劳下降及醒来后再次动作、正常保存重进与玩家界面影响仍未验证；床/沙发选择未实现。多NPC规模/响应性能、磁盘故障、强退事务、MP均未验证。基础代码接通不等于P2实机验收完成。
