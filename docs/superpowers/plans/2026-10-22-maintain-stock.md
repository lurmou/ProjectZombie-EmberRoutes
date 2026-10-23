# 仓储最低存量 Implementation Plan

用户已明确批准[实施设计 v1](../specs/2026-10-22-maintain-stock-design.md)，指示开始开发。主代理独立实施，不使用子代理。

**Goal:** 按仓内实物件数维持据点物资最低存量，自动生成并有界推进生产工单补齐缺口。

**Architecture:** 小型需求监督器（StockService/StockStore/StockRule）与现有生产执行权威（Production/ProductionChain/LaborStore）解耦。监督器只提交需求与周期状态，执行器拥有真实物理执行与资产核对权威。

**Tech Stack:** PZ42.21 / Kahlua Lua / 当前 Java 桥 / 分类仓储与现有据点界面。

**Spec:** [实施设计 v1](../specs/2026-10-22-maintain-stock-design.md) (Git commit: `eb6df49`)。

## 全局约束与红线

- 单人优先，本地世界执行者仲裁；UI 与外部修改走命令，只读返回 DTO。
- 纯仓内实物件数口径 $P$：仅算已登记、当前有读取权限的容器直接层物品。预留物品实际移出前计入 $P$。背包、地面、在途不计。
- 完整覆盖门禁：`complete == true`（unloaded/private/missing/limited 均为 0）才计算缺口与派单；UPDATING 或不完整时显式等待，不按未知为 0 派单。
- 相同产品存在未收束手动单时等待，进入 `WAIT_EXISTING_ORDER`，避免重复补货与预测双计。
- 单条规则最多 1 个未收束周期，单周期最多 1 个生产父单，上限最多 32 个原版批次。
- NPC 忙时不抢占，禁止调用 `cancelAll`。
- 跨据点容器重叠时（同产品已启用规则）置 `SCOPE_OVERLAP` 并停止派发。
- 严格受控的全局 Tick 预算：每 tick 最多评估 4 条脏规则，最多 1 次建单/恢复，每据点最多 32 条、全局最多 128 条规则。低频检查至少 60 未暂停游戏秒节流。游戏暂停时不推进派单。
- 禁用、删除、修改目标、读档与异常均有明确收束协议，提前收束（`TARGET_REACHED`）合法交付归还。

## Task 1: 纯规则契约与持久化存储 (StockRule & StockStore)

- [x] 新增 `Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/StockRule.lua`：
  - `evaluate(rule, inventory, orders)`：纯函数计算缺口 $D = \max(0, M - P)$、请求批次 `requested = min(D, 32 * yield, 9999)`、实际 `target = math.ceil(requested/yield)*yield`，返回状态与原因。
  - `validate(rule)`：校验 minimum (1~9999 整数)、fullType、recipeId、signature、npcId、surfaceId。
  - `uniqueKey(settlementId, fullType)`：唯一业务键。
- [x] 新增 `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/StockStore.lua`：
  - 接入世界根 ModData：`maintainStock = { format=1, revision=..., rules={...} }`。
  - 支持原子命令：`create`, `update`, `enable`, `disable`, `retry`, `delete`。
  - 规则数量上限守卫（据点 <= 32，全局 <= 128）。
  - 周期状态机管理（`PREPARED`, `ATTACHED`, `SETTLING`, `RECONCILE_REQUIRED`）与双向关联校验。
  - `deleting` 墓碑与关联收束清理。
- [x] 新增 `tests/lua/stock-rules-test.lua`：
  - 覆盖缺口计算、批次上限 32、多产物取整、校验规则、命令修改、版本递增、周期恢复。

## Task 2: 生产执行器适配与 CraftRecord 契约扩展

- [x] 扩展 `Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/CraftRecord.lua`：
  - 接入可选 `origin = { kind="MAINTAIN_STOCK", ruleId=..., cycleSequence=... }` 的版本化校验。
  - 支持合法提前收束：在 `r.reason == "TARGET_REACHED"` 且 `r.state == "DONE"` 时，允许 `r.delivered == r.produced <= r.target`（即便 `produced < target`），并确保 `released == true` 校验通过。
- [x] 适配 `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Production.lua`：
  - 支持外部预分配 `options.taskId` 与 `options.origin`，建立原子关联。
  - 支持非抢占式执行：`options.nonPreemptive = true` 时不调用 `Probe.cancelAll`，若 NPC 忙或有动作队列直接返回 `NATIVE_ACTION_BUSY`。
  - 批次安全边界提前收束检查：在每一批产物交付后、进入下一批或下一链节点前，若已达标（`TARGET_REACHED`），安全收尾已产出交付与工具归还，写入 `reason="TARGET_REACHED"`。
  - 提供同据点同产品根目标查询辅助方法 `Production.findRootOrders(settlementId, fullType)`，供规则检查手动单碰撞。
- [x] 更新 `tests/lua/craft-probe-test.lua` 或编写定向回归，确认普通手动单与配方链原件认领和恢复未被破坏。

## Task 3: 后台需求监督服务与生命周期调度 (StockService)

- [x] 新增 `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/StockService.lua`：
  - 管理后台 `WarehouseIndex.watch` 订阅与引用计数（窗口关闭后依然维持服务的后台运行，最后规则停用或世界切换时释放）。
  - 全局脏规则轮转队列，每 tick 最多评估 4 条，最多 1 次派发/恢复。
  - 低频检查节流（60 游戏秒）与暂停门禁（`isGamePaused()` 冻结）。
  - 完整盘点守卫（`WarehouseIndex.candidates` complete 检查）。
  - 容器重叠检测（`SCOPE_OVERLAP` 阻断）。
  - 派单前 NPC 状态重验（存活、绑定、健康、无其他任务、非抢占）。
  - 周期终结感知与强制重新盘点（关闭后先触发 `Index.refresh`，取得新 READY+complete 前不派下一周期）。
  - 保存屏障集成：保存时先停 StockService 派发，读档时先核对关联与声明，再恢复旧周期。

## Task 4: 制作界面第三视图与中英文本地化

- [x] 新增 `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/StockRules.lua`：
  - 制作面板第 3 个视图（与“配方”和“工单”并列）。
  - 列表展示：产品图标/名称、仓内 P / 目标 M、规则状态（达标/待盘点/补货中/等待工人/缺料/覆盖不全等）、当前周期进度。
  - 规则创建与配置表单：产品选择（或从仓储带入）、根配方、目标数量步进器、分配工人、工作台、启用开关。
  - 操作按钮：创建、更新目标、启用/禁用、重试、删除。
  - 使用原版裁剪与标准相对布局，隐藏页注销 UI 监听。
- [x] 适配 `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/CraftingPage.lua`：
  - 视图切换加入 `"maintainStock"`，支持按键导航与主题风格切换。
- [x] 仓储界面联动：
  - 在仓储详情卡或动作按钮区增加“设置最低存量”跳转，打开据点主面板制作页并切到最低存量视图、带入 `fullType`。
- [x] 增加 CN 与 EN 翻译字典项：
  - 编辑 `Contents/mods/EmberRoutesProbe/42/media/lua/shared/Translate/CN/IG_UI.json`
  - 编辑 `Contents/mods/EmberRoutesProbe/42/media/lua/shared/Translate/EN/IG_UI.json`

## Task 5: 全面验证与文档交接

- [x] 运行 Lua 定向测试（纯规则、持久化、生产适配与调度逻辑）。
- [x] 运行 `node ../.workbuddy/tools/pz.mjs preflight Contents/mods/EmberRoutesProbe/42` 检查。
- [x] 运行 `node ../.workbuddy/tools/pz.mjs doclink` 检查新增文档。
- [x] 运行 `node ../.workbuddy/tools/pz.mjs release-check`。
- [ ] 更新 `docs/BACKLOG.md` 与 `docs/HANDOFF.md`。
- [ ] 撰写版本技术审查与验证记录。
