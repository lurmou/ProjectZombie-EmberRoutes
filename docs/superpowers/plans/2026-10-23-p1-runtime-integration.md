# P1统一执行权运行接入计划

日期：2026-10-23。状态：计划已形成，运行代码未修改，以下步骤未执行。

执行方式：主代理顺序实施，不派子代理。按项目及用户规则采用实际风险对应的定向回归，不重复全历史测试；技能模板中的额外子技能不可用时不据此阻塞。

**Goal:** 使已有制作、搬运、随从、诊断及保存恢复通过唯一身体控制协议，不开发公共任务池和新工种。

**Architecture:** 复用ExecutionSessions内核，新增运行TaskController及动作停止核验适配。旧业务保留资产权威和恢复记录，控制器只持运行会话及恢复申请。Java移动/停止入口也必须识别当前授权，不能只封UI。

**Tech Stack:** 当前PZ安装JAR、Kahlua Lua、已有Java载体与构建脚本。

**Spec:** [唯一架构v1.1](../specs/2026-10-22-npc-behavior-architecture-design.md)、[迁移证据](../../reviews/2026-10-23/task-migration-boundaries.md)、[统一任务协议](../specs/2026-10-23-unified-task-dispatch-design.md)。

## Global Constraints

- 一NPC仅一主动身体执行者；身体停止未知时不授予第二执行者；资产未知不阻止已确认安全的撤离。
- 旧taskId、原件ID、声明及已确认效果不能因接入被重建或释放；不改最低存量产品语义。
- 本计划不迁移为多挂起Job存档，不放宽byNpc互斥校验，不提前开发公共目录/完整优先级/新行为树框架。
- Lua修改必跑preflight，Java修改构建并运行相关回归，发布升版本及release-check；实机未运行标未验证。

路径缩写：L=Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe，S=同media/lua/shared/EmberRoutesProbe，J=java/src/main/java/emberroutes/probe。每任务开始核查git diff，保留并行工作。

## Review Focus

1. moveTo内部清原生动作队列：任务2证明无授权移动不能影响现有制作。
2. stop/clear同步回调重入：任务1/3证明旧回调不能派下个动作或清新会话。
3. 制作提交已生效后异常：任务3保留真实原件与UNKNOWN，不自动重放。
4. 保存事件顺序及多恢复来源：任务4证明一个NPC最多一个恢复授权，失败不重开。
5. 诊断/旧Java命令旁路：任务2/3拒绝无授权写身体，不能只测普通页面。

## Task 1：控制器与停止证据协议

Files: Create L/TaskController.lua、L/TaskStopEvidence.lua；Test tests/lua/task-controller-test.lua；Consume S/ExecutionSessions.lua现有API，不复制内核。

目标接口：Controller.request(npcId,jobId,kind,adapter)返回ticket或拒绝原因；dispatch(ticket,callback)、requestStop(ticket,reason)、step()、beginSave()、finishSave(success)、retire()。adapter提供requestStop(reason)、observeStop()和记录效果/义务的业务方法；ticket不向UI公开。

- [ ] 写失败用例：同NPC竞争、两NPC隔离、停止重入、迟到回调、UNKNOWN义务已记录后允许关闭身体会话；未记录义务不能关闭。
- [ ] 运行 `java --class-path 'D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/*' tests/java/KahluaLaborTest.java task-controller-test.lua`，确认新模块缺失导致失败。
- [ ] 实现接口；request只登记请求，不在旧停止调用栈内启动新业务。step确认旧停止及效果后再授权。自理/恢复不经公共分配器。
- [ ] 定义observeStop返回bodyStopped/effects/reason；不能用Lua队列为空、Driver.stop返回true或moveResult=STOPPED中的单一信号当完整证据。
- [ ] 同命令通过；复用execution-sessions-test.lua核对内核协议。检查只为控制器逻辑，不声称原生停稳。
- [ ] 只提交本任务变更；文件已有他人变更时分块提交或保留未提交，不整批提交。

## Task 2：Java身体授权及停止快照

Files: Modify J/ProbeRuntime.java、J/CarrierRuntime.java、J/ProbeNpc.java、现有Java暴露注册入口（先以rg定位stopCarrier/commandFor注册，记录实际文件）、L/Driver.lua；Add相关Java控制授权回归。

目标：新增按npcId/world/sessionGeneration绑定的Java许可，移动/停止需匹配；Driver只从Controller拿许可。Java退役/世界退出有专用系统清理入口，不借用普通业务权限。权限撤销前先处理正在调用的动作，不能因旧许可失效拒绝必要停止。

- [ ] 先固定当前源码/JAR哈希；沿ProbeRuntime→CarrierRuntime→ProbeNpc检查直接写身体及所有注册入口，未列全不开始改动。
- [ ] 写失败用例：无许可/过期/错误NPC拒绝move/stop；正常许可可请求；保存屏障拒绝新移动，允许旧拥有者必要停止。
- [ ] 实现授权校验及只读停止快照，至少覆盖当前世界、角色身份、原生动作状态、寻路/移动状态。字段与当前JAR可见API逐项核查，不从桩猜方法。
- [ ] 核查ProbeNpc.moveTo先调用stopProbe→StopAllActionQueue的副作用；移动不能成为绕过动作停止协议的后门。
- [ ] 构建、跑相关Java回归；记录必须由单人实机确认的原生动作停止/迟到效果。API无法提供可靠证据时保留STOPPING/核对，不以超时自动宣布成功。
- [ ] 提交本任务变更，保留原始检查输出。

## Task 3：现有业务全部接线

Files: Modify L/Production.lua、CraftProbe.lua、Work.lua、WorkAgent.lua、WorkTransfer.lua、Companion.lua、CompanionAgent.lua、Actions.lua、Haul.lua、NpcCommands.lua；查询其他调用点，禁止遗漏Java命令旁路。

- [ ] 写定向失败用例：制作→随从申请、搬运→制作申请、Debug动作与正式任务竞争、两NPC互不影响、迟到取消不清新队列。
- [ ] 各业务注册adapter，所有Driver移动/停止与TimedAction入队/清理使用获授上下文；删除业务间直接抢占，但保留原件/容量门禁。
- [ ] 暂停先禁止下一动作，按原生停止和物理后置条件归账；COMMITTING不因为取消而假定回滚。已制作只交付，未知提交不重做。
- [ ] 接管Production.tickPending及CraftProbe.tickPending的自动续工：改提交恢复申请，不在回调直接execute取身体。
- [ ] 运行任务1命令及相关生产/搬运/随从最小回归；检查测试断言原件和交付事实，不仅检查调用了Controller。
- [ ] 汇总搜索所有clear/add/cancelAll/command调用，逐一登记已授权或专用系统清理依据。提交本任务变更。

## Task 4：统一保存屏障与恢复

Files: Modify L/Persistence.lua、StockService.lua、Production.lua、CraftProbe.lua、Companion.lua及加载入口；保留现有Java检查点格式，本阶段不重写存档。

- [ ] 写失败用例：OnSave中随从与制作同时请求恢复、保存失败、StockService正常保存后恢复、世界切换后旧回调、动作停止未确认。
- [ ] Persistence先Controller.beginSave，再停止/核对、保存业务与检查点；禁止靠独立OnSave监听器执行顺序形成屏障。StockService停派统一纳入编排，明确成功/失败路径均如何退出保存态。
- [ ] 保存成功后Companion.restoreState和制作恢复只入候选，Controller.finishSave(true)在全部记录核对后开放；失败finishSave(false)保留阻塞，不启动任何恢复。
- [ ] 读档先旧业务记录与Claims恢复，再控制器及观察恢复；不能新建taskId或把旧携货单公开重领。测试当前老格式不被改写丢字段。
- [ ] 验证StockService.afterSave现无明显调用点的风险，补入统一成功路径；失败路径保持暂停并可诊断，不无限静默暂停。
- [ ] 运行上述定向用例、必要preflight和Java构建；提交本任务变更。

## Task 5：P1单人实机验收及交付

- [ ] 升版本，运行 `node ../.workbuddy/tools/pz.mjs preflight Contents/mods/EmberRoutesProbe/42`、`& ./tools/build-probe.ps1`、`node ../.workbuddy/tools/pz.mjs release-check .`，检查包内源码/版本一致；保留输出。
- [ ] 集中实机确认：一NPC制作中切跟随、搬运中停止、提交边界中断、两NPC分别切换、正常保存恢复、保存失败门禁与Debug冲突。记录NPC/task/session和实际原件位置，不反复要求无关历史用例。
- [ ] 原生停止或恢复无法核实时标“已实现待验/受阻”，不继续将自主领单标成可上线；不得用Mock通过替代。
- [ ] 更新唯一架构的实现状态与BACKLOG。本计划P1通过后，才执行共享任务目录/优先级认领计划；清洁/守卫模型检查可以是协议测试，但不是新工种已可用。

## 当前完成与未完成

本轮已吸收评审、核对Java移动/停止源码链并形成计划。任务1～5尚未实施；底层JAR停止语义、实机效果、性能均未验证。后续从任务1开始，执行前按项目规则再次读取技能/API证据及当前差异。
