# 0.24.5 Java 只读热点下沉

延续[0.24.4 常驻性能优化](runtime-performance.md)及[实施计划](../../superpowers/plans/2026-10-24-native-read-performance.md)。用户授权继续整体优化并检查 Java 下沉。本轮不改变[唯一 NPC 架构](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)、Lua 业务策略、唯一认领、原件取放和保存恢复。

## 选择与实际变更

| 路径 | 源码确认的成本 | 本轮处理 |
|---|---|---|
| Driver.valid，统一运行器/随从/身体控制共用 | carrierPresent 后调用 carrierId；后者内部再完整调用 carrierPresent，重复线程/世界/存活/退休/格/身份检查 | ProbeRuntime.bindingValid 一次查询权威 handles，并执行一次原 carrierPresent 后比较稳定ID；未删除任何存在性条件，不缓存身体状态 |
| LaborProducers.eligible，制作/物流共用 | 普通物品需4次跨语言方法调用：ModData、分类、装备、收藏 | Java InventoryReads.eligible 一次读取并判断，保护标记保留 Lua 真值语义，0和空字符串仍为真 |
| LaborProducers.freeCarry，物流选路使用 | 最大负重、库存重量、库存对象及空余容量的重复跨语言调用 | Java freeCarry 合并读取与计算，保留身体上限和容器上限、非有限/负数输入拒绝 |
| WarehouseIndex.advance，UI/最低存量共用 | 每物品重复集合身份/大小/取项/归属/ID/类型调用，普通32件分支约192次桥接，不含分类和收尾 | 每批最多32件，一次 Java 只读批量读取返回 Kahlua 表；外围保留集合检查，普通批次约3次桥接，不代表CPU下降比例 |
| ProductionSupply.matchStep | 增广匹配的候选×需求边遍历，含原生 InputScript.canUseItem | 尚未迁移。适合后续完整有界匹配内核，单独再包一层 canUseItem 不会消除桥接 |
| ProductionChainPlan 分支展开、物流目标选路 | Lua 规则与查询密集，复杂度随分支或端点数量增加 | 保留现有预算和策略接口，待分项实测确定收益再迁移，避免双份规则失配 |

上述已改路径都有源码确认的重复调用，不是游戏分项计时已证实的热点排名。如果没有库存扫描、最低存量查询或物流制作活动，批量读取不会改善对应空闲场景。当前没有新增 RUNTIME_PERF 实机日志，不能声称已找到并解决全部150ms根因。

## 契约与边界

- Java 类 InventoryReads 无持久状态、无后台线程、无世界枚举和资产修改；ProbeRuntime 共新增4个只读接口，Lua 保留无扩展的兼容路径。物品 ModData 带元表时委托 Lua 读取虚拟保护字段，不用 rawget 绕过其他模组规则。原版物品实例直接传递，不重造物品。
- inventoryReadSlice 接收同一容器及原始 ArrayList 身份、预期大小、偏移及不超过32的数量。读取前后校验集合身份/大小，每项校验真实容器。错误不返回部分结果；超界或无界调用拒绝。
- 输出为扁平的 item/id/fullType 三元组 Kahlua 表，避免每件创建一张行表。调用方在同一 slice 内消费并丢弃，不把原件引用发布给 UI 或写入存档。
- WarehouseIndex 仍共享原128项预算。读取前预占本批全部工作量，发现重复或失效而提前退出也不会漏算已完成的预读；最终容器权限重验及重复 ID 拒绝保留。
- 快照不代替领取、转移或效果提交前的现存物理校验。没有扩大允许材料范围、搬运容量或扫描上限。
- 这些接口只能在现有游戏线程服务路径调用；本轮没有引入跨线程读取或宏观执行者。

## API与基线证据

使用 pz.mjs ask 查询原版 ItemContainer:getItems 调用，核对当前安装 projectzomboid.jar 的 ItemContainer.getItems/getFreeCapacity、InventoryItem.getID/getFullType/getContainer/getModData/getCategory/isEquipped/isFavorite、IsoGameCharacter.getMaxWeight/getInventoryWeight/getInventory 以及 InputScript.canUseItem 签名。PZ42.21.0 与 ZombieBuddy2.3.4 哈希由构建脚本强校验；Kahlua 表使用与游戏相同的 J2SEPlatform。InventoryItem 构造字节码研究位于 build/research/InventoryItem-native-read.javap.txt。当前在线需求已重新导出，SHA256 `1E802DFE03A43437C77DC8EF5D04A2E38EC9AE9970A71D349B302B9EFE2EFB08`，与此前审查一致，未引入平行产品需求。

## 验证与交付

- 新增 Java 回归在真实安装库存类和 Kahlua 表上通过30项：原件身份、收藏和保护标记、集合替换、大小变化、位置错误、最大切片及失败无部分输出、容量计算、元表委托及缺失身体拒绝等。测试使用脚本元数据构造物品，避开纹理/游戏文件系统启动；未构造活 NPC 或加载世界。身体正例/旧桥兼容/稳定ID变更的 Lua 回归使用替身，不能代替实机身体验收。
- 安装版 Kahlua 相关仓储、原生返回表分支、制作链、受控制作、物流、公共派工、自理与保存回归通过；原生返回表分支跑完整仓储服务的77项断言，142次模拟批读取均不超过32件，世界为替身。
- 0.24.5 构建通过，新增 Java 回归接入正常构建；modscan 无替换冲突。最终完整 preflight 全部通过（153个Lua）：基础检查0错误/1提示，LuaLS 0阻塞错误/415信息性警告（undefined-field236、need-check-nil174、其他5），未清零类型提示；release-check 为0错误、77条现有UI硬编码中文提示；相关5个Markdown文档 doclink 为0断链。
- 最终归档与当前源码逐文件SHA256比对160文件一致；ZIP SHA256 `90AAA76598C6F1100F95D90A1925094140574030B68CAE967B15D5265138C96C`。没有提交或发布工坊，保留原有未提交修改。
- **游戏调用、真实CPU/GC改善比例、Boot一秒低于50ms均未验证。** 新 Java 接口必须完全重启游戏加载新版 JAR，不能用旧进程热载 Lua 验收。

原始记录：build/logs/native-read-build.log、inventory-reads-tests.txt、native-read-lua-tests.log、native-read-integration.log、native-read-budget-tests.log、native-read-final-tests.log、native-binding-tests.log、native-read-preflight.log、native-read-preflight-final.log、native-read-release.log、native-read-modscan.log。
