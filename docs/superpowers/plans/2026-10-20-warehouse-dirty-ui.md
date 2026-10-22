# 仓储脏行更新修复计划

日期：2026-10-20；状态：0.9.1实现与本地检查完成，实机待复测。

用户已要求解决NPC存取时整面板闪烁。沿用已批准仓储/事件驱动UI，不做视觉重构。依据在线第11节局部脏标记、State单向更新；PZ42.21.0原版ISScrollingListBox.addItem/clear/prerender决定行字段和滚动高度契约。

**Goal:** 普通存取不清空列表、不重置页码/选中/滚动；待核实数量显式标记，不把旧展示当当前资产。

**Architecture:** Index保持失效即清候选和空业务快照；另发retain/dirtySources/dirtyAll展示失效元数据。UI/WarehouseRows将旧展示投影为只含明确待核实标记的行；READY对比标量内容复用未变行。CachedList.reconcile按fullType/id维护原条目，文本变化才排版；成员变化才重组可见数组。权限/范围/错误仍硬清理。

## 实施

- [x] Index增加不可变的失效元数据，待更新期间新受影响来源也通知；配置事件硬清理，原库存/已知原版容器事件软失效；未知来源标记全部待核实。
- [x] 新增WarehouseRows.project(snapshot,oldRows,resolveName)，保持未知数量为false并带pending，而非保留旧数。新增CachedList.reconcile(list,rows,caption,key)，按原版addItem建立新行，复用旧行与缓存文本，维护count/itemindex/height和滚动高度。
- [x] Dashboard收帧不重置page；选择按稳定key保留，只刷新选中项受影响的来源。零数量行/来源消失仍移除，不保留幽灵记录。
- [x] 增加真实Kahlua CN/EN回归：普通更新不清空、无关行/条目/文本不动、待核实数量/新增来源失效、分页/选择/滚动、隐私与错误清理、真实零数量删除；业务候选在UPDATING仍不可用。
- [x] 构建0.9.1、原搬运回归及preflight/release-check/doclink；记录未测GPU实机，不把列表对象复用当游戏无闪烁已验。

后台仍使用0.9.0按箱失效、有界全局归并；本轮不做逐件增减账或假定所有原版事件有类型信息。该保守选择避免未知变化、重复事件和物品状态变化引起累计偏差。实时行差分不等于GPU局部重绘。
