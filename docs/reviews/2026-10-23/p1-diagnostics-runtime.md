# P1诊断入口与控制调用核对（0.22.11）

状态：P1任务3的业务/诊断运行接线及控制调用静态核对完成；任务4统一保存、退出和读档恢复尚未实施，迁移总门闩继续关闭。代码接线完成不等于原生动作与交接已验收。

依据：[唯一架构v1.1](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)、[P1计划](../../superpowers/plans/2026-10-23-p1-runtime-integration.md)、[旧制作接线](p1-legacy-craft-runtime.md)。未改变架构、工单存储或最低存量语义，未开发公共任务选择、微观行为树及界面视觉。

## 实现及边界

- 新增TaskDiagnostic薄适配：旧Actions/Haul诊断Batch仍由原模块解释，只通过TaskRuntime申请身体与推进；没有第二个控制器、计时器或业务任务池。排队不提前生成样本，启动重复核验稳定NPC/世界/条件。
- Actions吃喝/背包转移、Haul移动/世界容器转移及清理使用获授body。原生动画、update、perform、stop均隔离过期会话，重复perform/同步stop重入有尝试标记；Probe的旧tick不重复推进受控批次。
- 诊断取消只请求自身Job停止；选择别的NPC不能取消原持有者。跨模块清理传入确切NPC及body，不能清另一NPC的样本。保留原诊断模块每类单批次的兼容限制，未把它们扩展为正式多NPC劳动内核。
- 停止验证实际原件身份/位置。`Registry.data().diagnosticRecovery={format=1,byNpc=...}`仅保存未解决诊断的标量恢复事实（jobId/kind/原件ids/reason），每世界至多256个NPC记录，每条至多32个ID；不是运行Job索引或新资产结算者。未知记录不被新成功记录覆盖，清理须匹配工种及原件集合；未知资产阻止新建资产诊断及移除NPC，但允许安全移动/显式健康诊断。
- Persistence的sample/clearsample/recover也经同一申请；checksample只读。样本操作及跨Actions/Haul清理的残留原件共同核验。恢复事实仍是世界内存/ModData状态，**未证明已落盘或可完整恢复**；任务4必须将它与样本清理、检查点及失败路径一起编排。
- NpcCommands的move/stop经受控移动或停止申请；stop不谎报立即停稳。remove先等待会话关闭、货物/诊断恢复义务解除并检查Lua队列，再调用Java专用removeIdleCarrier。Java复验世界、精确角色实例、无grant、非冻结/退役及原生停止位图；不重新开放旧command/remove旁路。

## 控制调用清单

本轮脚本扫描124个Lua/Java源码文件，138条文本匹配：owned 30、control 8、move 13、stop 29、queue 17、cancel 26、recovery 15。完整结果在`build/logs/p1-diagnostics-control-inventory.json`；补查了Java命令/内部stopProbe及Lua直接检查点调用。脚本包括定义，可能漏多行或间接调用；以下为实际源码路径判定，不能用匹配数证明运行正确。

| 调用归属 | 授权/保留依据 |
|---|---|
| TaskController及Driver的受控出口 | 私有票据、当前Session与Java grant绑定；统一add/clear/move/stop及停止快照；过期票据不能操作继任队列 |
| WorkAgent/WorkTransfer、Production/ProductionActions、CraftProbe、CompanionAgent | 新上下文传body；旧直调及cancelAll仅无body兼容分支；Production/Craft自动续工提交非抢占申请。旧Driver/Java命令对managed角色拒绝控制 |
| Actions/Haul | 受控入口走TaskDiagnostic；原始队列和Java移动/停止保留于无body旧分支。只读report及容器标签意图不写NPC身体；有body的回调检查当前/保留票据 |
| NpcCommands | gate开启时move/stop/remove提前转发，不进入旧cancelAll/command分支。inspect只读，spawn/spawnAdditional为新实体生命周期；idle remove另有Java门禁 |
| Persistence及PersistenceSamples | 样本写入已接获授上下文；旧stopCarrier/cancelAll仅在gate关闭分支。Samples的装备/健康/原件修改由样本命令调用，不从普通保存或只读检查触发 |
| Persistence.captureOnSave/restore/tick及Boot保存降级分支 | **任务4待迁移**：直接检查点捕获、恢复及保存后多源重启未统一。Java对managed旧保存/恢复仍拒绝；不能因任务3完成开启gate |
| Boot.cancelEvery/reset、ProbeRuntime.reset/retirementTick、CarrierRuntime/ProbeNpc内部停止 | 系统退役/死亡/移动终止/故障停机或旧兼容路径；普通Java command/commandFor/stopCarrier受managed门禁。引擎内部停止不授予第二个Session，失败仍须由当前任务核对实际效果 |

## 验证

- 安装Kahlua：诊断受控31项、直接命令8项、持久化样本11项通过，包含等待旧工作停止、样本迟到回调、异NPC取消/清理隔离、未知原件保留及匹配集合清理。移除桥和引擎动作仍是替身。
- 相关回归：原持久化编排35项、样本21项、正式制作28项、旧制作42项、运行服务36项、控制器28项、受控搬运20项及Controller/Driver桥接检查通过；复用夹具中的制作652项和多NPC48项等保留各自原始边界。未重复全历史套件。
- 0.22.11构建通过，含新增Java空闲生命周期断言及当前安装JAR基线核对；release-check为0错误、54条既有提示。ZIP内本轮关键Lua/JAR/mod.info等10文件逐一SHA256匹配工作区，版本一致。
- 最终preflight通过：108个Lua文件语法/结构检查无问题，LuaLS为0错误、72条既有信息性告警，分布回到既有基线。新增空值提示已定位至Actions.tick中局部检查前的读取，前移检查并缓存body后复核通过；既有原版ISFluidEmptyAction.lua的`0.0f`仍为工具解析缺口，不产出该文件结论。
- 5份本轮文档链接无断链，定向diff空白检查通过。原始输出见`build/logs/p1-diagnostics-final-tests.txt`、`p1-diagnostics-controller-work-tests.txt`、`p1-diagnostics-guard-tests.txt`、`p1-diagnostics-preflight-final.txt`、`p1-diagnostics-release.txt`；初次检查及提示明细也保留，不能将其当最终源码结论。
- 原生停止/移除、保存读档、退出故障恢复及性能**未验证**。BodyAuthority单测不证明原生角色移除成功，ModData恢复事实不证明磁盘保存成功。

## 在线需求与下一步

本轮再次成功读取[唯一在线需求](https://docs.google.com/document/d/1aTOBrzZvh_iCDkv045HNAV13i7vNf7OHk6E_sE7TWNM/edit)的TXT导出，SHA256仍为`1E802DFE03A43437C77DC8EF5D04A2E38EC9AE9970A71D349B302B9EFE2EFB08`，与上次成功读取一致；未发现导出正文变化，不据此判断评论或纯格式变更。当前副本仅在`build/logs/requirements-current.txt`，不建立平行需求。

下一步任务4：统一提前停派与OnSave同步事实捕获、诊断样本清理/diagnosticRecovery、检查点、退出及读档恢复、StockService与随从/制作唯一恢复来源。保存回调不能等后续tick，也不能把OnPostSave当落盘证明。完成后才打开总门闩进入任务5集中实机验收；界面视觉仍最后处理。
