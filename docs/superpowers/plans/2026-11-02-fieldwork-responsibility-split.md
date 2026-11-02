# FIELD 职责拆分实施计划

> 执行方式：本地 Codex 在当前会话顺序实施，保留已有未提交修改；不自动提交或推送，不派发子代理。此方式沿用用户已批准的开始执行与项目协作约束。

**Goal:** 将 FieldWork 的运行上下文及 Session 适配提取为两个有实际调用方的 FIELD 领域模块，保持现有行为。

**Architecture:** FieldWork 保留公共入口和世界局部协调；FieldContext 管运行上下文，FieldSession 构造既有 TaskRuntime spec。现有 TaskBusinessStop、LaborStore、FieldSupplies、FieldCargo 保持唯一责任。

**Tech Stack:** PZ B42 Lua、安装版 Kahlua/Java 宿主、现有 pz 工具入口。

**Spec:** [普通工作公共契约与 FIELD 职责拆分](../specs/2026-11-02-workflow-domain-boundaries-design.md)。本计划只实现该规格第 3 节，不代表完成第 4 节后续业务。

## Global Constraints

- FieldRecord format=1；不改 JobStore/Claims/UNKNOWN 隔离与 byNpc 契约。
- 保持所有公开入口、守卫顺序、失败语义、恢复与实际阶段推进。
- 保留用户/其他会话在 FieldProviders、工具归还及 UI 等文件中的未提交修改。
- 新模块无世界可变单例；无新调度器、无新资产账本、无原生 API 新增。
- 首批不修改 UI、Demand、连续作业策略或工具归还行为。

## Review Focus

- Context.new 认领失败必须在构建 spec/提交 Session 前返回，保留原拒绝路径。
- 提取后原始 job 身份、root 与 c.job 更新版本不能被混淆；复用 field-work 的认领冲突及过期上下文检查。
- 成员离队只允许已有货物清债，不重新开始劳动；复用 field-work 成员变更用例。
- 停稳前不释放；UNKNOWN 保留原件/目标；复用 field-work 的停止与未知效果用例。
- PREPARE、作业、货物与续作次序保持；复用 field-tool-supply、continuous-batch、actions/forage/spatial 的业务回归。

## Task 1：等价拆分运行上下文及 Session

**Files:**
- Create: `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldContext.lua`
- Create: `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldSession.lua`
- Modify: `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldWork.lua`
- Verify: `tests/lua/field-work-test.lua`、`field-actions-test.lua`、`field-spatial-test.lua`、`field-forage-test.lua`、`field-tool-supply-test.lua`、`field-continuous-batch-test.lua`

**Interfaces:**
- Consumes: 现有 actor、detached job、Driver binding、provider def、world root 和 FieldWork 所有的 cooldowns。
- Produces: `FieldContext.new(actor, job, binding, def, root)` 返回原 c 上下文或 nil；`FieldSession.spec(c, def, cooldowns)` 返回现有 Runtime spec。

- [x] 在改动前运行上述现有 Kahlua 套件，记录基线失败；不因拆分新增重复测试。
- [x] 将原 submit 的 c 创建、token、same/change/unknown/recoveryRequested/valid/move 原样移入 FieldContext.new；构造失败返回 nil，结束返回 c。
- [x] 将原 submit 的 spec 构造及其方法原样移入 FieldSession.spec；以 `c.actor/c.job` 绑定原 actor/job，保留原 cooldowns 引用。
- [x] FieldWork.submit 保留原准入检查和 definitions 查询，依次构造 Context、Session，再调用原 runtime.submit 并保存 live；移除仅用于已提取代码的 require。
- [x] 对比移动前后文本与闭包依赖，确认全部阶段、守卫、超时、返回值和写入顺序一致。
- [x] 执行安装版 Kahlua 同组定向回归；失败须定位实际契约，不放宽生产守卫。

## Task 2：验证、版本与交接

**Files:**
- Modify: `version.txt`、`Contents/mods/EmberRoutesProbe/42/mod.info`、`Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Build.lua`
- Modify: `docs/BACKLOG.md`、`docs/INDEX.md`
- Create: `docs/reviews/2026-11-02/fieldwork-responsibility-split.md`

**Interfaces:**
- Consumes: Task 1 模块及测试实际输出。
- Produces: 可审查的首批结构拆分、验证证据和剩余业务范围。

- [x] 将当前 0.29.17 递增为 0.29.18，三个版本来源一致。
- [x] 对三个 FIELD 文件运行 Lua 结构和类型检查，并执行安装版普通/Debug 编译；记录 warnings，不用类型检查替代实机。
- [x] 记录前后文件职责、行号、定向测试结果、检查失败及未运行项；不记性能提升或玩法验收通过。
- [x] BACKLOG 原位登记本批及下一业务批次，INDEX 登记本规格/计划/证据；不改在线需求或追加 HANDOFF 流水。
- [x] 运行 doclink 与 git diff --check，核对已有未提交修改仍保留；不自动 commit/push 或上传工坊。

## 后续

按规格第 4 节，先修工具返还责任闭环，再形成清洁 Demand/Feasibility 与动态展示的完整批次，之后改变 FIELD 连续作业决策。本批不预建这些模块的空壳。
