# 普通工作责任闭环与动态监控实施证据

> 日期：2026-11-02｜候选版本：0.29.20｜源码、安装版 Kahlua 替身与构建证据；PZ 实机未运行。

## 本批结果

沿用 Phase 3A 的 Job/Claim/唯一身体控制，不新增通用 Workflow Runner。FieldWork 保留接单、恢复、保留责任及退役；FieldContext、FieldSession、FieldWorkflow 分别承接上下文、身体会话与 FIELD 领域推进。删除 FieldWork 的条件尚未满足，不能以改名转移同一职责后宣布删除完成。

工具返还新增严格可选 `returnIntent={format=1,jobId,destinationId,scopeId}`，保持 ToolCustody format=1。不迁移旧档，不猜测无意图记录的目的地。冷加载保留 PENDING_RETURN；恢复会话只观察原件，不重放 PUT。已到指定合法仓库才清偿，仍在原 NPC 背包且停稳才撤销返还，未知保留责任。返还中及未知托管不能重新借用。

清洁待派需求由现有 PublicWork 在无人早退前观察，复用 FieldSpatial 预算；没有 NPC 也能显示已观察源。覆盖始终 PARTIAL，卸载保留陈旧事实，已认领点不重复计数，已证实消失或删除据点才移除。条件诊断分片核对现有授权、工作矩阵与工具角色，不创建 Job/Claim。

FIELD、CRAFT4、HAUL2/3、COOKING1 的监控步骤来自各自领域事实。配方单次效果、Manifest 部分交付/撤回、渐进流体、炉具义务分别保留。工具孤立责任仍可见。Cards 只读缓存，显式完成证据取代阶段索引猜测；长步骤文案在缓存生成时截断。

## 创建认领、正常释放与异常打断入口

| 责任 | 创建/认领 | 正常释放 | 异常/恢复 |
| --- | --- | --- | --- |
| 工具返还 | `ToolReturnProvider.lua:53` → `ToolReturnService.lua:96` → `LaborStore.assignToolReturn` | Service 的 `persistStopped` 核对原件并调用 `completeCustodyReturn`；Provider `advance:79` 消费 knownStopped 才释放目录 | Service `interrupt:46`、`reconcile:346`、`recoverFor:366` 复用 TaskBusinessStop；未知留 ToolCustody/Claim |
| FIELD | `FieldWork.lua:104` provider 与原 submit；`FieldContext.new` | 原 `FieldWork.advance:64` 退役链，Session 沿原 Stop 适配 | `FieldWork.prepareRecovery:49`，FieldSession 唯一 Runtime spec；FieldWorkflow:22 只决定领域下一步 |
| 待派需求 | `FieldDemand.advance:63` 仅建立派生坐标事实 | 已加载证实消失、据点删除或世界切换清除派生事实 | 未加载标 OBSERVING/STALE，不能释放实际 Job/Claim |

源码根为 `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/`；ToolCustodyRecord 位于同级 shared。行号对应本批工作树，后续修改可能变化。

## 检查结果

- 20 套定向 Kahlua 回归通过：业务投影、清洁需求、货物阶段、监控视图/命令、公共派工、工具返还/托管、FIELD 推进/劳动/供给/续作/forage/动作/空间、成员运行/命令、保存运行/诊断及 JobStore。新增据点删除反例后，清洁需求单独复跑为15项；监控视图19项通过。制作 COMMITTING 的活跃执行与停止后未知另加反例，业务投影最终16项通过。日志：`build/workflow-closure-regression.txt`（末次增补两套另行复跑）。
- 另5套烹饪接管/热源/流体、配送及制作运行回归通过，日志 `build/workflow-business-regression.txt`。其中生产测试含安装版来源适配，但原生效果仍被替身代替。
- `tools/build-probe.ps1` 成功；333 Lua 普通/Debug 编译零失败，固定 JAR 哈希、Java 逻辑/检查点/身体权威、安装版原生读取等构建检查通过，CN/EN 键集合一致。日志 `build/workflow-closure-build.txt`。
- 定向 LuaLS 15文件：0 Error，72 problems（Warning，集中 LaborStore/PublicWork 两文件）；不是无告警通过。日志 `build/workflow-closure-typecheck.txt`。本轮投影/返还新文件未报告类型错误。
- 完整 preflight 最终通过：结构检查333文件0 error/12 warning，默认关闭的 prerender 守卫通过，88条 mined 候选0命中；全仓 LuaLS 0 Error/612 Warning；索引新鲜度10项通过。动态字段/Java注入告警仍存在；未连接客户端的 check_health 被工具跳过。末次只读制作投影调整另经上述定向 LuaLS 与完整构建验证。
- 本轮 Markdown 相对引用无缺失；IG_UI 1801对键、Sandbox 3对键一致。
- 中英文聚焦监控预览生成并目视复核，`build/qa/settlement-visual-orders-CN.png` 与 `-EN.png`；数据和 ISUI 宿主为替身，不能当实机截图。既有字体图标缺字与页面按钮截断仍存在。
- 发布检查未通过：既有 `UI/PageLifecycle.lua:22,347` 两处 debug print；另23条硬编码中文提示。本批没有顺手改写其他 UI 生命周期工作。
- 扩大回归的 `labor-core-test.lua:50` 失败：旧夹具仍要求自动迁移，现行生产契约明确 `LEGACY_TASK_RESET_REQUIRED`。保留失败，没有放宽守卫或删除断言。完整 SettlementTabs 夹具另在仓储选中项 fullType 空值处失败；聚焦监控预览不覆盖该旧失败。
- 全工作树 `git diff --check` 仍含已有 UI 文档末尾空白及多文件空格缩进；没有为消除检查输出重排他人修改。

## 交付及未完成项

候选包：`build/packages/EmberRoutesProbe-0.29.20.zip`。构建会包含当前候选工作树已有修改，未提交、未推送、未发布，也未启动游戏验收。

本批闭环与展示接入完成不等于 v3 全部完成。有货跨目标连续采集尚未放开；搜寻输出含随机数量与 spawnFuncs，不能在只读诊断中生成原件后假装容量已知。其他工种独立源观察、补库存条件链尚未全面实施；没有假造全地图需求。工具已到仓中断、未加载/权限变化、保存重进、死亡与世界切换还需实机复核；故障恢复、完整 UI、性能和 B.5 均未验收，不宣称零损失或性能提升。
