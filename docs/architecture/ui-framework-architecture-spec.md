# EmberRoutes UI Framework Architecture Specification
# 余烬商路 UI 框架与轻量运行时架构规范

> 状态：Phase 0 权威设计基线｜版本：1.0.0｜编制日期：2026-11-01  
> 适用：EmberRoutes 全体 UI 页面、组件、展示适配与运行时基础设施

---

## 1. 架构目标与哲学

### 1.1 核心定位
**EmberRoutes UI Runtime** 是一套针对 Project Zomboid (B42)、Kahlua VM 和原生 ISUI 深度优化的**轻量级、显式、零 GC 压力、单向数据流 UI 运行时**。
它不是现代 Web 框架（Vue/React/Svelte）在 Lua 中的微缩复刻版，而是吸收其成熟软件工程思想，结合游戏引擎底层特性的专用架构。

### 1.2 技术思想取舍矩阵
| 参考框架 | 深度借鉴的设计思想 | 严禁引入的实现机制 |
| :--- | :--- | :--- |
| **Vue** | 显式响应式状态 (Store)、计算属性 (Computed/Selector)、组合式组件 | ❌ 模板编译器、Virtual DOM、Proxy 自动深度依赖追踪 |
| **React** | 单向数据流 (Unidirectional Data Flow)、显式状态所有权、严苛组件边界 | ❌ 每次更新全量重算组件树、Fiber 调度器、JSX |
| **Svelte** | 低运行时开销哲学、编译/前置计算、脏数据精确派生 | ❌ 代码生成器、独立 DSL 语法 |
| **Qt / MVP** | 控件对象生命周期闭环、父子所有权树、显式信号/槽 (Callback) | ❌ 巨型类多重继承深渊、强类型元对象编译 |

---

## 2. 总体四层架构与权威边界

UI 框架采用严格的四层分层结构，**业务服务层 (Business Services) 绝对独立于 UI 框架之外**：

```
┌────────────────────────────────────────────────────────┐
│              Business Services (业务服务层)             │
│   WarehouseIndex · PersonnelService · CraftingService  │
│   SettlementLedger · LaborClaims · ActivityService     │
│   ★ 掌握业务真相、持久化实体与状态变动的唯一权威       │
└───────────────────────────▲────────────────────────────┘
                            │ (业务事件通知 / 操作意图提交)
                            ▼
┌────────────────────────────────────────────────────────┐
│                   L4 · Pages (业务页面层)              │
│   WarehousePage · PersonnelPage · ActivityPage 等      │
│   ★ 组织页面布局、编排生命周期、派发用户意图           │
└───────────────────────────▲────────────────────────────┘
                            │ (消费展示快照 / 向上提交交互)
                            ▼
┌────────────────────────────────────────────────────────┐
│               L3 · Presentation (展示适配层)           │
│   Selectors · ViewModels · Formatters · Badges         │
│   ★ 纯无状态函数：将业务只读快照转换为玩家视口快照     │
└───────────────────────────▲────────────────────────────┘
                            │ (调用绘制与通用交互)
                            ▼
┌────────────────────────────────────────────────────────┐
│                  L2 · Widgets (通用组件库)             │
│   [Static Draw]   CardPanel · SemanticBadge · StatMeter│
│   [Interactive]   CachedList · StepperInput · Modal    │
│   ★ 具备稳定输入输出、统一主题契约的可复用单元         │
└───────────────────────────▲────────────────────────────┘
                            │ (底层生命周期、调度与布局支撑)
                            ▼
┌────────────────────────────────────────────────────────┐
│                L1 · Core Runtime (核心运行时)           │
│   State · PageLifecycle (Scope) · Scheduler · Layout   │
│   Theme · UICache · TooltipManager · Localization      │
│   ★ 驱动整个 UI 体系运转的基础设施                     │
└────────────────────────────────────────────────────────┘
```

### 2.1 依赖红线与权威隔离
1. **单一事实来源 (Single Source of Truth)**：
   - 真实库存、工单阶段、居民生理健康、NPC 任务认领等权威数据**永远归属 Business Service**；
   - **UI Store 严禁成为第二套业务数据库**。UI Store 仅允许存储“界面临时状态”（如当前选中项 `selectedId`、当前搜索词 `searchTerm`、当前筛选类别 `category`、抽屉是否展开 `drawerOpen`）。
2. **禁止跨层穿透**：
   - **禁止 Widget 直连 Service**：Widget 只能通过参数接收标量数据或回调，绝不允许在 `Card` 或 `Badge` 内部直接 `require('...Service')` 查询数据；
   - **禁止 Render 穿透**：`prerender` 与 `render` 必须绝对只读已缓存的 ViewModel，严禁在渲染循环中调用业务扫描、Java JNI 查询或重量级文本测量。

---

## 3. L1 Core Runtime API 契约规范

### 3.1 State (响应式局部状态)
- **定位**：页面或局部组件的纯状态容器；
- **契约 API**：
  ```lua
  local store = State.new(initialState)
  local unsubscribe = store:subscribe(listener, keyFilter)
  store:setState(partialState)
  local currentState = store.value
  ```
- **核心约束**：
  - 支持 `keyFilter`（脏键过滤），仅在关心的键变动时通知订阅者；
  - `setState` 自动执行单层浅比较与浅合并；若值未发生变化则阻断通知；
  - 严禁在订阅回调中同步递归调用自身的 `setState` 导致无限循环。

### 3.2 Lifecycle Scope (统一所有权与自愈释放)
- **定位**：树形所有权与生命周期的自动收割机；
- **生命周期树**：`Dashboard -> Page -> Component / Watch / Timer / Tooltip`；
- **契约 API**：
  ```lua
  local scope = Lifecycle.createScope(page)
  scope:watch(serviceWatchFn, callback)     -- 页面注销时自动关闭 Service Watch
  scope:subscribe(store, listener)           -- 页面注销时自动解除 Store 订阅
  scope:schedule(intervalMs, taskFn)         -- 页面注销时自动取消定时任务
  scope:registerTooltip(widget, config)      -- 页面注销时自动清空 Tooltip
  scope:dispose()                            -- 一键对称结清名下所有资源
  ```
- **核心约束**：
  - 严格保持 `activation token` 门禁，任何延迟到达的回调，只要 token 失效，立即静默丢弃；
  - 页面关闭或切页（`deactivate`）时，其名下持有的 Watch、监听、定时器、浮动抽屉、Tooltip 必须 100% 对称释放，严禁残留跨页悬挂。

### 3.3 Scheduler (刷新调度协调器)
- **定位**：全模组 UI 刷新的交通警察，杜绝全员无序高频轮询；
- **三级刷新契约**：
  1. **Event-driven (事件驱动级)**：仓储变化、工单流转、活动创建等有明确业务事件的数据，发生时仅打上 `dirty` 标记，由 Scheduler 合并至下一渲染帧前统一派发；
  2. **Fast Cadence (可见视口快节拍，3~5s)**：针对引擎底层绝对无事件通知的动态生理/健康数据（饥饿、受伤、疲劳），仅在**当前页面处于激活且物理可见**时执行低频补充扫描；
  3. **Slow Cadence (全局慢节拍，10~15s)**：非聚焦环境统计、远端据点状态等慢速数据。
- **调度红线**：
  - **隐藏即静止**：未激活（`not active`）或折叠隐藏的页面，其关联的所有 Cadence 任务必须立刻冻结，禁止在后台消耗 CPU 与 GC；
  - **合并去重**：同一刷新帧内收到同一数据源的多次通知，必须合并为一次展示投影计算。

### 3.4 TooltipManager (悬浮提示基础设施)
- **定位**：全模组 Tooltip 挂载、坐标纠偏、边缘夹持与生命周期闭环管理；
- **契约 API**：
  ```lua
  TooltipManager.register(widget, { owner = page, method = "prerender", text = "..." })
  TooltipManager.update(widget, dynamicTextOrData)
  TooltipManager.clear(widget)
  TooltipManager.clearOwner(owner)
  TooltipManager.clearAll()
  ```
- **核心约束**：
  - 必须对 B42 本地坐标偏移实施修正（`+32, +10`）；
  - 必须根据 `getCore():getScreenWidth/Height` 做屏幕边界夹持，防止右侧/下方内容溢出视口；
  - 页面 `unmount` 时必须通过 `clearOwner` 自动收割名下全部提示框，严禁残留悬浮窗。

### 3.5 Layout, Theme 与 UICache
- **Layout**：必须采用 `Layout.axis` 相对弹性布局计算，严禁手写硬编码魔法像素；布局结果必须在挂载或尺寸改变时完成计算并缓存，严禁逐帧调用；
- **Theme**：字体、间距、语义色（READY/WAIT/ALERT/INACTIVE）、边框统一使用 `Theme` 令牌；
- **UICache**：所有长文本换行（`Text.wrapLimited`）必须基于 `(text, width, font)` 建立哈希缓存，避免每帧执行底层 JNI 文本宽度测量。

---

## 4. L2 Widgets 开发规范

组件必须严格按照两种架构模式进行开发，严禁混淆：

### 4.1 模式 A：Static Draw (静态绘制组件)
- **适用场景**：列表中反复出现数百次的高密度视觉单元，如 `ItemCard`、`ResidentCard`、`SemanticBadge`、`StatMeter`、`CardPanel`；
- **实现契约**：
  - **严禁继承 `ISPanel` 或创建原生控件对象**；
  - 仅暴露纯无状态绘制函数：`Component.draw(target, x, y, width, height, data, ...)`；
  - 绘制所需坐标与尺寸必须由调用方传入；
  - **零 GC 红线**：绘制函数体内严禁动态创建 table、严禁字符串拼接，所需颜色与图标必须为预定义常量。

### 4.2 模式 B：Interactive Widget (原生交互组件)
- **适用场景**：真正需要键盘焦点、鼠标滚轮、文本输入或复杂状态交互的控件，如 `StepperInput`、`SearchInput`、`CachedList`、`ModalDialog`；
- **实现契约**：
  - 继承自标准 `ISPanel` / `ISUIElement`；
  - 具备明确的所有权定义（必须持有 `parent` 或 `owner`）；
  - 对外提供标准数据接口（如 `getValue() / setValue(v) / setOnChange(callback)`）；
  - 内部必须包含健全的事件守卫（如 `syncing` 标记防止外部级联反弹，删空时边界校验）。

---

## 5. L3 Presentation 与展示模型规范

### 5.1 单向数据流闭环
数据流严格遵循顺时针单向闭环，禁止双向倒灌：

$$\text{Service (业务事实)} \xrightarrow{\text{快照推送}} \text{Presentation (只读投影)} \xrightarrow{\text{派生}} \text{Cached ViewModel} \xrightarrow{\text{驱动}} \text{Render (零GC绘制)}$$
$$\text{User Interaction (用户点击)} \xrightarrow{\text{意图提交}} \text{Page (参数校验)} \xrightarrow{\text{调用}} \text{Service Command (权威判定)}$$

### 5.2 规范准则
1. **纯展示派生**：Presentation 模块必须由纯函数组成，负责将复杂的引擎数据类型转化为基础标量（字符串、布尔值、颜色配置）；
2. **禁止实体穿透**：ViewModel 中严禁直接挂载原版 Java 实体句柄（如 `IsoPlayer`、`IsoZombie`、`InventoryItem`），必须转化为安全持久的稳定标量（如 `fullType`、`count`、`displayName`、`npcId`）；
3. **脏数据驱动计算**：仅在 Store 状态或底层数据版本号置脏时重新执行投影，严禁每次重绘都执行投影计算。

---

## 6. L4 Pages、Dialog 与 Drawer 编排规范

1. **唯一所有权结构**：
   - 所有页面由 [`SettlementDashboard`](file:///c:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SettlementDashboard.lua) 通过 `PageRegistry` 统筹挂载；
   - 弹窗（Dialog）与浮动抽屉（Drawer）必须明确登记其 `owner` 页面，随页面的激活/休眠同生共死。
2. **标准生命周期四部曲**：
   - `new(owner, bounds)`：仅构造布局脚手架与子控件容器，不查询重型业务数据；
   - `createChildren()`：初始化静态控件结构，绑定事件；
   - `activate()`：通过 `Lifecycle.mount` 注册业务监听，启动可见视口节拍，执行首帧数据获取；
   - `deactivate()`：通过 `Lifecycle.unmount` 释放所有权资源，关闭所有浮动子抽屉，清空 Tooltip。

---

## 7. 性能、内存与 GC 红线 (Invariants)

1. **渲染零临时对象**：`render`、`prerender` 及列表的 `doDrawItem` 过程中，动态分配的 table 数量必须为 **0**；
2. **文本零动态拼接**：高频绘制中禁止使用 `..` 进行复杂字符串拼接，必须在 ViewModel 生成阶段格式化完毕；
3. **消除孤儿回调**：所有网络/异步/延迟任务必须以 `Lifecycle Scope token` 为硬性守卫，失效即止；
4. **拒绝全量扫描**：全员健康与状态轮询必须仅在页面激活视口内执行，且优先采取“选中项聚焦刷新”策略。

---

## 8. 测试与验收标准

| 验收维度 | 达标标准 | 验证手段 |
| :--- | :--- | :--- |
| **静态与类型** | 320+ 个源文件 0 语法错误，0 LC01 违规，符合统一规范 | `node .workbuddy/tools/pz.mjs lint` |
| **逻辑覆盖** | 核心 Runtime（State、Lifecycle、Scheduler、TooltipManager）100% 具备单测 | 纯数据环境自动化断言脚本 (`tests/lua/*`) |
| **生命周期闭环**| 页面来回切换 20 次，Store 订阅计数归零，无孤儿 Timer、无悬挂 Tooltip | 生命周期回归断言测试 |
| **性能基线** | 活跃视口渲染帧时间消耗在预算内，切出页面后后台轮询 CPU 消耗为 0 | 游戏内 Performance 采样与断言 |
