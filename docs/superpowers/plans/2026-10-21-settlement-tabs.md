# 统一据点窗口实施计划

用户于2026-10-21批准设计并要求开始。本会话主代理独立实施，不派生代理。

**Goal:** 单一窗口整合仓储与物流，隐藏页释放视图资源而不停止后台物流。

**Architecture:** SettlementDashboard拥有外壳及单例；WarehousePage/LogisticsPage拥有各自控件和状态；小型PageLifecycle管理同步回调安全的订阅激活/释放。保留旧物流open入口转发。

**状态：** 已实施并完成必要检查；实机未验证。

**Tech Stack:** PZ42.21.0原生ISUI、Lua/Kahlua；不修改Java产品代码。

**Spec:** [已批准设计](../specs/2026-10-21-settlement-tabs-design.md)。

## Global Constraints

- 版本0.16.0；CN/EN成对，布局随字体/窗口相对计算。
- 不更改资产、任务和物流权威；隐藏页不扫描或投影，后台物流继续。
- 实机未跑明确标注；不重复历史全量玩法测试。

## Review Focus

- 同步watch回调关闭窗口：返回的释放句柄必须立即执行。
- 切页返回：恢复搜索/页码/稳定ID选择，盘点中不显示旧数量为最新。
- 帮助、定位和焦点：停用时释放，不遗留独立渲染事件。
- 旧入口、反复打开和关闭：同据点复用，换身份完整释放，关闭幂等。
- 跨世界、越界或撤权：统一外壳关闭，无旧页面继续读取。

## Task 1：页面拆分与生命周期

**Files:** 创建UI/WarehousePage.lua、UI/LogisticsPage.lua、UI/PageLifecycle.lua；修改相关页面测试。

**Interfaces:** 页面new(owner,bounds)、activate()、deactivate()、dispose()；owner.close()/selectTab(id)/valid()。

- [x] 提取原页面控件、布局、状态投影与输入；移除独立窗口/关闭按钮与各页身份轮询。
- [x] 幂等停用释放watch、帮助、Tooltip和定位；保留页面查询与选择意图。
- [x] 回归同步watch回调释放、晚到通知、重复激活和切走后无投影。

## Task 2：统一外壳与兼容入口

**Files:** 修改SettlementDashboard.lua、LogisticsDashboard.lua、UI/CachedList.lua和CN/EN翻译。

**Interfaces:** SettlementDashboard.open(actor,id,tabId?)；selectTab("warehouse"|"logistics")；两页懒创建。

- [x] 以原版ISButton构建相对布局页签和统一关闭区；选中状态与可访问输入可见。
- [x] 先停用旧页，再隐藏，再激活新页；统一低频身份检查及关闭。
- [x] 保留旧物流入口转发；同据点重复打开复用窗口；验证新旧入口和失效处理。

## Task 3：版本与交付证据

**Files:** version.txt、Build.lua、mod.info、README.md、HANDOFF.md、BACKLOG.md、ui-architecture.md及本轮评审记录。

- [x] 跑相关Lua/Kahlua CN/EN检查与preflight，处理实际故障；不跑历史全套。
- [x] 更新0.16.0版本与本地进度，保存原始必要检查结果。
- [x] doclink/release-check通过，清楚记录真实渲染、手柄及性能实机未验证。

已按设计逐项自审范围、接口与验证归属；用户已授权当前会话独立执行。
