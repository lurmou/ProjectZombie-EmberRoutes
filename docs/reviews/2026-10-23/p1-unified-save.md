# P1统一保存、退出与恢复接线（0.22.12）

日期：2026-10-23。对应[唯一架构v1.1](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)及[P1计划任务4](../../superpowers/plans/2026-10-23-p1-runtime-integration.md)。代码接线完成，迁移门闩仍为false；新路径的游戏保存/退出/读档、原生停止及性能未验证，不记为P1通过。

## 实现范围

- 新增TaskPersistence，Persistence在受控路径转交保存编排。StockService取消独立OnSave/OnGameStart监听，改由Boot/Persistence明确调用停派、重置与恢复，避免事件注册顺序决定最终状态。gate关闭的旧保存编排保留，并补入正常tick上的StockService恢复。
- 提前准备调用Runtime.beginSave，后续正常tick可停稳。OnSave调用captureSave，对最多256个已有owner逐个进行一次停止尝试/观察；不调用step、不睡眠、不等待下一tick。确认停止和效果已记录后才释放控制；未确认时写UNKNOWN和恢复阻断，不把取消当回滚。
- 工作数据增加executionSave格式1标量收据（本次UUID、当前npcId/jobId/kind、停止/效果事实、对应随从意图）。原有Java检查点格式、labor/craftProbes及原件/容量声明不替换。COMMITTING及未知效果继续由原业务保留，不重做产物。
- 新增Java冻结空闲保存系统入口，捕获时不再调用stopProbe。saveBodyReady验证当前世界、精确body、无grant及原生stopMask；只在同步保存调用栈内提供临时cleanup能力，不能move/add/stop，返回前撤销。清理Actions/Haul临时样本，不删除PersistenceSamples或其他真实财产；无法核对原件时阻断并保留diagnosticRecovery。
- 冻结/退役同时拒绝旧Java写入口及新建载体，防止尚未获得首个grant的NPC从旧入口绕过屏障。读档restoreCheckpointFor使用稳定ID及空闲生命周期检查，不依赖当前UI选择。
- Boot先规范旧记录、重建LaborStore声明，然后允许运行/恢复。记录非法时关闭ready并暂停最低存量。恢复仅提交非抢占候选，保留原Job；原件由既有执行器在获授前再次索引核对。已有携货/未知资产不自动禁止当前明确跟随意图的安全移动，不改写或释放旧工单。
- 活世界中，制作afterSave仅在验证后开放候选；随从只恢复本次捕获的COMPANION Job。旧随从意图不能成为另一恢复来源。冷读档按捕获的当前Job选择恢复来源；搬运保留暂停和原件，既有物流可按既有非抢占入口申请续工，诊断不自动重放。未发布的纯规划草稿不冒充持久化Job。

## 保存文件核对的依据与边界

安装projectzomboid.jar SHA256仍为E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33。新增只读javap原始证据：build/research/p1-globalmoddata-javap.txt；GameWindow/IngameState证据沿用[生命周期核查](p1-save-lifecycle.md)。

原版GlobalModData.save写入版本249、表数量及带长度的表块，经global_mod_data.tmp复制到global_mod_data.bin；load使用GameWindow.ReadString及KahluaTable.load。ProbeSaveReceipt在OnSave结束前捕获本模组Work与NpcCheckpoints两张表的纯标量结构，在下一个正常tick只读一次原版bin，核对本次UUID、完整业务与检查点结构，且要求活世界内存仍匹配。不会调用GlobalModData.load替换运行中的表，也不写第二份存档。其他模组的表不解析。

OnPostSave不作为成功凭据；保存到ModData的CHECKPOINT_SAVED只是捕获结果。文件缺失、旧UUID、截断、业务不匹配或显式原生保存异常均保持冻结/停派，并记录原因，不逐帧重读。文件核对上限64MiB、32768表，结构快照上限一百万条目/32层；超限保守阻断，实际规模和耗时未测。引擎升级触发既有JAR基线复核，同时复核249格式。

这只证明本次本模组记录可从原版文件读回，不能证明其他世界文件成功或断电持久性。引擎可能在更后面保存其他系统时失败；无法观察的外部保存失败不宣称已解决。OnSave后才发现的错误只能阻断当前活世界并尝试毒化下一次保存，不能追溯改写已经写出的文件。原生退出若没有后续tick，不恢复任何任务。

## 验证

- 新增Kahlua定向：统一保存/恢复61项、真实Actions/Haul保存适配12项；覆盖同NPC竞争、非抢占候选、原Job、未知原件、未停稳、失败、旧世界、提前准备及临时清理能力撤销。引擎body/磁盘边界为替身。
- Java新增10项当前安装Kahlua真实序列化/保存文件封套核对，验证正常文件、旧UUID、声明变化、跨世界路径、缺表、截断、未来格式和循环表；构建同时执行BodyAuthority/旧检查点等既有必要检查。
- 控制器28、运行服务36、随从20、正式制作28、旧制作42、搬运20、旧保存35、Boot15、StockService18及Driver桥接相关回归通过。日志见build/logs/p1-save-*-tests.txt与save-receipt-tests.txt。
- 0.22.12构建、最终preflight通过（109个Lua，0错误，LuaLS保留72条既有信息告警）；release-check通过（0错误，54条既有中文硬编码提示），包内11关键文件与源码/JAR一致，6文档链接检查通过。工具首次LuaLS临时配置写入被沙箱限制，已按相同命令提升权限重跑。结构lint仍跳过原版ISFluidEmptyAction.lua的0.0f解析缺口，不当作本模组结论。

## 续接点

Task4代码已接，不再重建保存框架。保留本轮及其他AI的混合未提交改动。下一步任务5：复核完整迁移入口后开启controlledExecution，集中单人游戏验证切换/提交中断、双NPC隔离、保存与退出/读档及失败门禁，再按结果决定是否通过P1。公共任务目录、优先级认领和界面视觉均未在本轮开发。
