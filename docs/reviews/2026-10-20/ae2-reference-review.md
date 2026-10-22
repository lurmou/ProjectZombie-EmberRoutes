# AE2定向源码评审：仓储、调度与制作

日期2026-10-20；用户指定本地D:/Project/Applied-Energistics-2-main，只读评审。已核读21个源码/基线文件，未复制实现、未修改AE2或EmberRoutes生产代码，0.9.0不变。没有运行AE2构建、Minecraft测试或性能测试；下文区分源码事实与PZ适配建议。

## 可追溯基线

目录名main不能证明上游最新版本。Git命令对该目录访问被拒绝，未取得commit，不为此提权或改动权限。gradle.properties配置Minecraft26.3、NeoForge26.3.0.43-beta、Java25；这是该目录配置，不代表PZ兼容性。逐文件SHA256见[基线清单](ae2-source-baseline.json)，21文件集合摘要86FBD06D3EAC17BEF6301BDF34DA40D9857C0D7084CDF139F78ADBAE8FC88EAE。

源码路径均相对于上述AE2根目录；方法名用于定位，哈希约束具体结论。EmberRoutes现状依据[仓储契约](../../settlement-storage-architecture.md)和[0.9.0记录](probe-0.9.0-warehouse-contracts.md)。

## 源码发现与适配判断

| 源码事实/定位 | 借鉴价值 | PZ适配与实施时机 |
|---|---|---|
| me/service/StorageService.java：onServerEndTick、updateCachedStacks | 有观察者时每tick汇总存储，比较新旧数量；无观察者则标记缓存需更新，访问时惰性构建。该版本不是全程纯事件增量计数 | 借鉴按需生命周期，不照搬每tick全网汇总。我们保留变更失效、有界盘点、手工刷新兜底；同类游戏频率不能直接移植 |
| me/helpers/InterestManager.java：按AEKey映射订阅者，另有全量观察者集合 | BOM/阈值工单只关心少数物资时，可按需求类型通知 | 等真正有生产消费者时增加类型兴趣索引；仓储UI需要全量视图，当前无需再造一套订阅框架。来源卸载应表达未知，不能简单发“库存归零” |
| StorageService：cachedAvailableAmounts与公开cachedAvailableStacks分离 | 外部误改公开缓存不应污染内部差分依据 | 当前候选API已返回副本，但watch快照仍依只读契约共享；开放第三方订阅前应分离内部账量与外部快照或施加隔离。此为当前扩展边界，不声称0.9.0已有强制不可变保护 |
| StorageService.ProviderState：mount/unmount防重；NetworkStorage：挂载变更排队，mountsInUse防重入，遍历时跳过待卸载者 | 生命周期与遍历期间结构修改独立处理，避免“单线程就没有重入问题”的误判 | 将来多工单/仓库提供者动态接入时，在推进边界提交增删，失效先撤销可用性；每次物理效果仍经Registry.revalidate。现在不为假想网络拆分造通用图系统 |
| me/storage/ExternalInventoryCache.java：逐槽比较旧/新GenericStack，并处理槽数减少 | 兼容外部库存时缓存差分要处理替换、移除和容量变化 | PZ容器是实例列表，移除可能使位置整体移动，不能把数组下标当稳定物品身份。将来兼容事件不完整的容器采用低频、有界复核，仍按item ID归因；不凭条目数量不变推定内容未变 |
| NetworkStorage：按优先级分组，插入同级先首选存储再其他，提取方向相反 | 分拣规则、优先级和实际容器实现分开 | 自动分拣前先做权限/接收规则排除，再考虑策略优先级及物理路径、容量等；这些是候选策略，非当前批准的具体路由算法。AE2瞬时网络插拔不包含NPC行走成本 |
| me/service/TickManagerService.java：按Level分优先队列、nextTick到期处理，SLEEP/FASTER/SLOWER/URGENT调频 | 大量低频设备无需每帧逐一检查是否到期 | 多NPC/生产任务达到实际规模后采用到期队列与事件唤醒；当前活动仓储作业有界轮转即可。队列本身也须有每次推进预算，不能因“都到期”集中执行 |
| crafting/CraftingCalculation.java、CraftingPlan.java、inv/*SimulationState.java | BOM规划、分支模拟、缺料、实际使用量和产物可与执行分离；子状态可应用差分 | 后续制作阶段采用计划DTO、输入匹配规则、缺料说明、循环/替代配方边界及取消协议。当前fullType汇总仅作搜索/候选，实际配方还要按耐久、新鲜度、自定义状态等逐实例匹配 |
| inv/NetworkCraftingSimulationState.java：玩家启动规划重新读库存，其他请求可用缓存；注释明确后台模拟线程不能访问世界，否则可能死锁 | 规划快照的新鲜度与世界访问线程边界应明确 | PZ先在主线程有界取得标量快照，再做纯规划。当前不把ItemContainer/IsoObject/InventoryItem交给后台线程；是否有并行必要须先测，不复制Java线程wait/notify方案 |
| execution/CraftingCpuLogic.java：提交时tryExtractInitialItems；ExecutingCraftingJob跟踪tasks、waitingFor；执行有操作预算；取消后storeItems保留未插回余额 | “计划成功”不等于“已实际拿到材料”，任务/等待产物/货物占有需分别记录 | 生产提交时重验或预留原物品，动作与产物实际核对后推进。NPC取消后保留/交付真实携货，容器满、卸载和失败不得清空占有账来假装回滚 |

## 必须避免的误读

1. API里的SIMULATE只表示该操作不提交，不等于预留、更不等于存档事务。AE2规划提交仍可能缺料，我们也不能拿汇总数直接扣料。
2. AEItemKey.equals/hashCode考虑ItemStack的components，不是只比较注册类型名。借鉴的是“显示分类、材料匹配、物理身份分别定义”；不要求把AEKey体系完整搬进Lua。
3. CraftingCpuHelper.tryExtractInitialItems在初始取料不足时会尝试把CPU库存插回网络，然后clear；源码TODO明确提及插回失败的物品处理问题。此路径未逐项核对回存数量。不能据此笼统说AE2全局必丢物品，也不能把它当可靠原子回滚模板。EmberRoutes继续遵循真实原实例占有/失败保留规则。
4. AE2不存在PZ同样的NPC跨楼层寻路、丧尸打断、物品耐久/新鲜度、方格卸载和长时搬运语义。成熟架构只能作为模式参考，不能代替本游戏验证。

## 对后续顺序的结论

- 保持现有顺序：0.9.0实机反馈与正式UI设计，随后自动分拣；本次评审不改既定排期、不回头重写已验证底层。
- 分拣阶段：先完善策略与真实执行的边界，以及结构变更安全推进；单NPC闭环先验，多NPC前补物品/容量预留仲裁。
- BOM阶段：重点参考模拟状态/分支与计划DTO、提交重验、执行任务及待产物分离。AE2测试源码含递归、替代路径、剩余物、容器复用与受损物品用例，可借鉴问题集，结合PZ实际配方重写验收；未运行其测试。
- 规模确实需要时才引入类型订阅和到期优先队列；生产代码本轮不变。后续每个机制仍按Candidate/已验证分开记录。

## 许可证记录

仅记录本地文件标示：根LICENSE和实现文件头为LGPLv3（部分头允许或更新版本）；API子目录LICENSE为MIT并提示部分子包另有许可，README另列纹理/模型许可。此次只概括机制、记录定位，未复制实现/资产；未来若复制代码须逐文件核对，不能把API的MIT套给整个项目。本段不是完整许可审计。
