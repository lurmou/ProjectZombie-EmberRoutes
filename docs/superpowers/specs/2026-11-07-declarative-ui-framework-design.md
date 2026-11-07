# EmberRoutes 声明式排版框架详细设计规范 (Declarative Layout Framework Spec)

> 日期：2026-11-07｜状态：Phase 1 冻结 / Phase 2 仓储工具栏试点已接入、实机未验收｜适用：`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/`  
> 规范定位：作为 EmberRoutes UI 现代化基础设施，遵循 [UI 领域契约](../../domains/ui.md) 与 [生命周期铁律](../../../.agents/rules/provider-lifecycle.md)。

---

## 1. 架构目标与设计哲学

### 1.1 核心痛点
当前 UI 开发（如 `CraftingBrowser.lua`、`WarehouseControls.lua`）高度依赖 `Layout.axis` 进行人工多级“几何切片”：
1. **心算负担重**：开发者需手动管理 `regions[1]`, `regions[2]`, `controls[1]` 等多层嵌套坐标，排版与控件初始化严重揉杂；
2. **响应式断层**：面板尺寸变动或视口缩放时，必须全量重写各级切片逻辑；
3. **性能风险**：若引入自底向上反推（Intrinsic Measurement），在 PZ 引擎中会高频穿透 JNI 调用 `TextManager.MeasureStringX`，引发 CPU 穿透与 GC 抖动。

### 1.2 核心设计目标
构建一套**单趟线性约束求解、零运行期 GC 分配、几何与控件解耦、所有权闭环**的轻量声明式排版框架：
- **Flutter 单趟弹性约束（Single-Pass Flex）**：$O(N)$ 线性几何求解，自顶向下约束传递，支持 `grow`、`basis`、`margin`、`padding`、`gap`、`align`、`justify`；
- **Zero-GC 热路径铁律**：`solve()` 阶段零 table 分配、零字符串拼接、零动态闭包，直接原地覆写根节点预分配标量池（`_rectPool`）；
- **正交分层架构**：几何拓扑（Phase 1: `LayoutSolver` + `LayoutNode`）、原生承载（Phase 2: `LayoutHost`）、语法糖门面（Phase 3: `UI`）彻底解耦；
- **单一数据投影守卫**：彻底剔除侵入式的表单双向绑定（如 `UI.Model` / `UI.Bind`），保持 UI 为业务 Store 的纯只读消费者，防止与既有 `project()` 产生双重投影死循环。

---

## 2. 总体架构与三分层位置

```
┌────────────────────────────────────────────────────────┐
│                   Layer 4 · 业务页面层                  │
│    WarehouseControls · CraftingBrowser · SquadHUD      │
└───────────────────────────▲────────────────────────────┘
                            │ (声明式树状组合 UI.Row / UI.Column)
┌───────────────────────────┴────────────────────────────┐
│              EmberRoutes 声明式排版框架                │
│                                                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Phase 3: UI (DSL 语法糖门面)                    │  │
│  │  UI.Row · UI.Column · UI.Spacer                  │  │
│  └────────────────────────▲─────────────────────────┘  │
│                           │ (构建并装配节点树)          │
│  ┌────────────────────────┴─────────────────────────┐  │
│  │  Phase 2: LayoutHost (原生承载容器，继承 ISPanel) │  │
│  │  接管 ISUIElement · 应用 Root-local 坐标 · 脏同步  │  │
│  └────────────────────────▲─────────────────────────┘  │
│                           │ (持有 RootNode · 触发解算)  │
│  ┌────────────────────────┴─────────────────────────┐  │
│  │  Phase 1: 几何计算与拓扑核心 (纯 Lua，无引擎依赖)│  │
│  │  LayoutNode (拓扑所有权/固定槽位)                 │  │
│  │  LayoutSolver (单趟 O(N) 线性约束求解/零 GC)     │  │
│  └──────────────────────────────────────────────────┘  │
├────────────────────────────────────────────────────────┤
│  Layer 1 · 既有基础设施                                │
│  ISPanel · ISUIElement · Theme · PageLifecycle · State │
└────────────────────────────────────────────────────────┘
```

---

## 3. Phase 1 详细设计：几何与拓扑核心（已实现）

Phase 1 完全脱离 Java 桥与 `ISUIElement`，作为纯数学与纯数据树运行。

### 3.1 纯几何解算器：`LayoutSolver.lua`
- **入参与出参**：`Solver.solve(rootNode, bounds) -> pool, err`
  - 入参 `bounds`：`{ width = W, height = H }`（必须为正有限数）；
  - 出参：解算成功原地返回 `root._rectPool`；失败返回 `nil, err`。
- **失败语义与状态隔离**：
  - 非法边界（缺失、负数、NaN、无穷大）：返回 `nil, "INVALID_BOUNDS"`；
  - 空间不足：返回 `nil, "INSUFFICIENT_SPACE"`；
  - 求解失败时：整树标记保持 `dirty = true`，**绝不覆写已发布的 `_rectPool`**，不产生半成品几何脏数据。

#### 核心数学公式
1. **主轴可用空间与容差截断**：
   设主轴总长度为 $M$，两端内边距为 $P_s, P_e$，可见项数为 $N$，间距为 $G$，固定基准尺寸与外边距之和为 $F_{\text{fixed}} = \sum (\text{basis}_i + M_{s,i} + M_{e,i})$：
   $$S_{\text{free}} = M - P_s - P_e - \max(0, N - 1) \cdot G - F_{\text{fixed}}$$
   - **空间合法性判定**：若 $S_{\text{free}} < -\text{EPSILON}$（$\text{EPSILON} = 0.0001$），直接拒绝并返回 `nil, "INSUFFICIENT_SPACE"`；
   - **容差内负余量硬性归零**：若 $S_{\text{free}} \in [-\text{EPSILON}, 0)$，强制 $S_{\text{free}} = 0$。**严禁向弹性项分配负空间**。
2. **主轴弹性分配与浮点残差吸收**：
   设弹性总权重为 $W_{\text{total}} = \sum \text{grow}_i$：
   - 当 $W_{\text{total}} > 0$ 时：
     - 普通弹性项：$\text{alloc}_i = S_{\text{free}} \cdot \frac{\text{grow}_i}{W_{\text{total}}}$
     - 最后一项（吸收所有浮点残差）：$\text{alloc}_{\text{last}} = S_{\text{free}} - \sum_{j < \text{last}} \text{alloc}_j$
     - 最终尺寸：$\text{size}_i = \max(0, \text{basis}_i + \text{alloc}_i)$
   - 当 $W_{\text{total}} == 0$ 时，弹性分配为 0，空间按 `justify` 平移游标：
     - `"start"`: 游标从 $P_s$ 起始；
     - `"center"`: 游标起始偏移增加 $\max(0, S_{\text{free}} / 2)$；
     - `"end"`: 游标起始偏移增加 $\max(0, S_{\text{free}})$；
     - `"space-between"`: 额外间距分散至子项间距 $G' = G + \frac{\max(0, S_{\text{free}})}{N - 1}$。
3. **交叉轴空间校验与对齐**：
   设交叉轴长度为 $C$，内边距为 $C_s, C_e$，子项外边距为 $M_{cs}, M_{ce}$，可用交叉空间为 $A_c = C - C_s - C_e - M_{cs} - M_{ce}$：
   - 若 $A_c < -\text{EPSILON}$，返回 `nil, "INSUFFICIENT_SPACE"`；
   - 非 `"stretch"` 模式下，若 $\text{crossBasis} > A_c + \text{EPSILON}$，返回 `nil, "INSUFFICIENT_SPACE"`；
   - 对齐计算：
     - `"stretch"`: $\text{crossSize} = \max(0, A_c)$，偏移 $\text{offset} = C_s + M_{cs}$；
     - `"start"`: $\text{crossSize} = \text{crossBasis}$，偏移 $\text{offset} = C_s + M_{cs}$；
     - `"center"`: $\text{crossSize} = \text{crossBasis}$，偏移 $\text{offset} = C_s + M_{cs} + \max(0, (A_c - \text{crossSize}) / 2)$；
     - `"end"`: $\text{crossSize} = \text{crossBasis}$，偏移 $\text{offset} = C_s + M_{cs} + \max(0, A_c - \text{crossSize})$。

### 3.2 节点拓扑与槽位所有权：`LayoutNode.lua`
- **根所有权固定，允许局部增删，不支持跨根迁移**：
  - 根节点拥有唯一的扁平输出矩形池 `root._rectPool`；
  - 叶子项在挂载时分配固定槽位 `item.slotIndex = #root._rectPool + 1`，在其所属 Root 生命周期内**绝不移动、绝不缩容**；
  - 隐藏（`setItemVisible(item, false)`）不释放槽位；
  - 删除普通项（`remove(item)`）：将其在池中的槽位置为墓碑（`slot.visible = false`），不调用 `table.remove` 破坏已有索引；
  - 移除子树（`remove(childItem)`）：递归清理子树拓扑并打上墓碑，**不自动提升为独立 Root**；业务控件实体原样保留；
  - 当需要新的独立布局时，由调用方重新构建布局节点，业务控件直接复用；
  - **Zero-GC 边界**：严格约束 `solve()` 计算热路径；结构初次构建与局部变更属于冷路径，允许正常 table 分配。
- **初始尺寸双轴快照**：
  - `add(target, props)` 时自动捕获目标物初始尺寸快照（`initialBasis`, `initialCrossBasis`）；
  - `setItemBasis(item, nil)` 时回退至初始快照，杜绝“读取已被布局修改后的尺寸”导致的恶性反馈循环。
- **非测量模型契约边界**：
  - 显式 `basis` 仅代表**调用方在父级主轴上声明的预留基准尺寸**，不涵盖交叉轴，亦不会随子树内容动态自适应；
  - 调用方全权负责提供外层尺寸约束；当空间不足以满足预留基准时，内核严格拒绝排版（返回 `INSUFFICIENT_SPACE`），不静默截断、不反向探测 JNI 文本。

---

## 4. Phase 2 承载规划：原生宿主容器 (`LayoutHost.lua`)

> 状态：2026-11-07 用户授权开始；采用以下收口契约。Phase 3 不在本轮范围。

### 4.1 核心职责与设计边界
`LayoutHost` 继承自原生 `ISPanel`，作为连接 Lua 纯数据排版与 PZ 原生 JavaObject 控件树的唯一承载者：
1. **持有单一根节点**：内部实例化 `self.rootNode = LayoutNode.new(props)`；
2. **Root-local 相对坐标下发**：
   - PZ 引擎的 `ISUIElement:setX() / setY()` 均基于其父容器内部坐标（非屏幕绝对坐标）；
   - `LayoutHost` 作为直接父容器，`LayoutSolver` 产出的 `(slot.x, slot.y, slot.width, slot.height)` 直接 1:1 下发给子控件；
3. **安全更新门禁**：
   - onResize 或真正几何输入变化置脏；受 PageLifecycle activation token 门禁的 update 或显式 resolveLayout 求解/应用，render/prerender 只读缓存。
   - 使用控件公开 Lua setter，同步 Lua/Java 字段；应用尺寸后应用位置，最后应用可见性。不能只写 javaObject。
4. **生命周期闭环**：
   - 失活只停止更新、释放当前 scope 引用；再次激活复用原树及控件。永久 dispose 先隐藏/解绑原生目标，释放登记，最后销毁根；不调用业务目标销毁。
   - 解绑失败保留 target、item 和清理待完成状态；重复 dispose 继续清理。只有全部解绑成功才成为 closed 终态。

### 4.2 显式适配与所有权

- Page 拥有业务控件、回调、Store、Tooltip；Host 拥有布局拓扑与挂载关系，不持有业务 Store、不替换事件 target。
- Host 构造时以 Node.claimRoot 认领独立根，防止尚未发布的 Host 根被其他拓扑挂载；构建期虚拟子节点仍允许正常组合。
- Host 位置属于 Page-local；Root 求解从 (0,0) 开始。首版 native 必须直接挂在 Host 下，禁止隐式跨父级迁移/中间父级换算。Host 激活前必须挂到页面。
- `_leafItems` 为适配登记表，保存 kind、target、item；通过 item.slotIndex 取 `_rectPool`，不复制第二份矩形缓存。
- `addNative(node,widget,props)` 预检 setter、父级、重复登记，Node 登记后挂载，最后提交。失败回滚允许留下池墓碑；回滚解绑失败进入 CLEANUP_PENDING，保留引用、不报告成功。
- `addRect(node,rect,props)` 明确传入包含 x/y/width/height/visible 的普通可写矩形表，成功后 Host 将池标量写入此表；自绘消费者仅读它。不通过 target.bounds 猜适配类型。
- 首轮登记只在首次激活前开放；动态添加/移除不开放。可见性随成功发布的 slot.visible 下发；Node 拓扑移除不能绕过 Host。无绘制 Spacer 可以直接登记纯几何项。
- 首版支持固定左/上锚点、关闭右/下伸缩锚点且未开启 keepOnScreen 的原生叶子；冲突配置明确拒绝。透明背景不等于点击穿透，Host 显式关闭鼠标事件消费，原生输入仍须试点验证。

### 4.3 求解、应用与故障恢复

- Node revision 随输入失效向上递增；Host 分别记录 solvedRevision、appliedRevision、failedSolveRevision、failedApplyRevision。不能因每帧轮询递增输入版本。
- SOLVE_FAILED：不触碰原生控件，保留旧池，保持 Node dirty；同一 revision 不自动重试。新尺寸/新输入/新激活或显式 retryLayout 才允许再试。
- APPLY_FAILED：保留已发布池与 solvedRevision，不重新污染几何 dirty；停止本次剩余应用，记录失败 slotIndex、setter 与错误。原生状态可能混合，不宣称事务原子性。
- retryLayout 对有效激活执行显式重试；应用必须从第一个登记项完整重放，全部成功后才更新 appliedRevision。同一失败版本不逐帧重放。
- 应用前预检全部 item、矩形、原生句柄与 Lua/Java 直接父级；预检不能证明 setter 一定成功。支持集合之外的控件尺寸/内部布局约束另行验证，不声称所有零尺寸都会引擎崩溃。
- 登记、应用、清理的异常捕获范围限于 Host 拥有的边界；失败有可读诊断，不能大范围吞掉页面业务异常。
- 试点页面负责焦点、Tooltip 和共享 Combo popup 的退出；关闭弹层前核对 popup.parentCombo，不能影响其他页面。

### 4.4 验证试点与验收边界
- 唯一试点为 `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/WarehouseControls.lua`，覆盖输入框、下拉框和按钮。
- `Controls.new(owner,nativeParent,bounds)`：owner 保持 Page 业务身份，nativeParent 是 Host，bounds 从零开始。全部调用方同步修改，不保留旧签名兼容入口。
- 必须覆盖非零 Host 偏移、Lua/Java 几何、焦点/点击/共享弹层、失活重激活、求解失败抑制、setter 中途失败及完整重放、登记回滚与清理失败重试。
- 原生预览场景 `layout` 加载真实生产 Host/Controls，业务导航与查询可用明确夹具。CN/EN 回读截图，正常与较窄窗口分别验证；不改 Java Runner。预览不代替游戏世界内交互验收，不证明 GC 性能。

---

## 5. Phase 3 详细设计：声明式 DSL 门面 (`UI.lua`)（已实现）

> 状态：Phase 3 纯描述符门面与 Host 装配流水线已落地 (`UI.lua` + `LayoutHost:build`)，通过 Preflight 静态门禁与离线数学推演。

### 5.1 核心原则与四类公开工厂
`UI.lua` 是一个**无副作用布局描述符（Side-effect-free Layout Descriptor）工厂**，不持有任何全局状态，不触碰原生控件，也不监听任何数据源：

1. **`UI.Row(props, children)`**：创建水平横向布局描述符；
2. **`UI.Column(props, children)`**：创建垂直纵向布局描述符；
3. **`UI.Item(child, props)`**：**统一包装器**，声明原生控件或嵌套容器在父级布局中的占位策略：
   - `child` 可以是原生控件（`ISUIElement`）、绘图矩形（`rect`）、嵌套 `UI.Row`、嵌套 `UI.Column` 或 `UI.Spacer`；
   - `props` 严格受限：仅支持 `key`、`grow`、`basis`、`margin`；
4. **`UI.Spacer(grow)`**：创建纯几何弹性占位符（虚拟叶子节点），不关联原生控件，仅在布局树中分配槽位瓜分弹性空间。
5. **明确暂缓与排除清单**：
   - 第一版**不提供独立的 `UI.Padding`**（统一样式由容器属性或 `UI.Item` 的 `margin` 处理）；
   - 永久排除 `UI.Model`、`UI.Bind`、自动测量与双向绑定。

### 5.2 `LayoutHost:build(spec)` 四阶段构建提交流水线
1. **Preflight (纯静态校验)**：
   - 严禁重复 build（`HOST_ALREADY_BUILT`）；
   - 严格拒绝未知容器属性（如拼写错误 `paddding`）、未知 Item 属性；
   - 校验属性数值有限性、非负性、方向与枚举对齐合法性；
   - 静态查重：Widget 重复使用拦截、描述符成环拦截、`key` 全树全局唯一性校验；
   - **拦截裸嵌套容器**：嵌套容器必须通过 `UI.Item` 声明父级占位策略，严禁隐式尺寸。
2. **Stage (建立候选拓扑)**：
   - 在内存中构筑 `LayoutNode` 候选拓扑与平铺叶子列表 `stagedLeaves`；
   - 映射 `candidateHandles[key]`，不触碰原生父子树。
3. **Commit (执行原生挂载与反序回滚)**：
   - 遍历执行 `host:addChild(target)`，并将初始控件置为隐藏；
   - 任意挂载异常触发严格反序回滚（`detach`）；回滚失败进入 `BUILD_CLEANUP_REQUIRED` 隔离态。
4. **Publish (正式发布)**：
   - 提交 `_leafItems`，标记 `self.built = true`，标记根节点 `dirty = true`，向调用方返回 `handles`。

### 5.3 动态可见性与防闪烁契约 (`setItemVisible`)
```lua
host:setItemVisible(handles.search, false)
```
- **句柄归属校验**：严格验证 handle 属于当前 Host，且底层 item 未脱轨；
- **相同可见性直接忽略**：不产生冗余的 `markDirty()`；
- **防 1 帧位置闪烁机制**：
  - 隐藏时（`visible = false`）：立即调用 `target:setVisible(false)` 消失；
  - 重新显示时（`visible = true`）：仅更新布局节点标记，**原生控件保持隐藏，直到下一个 `update()` 求解并下发全新几何后，才在 `apply()` 中恢复显示**，彻底消灭旧坐标闪现；
- **释放恢复原貌**：Host 销毁（`dispose`）时，自动恢复控件接管前的原始可见性（`wasVisible`）。

---

## 6. 三要素闭环与生命周期铁律 (Closure Triad)

| 阶段 | 代码位置与机制 | 核心防御逻辑 |
| :--- | :--- | :--- |
| **创建与认领 (Claim)** | `LayoutNode:add` / `LayoutHost:addChild` | 1. 递归建立树所有权；<br>2. 校验无环图（`LAYOUT_CYCLE`）与无重复挂载（`LAYOUT_NODE_ALREADY_OWNED`）；<br>3. 在 Root 池分配稳定槽位，捕获初始快照。 |
| **正常释放 (Release)** | `LayoutNode:dispose` / `LayoutHost:dispose` | 1. 先隐藏并解绑原生目标，失败保留清理责任；<br>2. 成功后递归墓碑化并解除布局引用；<br>3. 不调用业务控件销毁，支持安全复用。 |
| **异常打断 (Interrupt)** | `Solver.solve` 失败返回 | 1. 遇到非法尺寸或空间不足立即返回拒绝码；<br>2. 保留 `dirty = true` 与上一次有效输出池，不污染正在渲染的界面；<br>3. 切出页面时通过 `PageLifecycle` 令牌阻断无效更新。 |

---

## 7. 验证证据与验收状态 (按 AGENTS.md:26)

本节原表为 Phase 1 初始证据截点。当前事实以 [Phase 1 收口证据](../../reviews/2026-11-07/declarative-layout.md) 和 [Phase 2 试点证据](../../reviews/2026-11-07/layout-host.md) 为准：安装版 Kahlua 136 项回归、376份生产 Lua 编译及构建通过；CN/EN 原生试点通过。现有旧仓储用例失败，完整模组 LuaLS 未完成，局部检查有 warning；不据此宣称全库或实机验收完成。

| 检查维度 | 验证方式 | 当前真实状态 | 详细说明 |
| :--- | :--- | :--- | :--- |
| **模块架构与依赖边界** | `tools/check-architecture.py` | **已通过** | 0 error，无非法跨层调用，无 target 属性污染 |
| **Kahlua 字节码编译** | `tests/java/KahluaCompileTest.java` | **已通过** | 375 files 编译零故障，语法与环境兼容合法 |
| **生产打包流水线** | `tools/build-probe.ps1` | **已通过** | BUILD_OK，严格门禁全绿通过 |
| **定向数学与拓扑推演** | 离线 Scratch 脚本 (`lua.exe 5.1`) | **已通过** | 负余量截断、残差吸收、槽位墓碑化、空间拒绝均核对吻合 |
| **游戏运行时真实表现** | 真实 PZ 客户端会话 | **未实机验证** | 尚未在真实游戏会话中挂载运行 |
| **热路径 GC 测量** | 实机内存分配监控 | **未实机验证** | 代码静态审查确认零 GC，实机数值未实测 |
