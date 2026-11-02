# 搬运/配送读取计算下沉 Java

日期：2026-11-02；phase-3a-consolidation@eb65db6 加本会话0.29.23工作树；候选0.29.24。用户要求能用Java的优先Java，并指定参考ProjectRemnants（projectrename）。本轮落实当前搬运/配送的计算路径，不宣称所有领域全部改写完成。

## 参考核对及方案取舍

只读参考根目录 D:/Project/ProjectRemnants/NPCFW.jar，SHA256：5229EB5A6871514DE274FEB91E8DB353FDBDE8FB42FD9741493D40CDE85BA19E。_decompiled/v2 只导航；使用当前根JAR的 javap -p/-c 核对类、方法及关键调用。

- SafehouseHaulerJob.tickPlan：Java内选择批次原件、移动源/目标和推进FETCH/DELIVER。
- ensurePickupTransfer/ensureStoreTransfer：当前JAR实际调用 NPCItemTransferExecutor.takeFromContainer(List,ItemContainer)/storeInContainer，构建Java任务后送其TaskRunner；不是仅因为目录里存在Java类就认定已接入。
- reservePlan、finishPlan、cancel/clearPlan 是参考创建/释放/异常入口；其任务与存储模型不等于本项目的Job/Claims/Session，也不是实机验收证据。
- 当前参考仍存在对 NPCFW_queueCorpseGrab 等Lua桥的调用，不是所有能力都位于Java。

比较：保留逐物品Lua读/匹配，跨语言调用随物品数增长；复制参考TaskRunner/独立转移执行，会产生第二身体与效果权威；本轮选择独立实现Java批量计算，保留现有物理效果协议。借鉴职责，不复制参考代码或修改参考项目。

## 实际下沉范围

- InventoryIndex.begin/step/index：接管InventoryView的分帧扫描、集合身份/大小校验、重复ItemID索引与原件引用输出。保留单容器2000件与SCAN_PENDING/INVENTORY_CHANGED/INVENTORY_SCAN_LIMIT语义，不创建世界级缓存。
- DeliverySelection.scan：一次桥接扫描一个来源切片，Java内完成物品元数据读取、请求匹配、当前Claims owners排除、保护物品判断、实际接收容量/负重与跨箱累计。请求建立派生HashMap索引，避免对每件物品重扫整张清单。
- DeliverySelection.received：Java纯函数投影已确认收货，指定来源优先、逐原件只计入一条请求。
- ProbeRuntime暴露上述接口；InventoryView/DeliveryService生产调用已接，不是仅增加未使用Java工具。
- Lua仍拥有来源端点政策、注册扩展、订单提交、唯一Job/Claims提交、原版TimedAction适配和停止/恢复。未迁入参考的NPC/TaskRunner/库存写操作。

## 所有权与生命周期

库存索引和请求HashMap属于调用方临时scan state；无静态按NPC缓存，无第二持久root。原件引用仅用于观察，不认领或转移。请求索引放在现有scans的临时表内，不能写入Job/ModData；世界切换、取消与Delivery.reset沿现有路径丢弃该表及Java派生对象。

创建/认领仍为 DeliveryService.claim → Work.assign → HaulJobs.claim → 既有Claims/Job提交；正常清偿仍为 HaulAgent.knownTransfer → settleHaulLines；异常仍为 stopAdapter → TaskBusinessStop/领域恢复。Java scan不释放或创建任何声明。

使用现有唯一Claims owners作为可信内部只读输入，避免每个候选再跨语言调用Store.owner并复制owner快照。它只是观察，真正认领仍由Claims裁决。

普通物品无需逐件Lua回调。InventoryReads.eligible 遇ModData元表返回未决时，仅将该件交回Lua的Producers.eligible求值，再继续Java扫描；不把元表字段强行rawget为可用。无Java桥的独立宿主/兼容路径保留现有Lua实现，Java执行异常不自动回退重试。

## 证据与边界

- javap 核对安装JAR的ItemContainer/InventoryItem/KahluaTable接口，使用现有InventoryReads的真实原件与元表契约。
- InventoryReadsTest 36项实际ItemContainer/Kahlua检查通过，包含新分片预算、原件位置、集合改变、跨容器重复ID与来源收货计数。
- delivery-service-test 55项、work-transfer-continuity-test 8项通过。旧替身不提供本轮Java扫描桥，因此主要覆盖Lua兼容路径和业务协议，不能宣称已经验证真实NPC的Java选货容量执行。
- Java新类单独编译及完整构建通过；347份Lua普通/Debug编译、CN/EN键集通过；候选包363文件逐项哈希与工作区一致。4份文档引用零错误、git diff --check无错误。末次虚拟属性布尔归一修订补双模式编译并重打包，build报告ZIP哈希同步。
- 没有重跑完整回归或全库LuaLS/preflight；仅必要检查，实机由用户确认。

可由代码确认的是逐物品Lua循环/JNI往返减少，不是实测帧率提升。真实NPC选货、连续动作、正常保存重进与规模性能未验证。Java更改需要完全退出并重新启动游戏加载新JAR。未提交、推送或上传工坊。
