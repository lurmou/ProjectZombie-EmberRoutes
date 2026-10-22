# 0.9.0 仓储基础设施收口

日期2026-10-20；用户批准本轮基建；主代理独立实施。用户明确0.8.2虚影修复成功，按该项反馈登记，不扩展为全功能验收。

## 需求与基线

在线唯一需求v3.2成功重新导出，build/research/online-current.txt的SHA256仍为794B68E2357A42451BA76DED8B266E707B94FD1C390ACAEE47AFF5207A2C9BA4。浏览工具导出不可用，但PowerShell直连导出成功，未改在线文档。设计见[规格](../../superpowers/specs/2026-10-20-warehouse-contracts-design.md)、[计划](../../superpowers/plans/2026-10-20-warehouse-contracts.md)。沿用固定安装游戏JAR/ZombieBuddy构建检查。

当前原版ISInventoryPage按getContainerCount与getContainerByIndex(0基)枚举各格；现有原版转移动作保留。查询不以原版OnContainerUpdate充当所有物品变更通知，不创建全局动作覆盖。

## 实施

Registry统一describe/revalidate/affected，保持旧ID和nil缺省主格记录；拒绝畸形坐标/索引，副格不回退主格。通知能定位已移除对象的旧身份，实际取放另经权威复验。Work和读取复用同一物理端点复验。

WarehouseRollup提取纯状态机，每容器/物品ID/类型贡献/归并排序输出均计入128总推进预算；游标和累计已知件数消除重复扫描脏箱/累计贡献。末尾全量去重和table.sort已替换为分片归并，仍不宣称原版API、回调和GC都在墙钟时间预算内。

15推进tick静默合并，最长60；非相关箱变更不取消当前读取。读取或归并中断累计8次明确失败，刷新可恢复。最后消费者释放或跨世界时清扫描/归并/候选引用。

Index.candidates返回经过Ledger.view验证的精确类型候选、副本来源、代次、已知数量和完整性；更新中/错误/未请求不暴露旧量。几何排序不是寻路，不授予预留/扣料权。本轮不做视觉重构、分拣、生产、贸易或MP。

## 验证

真实安装Kahlua CN/EN：75仓储检查，含旧记录、冰柜独立原库存、重建保存表、通知洪泛、8次中断恢复、归并期间失效、候选权限/副本/部分状态及有界汇总排序；既有24过滤面板、21侧栏、22据点UI检查通过。ISUI宿主为替身。原Work 69检查通过（其内部旧动作/搬运检查不相加冒充新增覆盖）。

纯算法工作量用例：20000物品ID、2048类型，含去重与11轮归并排序共44577单位，预算17时分2623次完成，内部每次核对预算。此为Kahlua执行的工作量断言，不是PZ帧耗或最大规模实测。

本地源输出：build/logs/0.9.0-*。最终构建/静态/包核对随交付补记。真实存档、冰柜搬运和游戏帧耗待[合并复测](../../testing/single-player-warehouse-contracts.md)。纯表重建不等于原生序列化/崩溃恢复验证。

补充：宽大稀疏范围在桶求交与最多256登记条目的直接检查间择低成本路径；XY无法定位的畸形记录使查询明确失败，修复后刷新恢复，避免未知成员冒充完整性。新增对应回归。没有全地图扫描或额外库存发现。

最终结果：标准Lua与真实Kahlua CN/EN各75项仓储检查通过；65 Java与42检查点/门禁、固定安装哈希和override-first类加载构建通过。preflight为39 Lua、0错误/0警告；release-check通过，9文档doclink无断链；包内45生产文件与源码逐字节一致。包SHA256：50BEC16B79AD8E675B2E75AB052BABE1A11ED8E38676001B72A88A686BE9E070。机器可读结果见[验证摘要](probe-0.9.0-verification.json)。
