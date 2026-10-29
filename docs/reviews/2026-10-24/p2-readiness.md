# P2 生活闭环推进条件核查

日期：2026-10-24。依据[唯一架构 v1.1](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)第3～7节及其[统一任务细化](../../superpowers/specs/2026-10-23-unified-task-dispatch-design.md)。本轮只核查与记录，未修改运行代码、未构建或运行游戏。

## 结论

可以沿既定架构细化并推进P2，无需更换HFSM、效用仲裁、统一控制器和小型BT的分层。现有实现尚不能直接开启生活行为：独立Job存储已具备基础，但业务索引、个人仲裁、生活动作效果核对及恢复接线仍是本阶段必做项。

P1约定单人流程已有用户验收记录；0.23.0公共下单、双人优先级、跟随恢复及正常保存重进仍未登记游戏集中验收通过。本轮宿主回归不能替代该记录，也不能据此认定公共认领与P2组合在实机可靠。后续按用户已批准的整组交付节奏进行集中验收，不逐内部切片发测试包。

## 本轮基线

- Git HEAD：`63fbf95efcdd57bbbf2caf826858f7282e6b57a5`；开始时`git status --short`为空，结束时出现并行UI、WorkAgent和相关测试改动，已保留，未纳入本轮核查结论或替其验证。
- 当前安装`projectzomboid.jar` SHA256：`E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`，与[既有调研基线](../2026-10-22/npc-behavior-baseline.json)记录一致。
- 通过HTTPS文本导出读取[唯一在线需求](https://docs.google.com/document/d/1aTOBrzZvh_iCDkv045HNAV13i7vNf7OHk6E_sE7TWNM/edit)，正文SHA256为`1E802DFE03A43437C77DC8EF5D04A2E38EC9AE9970A71D349B302B9EFE2EFB08`，与[10月23日核查](../2026-10-23/requirements-update.md)一致。只读导出保存在`build/research/requirements-2026-10-24.txt`；不修改在线或历史需求快照。
- 安装JAR的`IsoGameCharacter`/`IsoPlayer`字节码只读输出位于`build/research/p2-IsoGameCharacter-javap.txt`和`build/research/p2-IsoPlayer-javap.txt`。

## 代码条件与缺口

| 边界 | 当前证据 | P2必须落实 |
|---|---|---|
| 身体独占与停止 | `TaskRuntime`/`TaskController`已有替换、停止确认、过期票据和保存屏障；Runtime本身明确不做候选选择 | 个人候选复用同一Session，停止和效果落账完成后才启动自理；不能直接清队列后越权运行树 |
| 多Job存储与业务索引 | `JobStore.forNpc`支持多Job；`BusinessJobs.load`却拒绝任何非CRAFT/HAUL的provider，`flush`统一按旧劳动payload推导状态 | 先让生活Job与挂起劳动Job共存，按provider管理派生状态和恢复义务；不能只给公共目录加一个自理候选 |
| 需求观察与仲裁 | `WorkSelector`只比较普通工种0～4；`PublicWork.advance`在现有制作、Work忙碌、非HOLD时提前返回 | 个人需求观察不能藏在这些普通工作准入之后；跟随安全间隙和携料工作也要可评估，先个人紧迫级再普通工作评分，落实滞后/冷却和全局预算 |
| 自理后的恢复 | `Production.pause`仅对SAVE保存自动恢复候选；`PublicWork`搬运恢复仅识别SAVE/LOAD_RECOVERY | 明确自理中断来源及原Job引用，按稳定ID/有效代次/原件和效果核对恢复；用户暂停、取消和新指令必须撤销或覆盖旧恢复意图，不能把所有REPLACED一律自动续工 |
| 保存与读档 | `TaskPersistence.candidate`分支目前识别COMPANION、PRODUCTION和CRAFT_PROBE，没有生活恢复接线 | 同时捕获生活效果与劳动恢复义务，读档先恢复声明再构造树；未知消费隔离，不能仅存树节点下标或只恢复保存时当前身体任务 |
| 原件声明 | 已有LaborClaims唯一协调及制作/搬运托管 | 私人吃喝不抢公共Order，但真实食物、水和设施仍须核验/声明；禁止食用另一Job已托管的材料；失败只撤销本次未生效声明 |
| 小型BT | 未发现正式生活树实现 | 按唯一架构提供记忆Sequence/Fallback、Condition/Action和有限深度Subtree；清理中不作普通Failure，效果不明时不进入替代消费分支；不另建通用步骤运行器 |

上述属于既定P2接入工作，不是要求另选架构。业务provider分发、持久步骤名、阈值和预算可以在阶段计划细化，不建立第二份权威设计。

## 原版动作核查

安装目录`media/lua/shared/TimedActions`：

- `ISEatFoodAction`的`start`可能先消耗所需点火物；单人`stop`会调用`serverStop`并可能按进度消费食物，`complete`执行原生Eat。停止不是回滚，食物剩余和需求变化必须落账。
- `ISDrinkFluidAction.update`在单人推进时调用`updateEat`逐步消费；`complete`核对到目标比例。重建动作不能沿用已经消费前的请求量重放。
- `ISDrinkFromBottle`是另一个契约，在stop/complete消费，与流体动作不能共用未经适配的效果假设。当前诊断样本使用的是`ISDrinkFluidAction`。
- `ISRestAction`按ENDURANCE推进或切换坐姿，其源码不能证明FATIGUE已经恢复。疲劳睡眠须独立适配与验收。

原版`client/ISUI/ISWorldObjectContextMenu.lua`的睡眠流程还调用玩家索引、UI淡出、全体玩家睡眠判断、加速和保存。不能直接把玩家菜单回调套到NPC。当前JAR的`IsoPlayer.updateStats_Sleeping`确有原生耐力/疲劳处理，但无玩家槽位的ProbeNpc能否完整入睡、正常恢复疲劳、唤醒和保存续接仍未验证；应先做聚焦原型，不手写固定减疲劳冒充已复用原版睡眠。

[0.2.0原生动作实机记录](../2026-10-19/probe-0.2.0-runtime.md)已有吃喝及中断部分消费成功证据，可作为白名单适配起点；它不覆盖当前自动找食物、携料自理、生活BT或睡眠。

## 建议实施顺序及验收映射

1. 补生活provider、业务索引、恢复义务和保存分发，明确劳动Job与生活Job并存；同时核实NPC原生需求随游戏时间增长及睡眠恢复路径。
2. 接只读需求观察、个人候选和分级仲裁，再接最小BT。共用调度预算；危险/急救层保留最高级边界，P2不宣称已实现完整战斗或医疗。
3. 贯通工作取料→安全中断→寻找并真实消费食物/水→核对→恢复同一Job；跟随自理后回原上下文，不回据点抢工作。
4. 加入耐力休息及疲劳睡眠的各自动作适配，明确可达设施、占用、无床回退、唤醒和取消。完整住房质量、士气Buff及守卫换岗不因P2基础休息自动记为完成。
5. 成组验证双NPC竞争资源、部分消费中断、材料被玩家移动、用户暂停/取消覆盖、保存中自理与挂起工作共存、正常读档无重复消费/认领。未知效果保留可诊断等待，不重放。

## 实际验证与准确续接点

本轮使用当前安装Kahlua运行既有定向夹具：`public-work-test.lua`44项、`job-store-test.lua`22项、`task-runtime-test.lua`38项、`task-save-runtime-test.lua`61项，合计165项通过。命令为`java --class-path <游戏目录>/* tests/java/KahluaLaborTest.java <夹具名>`。原生身体、世界和保存效果使用替身，未新增P2运行测试。

下一步据唯一架构制定P2实施计划，先处理生活provider/多Job义务与恢复分发，再接观察、仲裁和BT；睡眠先验证原生边界。0.23.0公共流程实机、P2实机、磁盘故障、强退和性能均未由本轮验证，不变更为已通过。
