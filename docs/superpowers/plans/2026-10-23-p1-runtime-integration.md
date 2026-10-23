# P1统一执行权运行接入计划

日期：2026-10-23。状态：任务1～4代码接线完成；0.22.13已启用完整路径，任务5实机未完成。当前入口见[启用与集中验收](../../testing/p1-runtime-acceptance.md)，保存实现见[统一保存与恢复](../../reviews/2026-10-23/p1-unified-save.md)。

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

0.22.11进度：TaskRuntime、票据body、Companion、正式Production、Work搬运及旧CraftProbe格式1/2/草稿、Actions/Haul/NpcCommands/Persistence样本入口已接；自动续工非抢占。任务3代码接线和静态调用核对完成，原生交接与诊断竞争实机未验；保存/恢复直接检查点路径归任务4，不能先开启门闩。

Files: Modify L/Production.lua、CraftProbe.lua、Work.lua、WorkAgent.lua、WorkTransfer.lua、Companion.lua、CompanionAgent.lua、Actions.lua、Haul.lua、NpcCommands.lua；查询其他调用点，禁止遗漏Java命令旁路。

- [ ] 写定向失败用例：制作→随从申请、搬运→制作申请、Debug动作与正式任务竞争、两NPC互不影响、迟到取消不清新队列。
- [x] 各业务注册adapter，受控Driver移动/停止与TimedAction入队/清理使用获授上下文；业务间直接抢占保留在gate关闭的兼容路径，原件/容量门禁不放宽。
- [x] 暂停先禁止下一动作，按停止观察和物理后置条件归账；COMMITTING不因为取消而假定回滚。已制作只交付，未知提交不重做。宿主通过，原生实机归任务5。
- [x] 接管Production.tickPending及CraftProbe.tickPending的自动续工：改提交恢复申请，不在回调直接execute取身体。0.22.9/0.22.10已接；统一保存屏障仍属于任务4。
- [ ] 运行任务1命令及相关生产/搬运/随从最小回归；检查测试断言原件和交付事实，不仅检查调用了Controller。
- [x] 汇总搜索clear/add/cancelAll/command及body/Java控制调用，登记已授权、旧兼容、系统清理及任务4保存范围；清单见0.22.11证据。保留当前混合未提交改动，不整批提交其他人的文件。

## Task 4：统一保存屏障与恢复

0.22.12代码已接：新增TaskPersistence及只读ProbeSaveReceipt，详见[保存证据](../../reviews/2026-10-23/p1-unified-save.md)。核对本次原版bin两表后才允许正常tick恢复，没有OnPostSave单信号开闸。下列项目的原生实机验收归任务5；本轮混合改动保留未提交，不整批提交。

Files: Modify L/Persistence.lua、StockService.lua、Production.lua、CraftProbe.lua、Companion.lua及加载入口；保留现有Java检查点格式，本阶段不重写存档。

- [x] 写失败用例：OnSave中随从与制作同时请求恢复、保存失败、StockService正常保存后恢复、世界切换后旧回调、动作停止未确认。
- [x] Persistence区分提前准备与原生同步保存：提前请求可跨正常tick停派/核对；OnSave只同步捕获可确认事实，未停稳/COMMITTING记UNKNOWN及恢复阻断，不等待step、不假定可取消引擎保存。StockService停派统一纳入编排，不依赖监听器注册顺序。
- [x] Companion.restoreState和制作恢复只入候选；OnPostSave不是磁盘成功凭据。世界仍活跃且业务/声明已核对时，才在后续正常tick调用Controller.finishSave(true)开放；失败或未知finishSave(false)保留阻塞，退出无tick时不恢复。
- [x] 读档先旧业务记录与Claims恢复，再控制器及观察恢复；不能新建taskId或把旧携货单公开重领。测试当前老格式不被改写丢字段。
- [x] 验证StockService.afterSave现无明显调用点的风险，补入统一成功路径；失败路径保持暂停并可诊断，不无限静默暂停。
- [x] 纳入诊断的受控清理与diagnosticRecovery标量事实；不能在冻结后用普通body.current清理或假定记录已落盘。原件未知不准生成替代样本或移除NPC，安全移动仍可独立获授。
- [x] 运行上述定向用例、必要preflight和Java构建；本轮混合改动保留未提交，不整批提交。原生验收仍属任务5。

## Task 5：P1单人实机验收及交付

2026-10-23更新：用户已确认约定三组测试全部成功，P1单人流程验收通过，见[验收登记](../../testing/p1-runtime-acceptance.md)。下方0.22.13启用说明为历史；当前运行0.22.16。磁盘故障/强退和性能未包含在本次通过结论。

0.22.13已按用户授权启用controlledExecution，补齐启动能力核验、后台服务加载及原生清理/正常执行区分；新增启动30项通过。用户此前明确由其在游戏中测试，合并为[三组验收](../../testing/p1-runtime-acceptance.md)，保留未验证项，不用宿主结果替代。

- [x] 升版本，运行 `node ../.workbuddy/tools/pz.mjs preflight Contents/mods/EmberRoutesProbe/42`、`& ./tools/build-probe.ps1`、`node ../.workbuddy/tools/pz.mjs release-check .`，检查包内源码/版本一致；保留输出。0.22.13已通过，包内12关键文件一致。
- [x] 按约定三组集中实机确认交接/原件、双NPC/诊断及保存/正常重进，用户确认全部成功；按用户反馈登记，未冒充磁盘故障和全部提交边界取证。
- [x] 根据用户反馈登记P1单人通过；公共认领仍未实现，真正磁盘故障、强退事务及性能继续列为未验证，不用Mock通过替代。
- [x] 更新唯一架构的实现状态与BACKLOG，明确P1实机待验收。本计划P1通过后，才执行共享任务目录/优先级认领计划；清洁/守卫模型检查可以是协议测试，但不是新工种已可用。

## 当前完成与未完成

2026-10-23最新：任务5按约定单人测试由用户验收通过；下一阶段共享任务接入尚未实施。以下是启用时的历史状态，不覆盖最新验收登记。

任务1～4模块及业务/诊断/保存运行接线和控制调用核对已完成；完整路径默认启用，任务5实机仍待完成。任务3/4的集成场景需任务5原生验证，不能把代码完成写成游戏验收。下一步按三组操作反馈核查日志与原件；不重复创建已完成的运行服务、保存编排或业务/诊断适配，不提前记为自主认领已实现。界面视觉最后处理，当前复用既有UI基础。
