# EmberRoutes UI Runtime 现状核验报告 (Current State Audit)

> 日期：2026-11-01  
> 基线：`version.txt 0.29.14`，Git HEAD `667c7c2` + 本地已提交及工作区治理变更  
> 状态：Phase 0 现状核验完成，作为架构规范的实地依据

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

| 页面 | 当前挂载监听 (Mount) | 当前周期刷新 (Update) | 卸载与清理 (Deactivate) | 存在的问题与诊断 |
| :--- | :--- | :--- | :--- | :--- |
| **WarehousePage** | `Index.watch(id, cb)` | 无定时轮询，完全由事件与用户输入触发 | 已简化为 `Tooltip.clearOwner(self)`；释放购物车抽屉与巡查器 | **健康**。完全事件驱动，无无界空转。 |
| **OrderMonitorPage** | `OrderMonitorService.watch(id, cb)` | 无定时轮询，依赖工单执行事件通知 | 已接入 `Tooltip.clearOwner(self)`，注销 Watch | **健康**。数据按需推送。 |
| **ActivityPage** | 挂载本地 Store 订阅，监听活动生命周期 | 无盲目轮询，由草稿切换与列表刷新驱动 | 清理规则控件、重置输入框 | **较健康**。尚未接入完整的 `PageLifecycle.mount` 自动注销。 |
| **PersonnelPage** | `Crafting.watch(actor, id, cb)`（**错位监听**） | `self.nextSyncCheck = now + 5000`（**5 秒全员轮询**） | 已接入 `Tooltip.clearOwner(self)`，释放详情抽屉与选人缓存 | **存在结构矛盾**：监听了无关的工单模块；每次轮询全量扫描全体居民的生理健康。 |
| **LogisticsPage** | `LogisticsService.watch(id, cb)` | 无定时轮询 | 注销 Watch，重置选区 | **健康**。 |

---

## 四、`PersonnelPage` 数据依赖实地审计结论

1. **静态与慢速数据（已有 Service 缓存）**：
   - 性别、职业、立绘（[`PersonnelService.lua:67-108`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/PersonnelService.lua#L67-L108)）：一次性解析并永久缓存于 `cache[id].static`；
   - 技能等级与 XP 倍率（[`PersonnelService.lua:151-171`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/PersonnelService.lua#L151-L171)）：缓存在 `cache[id].static.skills` 中，仅在结算时失效；
   - 已知配方与特质（[`PersonnelService.lua:172-187`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/PersonnelService.lua#L172-L187)）：同样缓存在 `static` 表中。
2. **动态生理与健康数据（引擎底层绝对无事件通知）**：
   - 饥饿、疲劳、口渴、压力、情绪（[`PersonnelService.lua:110-127`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/PersonnelService.lua#L110-L127)）：Java 虚拟机在游戏刻内逐刻更新，Kahlua 侧没有任何 Listener 机制；
   - 身体损伤（生命值、流血部位数、感染、骨折创伤）（[`PersonnelService.lua:129-149`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/PersonnelService.lua#L129-L149)）：同样无事件通知。
3. **关键裁决**：
   - **不能彻底删除定时刷新**：若盲目追求事件驱动而删除轮询，打开页面后 NPC 的流血、饥饿与濒死状态将永久定格；
   - **优化方向**：剥离无关的 `Crafting.watch`；将全员扫描改为“当前视口选中者聚焦刷新（3~5s） + 列表大状态超低频刷新（10~15s）”，并在切出页面（`deactivate`）时坚决停更。

---

## 五、保留资产与技术债务清单

### 1. 明确保留且需推广的优秀设计
- `PageLifecycle` 的 `activation token` 异步门禁机制（杜绝孤儿回调）；
- `Layout.axis` 相对弹性布局体系（杜绝手写魔数绝对坐标）；
- `CardPanel.draw` 与 `SemanticBadge.draw` 的 Static Draw 模式（零 GC、无控件树开销）；
- `TooltipManager` 的屏幕边界夹持与 owner 级联自愈释放；
- `Presentation` 层的纯函数展示适配。

### 2. 需在 Phase 1 重点治理的技术债务
- **`PageLifecycle` 孤立使用**：目前主要在 `WarehousePage` 和 `PersonnelPage` 接入，`ActivityPage` 和部分子抽屉仍手写 `activate/deactivate`；
- **错位数据监听**：`PersonnelPage` 依然挂在 `Crafting.watch` 上；
- **缺乏统一调度器 (Scheduler)**：各页面自备 `nextSyncCheck` 或 `update` 计数器，缺乏统一的可见性门禁与节拍控制；
- **Store 能力单薄**：`State.lua` 每次 `setState` 广播全量更新，缺乏分键（Key-specific）订阅与合并能力。
