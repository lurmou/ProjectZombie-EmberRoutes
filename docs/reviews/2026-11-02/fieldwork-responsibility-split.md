# FIELD 职责拆分首批证据

> 日期：2026-11-02｜版本：0.29.18｜基线：`phase-3a-consolidation@4a8c57c` 加开始时已有的 24 个已修改文件及 2 个未跟踪文件。
> 范围：等价拆分；不是连续作业、Demand 或动态 UI 的功能验收。

## 已实施

按[确认设计](../../superpowers/specs/2026-11-02-workflow-domain-boundaries-design.md)与[首批计划](../../superpowers/plans/2026-11-02-fieldwork-responsibility-split.md)：

- FieldWork 从 345 行减为 191 行，保留 provider/offer/retained/wake/advance/prepareRecovery 与唯一 runtime.submit。
- FieldContext.new 提取原上下文、FIELD token 认领、同世界/版本校验、权威 change/unknown、成员清债与移动适配。增加 binding 引用供 Session 组合使用；构造失败由 nil 映射回 submit 原有 false。
- FieldSession.spec 提取既有 Runtime spec、原阶段推进与 TaskBusinessStop；没有新增 Runtime、tick 调度器或资产权威。
- 精确文本比对：将构造返回值与 binding 字段适配归一后，Context 和 spec 的移动函数体与 HEAD 原 submit 对应部分完全相同。业务行为变更另批处理。
- provider-lifecycle 补充本轮已确认的“责任覆盖而非每工种固定物理阶段”语义。本批仍保留原有实际阶段。
- 模组三个版本来源同步为 0.29.18；现有 FieldProviders、工具返还、人员和 UI 的未提交修改未被重置或清理。

## 创建、正常释放、异常闭环位置

| 边界 | 当前代码位置 | 本批变化 |
|---|---|---|
| 接单与持久记录 | FieldWork.provider / p.claim（104/111 行）；仍 JobStore.create → LaborStore.claimField | 保留 |
| 身体执行准入 | FieldWork.submit（29 行）→ FieldContext.new（7 行）→ FieldSession.spec（4 行）→ runtime.submit（40 行） | 组合替代内联 |
| 运行事实和目标声明 | FieldContext.change → LaborStore.replaceField | 原样移动 |
| 正常终结/异常停稳 | FieldSession.spec.stopAdapter → TaskBusinessStop；persist 核对已知效果后写终态，否则 SUSPENDED/RECONCILE_REQUIRED | 原样移动 |
| 目录、Claims 和记录退役 | FieldWork.advance（64 行）→ Directory.release / LaborStore.finishField / removeSettled | 保留 |
| 保存后恢复 | FieldWork.prepareRecovery（49 行）及 wake（45 行） | 保留，未知效果不重放 |

上述是调用和代码结构证据，不等于所有原版动作、故障恢复窗口已经实机验收。

## 实际检查

安装版 Kahlua 命令（拆分前、后各运行一次）：

```powershell
java --class-path 'D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/*' tests/java/KahluaLaborTest.java field-work-test.lua field-actions-test.lua field-spatial-test.lua field-forage-test.lua field-tool-supply-test.lua field-continuous-batch-test.lua
```

两次均通过：36 + 13 + 15 + 9 + 30 + 39 = **142 项**。使用安装版 VM/标准库，原生身体、世界和物品效果为替身。没有修改测试预期或放宽生产守卫。

```powershell
java --class-path 'D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/*' tests/java/KahluaCompileTest.java
node ../.workbuddy/tools/pz.mjs lint Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldWork.lua Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldContext.lua Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldSession.lua
```

- 安装版普通/Debug 编译：均 328 文件、0 失败；最大 Debug 局部名称表 134，位于既有 LaborStore。
- 三文件结构检查：未发现问题。工具知识库仍有一份原版 Fluids/ISFluidEmptyAction.lua 因 Java 风格 `0.0f` 无法解析，未将该文件算作已审查。
- LuaLS：三份精确源码副本作为检查目标，完整生产 client/shared 与 Umbrella 作为类型依赖；使用绝对 configpath。最终 **0 Error、2 条去重 Warning**，均为搬移的 `ledger.jobPolicies` 动态字段；未改变字段读取来消警。原生 LuaLS 进程对 warning 返回 1，不冒称进程退出 0。输出与配置位于本地 build/field-split-typecheck.txt、build/field-split-typecheck-config.json，不纳入发布包。
- 最初相对 configpath 检查未加载完整类型依赖，出现 8 条 undefined-global，已弃用该结果；改用绝对路径复核。一次 `luals --help` 被工具解释为默认扫描，已中止，不计入本项目证据。
- 工作区全局 `git diff --check` 发现原有人员/UI/工具及测试等文件的缩进告警；没有为了取得全绿重排其他会话的代码。本轮已跟踪文件定向 `git diff --check` 退出 0；新文件单独检查尾随空白与 EOF 通过。doclink 检查 6 份文档，0 错误/断链，1 条既有规则文件缺日期/状态头部提示。

## 未实施与未验证

尚未修改工具返还的目录释放、持久恢复位置核对，也未新增独立 Demand/Feasibility、动态工单投影或 FIELD 提前续作策略。后续按设计分批实现，不将本批记为公共 Workflow 内核或全业务接入完成。

未构建部署、未上传工坊；未运行全量回归/preflight，留待正式实机候选集中执行。未运行游戏实际动作、正常磁盘保存重进、崩溃恢复与性能采样，不宣称玩法通过、性能提升或恢复安全已完成。Phase 3A 的 B.5 实机门禁仍开放。
