# UI 表现层领域契约 (UI Domain Spec)

> 更新：2026-11-06｜状态：active
> 适用物理路径：`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/`  
> 层级定位：Layer 3 核心领域契约（展示与交互层）

---

表现质量先遵循[全项目前端视觉与交互设计原则](../architecture/frontend-design-principles.md)。本领域文档规定实现边界，不能代替视觉与交互验收。

## 1. 领域职责与非职责 (Scope & Non-Goals)
- **负责**：
  - 玩家交互界面呈现：据点总览仪表盘（Dashboard）、人员工作矩阵、仓储物流面板、小队悬浮 HUD；
  - 交互意图收集与提交（向 Service 提交操作意图，如修改工种优先级、设置配额、发送小队指令）；
  - 状态数据消费与只读呈现（只读消费 Service / Presentation 派生的标量快照）。
- **绝对不负责（Non-Goals）**：
  - 严禁成为业务状态的第二权威；
  - 严禁绕过领域 Service 直读或直写 `ModData`、`JobStore`、`TaskController` 底层；
  - 严禁在 UI 层直接驱动角色身体（如移动、播放动作）。

---

## 2. 数据权威与持久事实 (Single Source of Truth)
- **数据权威**：UI 自身**绝对无持久化业务状态**。所有业务数据权威属于对应领域（Settlement / Work / Warehouse 等）。
- **缓存机制**：
  - Presentation 为纯无状态函数，仅在数据置脏（Dirty）时派生标量展示快照并缓存；
  - 禁止双重投影（`Store:setState` 驱动投影后，严禁紧接着手动追加 `project` 调用）。

---

## 3. 业务生命周期状态流 (Lifecycle State Machine)
- **树形所有权关系**：`Dashboard -> Page -> Component / List / Card / Tooltip / Watch`。
- **对称释放铁律**：
  - 页面切出或关闭（`deactivate` / `dispose`）时，其持有的所有资源必须 100% 彻底释放：
    1. 解除 Store 订阅与注销 Service Watch 监听句柄；
    2. 清理所有附加的 Tooltip（`Tooltip.dismissOwner` / `Tooltip.unregisterOwner`）；
    3. 销毁所有派生的浮动子窗口（如 Inspector、Drawer、ModalDialog）；
    4. 停止刷新计时器。
  - **严格以 `PageLifecycle` 的 `activation token` 作为异步与事件门禁**，彻底杜绝孤儿回调。

---

## 4. 组件注册库与轮子禁造令 (Widget Registry & No Reinventing)
UI 开发必须从“页面驱动”全面转向“基础设施驱动”。严禁在业务页面中手写第二套基础控件、严禁复制卡片背景与强调条、严禁私创未经登记的色彩规范。**新增或修改业务页面必须 100% 优先复用以下已有标准基础设施**：

| 组件名称 | 规范源码路径 | 核心职责与规约 |
|---|---|---|
| `StepperInput` | `.../UI/StepperInput.lua` | **数字步进输入器**：唯一指定数字增减输入框，严禁手写第二套输入框加减按钮 |
| `CachedList` | `.../UI/CachedList.lua` | **高性能虚拟列表**：稳定列表行、平滑滚动、屏外剔除，严禁直接使用裸 `ISScrollingListBox` 承载业务数据 |
| `FilterList` | `.../UI/FilterList.lua` | **过滤列表**：带规则过滤与高度缓存的数据列表 |
| `FilterChips` | `.../UI/FilterChips.lua` | **标签/分段胶囊**：页面与状态快速过滤胶囊 |
| `LayoutNode` / `LayoutSolver` | `.../UI/LayoutNode.lua`、`LayoutSolver.lua` | 纯几何拓扑与 Root-local 矩形池；失败保留上次完整输出；不碰原生控件 |
| `LayoutHost` | `.../UI/LayoutHost.lua` | 显式 native/rect 登记、直接原生父级、激活门禁、独立求解/应用版本及失败重试；首轮只接仓储工具栏；不接管 Store/回调/Tooltip，不在渲染求解；尚未游戏实机验收 |
| SpringDriver | .../UI/SpringDriver.lua | **弹簧阻尼与动态物理引擎**：纯标量 Zero-GC 物理驱动器，提供 2 阶阻尼弹簧与指数平滑，严禁手写第二套动画插值 |
| `SemanticBadge` | `.../UI/SemanticBadge.lua` | **语义徽章**：警告、成功、中立等统一样式徽章 |
| `StatusVisual` | `.../UI/StatusVisual.lua` | **状态轨道与阶段可视化**：统一步骤、进度条与状态几何指示 |
| `Viewport` | `.../UI/Viewport.lua` | **视口 Stencil 裁剪**：负责复杂画布的自绘区域安全裁剪，杜绝越界溢出 |
| `TooltipManager` | `.../UI/TooltipManager.lua` | **提示框挂载锚点**：统一跟随鼠标与浮动提示生命周期，关闭时必须对称注销 |
| `Theme` / `UICache` | `.../UI/Theme.lua`, `.../UI/UICache.lua` | **唯一视觉与色彩规范**：统一面板底色、强调色、文字色；渲染层使用单例色彩对象杜绝 GC |

---

## 5. PZ v42 原生 Java 桥接生命周期铁律 (PZ v42 Engine Invariants)
- **严格区分 `new`、`initialise` 与 `instantiate`**：
  在 Project Zomboid v42 中，继承自原生 Java `UIElement` 的控件（如 `ISTextEntryBox`、`ISScrollingListBox`、`ISButton`），其底层的 Java 句柄（`self.javaObject`）**只有在 `instantiate()` 被显式调用，或者通过 `addChild()` 挂载到已经完成 `instantiate` 的父容器时才会创建**！
  - **严禁提前调用 Java 方法**：在 `entry:instantiate()` 之前，调用任何依赖 `self.javaObject` 的方法（如 `setOnlyNumbers`、`setEditable`、`setMaxTextLength` 等）都会直接引发 `attempted index: ... of non-table: null` 崩溃！
  - **规范写法**：此类属性配置必须在控件完成 `instantiate()` 之后执行，或在 `createChildren` 挂载后统一安全初始化。
- **视口 Stencil 裁剪闭环（杜绝向下滚动突出越界）**：
  - 凡是自绘滚动容器（如网格、自定义卡片组）或带滚动的面板，**必须严格限制绘制边界**；
  - 内部绘制必须通过 `Viewport.draw` 或在 `prerender` / `render` 中成对执行 `setStencilRect` / `clearStencilRect`；
  - 必须对视口边界进行绝对坐标约束（结合 `clampToParentY` 或容器高宽），绝不允许滚动内容在下滑时越过底边突出显示在面板之外。
- **Zero-GC 与展示层只读**：
  - `render` / `prerender` 阶段必须绝对只读缓存，严禁进行动态 table 分配、字符串格式化拼接（如 `string.format`）、JNI 文本测量（`MeasureStringX`）或直接扫描 ModData/背包实体；
  - 所有展示数据必须在数据变化时由 `Presentation` 派生标量快照并缓存。

---

## 6. 对外服务与依赖方向 (Dependencies)
- **依赖方向**：UI 仅单向依赖各领域的只读 Service、Presentation 与 UI 基础组件库。
- **严禁反向依赖**：任何业务领域（如 Cooking、Work、Warehouse）严禁 `require "EmberRoutesProbe/UI/..."`。

---

## 7. 契约测试与验证基线 (Executable Contracts)
- **运行回归测试**：`powershell -ExecutionPolicy Bypass -File tools/test-ui-kahlua.ps1`
- **核心测试文件**：
  - `tests/lua/settlement-overview-ui-test.lua`
  - `tests/lua/squad-command-ui-test.lua`
  - `tests/lua/ui-layout-consolidation-test.lua`
  - `tests/lua/storage-panel-test.lua`

---

## 8. 高危陷阱与架构暗礁 (Gotchas & Risks)
1. **未完成 `instantiate` 即调用 Java 方法**：导致游戏直接崩溃。
2. **滚动容器漏做 Stencil 裁剪**：导致内容滚动时溢出面板底部。
3. **离开页面未注销 Watch / Tooltip**：导致内存泄漏与悬挂回调。
4. **双重投影与在 `render` 中动态分配 table**：导致 PZ 严重掉帧与 GC 卡顿。
