# EmberRoutes UI Runtime 现状核验报告 (Current State Audit)

> 日期：2026-11-01  
> 基线：`version.txt 0.29.14`，Git HEAD `c12a14d` (commit c12a14d0f945073716306f0ff7ae5c975a82e0ef)
> 状态：Phase 0 实施复核与设计纠偏完成，作为 Phase 1 细化实施的实地依据

---

## 一、Git 状态与工作区基线核实

1. **版本与分支状态**：
   - 当前模组版本为 `0.29.14`；
   - 代码根目录位于 `Contents/mods/EmberRoutesProbe/42/media/lua/`，所有核心 UI 模块集中在 `client/EmberRoutesProbe/UI/` 下；
   - 静态检查基线：323 个 Lua 源文件通过 `pz.mjs lint` 扫描，0 错误；已消除 `LC01-prerender-must-reach-ancestor` 违规。

2. **审计报告结论落地复核**：
   - **`PublicOrderDialog` 接入 `StepperInput`**：已完成。消除了 55 行手写步进器样板代码，统一由 [`UI/StepperInput.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/StepperInput.lua) 提供单次委托量、最低存量与批次量调节；
   - **`ActivityScenarioCard` 委托绘制**：已完成。卡片背景与左侧状态条委托给 [`UI/CardPanel.lua:34`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/CardPanel.lua#L34)；
   - **`PersonnelPage` 消除双重投影**：已完成。删除了 [`UI/PersonnelPage.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PersonnelPage.lua) 中 `setState()` 后多余的手动 `project()` 调用；
   - **`ActivityDialog.lua` 消除双轨制**：已完成。全库检索确认无外部菜单依赖旧窗口；原 519 行重复旧实现已重构为 20 行透明转发层（Shim），统一导向 [`UI/ActivityPage.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityPage.lua)，回归测试 28 项断言全部通过；
   - **`TooltipManager` 建设**：已完成。新建生命周期自愈型 [`UI/TooltipManager.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/TooltipManager.lua)，并在 [`UI/PageLifecycle.lua:29`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PageLifecycle.lua#L29) 的 `unmount()` 中接入级联清理，`WarehousePage` 等页面的手动清理代码已简化。

---

## 二、现有模块清单与依赖关系盘点

经过全盘代码扫描，现有 UI 体系包含 60 个相关源文件，划分为以下四个梯队：

### 1. 核心基础设施（Core Runtime 雏形）
| 文件路径 | 行数 | 职责与能力 | 现状与问题 |
| :--- | :---: | :--- | :--- |
| [`UI/State.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/State.lua) | 52 | 局部状态 Store，支持 `setState` 与监听者订阅 | 缺少精细脏键通知与批量更新合并机制 |
| [`UI/PageLifecycle.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PageLifecycle.lua) | 32 | `mount/unmount` 门禁，基于 activation token 防止孤儿回调 | 已集成 `TooltipManager.clearOwner`，需扩展为通用 Scope |
| [`UI/Layout.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/Layout.lua) | 98 | 相对轴向弹性布局计算 (`Layout.axis`) | 运行良好，计算结果必须在 resize/mount 时缓存，严禁逐帧计算 |
| [`UI/Theme.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/Theme.lua) | 95 | 统一调色板、语义色、按钮与面板样式 | 颜色令牌完整，部分业务页面仍存在局部硬编码 `getCore():getScreenWidth()` 比例 |
| [`UI/UICache.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/UICache.lua) | 48 | 文本测量与格式化字符串缓存 | 覆盖有限，未在所有列表项中强制接入 |
| [`UI/TooltipManager.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/TooltipManager.lua) | 148 | 统一悬浮提示、屏幕边缘回弹与所有权级联清理 | 已替代原 35 行 `TooltipAnchor`，各页面正逐步接入 |
| [`UI/PageRegistry.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PageRegistry.lua) | 165 | 集中注册仪表盘页签与元数据 | 承担路由导航职责，运行稳定 |

### 2. 通用与展示组件（Widgets & Components）
| 模块名 | 模式类别 | 代码文件 | 现状分析 |
| :--- | :--- | :--- | :--- |
| `CardPanel` | Static Draw | [`UI/CardPanel.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/CardPanel.lua) | 提供只读面板背景与 Accent 条绘制，无 ISPanel 开销 |
| `SemanticBadge` | Static Draw | [`UI/SemanticBadge.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/SemanticBadge.lua) | 统一状态徽章绘制（READY/WAIT/ALERT/INACTIVE） |
| `StatMeter` | Static Draw | [`UI/StatMeter.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/StatMeter.lua) | 属性进度条与阈值警示绘制 |
| `CachedList` | Interactive | [`UI/CachedList.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/CachedList.lua) | 滚动列表基础控件，行高缓存与只读绘制 |
| `StepperInput` | Interactive | [`UI/StepperInput.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/StepperInput.lua) | 数字步进输入框，已支持增减、滚轮与清洗 |
| `FilterChips` | Interactive | [`UI/FilterChips.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/FilterChips.lua) | 标签式筛选选择器 |
| `ActivityScenarioCard` | Hybrid | [`UI/ActivityScenarioCard.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityScenarioCard.lua) | 业务情境卡片，已成功接入 `CardPanel.draw` 基础设施 |

### 3. 数据适配层（Presentation）
- [`UI/ItemPresentation.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ItemPresentation.lua)：将底层物品类型、重量、品类格式化为展示快照；
- [`UI/ActivityPresentation.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityPresentation.lua)：无状态纯函数层，负责将底层考勤状态码转换为玩家通俗语言和语义徽章；
- [`UI/LogisticsPresentation.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/LogisticsPresentation.lua)：物流链路与运力状态呈现。

### 4. 业务页面（Pages）
- [`UI/WarehousePage.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/WarehousePage.lua) (656 行)：仓储管理主页面，拥有网格、列表、筛选条及购物车抽屉；
- [`UI/PersonnelPage.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PersonnelPage.lua) (663 行)：居民工作安排与档案管理；
- [`UI/ActivityPage.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityPage.lua) (640 行)：社区生活与公共活动编排；
- [`UI/OrderMonitorPage.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/OrderMonitorPage.lua) (270 行)：公共委托与生产工单监控；
- [`UI/LogisticsPage.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/LogisticsPage.lua) (326 行)：运输路线与站点分配。

---

## 三、各页面刷新机制与生命周期现状审计

| 页面 | 当前挂载监听 (Mount) | 当前周期刷新 (Update) | 卸载与清理 (Deactivate) | 存在的问题与实地诊断 |
| :--- | :--- | :--- | :--- | :--- |
| **WarehousePage** | `Index.watch(id, cb)` | 无定时轮询，由事件与用户输入触发；`Input.delivery(self)` 捕获输入 | 已简化为 `Tooltip.clearOwner(self)`；释放购物车抽屉与巡查器 | **健康**。完全事件驱动，无无界空转。 |
| **OrderMonitorPage** | `OrderMonitorService.watch(id, cb)` | 无定时轮询，依赖工单执行事件通知 | 已接入 `Tooltip.clearOwner(self)`，注销 Watch，销毁弹窗 | **健康**。数据按需推送。 |
| **ActivityPage** | 挂载本地 Store 订阅，监听活动生命周期 | [`ActivityPage.lua:611-617`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityPage.lua#L611-L617)：**每 1000ms 轮询检查 `Service.revision` 与游戏分钟数** | 清理规则控件、重置输入框、清理控件 Tooltip | **需治理**。存在独立的 1 秒 revision 轮询；尚未接入完整生命周期作用域。 |
| **PersonnelPage** | `Crafting.watch(actor, id, cb)`（**历史借用监听**） | [`PersonnelPage.lua:577-580`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PersonnelPage.lua#L577-L580)：**每 5000ms 全员无差别扫描动态生理** | 已接入 `Tooltip.clearOwner(self)`，释放详情抽屉与选人缓存 | **存在结构矛盾**：借用工单监听捕获世界重置；每次轮询全量扫描全体居民的生理健康与创伤。 |
| **LogisticsPage** | `LogisticsService.watch(id, cb)` | 无定时轮询 | 注销 Watch，重置选区 | **健康**。 |

---

## 四、数据依赖与观察源实地审计结论

### 1. `PersonnelPage` 动态生理与静态数据分离
1. **静态与慢速数据（已有 Service 缓存）**：
   - 性别、职业、立绘（[`PersonnelService.lua:67-108`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/PersonnelService.lua#L67-L108)）：一次性解析并永久缓存于内部闭包 `cache[id].value`（由 `static()` 生成）；
   - 技能等级与 XP 倍率（[`PersonnelService.lua:151-171`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/PersonnelService.lua#L151-L171)）：缓存在 `cache[id].value.skills` 中，仅在结算或 LevelPerk 时失效；
   - 已知配方与特质（[`PersonnelService.lua:172-187`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/PersonnelService.lua#L172-L187)）：缓存在 `cache[id].value` 表中。
2. **动态生理与健康数据（引擎底层绝对无事件通知）**：
   - 饥饿、疲劳、口渴、压力、情绪（[`PersonnelService.lua:110-127`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/PersonnelService.lua#L110-L127)）：Java 虚拟机在游戏刻内逐刻更新，Kahlua 侧无 Listener 机制；
   - 身体损伤（生命值、流血部位数、感染、骨折创伤）（[`PersonnelService.lua:129-149`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/PersonnelService.lua#L129-L149)）：同样无事件通知。
3. **全员扫描痛点与性能瓶颈**：
   - `enrichWorkers`（[`PersonnelService.lua:272-321`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/PersonnelService.lua#L272-L321)）对名册内所有 NPC 逐一读取 body damage 和 4 项 CharacterStat。当居民增多时，每 5 秒触发密集的 Java JNI 反射穿透与堆内存 table 创建；
   - **优化架构**：拆分为“名册结构 (事件驱动) + 静态档案 (永久缓存) + 动态健康 (当前选中 NPC 聚焦采样 3~5s)”，非聚焦居民仅展示极轻量标量 summary。

### 2. `SettlementLedger` 与 `CraftingService.watch` 的代码事实澄清
- **严禁未经证明将 `Crafting.watch` 替换为 `SettlementLedger`**：
  1. `SettlementLedger.lua:4, 81-84` 仅有裸数组 `listeners`，无标准 watch/subscribe 接口；
  2. `SettlementLedger.notify` 仅在 `setReturnPoint` 与 `commit`（划区/改名）时触发，**完全不感知居民加入/离开、工种优先级分配，也无法感知 `WORLD_RESET`**；
  3. `CraftingService.watch`（[`CraftingService.lua:171-184`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/CraftingService.lua#L171-L184)）实质承担了 `WORLD_RESET` 实例比对守卫职责。盲目替换会导致页面失去跨世界重进退出保护。必须通过全局生命周期基准源进行规范解耦。

---

## 五、保留资产与技术债务清单

### 1. 明确保留且需推广的优秀设计
- `PageLifecycle` 的 `activation token` 异步门禁机制（杜绝孤儿回调）；
- `Layout.axis` 相对弹性布局体系（杜绝手写魔数绝对坐标）；
- `CardPanel.draw` 与 `SemanticBadge.draw` 的 Static Draw 模式（零 GC、无控件树开销）；
- `Presentation` 层的纯函数展示适配；
- `StepperInput` 标准控件接入（消除手写步进器）。

### 2. 实地复核新暴露的技术债务 (Phase 1 修正治理项)
- **`TooltipManager` 生命周期闭环缺陷**：`registry` 存在被销毁控件强引用内存泄漏；切出页面后所有权表被清空导致再次激活时 Tooltip 成为不可清理的幽灵；硬编码了业务子控件字段；
- **`ActivityAtmosphereBoard` 违反零 GC 规范**：[`ActivityAtmosphereBoard.lua`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityAtmosphereBoard.lua) 在绘制循环中存在每帧动态 table 分配、字符串拼接与 JNI `MeasureStringX` 文本测量；
- **多页面孤立轮询计数器**：`PersonnelPage` (5s) 与 `ActivityPage` (1s) 各自维护私有计数器，缺乏统一调度器 (Scheduler) 的可见性门禁与 Dirty 合并机制。
