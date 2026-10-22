# 据点与仓储读取基础

0.9.1更新展示契约：[脏行修复](reviews/2026-10-20/probe-0.9.1-warehouse-dirty-ui.md)。业务UPDATING快照仍不提供旧库存；新增retain/dirtySources/dirtyAll，仅允许UI保留行结构，受影响数量必须标未知。权限/范围/错误立即清理；READY按稳定key修补，页码/选择/滚动不因存取重置。该补充覆盖下文“撤下旧可见行”的视觉策略，候选和资产边界不变。

日期：2026-10-20；状态：0.8.0实现，本地检查完成后仍须实机验收。依据[本阶段设计](superpowers/specs/2026-10-20-settlement-storage-design.md)。用户明确基础架构的性能、扩展和维护性优先；以下是可核查契约，不是未测性能承诺。

0.9.0收口依据[新设计](superpowers/specs/2026-10-20-warehouse-contracts-design.md)和[实施计划](superpowers/plans/2026-10-20-warehouse-contracts.md)，覆盖下文原有预算/通知细节；[集中复测](testing/single-player-warehouse-contracts.md)。

## 模块与依赖方向

| 模块 | 契约 | 不承担的职责 |
|---|---|---|
| SettlementGeometry（shared） | rectangle/valid/contains/inside/overlap，整数半开矩形 | 不访问引擎、不保存、不创建原版区域 |
| SettlementLedger | commit(actor,id,name,area)，get/list/view读取副本，变更revision通知 | 不计库存，不驱动NPC，不由UI直接改持久表 |
| SettlementMembership | query(settlement)返回稳定容器ID集合 | 不枚举地图方格/物品，不复制容器身份 |
| ContainerRegistry | describe(id)脱离持久表；resolve/revalidate物理端点；affected定位变更源 | 通知不授权取放，身份仍由稳定ID加当前物理对象复验 |
| WarehouseRollup（shared） | new(ids,results,maxItems,maxTypes)，step(budget)返回spent/state/reason；rows/counts/byType | 不访问引擎、不结算资产；仅处理单次作业的标量贡献 |
| WarehouseIndex | watch(id,fn)→release；refresh(id)，版本化只读快照 | 不扣料，不移动物品，不把缓存当资产账本 |
| WarehouseQuery（shared） | 缓存文字/类别过滤与分页 | 不查世界、不调用名称翻译接口 |
| UI/CachedList、SettlementDashboard、UI/SettlementSelector | 组件组装、输入、状态订阅、草稿与命令提交 | 绘制时不盘点库存，不把动画当实际效果 |

读取链：本地执行者校验据点 → 已登记坐标求成员 → 重建物理端点与权限 → 有界读取已登记的实际容器 → 只读快照 → 缓存查询/UI。后续分拣/生产/贸易可取候选来源，但执行前必须重查原实例、容量、权限和预留，不能直接使用汇总数量提交扣除。

## 身份与持久化

命名空间EmberRoutes/Settlements/v1仅存format、revision、稳定factionId及据点记录。每个据点有稳定id/name/factionId/revision/areas。所有成员容器沿用ContainerRegistry原ID与坐标索引；不改旧Work任务的local-world scope。SP本世界阵营身份持久化，不绑定角色临时玩家索引；这不是MP可信账户继承的实现。

账本的底层data()是持久化/查询服务适配入口；UI通过get()/view()取得脱离持久表的副本，改副本不会暗写账本。写入集中在commit()，失败校验先于修改。将来替换存储或添加服务端裁决时，从该边界适配；不能直接让MP客户端写GlobalModData。

区域为多个矩形的逻辑并集、覆盖各楼层。同据点多块重叠不重复计数；两个同阵营据点可重叠，但本版不执行两个账本的合并/解散。跨据点视图可能共享同一箱子，不能把它们相加当作阵营资产；未来全阵营查询须再次按containerId/物品ID去重。系统NPC城镇未生成，validators仅为注册边界/间隔的纯校验接口，不能宣称城镇避让、防刷新或区域保护已完成。

## 只读快照

format=1；settlementId、settlementRevision、revision（读取视图代次）、coverage=ROOT_ONLY、state、rows、counts、reason、readAt。readAt是本服务推进计数，不是现实时间或可结算时钟。rows按fullType汇总，保留分类node、原实例件数和各source的稳定ID/XYZ/数量/容器名称元数据；不发布或持久化userdata。订阅者按只读契约使用共享快照，派生UI行自行复制。

数量表示InventoryItem实例件数，不是液体体积、重量、配方份数或可支配余额。只覆盖已登记容器的直接物品（0.8.1起包含独立登记的冰柜副格），不含包内、NPC身上或未加载库存。错放物品仍是实际存量：过滤规则限制NPC存入，不把已存在的物品从盘点隐藏。私人/停用或未配置不读其库存；未配置容器不会为了计数而被全地图发现。

状态将loaded/unloaded/private/missing/limited区分；READY表示本次已知成员完成检查，不表示未加载仓库为零。ERROR不给部分结果冒充总量。新盘点/撤权立即撤下旧可见行；重复物品ID拒绝该轮汇总。普通世界保存不等于跨文件崩溃原子性。

## 更新、预算与资源释放

- 成员索引按10格空间桶索引登记坐标，求交矩形后按容器ID去重，跨楼层共享平面归属。不逐格遍历地图找箱子。
- 同一据点多个订阅共享盘点。精确库存事件定位一个ID，对象事件定位各格；拆除后事件仍能撤销旧定位，不要求对象仍在方格列表。已知未登记对象不引发无关全量刷新；未知来源才合并失效活动请求。通知等待15个UI推进tick静默，最长等60；另一箱变更不取消当前箱读取。读取或标量归并累计中断8次明确INVENTORY_UNSTABLE，手动刷新恢复。
- 单次推进总预算128单位：检查候选/提交箱贡献/读取单件各计一；归并中每容器、每物品ID去重、每类型贡献、每归并排序输出各计一。末尾不再同步遍历所有ID/排序。自底向上归并排序O(T log T)，精确类型索引O(1)定位；游标找脏箱替代每箱从头搜索，已知总件数增减维护，不重复累加所有贡献。最多每箱2000、一次20000件/2048类型，超限明确失败。空间成员查询、原版方格对象枚举、回调/UI文字处理和GC不计入此标量预算，因此它不是墙钟毫秒或整帧耗时保证。
- 原版IngameState实际触发OnTickEvenPaused，盘点在暂停时也能完成；没有待查询时不会读库存。列表每页60行；搜索/分类/翻页只处理最多2048条缓存类型，不因按键重新访问世界。
- 最后一个订阅释放即移除上下文和活动原容器引用；旧会话释放不能误删新会话请求。OnGameStart先取消所有旧作业，再发布WORLD_CHANGED清掉旧可见库存。
- Registry.inventoryChanged由已核对成功的原实例搬运发出。它与配置通知均为观察事件，观察者失败记录日志，不否决已经成功的业务效果。查询服务移除失败UI观察者，避免孤立扫描和故障扩散。

OnContainerUpdate本身不足以证明所有物品变更都有通知。当前NPC正式搬运有明确的成功通知；玩家/第三方修改物品后可以显式刷新，不通过全局覆盖原版动作类实现“看似自动”。其他执行适配器可在确认实际效果后接入同一通知接口。缓存不用于结算，因此未覆盖事件不会产生资产扣取。

## 当前边界与后续

窗口打开时检验本地角色/归属/位置；已开只读窗口不每帧轮询玩家坐标。当前32据点、16矩形/据点、每块128×128是安全边界，不是经过压测的规模指标。动态缩放、实际手柄硬件、世界框选、正常存取、CleanUI和大型仓储帧耗须分别实测。

下一阶段可基于这些接口增加多仓分拣；多NPC并行之前必须先增加物品/容量/任务预留与仲裁。BOM、宏观商队、嵌套库存访问器和账本合并迁移均另验，不能复用“只读汇总通过”作为结算正确证据。

实现和证据：[0.8.0记录](reviews/2026-10-20/probe-0.8.0-settlement-storage.md)。

## 0.8.1容器身份兼容

旧主容器仍使用对象EmberRoutesContainer及原ID；副容器在EmberRoutesContainers中以0基容器索引独立登记。坐标记录追加containerIndex/containerType；旧记录缺省索引0，无需批量迁移。执行和读取同时重验对象标记、实际容器索引与类型；副格消失不得回退到主格。索引/类型不能识别第三方在同对象同槽位同类型的原位替换，遇到此类兼容应补验证，不能宣称支持任意容器重排。配置、隐私、实际搬运通知和盘点均按实际端点处理，界面不靠缓存库存身份裁决。

## 0.9.0候选与执行接口

`Index.candidates(actor,settlementId,{fullType,origin?,limit?})`先经Ledger.view验证本地角色、归属与位置。fullType为精确类型字符串；origin是有限XYZ数值，limit为1..256整数、默认32。调用方持有watch订阅及release，查询本身不隐式启动后台作业。未请求返回NOT_REQUESTED；更新/错误返回状态而没有旧数量。READY才有knownCount（已知可读成员中的原实例件数）、complete和脱离缓存的sources；部分范围中某类型knownCount=0不代表全据点为零。

complete只在未加载/私人/失效/超限均为0时为true，它仍不表示全局时点一致或资产可预留。来源带稳定ID/XYZ/count/名称；可选distanceSquared为XYZ几何距离，非路径代价。来源最多256，有限数组确定性排序：几何距离、再稳定ID；limit截断附truncated。返回revision及settlementRevision供调用方识别代次，失效即清内部类型索引。消费方仍须Registry.resolve并定位真实物品、检查容量/权限/预留；跨帧盘点不是原子世界快照。

Registry.describe读取副本并验证整数坐标/索引（旧记录仅nil缺省0，不接受false）。无法识别XY坐标时无法确定归属，活动盘点保守失败为CONTAINER_RECORD_INVALID；修复登记后刷新恢复，不能把未知记录默默漏掉当完整库存。可定位但索引/类型失效的记录仍属于成员并计为失效。revalidate除登记/权限/加载外，还比较已持有端点的实际对象和容器。Work和盘点共用该入口。affected只是失效定位，不授予访问，因此可处理已移除对象上的旧标记。已加载端点仍可能受第三方原位替换影响；不承诺任意模组的容器重排兼容。

成员索引采用有界的自适应查询：估计矩形涉及的空间桶数；若空桶遍历比已登记条目乘区域数更贵，就直接检查最多256个登记坐标，否则沿10格桶求交。两条路径都只访问登记表，不发现或读取地图库存。
