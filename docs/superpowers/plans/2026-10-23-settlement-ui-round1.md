# 据点控制台第一轮实施计划

**Goal:** 接入仓储/工单监控主导航，用稳定工单ID浏览当前制作和搬运任务，保留旧任务操作与配置入口。

**Architecture:** 新增OrderMonitorService只读投影和OrderMonitorPage，复用既有账本、CraftingService、Work、TaskRuntime及UI组件。当前任务仍来自旧byNpc/搬运记录，不冒充公共Order；命令重新核对工单ID、代次与据点。旧制作/最低存量及搬运配置作为监控内兼容入口保留。

**Tech Stack:** PZ42.21 Lua/ISUI、Kahlua、现有Theme/Layout/State/CachedList/PageLifecycle。

**Spec:** [已确认UI设计](../specs/2026-10-23-settlement-ui-design.md)、[NPC架构v1.1](../specs/2026-10-22-npc-behavior-architecture-design.md)。本轮由当前代理顺序执行，不安排子代理，不提交混合工作区。

## Global Constraints

- 用户已批准将新外壳和工单监控前移；P1实机仍未通过，公共Order/优先级/Stock迁移不在本轮。
- 只开放仓储、工单监控，不放空人员/防御页，不新增指定NPC的正式下单入口。
- 视图只读标量副本；隐藏释放订阅，无库存扫描、配方全目录规划或独立调度器。
- 暂停/取消经既有服务，身体停止未确认时不能直接显示已暂停；原件未知不能删单解锁。
- 保留现有未提交改动；CN/EN配对，完成preflight、构建、release-check与相关最小回归。

## Review Focus

- 同NPC新工单替换旧单后，旧视图命令不得误操作新单。
- 跟随、停工请求与本单执行分开，已携原件与未知提交可诊断。
- 无载体/不在物流工人池的旧任务仍可见，不因界面迁移丢失入口。
- 窄屏列表/详情切换、长双语文本、空列表和筛选不产生负尺寸。
- 关窗/切页/权限变化/迟到回调释放，后台任务不因关闭监控而停止。

### Task 1: 工单投影及命令保护

Files: 新建client/EmberRoutesProbe/OrderMonitorService.lua；修改TaskRuntime.lua增加只读状态查询及离散状态通知、Work.lua增加针对稳定Job的操作入口；测试tests/lua/order-monitor-service-test.lua。

- [x] 先用账本替身覆盖制作/搬运/离线载体、据点过滤、稳定ID及代次拒绝。
- [x] 投影当前记录的真实阶段、数量、原件义务、配方链节点及身体行为；不生成持久UI账本。
- [x] 暂停/继续制作复用CraftingService；搬运暂停/继续经Work按明确NPC和Job核验；未支持的取消保持兼容入口。
- [x] 定向Kahlua验证，运行服务状态不改变执行权协议。

### Task 2: 新控制台与工单页面

Files: 新建UI/OrderMonitorPage.lua、UI/OrderMonitorCards.lua；修改SettlementDashboard.lua及CN/EN翻译；保留CraftingPage/LogisticsPage为兼容入口；测试tests/lua/settlement-tabs-test.lua及新页面夹具。

- [x] 主导航为仓储、工单监控；旧页面不再占主导航，外部旧入口仍可达。
- [x] 工单筛选、左列表右详情；窄屏改列表/详情导航，操作和原因常驻。
- [x] 页面以工单ID选中，显示执行者/身体行为、已制成与已入库、链节点、原件及端点；不显示伪倒计时。
- [x] 监控内保留旧制作/规则及搬运设置入口，关闭不停止业务；保留列表键盘/手柄焦点与现有快捷键，完整输入实机仍待验。
- [x] 测试切页/迟到回调、稳定选中、窄布局和CN/EN文本；必要时生成实际Lua绘制预览。

### Task 3: 构建与续接

- [x] 版本0.22.16；preflight、定向逻辑/生命周期检查、构建、发布及包内一致性。
- [x] 更新BACKLOG/HANDOFF/UI设计的实际状态，记录未实现功能和未验证实机效果。
