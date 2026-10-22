# 0.8 据点仓储实施计划

日期：2026-10-20；状态：实施与本地检查完成，新功能实机待验。依据[已批准设计](../specs/2026-10-20-settlement-storage-design.md)。主代理独立实施，未派子代理；不提交未跟踪仓库。

1. shared/SettlementGeometry.lua与client/SettlementLedger.lua：纯坐标、版本账本、稳定身份、变更通知；测试边界、同阵营重叠、无效/超限、取消不写和旧世界隔离。
2. client/SettlementMembership.lua与WarehouseIndex.lua：坐标候选/ID去重、可取消有界盘点、已加载主容器只读快照、失效协议；测试隐私、卸载、重复ID、预算、无消费者和原实例不变。
3. client/UI/SettlementSelector.lua、WarehouseList.lua、SettlementDashboard.lua：按原版生命周期组装，框选只绘边界，面板分物品/来源并按缓存搜索；接右键菜单和CN/EN，测试输入/草稿/生命周期及实际Kahlua中文字。
4. 更新0.8.0、构建、针对性Lua/Kahlua、preflight/release/doclink；本地归档证据和批量实测说明。更新HANDOFF/BACKLOG及用户0.7.3通过反馈。未验防刷新/MP/BOM/嵌套库存不记作完成。

以上四步已完成；最终0.8.0与工作区产物已核对。[结果与证据](../../reviews/2026-10-20/probe-0.8.0-settlement-storage.md)，实机按[集中测试](../../testing/single-player-settlement-storage.md)验收。
