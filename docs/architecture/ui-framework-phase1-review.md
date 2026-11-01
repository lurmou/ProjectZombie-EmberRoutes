# EmberRoutes UI Framework Post Phase 0 Review & Phase 1 Plan Correction
# 阶段零实施复核与阶段一设计修正审查报告

> 评审日期：2026-11-01  
> 评审基线 Commit：`c12a14d0f945073716306f0ff7ae5c975a82e0ef`  
> 状态：架构审查就绪，待用户裁决后启动阶段一细化实施  
> 约束遵守：严格执行反谄媚、代码证据前置、三要素闭环红线；本次仅限审计与文档，未触碰任何生产代码。

---

## 一、Git 基线与提交文件任务全量映射

### 1. 仓库环境现状核实
- **工作区绝对路径**：`c:\Users\MuMu\Zomboid\Workshop\EmberRoutes`
- **当前活跃分支**：`phase-3a-consolidation`（与 `origin/phase-3a-consolidation` 完全同步）
- **当前 HEAD Commit**：`c12a14d0f945073716306f0ff7ae5c975a82e0ef`
- **工作区状态**：`working tree clean, nothing to commit`

### 2. 提交 `c12a14d` 33 个文件全景穿透审计与归类
提交 `c12a14d` 包含了 33 个文件的变动（+5165 / -4104 行），通过对每一个文件的 diff 进行实地代码审计，识别出本次提交实际由 **原定 Phase 0/早期待办** 与 **混入的活动系统/仓储重构业务代码** 复合组成：

| 序号 | 文件路径 | 行数变动 | 任务归属与性质 | 实地审计说明与潜在风险 |
| :---: | :--- | :---: | :--- | :--- |
| **A** | **Phase 0 架构规范与登记** | | | |
| 1 | `docs/architecture/ui-framework-architecture-spec.md` | +208 | Phase 0 规范基线 | 确立四层架构、静态绘制 vs 交互组件、生命周期与零 GC 铁律。 |
| 2 | `docs/architecture/ui-framework-current-state.md` | +105 | Phase 0 现状报告 | 梳理 60 个 UI 相关源文件。注：下文已纠正 ActivityPage 刷新机制描述。 |
| 3 | `docs/architecture/ui-framework-phase1-plan.md` | +101 | Phase 1 执行计划 | 初版 8 个任务分解。注：下文已根据真实数据源纠正 Task 1.6 设计。 |
| 4 | `docs/INDEX.md` | +1 | 文档导航索引 | 登记 UI 运行时架构规范与现状核验入口。 |
| **B** | **早期技术债务治理（已批准）** | | | |
| 5 | `AGENTS.md` | +14 | 规则准则登记 | 补充《UI 架构与基础设施开发红线 (UI Framework & Lifecycle Invariants)》。 |
| 6 | `UI/PublicOrderDialog.lua` | +38 / -106 | Task 1.1 (债务出清) | 移除 55 行私创步进器，接入 3 个标准 `StepperInput`（单次、最低存量、批次）。 |
| 7 | `UI/StepperInput.lua` | +17 / -1 | Task 1.1 (基础设施) | 强化 `syncing` 守卫，输入删空时支持 `onChange(nil)` 回调。 |
| 8 | `UI/ActivityScenarioCard.lua` | +87 (新建) | Task 1.2 (组件复用) | 将场景卡片底色与 Accent 条委托给 [`CardPanel.draw`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/CardPanel.lua#L34)。 |
| 9 | `UI/PersonnelPage.lua` | +1 / -2 | Task 1.3 (缺陷修复) | 删除 L338 `self:project(...)` 冗余重复投影调用。 |
| 10 | `UI/ActivityDialog.lua` | +20 / -504 | Task 1.4 (消除双轨制) | 519 行旧窗口精简为 20 行透明转发 Shim，无缝导向 Dashboard `activities` 页签。 |
| 11 | `UI/TooltipManager.lua` | +175 (新建) | Task 1.5 (基础设施) | 集中管理 Tooltip 坐标纠偏、边缘夹持与级联清理。详见第二节专项审计。 |
| 12 | `UI/TooltipAnchor.lua` | +23 / -16 | Task 1.5 (向下兼容) | 设为透明代理，保持 23 个既有文件的调用契约不变。 |
| 13 | `UI/PageLifecycle.lua` | +2 | Task 1.5 (基础设施) | 在 `unmount` 中接入 `TooltipManager.clearOwner(page)`。 |
| 14 | `tests/lua/tooltip-manager-test.lua` | +103 (新建) | 单元测试 | 验证 Tooltip 基础纠偏、屏幕夹持与单次清理（14 项断言 PASS）。 |
| 15 | `tests/lua/activity-dialog-test.lua` | +136 / -5 | 单元测试 | 验证旧 Dialog 转发至 Dashboard 的兼容性（5 项断言 PASS）。 |
| **C** | **混入的活动系统 UI/UX 开发代码** | | | |
| 16 | `ActivityScenarioCatalog.lua` | +82 (新建) | 业务配置扩展 | 定义活动场景编排元数据（读书会、健身、就餐等场景）。 |
| 17 | `UI/ActivityAtmosphereBoard.lua` | +162 (新建) | 业务组件 (违规) | 氛围与阶段看板组件。**严重违反 Static Draw 零 GC 规范**（见第六节）。 |
| 18 | `UI/ActivityPage.lua` | +38 / -34 | 业务页面接入 | 接入氛围看板、场景卡片，存在每秒 `Service.revision` 轮询检查。 |
| 19 | `UI/ActivityPresentation.lua` | +220 (新建) | 展示适配层 | 考勤状态与氛围阶段文本格式化纯函数。 |
| 20 | `docs/superpowers/specs/2026-11-01-activity-ui-ux-redesign-spec.md` | +228 (新建) | 业务设计规范 | 活动系统 UI/UX 重设计规范，非框架核心文档。 |
| 21 | `tests/lua/activity-page-test.lua` | +11 / -7 | 业务回归测试 | 页面状态切换测试（23 项断言 PASS）。 |
| 22 | `tests/lua/activity-presentation-test.lua` | +87 (新建) | 业务单元测试 | 考勤展示纯函数测试（15 项断言 PASS）。 |
| **D** | **混入的仓储 AE2 交互调整代码** | | | |
| 23 | `UI/WarehouseControls.lua` | +5 / -8 | 仓储业务调整 | 搜索模式与按钮布局微调。 |
| 24 | `UI/WarehouseDetails.lua` | +1 / -1 | 仓储业务调整 | 引用 TooltipManager 简化清理代码。 |
| 25 | `UI/WarehouseGrid.lua` | +5 / -6 | 仓储业务调整 | 网格项目选中与滚轮联动微调。 |
| 26 | `UI/WarehouseInput.lua` | +26 / -16 | 仓储业务调整 | 呼叫配送输入框事件处理。 |
| 27 | `UI/WarehousePage.lua` | +25 / -87 | 仓储主页面 | 清理手写 Tooltip 逻辑，改名为 WarehouseSourceTable。 |
| 28 | `UI/WarehouseSourceTable.lua` | +8 / -8 (重命名) | 仓储业务重命名 | 由原 `WarehouseList.lua` 重命名为来源明细表。 |
| 29 | `tests/lua/warehouse-ae2-test.lua` | +21 / -23 | 仓储单元测试 | 验证 AE2 交互（20 项断言 PASS）。 |
| 30 | `tests/lua/delivery-cart-test.lua` | +8 / -7 | 仓储单元测试 | 验证配送购物车逻辑（16 项断言 PASS）。 |
| **E** | **翻译同步与通用微调** | | | |
| 31 | `UI/OrderMonitorPage.lua` | +1 / -3 | 通用清理简化 | 统一调用 `Tooltip.clearOwner(self)`。 |
| 32 | `Translate/CN/IG_UI.json` | +1648 / -1609 | 国际化词条 | 全量 JSON 格式化与中文字典同步（含活动/仓储新键）。 |
| 33 | `Translate/EN/IG_UI.json` | +1629 / -1590 | 国际化词条 | 全量 JSON 格式化与英文字典同步。 |

> **基线判定结论**：  
> 虽然 `c12a14d` 混入了部分仓储与活动系统的业务提交，但这些代码本身均属于当前开发分支的合法业务成果，且未破坏架构隔离。**支持用户的决策：不执行回滚，保持代码现状；在后续任务中严格执行“单任务单提交、文件严格对应”的纪律**。

---

## 二、TooltipManager 专项审计与缺陷根因

实地代码位置：[`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/TooltipManager.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/TooltipManager.lua)

### 1. 发现的六大架构缺陷与隐患

#### 缺陷 1：`registry` 内存泄漏（持有被销毁 Widget 强引用）
- **代码位置**：[`TooltipManager.lua:53`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/TooltipManager.lua#L53) 与 [`TooltipManager.lua:118-121`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/TooltipManager.lua#L118-L121)
- **代码事实**：
  ```lua
  for widget in pairs(list) do
      Manager.clear(widget)
      if registry[widget] and registry[widget].owner == owner then
          registry[widget].owner = nil  -- 仅将 owner 置空，registry[widget] 条目依然存在！
      end
  end
  ```
- **后果**：`registry` 是模块级局部表（强引用）。`clearOwner` 之后，`registry[widget]` 依然存在。如果 Widget 已经被父级销毁，它仍然被 `registry` 强引用，导致 Lua GC / JVM 永远无法回收该控件及其附带的闭包。

#### 缺陷 2：页面再次激活后所有权断裂与幽灵 Tooltip（Ghost Tooltips）
- **代码位置**：[`TooltipManager.lua:123`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/TooltipManager.lua#L123)
- **调用链推演**：
  1. 页面创建时：`createChildren()` 调用 `Manager.attach(button, 'prerender', page)`，注册进 `owners[page][button] = true`；
  2. 玩家切出标签页：`page:deactivate()` 调用 `PageLifecycle.unmount(page)`，触发 `Manager.clearOwner(page)`；
  3. 执行 `owners[page] = nil`，所有权表被销毁；
  4. 玩家再次切回该标签页：`page:activate()` 被调用。**但 ISUI 控件不会重新执行 `createChildren()`**！
  5. 控件的 prerender hook 依然工作，鼠标悬停依然会弹出 Tooltip；
  6. 玩家再次切出标签页：触发 `Manager.clearOwner(page)`，但此时 `owners[page]` 为 `nil`！
  7. **致命后果**：下一次切页时没有任何控件会被关闭，弹出的 Tooltip 将永久定格在屏幕上，沦为“幽灵悬浮窗”！

#### 缺陷 3：所有权变更处理缺失
- **代码位置**：[`TooltipManager.lua:63`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/TooltipManager.lua#L63)
- **代码事实**：当调用 `register(widget, { owner = newOwner })` 时，代码仅执行了 `registry[widget].owner = owner`，但**没有从旧 Owner 的 `owners[oldOwner][widget]` 中移除**！导致旧 Owner 销毁时误伤已转移给新 Owner 的控件。

#### 缺陷 4：子控件清理充斥业务硬编码（反架构模式）
- **代码位置**：[`TooltipManager.lua:127-158`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/TooltipManager.lua#L127-L158)
- **代码事实**：
  ```lua
  if owner.details then ... end
  if owner.controls then ... end
  if owner.itemGrid then ... end
  if owner.sourceList then ... end
  if owner.orderList then ... end
  if owner.priorityHeaders then ... end
  if owner.skillsList then ... end
  ```
- **后果**：通用 Core 运行时严重反向污染，硬编码了仓库页、居民页的专属字段；新编写的页面（如活动页、物流页）字段若不在此列，则完全享受不到级联清理。

#### 缺陷 5：API 语义模糊（隐藏显示 vs 注销所有权混淆）
- `clear(widget)`：实质是 **Dismiss / Hide**（关闭可见性，隐藏 UI）；
- `clearOwner(owner)`：实质是 **Dismiss UI + 尝试 Unregister**，但只注销了一半（留下了 `registry` 强引用，破坏了 `owners` 使得再次切入无法工作）。

### 2. TooltipManager 修正架构设计
必须正交拆分两个维度的职责：
1. **显示层控制（UI Dismiss）**：
   - `Manager.dismiss(widget)`：立即隐藏单个控件的悬停框；
   - `Manager.dismissOwner(owner)`：页面切出（`deactivate`）时调用，仅隐藏名下所有控件当前弹出的 Tooltip 视口，**保留注册关系**！
2. **生命周期注销（Lifecycle Unregister）**：
   - `Manager.unregister(widget)`：彻底从 `registry` 与 `owners` 中删除该 widget，还原原生 hook；
   - `Manager.unregisterOwner(owner)`：页面真正销毁（`dispose`）时调用，递归注销所有子控件并释放所有表引用。
3. **消除硬编码，改用通用树遍历或 Scope 集中登记**：
   - 杜绝在 Manager 内部写 `owner.itemGrid`、`owner.skillsList` 等特化字段；
   - 所有子控件在创建时，通过 `scope:registerTooltip(widget, config)` 显式登记在当前页面的生命周期作用域中。

---

## 三、PersonnelPage 刷新机制与数据依赖深度审计

### 1. 关键代码实地查验事实

| 模块 / 函数 | 源码位置 | 真实代码事实与能力边界 |
| :--- | :--- | :--- |
| **CraftingService.watch** | [`CraftingService.lua:171-184`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/CraftingService.lua#L171-L184) | 维护 `token.world` 并与 `Registry.data()` 比较。当世界重置时下发 `{reason="WORLD_RESET"}`；同时挂载了 `Signals`、`Registry`、`Ledger` 的变动通知。 |
| **SettlementLedger** | [`SettlementLedger.lua:4, 81-84`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SettlementLedger.lua#L4) | 仅维护裸表 `listeners={}`。**无公开 watch/subscribe API**。仅在 `setReturnPoint`(L98) 与 `commit`(L146)（据点创建/改名/划区）时触发通知。**完全不感知居民加入/离开，不感知工种变化，无法捕获 WORLD_RESET**！ |
| **MembershipService** | [`MembershipService.lua:14, 19-23`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/MembershipService.lua#L14) | 持久化位于 `Registry.data().npcMembership`。其 `notify(id)` 触发 `LaborSignals.changed(id)` 与 `S.changed(id)`。负责居民身份认领、据点归属分配。 |
| **PersonnelService.enrichWorkers** | [`PersonnelService.lua:272-321`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/PersonnelService.lua#L272-L321) | 对输入的**每一个居民**执行 `readBodyDamage`（遍历身体各部位检查流血、感染、骨折）、4 次 `getStatVal`（读取疲劳、饥饿、口渴、耐力）、`Public.priorities`。每次调用执行几十次 Java JNI 穿透并频繁分配临时 table。 |
| **PersonnelPage:activate** | [`PersonnelPage.lua:296-309`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PersonnelPage.lua#L296-L309) | 挂载在 `Crafting.watch` 上。当收到 `WORLD_RESET` 时执行 `self.owner:close()`；其余任何微小制作变动都会触发 `self:refresh()`。 |
| **PersonnelPage:update** | [`PersonnelPage.lua:573-581`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PersonnelPage.lua#L573-L581) | 拥有独立的 `self.nextSyncCheck = now + 5000` 计数器，每 5 秒无条件调用一次 `self:refresh()`（全员扫描）。 |

### 2. 核心架构裁决：严禁未经证明将 `Crafting.watch` 替换为 `SettlementLedger`
原 Phase 1 计划中提出的“改用 SettlementLedger 观察句柄”是**严重脱离源码事实的错误设想**：
1. `SettlementLedger` 无法提供世界重置（`WORLD_RESET`）通知；直接替换会导致页面在跨世界重进时失去退出保护；
2. `SettlementLedger` 在居民增减、工作优先级调整时**根本不会被触发**；直接替换会导致居民页面成为死界面；
3. **真实根因**：原代码之所以借用 `Crafting.watch`，是因为 `CraftingService` 恰好整合了 `Registry.data()` 实例检查与 `Signals`。
4. **正确解决方案**：
   - 严禁假借据点账本替换；
   - 应当由 `RuntimeGate` 或通用 `WorldLifecycle` 统一暴露官方的 `watchWorldReset(callback)`；
   - 居民名册变动应当监听 `LaborSignals` 与 `MembershipService`；
   - 居民生理状态采样必须与名册解耦。

### 3. PersonnelPage 三级数据正交解耦模型

```
┌────────────────────────────────────────────────────────────────────────┐
│                   Level 1: Roster Snapshot (名册结构)                  │
│   数据源: MembershipService.members + PublicWork.priorities            │
│   内容: NPC ID, 姓名, 基础职业, 工作分配优先级                          │
│   刷新机制: 事件驱动 (LaborSignals / MembershipService)                │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│               Level 2: Static Profile Cache (技能与档案)               │
│   数据源: PersonnelService 内部 cache[id].value (由 static() 产出)     │
│   内容: 技能等级, XP倍率, 特质清单, 已知配方                           │
│   刷新机制: 永久缓存，仅在 LevelPerk 引擎事件或完成研习时按需置脏失效  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│              Level 3: Dynamic Health Snapshot (动态健康快照)           │
│   数据源: Java getBodyDamage() / getStats()                            │
│   内容: 生命值, 流血, 感染, 疲劳, 饥饿, 耐力                           │
│   刷新机制: 严禁全员无差别扫描！                                       │
│   ★ 主页面常驻 Physiological Inspector 消费当前选中居民 (selected)     │
│     在页面激活时调度快节拍 (3~5s) 采样其动态生理；展开详情抽屉时进一步 │
│     采样心情与日常日程；未选中 NPC 绝不执行高频 JNI 深度扫描           │
│   ★ 列表项仅展示极轻量的标量 summary (如是否有伤)，切出页面立即停止   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 四、RefreshScheduler 设计修正

### 1. 全页面周期刷新与轮询现状核实
实地查验全库 5 个主要业务页面：
- [`UI/WarehousePage.lua:644`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/WarehousePage.lua#L644)：仅调用 `Input.delivery(self)` 捕获输入，无周期轮询，完全由仓储事件驱动；
- [`UI/OrderMonitorPage.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/OrderMonitorPage.lua)：无 `update`，完全由 `OrderMonitorService.watch` 驱动；
- [`UI/LogisticsPage.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/LogisticsPage.lua)：无 `update`，事件驱动；
- [`UI/PersonnelPage.lua:577`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PersonnelPage.lua#L577)：**存在 5 秒全员无差别扫描轮询**；
- [`UI/ActivityPage.lua:611-617`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityPage.lua#L611-L617)：**存在每 1000ms 执行一次 `Service.revision()` 的周期检查**，若选中 Scene 还每分钟比对 `getWorldAgeHours`。

> **现状报告纠偏**：原报告将 ActivityPage 归类为“无盲目轮询”不准确，必须如实纠正为“存在 1 秒版本轮询”。

### 2. 最小 Scheduler API 规约与设计

严禁为每个页面继续手写 `self.nextSyncCheck` 或 `self.nextRefresh`。建立全模组单一调度器 `UI/Scheduler.lua`：

```lua
---@class EmberRoutesUIScheduler
local Scheduler = {}

-- 三级节拍定义 (毫秒)
Scheduler.CADENCE = {
    FAST = 3000,    -- 3s: 视口内选中实体的高频动态生理采样
    SLOW = 10000,   -- 10s: 列表慢速同步与版本巡检
}

-- 核心调度接口
---@param owner table 绑定的所有者页面/组件 (必须实现 valid() 或 getIsVisible())
---@param cadence number 刷新周期 (毫秒)
---@param taskFn function 具体的刷新操作函数
---@param priority string? 'HIGH' | 'NORMAL' | 'LOW' (默认 NORMAL)
---@return table handle 包含 cancel() 方法的任务句柄
function Scheduler.schedule(owner, cadence, taskFn, priority)

-- 事件脏标记合并接口 (在下一渲染帧前统一派发，避免 1 帧内多次触发)
---@param key string 业务脏键 (如 "settlement_workers" 或 "activity_revision")
---@param batchFn function 合并后执行的回调
function Scheduler.markDirty(key, batchFn)

-- 统一心跳入口 (由 EvenPaused 或 UI 根容器调用)
function Scheduler.tick()
```

#### 关键约束与安全防护：
1. **可见性与激活门禁 (Visibility Guard)**：
   每次执行前严格检查 `if not owner.active or not owner:getIsVisible() then return end`。页面隐藏或折叠时**绝对静止**，零 CPU 与零 GC 消耗；
2. **Dirty 合并 (Batch Coalescing)**：
   同一渲染帧内收到多次同一 key 的置脏通知，仅记录 `dirtyKeys[key] = true`，在 `tick` 阶段合并为单次执行；
3. **错误隔离 (Error Boundary)**：
   所有任务执行必须使用 `pcall` 包裹，若单次执行抛错，记录警告并启动指数退避，严禁阻断游戏主循环或其他页面；
4. **生命周期自动绑定**：
   任务句柄直接注入页面当前的作用域（Scope），页面 `deactivate` 时由框架自动 cancel，彻底杜绝孤儿定时器。

---

## 五、LifecycleScope 架构设计：双层作用域模型

为彻底解决“生命周期清理过度导致重新激活无法工作”与“生命周期清理不足导致内存泄漏”的双重矛盾，建立分层的生命周期体系：

```
Page Instance (创建: page:new / createChildren)
│
├── [PageLifetimeScope] (宿主级生命周期，生命期 = 页面实例存活期)
│   ├── 管理: 子控件树 (Child Widgets)
│   ├── 管理: Tooltip 静态注册 Hook (保留在 registry 中，切页不注销)
│   ├── 管理: 本地 Store 实例 (持久临时状态如 search, category)
│   └── 释放契约: 仅在 page:dispose() 时彻底注销并解开强引用
│
└── [ActivationScope] (会话级生命周期，生命期 = 页面激活活跃期)
    ├── 管理: 业务 Service Watch 订阅 (切出即断开)
    ├── 管理: Scheduler 周期定时任务 (切出即注销)
    ├── 管理: 临时模态弹窗 / 浮动抽屉 (切出即关闭)
    ├── 管理: 屏幕可见的 Tooltip 视口 (切出即 dismiss 隐藏)
    ├── 门禁: 具备 activation token，失效时静默丢弃一切异步回调
    └── 释放契约: 每次 page:deactivate() 时完整、对称释放
```

### 兼容性契约与集成
- 保持对现有 `PageLifecycle.mount(page, watch, receive)` 的完全兼容；
- 扩展 `PageLifecycle.createScope(page)`：
  ```lua
  function PageLifecycle.createScope(page)
      local scope = {
          token = {},
          active = true,
          watches = {},
          schedulers = {},
          drawers = {}
      }
      function scope:watch(serviceWatchFn, cb) ... end
      function scope:schedule(cadence, taskFn) ... end
      function scope:own(drawerOrModal) ... end
      function scope:dispose() ... end -- 一键释放 ActivationScope 名下全部资源
      return scope
  end
  ```
- 这样，`TooltipManager.dismissOwner(page)` 仅作为 `ActivationScope` 的一部分隐藏悬浮窗；而 `TooltipManager.unregisterOwner(page)` 归入 `PageLifetimeScope` 在 `dispose` 时执行。

---

## 六、Static Draw 规范合规审计

实地代码位置：[`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityAtmosphereBoard.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityAtmosphereBoard.lua)

### 1. 违背规范的代码事实与诊断

| 违规项 | 源码行号 | 违规代码片段 | 违规性质与引擎影响 |
| :--- | :--- | :--- | :--- |
| **动态 table 分配** | L43-45 | `local badgeCol = state == 'RUNNING' and { r = 0.25, g = 0.75, b = 0.45, a = 1 } or ...` | **高频 GC 炸弹**。每次 `drawStrip` 绘制都在堆内存分配新 table。 |
| **动态 table 分配** | L72 | `Theme.rect(owner, ..., { r = 0.15, g = 0.18, b = 0.22, a = 1 })` | 进度条背景每帧分配 table。 |
| **动态 table 分配** | L98, L124-128, L142, L158 | 多处 `{ r = ..., g = ..., b = ... }` 硬编码颜色表 | 每一个居民卡片每帧分配 3~4 个 table。 |
| **高频字符串拼接** | L48 | `t('currentPhase') .. ': ' .. phaseName` | 绘制循环中进行字符串连接，产生瞬态垃圾。 |
| **高频字符串拼接** | L96 | `Presentation.outcomeText(detail.outcome) .. ' · ' .. t('benefitDebriefNotice')` | 结语条幅每帧拼接字符串。 |
| **高频字符串拼接** | L135-136 | `name .. roleTag` | 每个居民每帧拼接头衔。 |
| **JNI 文本测量穿透** | L64 | `getTextManager():MeasureStringX(UIFont.Small, timeText)` | 逐帧穿透至 Java 层进行字符串宽度计算。 |
| **JNI 文本测量穿透** | L140 | `getTextManager():MeasureStringX(UIFont.Small, badgeText)` | 每一个居民状态胶囊每帧调用 Java 文本测量。 |
| **Render 阶段业务计算** | L40, L53, L76-86 | `getGameTime():getWorldAgeHours()`, 计算倒计时与进度百分比 | 业务计算侵入绘制层，违反 Presentation 单向准备原则。 |

### 2. 关联组件违规扫描
- **`ActivityPage.lua:579`**：在 `Page.drawRow` 中同样存在逐帧 `MeasureStringX(UIFont.Small, badgeText)`，且手写了 `drawRect`、`drawRectBorder`，未复用标准 `SemanticBadge.draw`。
- **整改要求**：
  1. 所有颜色值全部提取至 `Theme.lua` 作为静态单例常量或 Theme 语义令牌；
  2. 文本拼接与倒计时格式化必须移入 `ActivityPresentation.lua`，在数据变化或更新节拍时派生为 ViewModel 快照；
  3. 文本宽度必须在 ViewModel 准备阶段调用 `UICache` 预先计算并缓存在行对象中；
  4. Draw 函数内必须实现 100% 只读渲染，**0 table 分配、0 字符串拼接、0 JNI 测量**。

---

## 七、调整后的 Phase 1 阶段工程路线图

根据本次代码证据前置审查，原计划的 Task 1.6 存在严重数据源设计缺陷，且缺少前置的生命周期双层管理。现对 Phase 1 执行顺序进行如下调整：

```
阶段一重构路线图 (调整后)
│
├── [已完成] Task 1.1 ~ 1.5: 首批技术债务出清 (StepperInput, CardPanel, Shim, 初版Tooltip)
│
├── [P0] Task 1.5A: TooltipManager 架构修正与双层生命周期对齐
│   ├── 消除 registry 强引用内存泄漏 (注销时真正移除条目)
│   ├── 正交解耦 UI Dismiss 与 Lifecycle Unregister (支持多次挂载/切页)
│   ├── 消除硬编码业务字段，改为通用树遍历与 Scope 登记
│   └── 落地多轮切页与所有权变更专项回归测试
│
├── [P1] Task 1.5B: 新组件 Static Draw 零 GC 规范合规化
│   ├── 重构 ActivityAtmosphereBoard: 消除 100% 动态 table 分配
│   ├── 文本测量与格式化全部前置入 ActivityPresentation ViewModel
│   └── ActivityPage.drawRow 接入标准 SemanticBadge.draw
│
├── [P0] Task 1.6: LifecycleScope 双层作用域基础设施落地
│   ├── 明确区分 ActivationScope (切出释放) 与 PageLifetimeScope (销毁释放)
│   ├── 统一托管 Watch、Store 订阅、Scheduler 任务、弹窗与 Tooltip
│   └── 保持 activation token 门禁向后兼容
│
├── [P0] Task 1.7: RefreshScheduler 统一调度器建设
│   ├── 建立 FAST (3~5s) / SLOW (10~15s) 分级节拍与 Dirty 合并机制
│   ├── 接入物理可见性与激活门禁 (未激活绝对静止)
│   └── 包含 pcall 错误隔离与退避防护
│
├── [P0] Task 1.8: PersonnelPage 刷新重构与数据模型三级解耦
│   ├── 查明世界重置基准源，严禁未经证明将 Crafting.watch 替换为 SettlementLedger
│   ├── 名册结构 (事件驱动) + 静态档案 (永久缓存) + 动态健康 (聚焦快节拍) 三级分离
│   ├── 切出页面 0 轮询，抽屉未展开时不扫描单人身体细节
│   └── ActivityPage 的 1 秒 revision 轮询平滑迁移至 Scheduler
│
└── [P0] Task 1.9: 阶段一全量回归测试与质量验收
    ├── 全量单元测试通过 (tests/lua/*.lua)
    ├── 静态规则扫描 0 错误 (pz.mjs lint)
    └── 内存分配与 GC 压力对照测试
```

---

## 八、测试矩阵与验证规划

| 测试文件 | 目标验证场景 | 预期断言 |
| :--- | :--- | :--- |
| `tests/lua/tooltip-lifecycle-test.lua` (新建) | 1. 注册 -> 显示 -> 切出 (dismiss) -> 切回 -> 显示 -> 切出 (dismiss) 全链路；<br>2. 页面 `dispose` 后 `registry` 彻底释放；<br>3. 控件 Owner 动态变更；<br>4. 两个独立页面互相切页时不产生幽灵 Tooltip。 | 断言再次切入后 Tooltip 仍可工作；断言多次切页后 registry 不泄漏；断言跨页面不误杀。 |
| `tests/lua/atmosphere-board-zero-gc-test.lua` (新建) | 1. Static Draw 阶段内存开销测试；<br>2. 验证绘制函数内不调用 `MeasureStringX`、不产生 table 分配。 | Mock table 创建与 JNI 拦截，断言 drawStrip 与 drawResidentCard 过程内 0 次 table 分配。 |
| `tests/lua/lifecycle-scope-test.lua` (新建) | 1. ActivationScope 一键释放 Watch、Scheduler 与 Modal；<br>2. 异步回调在 token 失效后静默阻断；<br>3. PageLifetimeScope 在页面注销时对称结清。 | 断言异常打断、切页时所有外部订阅 100% 解除。 |
| `tests/lua/scheduler-test.lua` (新建) | 1. 未激活页面任务不执行；<br>2. 同一帧多次 markDirty 合并为 1 次派发；<br>3. 单任务抛错不影响后续任务。 | 断言合并派发次数；断言可见性门禁生效。 |
| `tests/lua/personnel-refresh-test.lua` (新建) | 1. 名册变更触发列表更新；<br>2. 未展开抽屉时不执行单人生理读取；<br>3. 切出页面后后台 0 采样。 | 断言 JNI 采样次数仅限制在当前选中项。 |

---

## 九、风险与未验证项声明

1. **未在当前轮次修改代码**：根据用户指令，本次审查仅限深度实地审计与技术方案修正，生产代码严格保持在 `c12a14d` 基线；
2. **Kahlua 实机 JNI 特性差异**：标准 Lua 替身环境下通过 mock 测试，但 Project Zomboid 42.21 实机对 table 遍历、`getTextManager` 的具体表现仍需在实机调试时进行微调；
3. **世界重置官方标准接口尚待沉淀**：目前全模组缺乏统一的全局 `WorldLifecycle` 观察者，`CraftingService.watch` 的历史借用虽有结构瑕疵，但在新机制就绪前不可强行粗暴剥离。
