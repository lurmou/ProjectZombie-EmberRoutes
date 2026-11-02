# FIELD 领域步骤实施计划

> 日期：2026-11-02｜状态：按用户“继续”实施｜本地 Codex 顺序执行，保留并行改动，不自动提交或推送。

**Goal:** 让 FIELD 决定是否需要货物阶段和何时续作；修正目标切换的原件责任与 forage 身份处理。

**Architecture:** FieldWorkflow 是 FIELD 专属流程；FieldSession 管 Runtime 生命周期，FieldWork 管领域接单/恢复/退役。现有 Claims、停止回执与存档格式保留。

**Tech Stack:** PZ B42 Lua，安装版 Kahlua 与现有 Java 测试宿主。

**Spec:** [已确认设计及本轮细化](../specs/2026-11-02-workflow-domain-boundaries-design.md)。

## Global Constraints

- FieldRecord format=1，Claims 上限128、assets上限96，不改 Validator/UNKNOWN 作用域隔离。
- 无产物可以直接续作或结算；有产物先沿已验证货物链，不宣称完成有货多目标批次优化。
- 唯一体控和停止仍经 TaskRuntime/TaskBusinessStop；不新增通用执行引擎。
- 现有工具返还、Demand、UI 待办不删除，也不在本批夹带修改。

## Review Focus

- 原版效果未知或未结 attempt 不允许续作或结清。
- 空产物不调用货物执行器；地面/背包原件必须进入货物链且不丢 claims。
- 准备完成只进入 WORK，不结束 Job。
- 同格 forage icon 分别认领；目标变更复位 spotted，重复同源不续作。
- 认领失败/CAS失败保留原目标、货物及原托管；新领工具未成功接入须回滚。

## Task 1：领域推进

**Files:** 新增 `client/EmberRoutesProbe/FieldWorkflow.lua`（路径根为 Contents/mods/EmberRoutesProbe/42/media/lua），修改同目录 FieldSession.lua；新增 tests/lua/field-workflow-test.lua。

**Interfaces:** `FieldWorkflow.step(c,def)` 消费现有 FIELD context、`def.step/continue/collect/destination`，返回 Running/Success/Failure；不写终态或释放 Claims。

- [x] 新增反例：空产物直接结算/续作、不调用 Cargo、未知效果/attempt/holding 拒绝结清、准备不误结算、真实原件先交付、失败提交不推进。
- [x] 运行新用例确认旧实现缺少该模块而失败。
- [x] 实现领域推进并令 Session 委托；保留 Session 原终态与失败收束。
- [x] 运行 field-workflow 和现有 field-work/tool-supply/forage/actions/spatial 定向回归。

## Task 2：安全换目标

**Files:** FieldProviders.lua、tests/lua/field-continuous-batch-test.lua。

**Interfaces:** 保留 `def.continue(c)` / provider.continue(c) 返回布尔值；失败不更换持久目标，原件与原有托管继续归原 Job。

- [x] 补真实 Store 接缝断言：GROUND+HELD 与非目标 Claim 保留、spotted复位、同格不同icon、拒绝未结attempt、目标提交失败与新增托管回滚。
- [x] 去除 IsoObject/坐标不同的通用续作假设，以分型 Discovery.claim 复验并比较完整源身份。
- [x] 仅替换 target Claims，保留原件和非目标 claims；按新工具需求选择 PREPARE/WORK；失败回滚本次新建托管。
- [x] 复跑相关套件，不放宽 Validator 或实际生产守卫。

## Task 3：验证与进度

- [x] 递增版本 0.29.19，运行普通/Debug 编译与本轮结构/类型检查。
- [x] 更新证据、BACKLOG 与 INDEX；doclink 和定向差异检查。
- [x] 报告实际通过、失败和未运行项；不将未实机的流程或旧文件退休记为完成。
