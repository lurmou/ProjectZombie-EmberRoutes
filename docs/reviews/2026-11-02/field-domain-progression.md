# FIELD 领域推进与目标责任核验

> 日期：2026-11-02｜版本：0.29.19｜基线：`4a8c57c` 加前轮 0.29.18 拆分及已有未提交修改。
> 范围：领域步骤与目标认领缺陷修复；未实机，未完成全业务 Workflow。

## 已实施

按[设计细化](../../superpowers/specs/2026-11-02-workflow-domain-boundaries-design.md)和[本轮计划](../../superpowers/plans/2026-11-02-field-domain-progression.md)：

- FieldSession.tick 不再规定 WORK 后必须 COLLECT/DELIVER，也不决定何时调用 continue。新 FieldWorkflow 是 FIELD 专属领域流程，不是跨工种公共引擎；准备阶段仍只完成准备，业务 Success 仍须经过停止/持久责任校验才能成为 Job 终态。
- WORK 完成且无未结原件时直接续作或申请结算；有地面原件则进入 COLLECT，只有背包原件则进入 DELIVER。货物 Success 后再次检查原件/holding/capacity/toolSupply/attempt/effects，不能以成功字符串释放责任。
- FieldProviders.continue 仅接受已确认 workDone、已知效果、无未结 attempt/holding/capacity/toolSupply 的边界。满96份资产记录不再开下一目标。没有放宽现有 FieldRecord、JobStore 或 Claims 校验。
- 换目标只剔除旧 field-target Claim，保留 item/其他 Claims 和 assets；同格不同 forage icon 经过 Discovery.claim 的分型复验可接续，不要求伪造 IsoObject。相同完整源身份不再重复接续。
- 新目标清除 workDone/attempt/spotted，保留单调 sequence；需领取新工具时进入 PREPARE。认领冲突/目标提交失败仅回滚本次新建而未生效的托管，原有工具及原件仍归原 Job；回滚无法确认则 UNKNOWN 留责，不以失败继续结算。
- 尸体合法处置区验证移至工具托管创建之前，避免拒绝目标后遗留新工具声明；其权限接受条件没有放宽。
- 新诊断文案 CN/EN 成对增加，1727 个键一致。版本三个来源同步为 0.29.19。其他会话的人员/UI/工具归还等修改保留。

## 为什么未删除 FieldWork.lua

FieldWork 仍唯一拥有 provider.claim、submit/live、advance/retire、prepareRecovery/wake、offer/cooldown/retry。FieldProviders、PublicWork、TaskPersistence 和 TaskResume 仍通过它接单、阻止重复劳动和恢复原任务。移走固定流程决策不等于这些责任已经被替代。直接删除会断恢复入口；只换文件名不构成架构收益。因此当前保留该领域协调入口，不声明旧文件退休。

创建认领仍经 FieldWork.provider.claim → JobStore.create / LaborStore.claimField；目标转换经 FieldProviders.continue → FieldContext.change → LaborStore.replaceField；正常释放仍经 FieldSession.stopAdapter.persist → FieldWork.advance → LaborStore.finishField / Directory.release / removeSettled；异常仍由 TaskBusinessStop 与 UNKNOWN/SUSPENDED/RECONCILE_REQUIRED 负责。

## 实际测试与反例

新 field-workflow-test 首次运行因模块不存在失败；增加资产保持断言后，原 continuous-batch 实现在“switching target retains GROUND and HELD originals”处失败。随后实现修复，不删除失败用例。

```powershell
java --class-path 'D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/*' tests/java/KahluaLaborTest.java field-workflow-test.lua field-continuous-batch-test.lua field-work-test.lua field-tool-supply-test.lua field-forage-test.lua field-actions-test.lua field-spatial-test.lua
```

最终 **7 套、178 项通过**：20 + 55 + 36 + 30 + 9 + 13 + 15。安装版 VM/标准库，身体/世界/物品效果为替身。

新增覆盖：无产物不调用 Cargo、浇水直接续作、准备不误结算、GROUND/HELD 保留、未知效果和未决 attempt 拒绝推进、未结容量/尸体拒绝结算、货物伪 Success 不释放、失败目标提交保持旧权威、同格两个 icon、spotted 复位、新工具 PREPARE 及失败回滚。旧 continuous-batch 夹具补 workDone 等生产边界事实，并显式提供已核对交付事实后才清偿其测试资产；没有为夹具放宽生产守卫。

```powershell
java --class-path 'D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/*' tests/java/KahluaCompileTest.java
node ../.workbuddy/tools/pz.mjs lint Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldWorkflow.lua Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldSession.lua Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/FieldProviders.lua
```

- 普通及 Debug 编译各329文件、0失败，最大局部名称表仍134。
- 三文件结构检查未发现问题；工具仍跳过原版 Fluids/ISFluidEmptyAction.lua 的 `0.0f` 解析失败文件，不据此宣布引擎源码全覆盖。
- 五文件 LuaLS（FieldWork/Context/Session/Workflow/Providers），完整生产源与 Umbrella 作依赖：0 Error、5 条去重 Warning。两条为 ledger.jobPolicies 动态字段，三条为 Discovery.claim 成功返回 keys 的关联类型推断；未放宽生产契约消警。原生进程因 warning 退出1，未记为退出0。配置/输出在本地 build/field-progression-typecheck-config.json 和 build/field-progression-typecheck.txt。
- 本轮定向 git diff --check 退出0，新文件尾随空白/EOF检查通过；doclink 扫5份文档，0错误/断链、0提示。最终五份源码与类型检查副本仅缩进空白差异（按tab宽8归一后完全相同）；原有其他文件的缩进告警未顺带整理。

## 未实施/未运行

有原件工作仍沿现有逐件取放链后再续作；保留 assets 是必要安全基础，不代表已经允许“砍多棵树再一次回仓”或“觅食多图标一次交付”。下一步需要可信产量、负重与记录容量预算，不能猜测剩余容量足够。

工具返还的 Offer 释放和冷启动已到仓未清偿、Demand/Feasibility、动态 UI/步骤历史及跨业务接入仍未实施。旧监控仍使用固定阶段投影，本批没有把执行改动误记为 UI 已完成。

未构建部署、未运行完整 preflight/全历史回归、未上传工坊；真实动作/路径、磁盘保存重进、崩溃窗口与性能未验证。正式实机候选再集中构建和全量检查，不宣布 Phase 3A B.5 关闭。
