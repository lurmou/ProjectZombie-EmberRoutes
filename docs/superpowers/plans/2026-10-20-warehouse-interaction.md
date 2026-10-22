# Warehouse Interaction Implementation Plan

日期2026-10-20；状态：本地实施/检查完成，新实机待验。用户已批准范围及主代理在本会话实现，无额外审批，不派代理、不自动提交。

**Goal:** 完成仓储查询、来源定位、交互状态及可测量的性能基线。
**Architecture:** 纯查询模型缓存结果并按稳定身份锚定分页；来源定位服务独立复验世界资产；状态驱动控件，采样仅显式开启。
**Tech Stack:** PZ42.21.0原生ISUI/Kahlua、ZombieBuddy2.3.4只读时钟。
**Spec:** [批准范围与设计](../specs/2026-10-20-warehouse-interaction-design.md)

## Global Constraints

单人优先；不直接消费汇总资产；CN/EN成对并优先原版通用键；绘制不测量/扫描库存；限2048类型、采样每类2048值上限/128值窗口；GPU计时未实现。

## Review Focus

未知数量与相等值稳定排序；数据排序跨页后仍锚定选中；输入焦点不抢键；旧世界/撤权来源不能定位；关闭窗口后定位租约仍须到期释放且不永久轮询。

### Task 1: Query/cache and anchors
- [x] 修改shared/WarehouseQuery.lua：new():page(rows,search,category,page,sort,anchor)缓存，page兼容原接口；CachedList.reconcile增加显式偏移锚定。
- [x] tests/lua/warehouse-query-test.lua验证四排序、未知、tie、缓存、跨页锚定和源输入不变；原仓储/行身份回归。

### Task 2: Validated source locator
- [x] client/WarehouseLocator.lua以new(actor,id)捕获世界，locate(sourceId)/clear管理5秒租约；复用Registry.resolve/Geometry/Ledger，原版OnRenderTick/addAreaHighlightForPlayer。
- [x] 替身测试加载/私有/移除/范围/世界变化、替换/到期释放与500ms复验上限。

### Task 3: UI composition and input
- [x] UI/WarehouseControls.lua组装搜索/清空/分类/排序；UI/WarehouseDetails.lua增加来源选择和定位控件；Dashboard协调状态/焦点/按钮；CachedList统一键盘/手柄路由。
- [x] 实际Kahlua CN/EN检查加载/错误/禁用/焦点/来源、分页位置与四种字号；更新AWT捕获进行视觉检查。

### Task 4: Bounded metrics and delivery
- [x] shared/WarehouseMetrics.lua提供start/stop/begin/finish/report；ProbeRuntime只读nanoTime；Index/UI挂接默认关闭的有限采样，调试菜单入口。
- [x] 增加纯VM查询耗时基线和采样禁用/容量检查；构建0.11.0、preflight/release-check/doclink、包比对、本地进度及集中实机说明。
