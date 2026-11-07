# 声明式布局后续实施计划与最终方案

> 实施方式：本会话串行实施；不启用子代理。2026-11-07 用户已授权 Phase 2 实施，仓储工具栏试点已接入，证据见下；历史提案描述不代表已验收，Phase 3 未授权启动。

当前执行状态：Task 1–3 的生产接入与原生试点已落盘；Task 4 构建、局部类型与原生预览有证据，旧仓储测试仍失败、游戏实机与性能未验证，不能标为全部通过。正式采用[规格§4](../specs/2026-11-07-declarative-ui-framework-design.md)收口版本：首轮登记在首次激活前开放，不开放动态叶子移除，不实现通用原生剪裁器；原生场景使用 `-Scene layout`，不改 Java Runner。详见[实际范围与差额](../../reviews/2026-11-07/layout-host.md)。

**Goal:** 完成可验证、生命周期闭合的 LayoutHost，并用仓储工具栏验证坐标、原生控件和业务行为保持一致。

**Architecture:** 保留纯几何 Node/Solver；Host 持有根节点及显式适配登记，只应用成功发布的几何；Page 保持业务事件、Store、Tooltip 与激活所有权。试点通过后才实施纯构建 DSL，暂不全库迁移。

**Tech Stack:** PZ B42 安装版 ISPanel/ISUIElement、Kahlua、既有 PageLifecycle、原生 OpenGL 预览工具。

**Spec:** [冻结规格](../specs/2026-11-07-declarative-ui-framework-design.md)。Phase 1 已冻结；本文涉及收口补充和 Phase 2 决策须确认后实施。

## 当前证据与待决冲突

- `UI/LayoutNode.lua:27` 挂载预构建子树仍重分配槽位，因此“终身固定”应限定为最终根归属建立之后；构建期尚未交给 Host 的临时树允许装配，Host 不接受从另一存活 Host 转来的树。
- `UI/LayoutNode.lua:113` 删除子树调用 clear，业务 target 不销毁；`:157` dispose 与 `:162` removeChildNode 仍有 disposing 布尔旁路，需要统一释放入口。
- `UI/LayoutSolver.lua:101` 起始坐标固定为零；输出相对 Root，不能再叠加 Host 在页面中的偏移。
- `UI/WarehousePage.lua:94` 调用 Controls.new(self,regions[2])；`UI/WarehouseControls.lua:19/26` 同一 owner 负责回调和原生挂载，迁移须分离。
- 安装版 `media/lua/client/ISUI/ISUIElement.lua:230/245` 的公开尺寸 setter 同步 Lua 与 Java；`:1451` addChild 负责实例化及挂载。禁止直接只写 Java 尺寸。
- 冻结规格 §4.1 允许 prerender 求解，与项目只读渲染红线冲突；采用显式刷新及受激活门禁控制的 update，render/prerender 不求解、不应用几何。
- 冻结规格 §4.2 的试点路径错误，实际为 `client/EmberRoutesProbe/UI/WarehouseControls.lua`。
- 2026-11-07 尝试读取唯一在线 Google Docs，连接器 HTTP transport 失败；本计划依据用户批准规格及本地代码，不宣称在线需求已同步。
- 另一 AI 报告 Lua 5.1 临时四类案例通过；本轮未复跑，且 Lua 5.1 不能代替安装版 Kahlua 执行证据。没有新增性能证据。

## Global Constraints

- 不改现役 Layout.lua；不新增旧签名 fallback、兼容别名、跨根迁移或表单双向绑定。
- solve 热路径不分配 table、拼接字符串或创建闭包；结构增删允许冷路径分配，不宣称实测 Zero-GC。
- Root-local 输出为 x/y/width/height/visible；_rectPool 是唯一已发布几何池。
- 本轮不交付新测试脚本、不修改 Java Runner；定向案例用临时文件执行并保留命令、输出及源码哈希证据。
- 页面/组件改动必须补现有原生预览 Lua 场景夹具并回读 CN/EN 截图，不要求用户截图。
- 不把整个工作区构建包称为隔离发布成果，不提交或清理无关改动。

## 最终接口提案

以下路径统一以 `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/` 为前缀。

### Host 与适配登记

- `LayoutHost:new(x,y,width,height,props)`：继承 ISPanel，持有唯一 rootNode、预分配求解 bounds 和 `_leafItems`。x/y 仅定位 Host；bounds 只有 width/height。
- `host:addNative(node,widget,props) -> item`：node 必须属于该 Host 根；widget 无父级或已直接挂在该 Host；拒绝其他父级、重复 target、已释放 Host。通过 addChild 完成挂载与 instantiate，再登记 item；不接管回调 target。
- `host:addRect(node,rect,props) -> item`：rect 明确为调用方提供的可写矩形及可见性对象，包含 x/y/width/height/visible；不通过 target.bounds 猜适配类型。调用方自绘仅读这些字段。
- `_leafItems` 是稠密的适配记录序列，每项保存 item 句柄、kind(native/rect)、target；不缓存第二份几何。slotIndex 只从 item 读取，不依赖 `_leafItems` 数组下标。
- node 的纯拓扑/尺寸快照保持引擎无关；适配类型仅存在 Host。Spacer 可为无 target 的几何 item，不登记适配。
- Host 建立后，叶子只能通过 Host 入口登记/移除；Node Setter 仍可直接调用。登记先做全部可预检校验，失败不得留下半登记；原生 setter 应用异常作为单独错误报告，不声称原生控件应用具有事务回滚能力。
- `host:removeItem(item)`：先隐藏并解绑相应 native，或令 rect.visible=false，再释放适配记录及布局 item；子树移除覆盖全部后代。不得销毁业务对象，不得让失效登记继续参与应用。

### 刷新与失败

- `host:setActivation(scope)`：由页面提供当前 ActivationScope；Host 不创建第二套 page token，也不持有 Service watch。scope:isCurrent() 为更新门禁。
- `host:resolveLayout() -> pool,changed|nil,err`：只有激活且原生 Host 已实例化时可求解/应用；求解成功后才应用 native 公开 setter 或 rect 标量，应用 slot.visible。无变化不重复 setter。
- `LayoutNode` 增加构建期预置 `revision=0`；markDirty 向上递增各节点 revision。用于 Host 区分新变更与同一失败，不改变 Solver 失败保留 dirty 的语义。
- Host 记录最近尝试的 root revision、width、height。失败保留旧几何及 error，dirty 仍为 true；同一组合不在 update 每帧重试。新 revision、新尺寸、新激活或显式 resolveLayout 才重试。
- onResize 仅更新预分配 bounds 并置脏；update 检查激活及变化后刷新。首次布局由 activate 在显示可交互内容前显式刷新。render/prerender 仅读缓存。
- 失败缩窗时旧矩形可能大于新 Host：由 Host 按已核对原生裁剪方式限制绘制；页面保留可访问的退出/放大路径。首次无成功布局则叶子保持隐藏。错误记录不能变成每帧日志。

### 生命周期与业务边界

- `host:deactivate()` 停止更新、清除 scope 引用；保留布局与控件以便原页面再次激活，不销毁整个布局。
- `host:dispose()` 幂等：禁止后续更新，隐藏/解绑 native、隐藏 rect、释放适配记录与 rootNode，并从父面板脱离；不清业务 Store、不调用 target 销毁、不接管页面 Tooltip 注册。
- `Controls.new(owner,nativeParent,bounds)`：owner 保持 Page 回调与 Tooltip 所有权；nativeParent 仅负责 addChild；bounds 为 nativeParent-local。
- Page deactivate 继续关闭 Combo popup、清焦点、dismiss Tooltip，并 deactivate Host；Page dispose 在既有清理链中 dispose Host、unregisterOwner。用现有 lifetime scope 或明确已有 dispose 链登记一次，不双重维护所有权。

## Review Focus

1. 非零 Host x/y 与嵌套布局：最终屏幕位置只叠加一次 Host 偏移。
2. 失败后连续 update：不反复求解，不应用半成品；修改输入后可以恢复。
3. 隐藏/移除/独立子树 dispose：矩形与原生可见性一致，业务控件不销毁，存活索引不变。
4. 切页/重复激活/关闭：旧 token 无效，无后台布局或悬挂 target/Tooltip/Combo popup。
5. 原生尺寸/可见性与 Lua 字段一致；CN/EN、小窗口和异常边界均有原生截图。

## Task 1：Phase 1 收口与可重复证据

2026-11-07 用户要求先完成 Phase 1：已统一释放、补构建换池墓碑、成功发布根锁定、已销毁 Setter 预检及大权重数值处理，136 项安装版 Kahlua 定向检查与最终构建通过，见[证据](../../reviews/2026-11-07/declarative-layout.md)。revision、Host 认领与激活机制留到 Phase 2；下列原计划清单保留用于核对，不能据此宣称 Phase 2 已授权或实施。

**Files:** 修改 LayoutNode.lua；必要时仅按实际失败修改 LayoutSolver.lua；证据写 `docs/reviews/2026-11-07/declarative-layout.md`。

**Interfaces:** 保留 add/remove/Setter/resolveIfDirty；removeChildNode(child) 不再接收 disposing；增加 revision 标量。

- [ ] 统一 removeChildNode -> remove -> clear；child.dispose 有父级时委托并返回，避免重复清理。
- [ ] 构建期 bindRoot 隐藏旧池对应槽位；挂载前检查已认领根，禁止已交给 Host 的根被重新装配。最终根建立后的存活槽位不重编号。
- [ ] 在安装版 Kahlua 临时执行：容差负余量、三项残差、非对称 margin/嵌套偏移、隐藏再显示、子树删除/重复 dispose、深层失败后整个池不变、非法 bounds/交叉轴不足、旧池槽位隐藏；保留实际输出，不检入临时测试文件。
- [ ] 记录 Node 创建/删除/dispose 和 Solver 失败的最终代码位置及哈希；有失败先修复，不以编译覆盖。

## Task 2：LayoutHost 与双类型适配

**Files:** 新建 LayoutHost.lua；修改现有 `tools/ui-preview/widgets-scene.lua` 或其同场景加载的 Lua 夹具；不改 Java Runner。

**Interfaces:** 实现上述 new/addNative/addRect/removeItem/setActivation/resolveLayout/deactivate/dispose；树构建先使用 LayoutNode.new 与 add(childNode)。

- [ ] 先核对当前安装 ISPanel/ISUIElement 及现有 Viewport 的实例化、尺寸同步、裁剪和脱离父级实际行为，保留来源基线。
- [ ] 实现显式适配登记、预检、尺寸下发、visibility 与释放；禁止调用 rect target 方法或猜测 bounds。
- [ ] 实现 revision/尺寸/激活门禁和失败重试规则；验证同一失败多次 update 只尝试一次，新变更可恢复。
- [ ] 夹具构造非零偏移 Host、嵌套 native 与 rect、隐藏/移除、失败后恢复、失活后拒绝更新；通过生产 Host 绘制，不能复制一套替身应用器。
- [ ] 临时安装版 Kahlua 验证回调 owner 不变、重复 target/错父级拒绝、同版不重复 setter、释放无遗留登记。原生行为由下一项截图补充。
- [ ] 执行 `pwsh -File tools/preview-native-ui.ps1 -Scene widgets -Smoke -Language CN` 及 EN，回读 latest.png/preview-rN.png；不通过持续修正。

## Task 3：仓储工具栏单点接入

**Files:** 修改 UI/WarehouseControls.lua、UI/WarehousePage.lua；适配真正受影响的现有测试调用；补现有 Lua 原生预览场景夹具。

**Interfaces:** 全部调用方更新为 Controls.new(owner,nativeParent,bounds)，不保留旧入口；Page 持有 controlsHost。

- [ ] 保留现有五项工具栏比例、gap、业务按钮及回调；Host 放在 regions[2]，子项 bounds 从零开始，不改仓库服务/查询语义。
- [ ] 搜索、分类、排序、制作与最低库存入口全部保留 Page owner；Page 现有 search/categories 等引用保持业务有效。
- [ ] 接入 activate/deactivate/dispose；调整大小时父 Page 更新 Host 区域，Host 负责内部重排，避免两个系统重复负责子项坐标。
- [ ] 搜索全部 Controls.new 调用及既有测试替身，按新生产签名适配，区分调用适配和预期变化；不放宽原生守卫。
- [ ] CN/EN 原生夹具验证非零偏移、窗口宽度变化、输入/按钮命中、下拉弹层、失活及再次激活；真正实例化 WarehouseControls，业务 Store/导航可用明确替身，不把替身点击计为游戏业务验收。

## Task 4：集中交付验收

**Files:** 原位更新 BACKLOG 当前记录、UI 领域注册库、证据及 INDEX 导航；确认后才回填规格中已批准契约。

- [ ] 运行 `python tools/check-architecture.py`、`python tools/check-i18n.py`；运行受影响的现有 Kahlua 用例及最终 build-probe.ps1，不重复无关全库测试。
- [ ] 原生预览至少覆盖 CN/EN、正常尺寸与最窄支持尺寸、失败恢复；回读截图记录路径。未覆盖实际场景必须补夹具。
- [ ] 分开报告：静态/编译、临时数学执行、原生预览、游戏实机、分配/性能。未实机与未测性能继续标未验证。
- [ ] 更新旧 BACKLOG 中“分离建新池”的过时描述；只登记本轮实际完成项，不先标完成。

## Task 5：Phase 3（在试点通过后单独启动）

**Files:** 新建 UI.lua；只替换试点已证实重复的构建样板，不迁移全库。

- [ ] 固定 UI.Row(props,children)、UI.Column(props,children)、UI.Spacer(grow) 为纯节点构建器；Host 使用与 Task 2 相同的显式适配入口，不再引入第二套 attach/build 路线。
- [ ] 不实现 UI.Bind/UI.Model、intrinsic measurement、min/max/shrink 或跨根迁移；未来需求另行设计。
- [ ] 比较试点代码可读性、重复配置与生命周期复杂度后再决定推广范围；没有测量不宣传性能提升。

## 决策建议

推荐批准上述 Phase 2 接口及渲染阶段修正后，串行执行 Task 1–4 成组交付。Task 5 后置；这轮不把全 UI 迁移作为交付目标。保持独立 Host 的收益是坐标与原生父级一致，成本是新增一层原生容器、显式适配表和生命周期管理；试点用于核实这些成本是否值得，不宣称已经最优。
