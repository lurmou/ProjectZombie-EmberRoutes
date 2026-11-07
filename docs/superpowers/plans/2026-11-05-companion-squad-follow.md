# 小队基础跟随首期实施计划

> 执行方式：按用户“可以，开始任务”在当前会话顺序推进，不另开聊天、不默认启用子代理。先完成设计收敛和可执行计划；引擎原型、生产接线及实机验收分别记录，不能把计划勾选视为实现证据。

**Goal:** 在现有唯一身体控制和成员命令链上，交付最多三人显式槽位、连续跟随、通道让路及停止/自理/返回/正常恢复闭环。

**Architecture:** Lua 保留 Membership 命令、任务仲裁、标量意图和自理交接；Java 负责已有授权之下的高频导航计算及原生移动。复用 ProbeNpc.doDeferredMovement 唯一位移出口，不复制参考项目独立 TaskRunner，不为最终一致新增通用事务或恢复平台。

**Tech Stack:** 当前安装 PZ 42 JAR、ZombieBuddy、Java 17 编译目标、Kahlua Lua、既有 ISUI 菜单和翻译体系。

**Spec:** [小队跟随设计 1.2](../specs/2026-11-05-companion-squad-follow-design.md)。

## 最终方案（2026-11-05 定稿）

### 功能对标目标（用户本轮确认）

ProjectRemnants 的**小队同伴系统**是最低功能对标范围：跟随、战斗、载具、指挥与自理，不扩成整个 NPCFW。首期三人是交付与验收范围，不是最终人数上限；后续分期不代表可以永久省略参考已有的小队能力。

后续逐项核对参考当前根 JAR 与 Lua 正式调用链，记录玩家入口、执行效果、取消/恢复及本项目对应实现。已找到小队搜刮、修整/装弹、Stance/ROE、槽位UI、背包与驾驶指令等入口；这些属于功能对照线索，接口存在不代表已经完成参考实机验证，更不代表本项目已经实现。

目标是玩家可观察能力至少对等，并争取在相同体验质量下提高规模与性能；目前没有双方同场景测量，不能声称已超过或保证具体人数。D1–D3 是实现能力的技术候选，不是以行数/人数阈值代替验收，也不要求为对标功能机械复制参考架构。

人数超过三人时重新验证角色更新、寻路提交、局部避让、动画与UI成本；不能把格点公式可延展等同于只改几个常量即可证明规模上限。保持单人、唯一身体控制和无旧契约兼容的既有边界。

### 分工

| 层 | 归属 | 内容 |
|---|---|---|
| 命令与权威 | Lua：`MembershipService` / `MembershipRuntime` / `MembershipMenu` | 成员命令、`followSlot` 持久、占用校验、任务仲裁 |
| 行为 | Java：`LeaderTrail` / `SquadTrail` / `CompanionNavigation` | 轨迹、槽位格点、列队、排队、三级让路、分段节拍 |
| 路由与通行 | 引擎 `PathFindBehavior2` | 寻路、开门、翻窗、翻越、楼梯、动画与根运动 |
| 导航请求提交 | `CompanionNavigation.submitSegment` 单点 | 物理根运动仍经 `ProbeNpc.doDeferredMovement`；换执行器须同时核对交接协议 |

### 数据契约

`npcMembership.byNpc[id].followSlot`（整数 0..2）：FOLLOW 提交写入、离开 FOLLOW 清除；同队长占用返回 `SLOT_TAKEN`；不升 `format`、不改 `ProbeCheckpoint` 封包、不迁移旧数据；恢复只从成员行读。

### 执行策略（均有源码依据）

- 段末续段：路径未结束不重定向（`pathToLocationF` 会取消在途搜索）；同层段终点跨度最多 2.5 格（不承诺原生绕行路径长度；跨层交引擎）。
- 轨迹：0.25 格采样、96 点、2.5 格跳变或换层断段；每队长一份、引用计数、上限 4。
- 编队：槽位格点 `slotBack/slotSide`，rank 0..2 与原布局一致，向上按“左右成对、每排后退 1.05”延展。
- 静止：队长静止 >400ms 改按几何落槽，不留在旧轨迹点。
- 让路：1.2s 无进展才探测；有队友在前 0.8 格判排队；否则侧移 → 后退 → 报告；三次失败终止。
- 失败唤醒：队长移动 ≥1.5 格、换层或新宏观命令。

### 分期与门槛

首期闭环 → 实机数据 → D1 执行器（400–600 行，解锁逐帧侧移与速度）→ D2 门纪律（150–250 行，须在 D1 后）→ D3 搜索与预算（400–700 行，人数 ≥8 才做）。G1–G3 触发条件见设计 §12.3。

### 本轮剩余步骤

1. 已完成 Lua 接线：`MembershipService`（`followSlot` 校验/写入/清除/唯一性）、`MembershipMenu`（槽位子菜单）、`Companion.lua`/`CompanionAgent.lua`（去掉两处硬编码 0，改读成员行）、CN/EN 文案。
2. 构建与 11 套定向 Kahlua 已通过；最终代码打包后进入实机。用户已确认新建独立测试档，不使用正式存档。
3. 实机：直线、急转、反向、门口堵人、楼梯、三人互让、WAIT、自理、RETURN、保存重进。
4. 已接会话内诊断：寻路提交次数、恢复/排队/受阻阶段时长占活跃跟随时长比例、排队及搜索等待秒数（NPC 时间累计）。实机另记录门重复开合及落后不收敛次数，不能仅凭计数判定全部 G1–G3。

## 全局约束

- 可维护、已确认需求的扩展和性能优先；额外安全工程靠后。
- 身体执行权即时唯一；物理效果不盲目重放；派生状态允许最终一致。无法核对时停止业务或重载最后存档。
- 单人新功能，不增加联机成本；既有联机适配不动。无旧格式迁移、兼容入口和双轨生产链。
- 多 NPC 按稳定 ID 隔离；常驻最多三名小队同伴，不自动按装备重排槽位。
- 不传送、不直接写角色坐标纠偏、不关闭碰撞；保留现有责任及正常保存恢复。
- 不修改在线唯一需求；车辆、完整战斗/HUD、建筑搜刮和卸货不混入基础跟随交付。
- 保留开始时全部未提交用户改动；不未经要求提交、推送或发布工坊。

## 重点边界

1. 旧会话停止后新会话已授权，旧导航状态/回调仍到达：不得驱动新身体。
2. 玩家过门后反向、停在门口或轨迹不足：不得切墙、顶人或无限重寻路。
3. 两名随从同处楼梯口，或换层时轨迹断开：不能跨层插值或永久互等。
4. 跟随中吃喝/包扎以及保存发生在交接中：只恢复当前有效宏观命令，不重复消费。
5. 旧托管工具与普通战利品同时在背包：不能全包解锁/自动卸货，也不能为普通战利品强制建入仓义务。

## 已完成：基线与设计收敛

- [x] 读取 HANDOFF、BACKLOG、唯一 NPC 架构、开发规则及本轮源文件。
- [x] 读取在线需求；核对 ProjectRemnants 根 JAR 的轨迹、避让与 FollowLeaf 关键分支及当前游戏 JAR 哈希。
- [x] 确认创建 Companion → Runtime → Controller、停止确认再释放、自理 Resume、实际到达再交接 RETURN 的现有接缝。
- [x] 修订原稿为 1.1，划分即时正确性和最终一致，取消错误源码结论与无证据验收承诺。
- [ ] 首期整体交付：Task A/B 代码及 Lua 显式槽位已接，构建与定向检查通过；全部实机项仍待验收。

## Task A：持续移动和停止的当前引擎原型

**Files:**
- Modify: `java/src/main/java/emberroutes/probe/ProbeNpc.java`，在 moveTo/stopProbe/doDeferredMovement 现有移动职责内接入。
- Modify: `java/src/main/java/emberroutes/probe/ProbeRuntime.java`，受控 bridge 出口及包可见 authority 校验。
- Create: `java/src/main/java/emberroutes/probe/CompanionNavigation.java`，只有当前跟随会话的导航状态，不持有资源权威。
- Test: `tests/java/emberroutes/probe/ProbeBridgeSurfaceTest.java`、`java/src/test/java/emberroutes/probe/FollowProgressTest.java`，桥元数据和节拍/进展边界；原生动作仍须实机。

**接口提案（先按当前 JAR 验证，不能把名字当作已有能力）：**
- `followWithControl(IsoPlayer body, String key, IsoPlayer leader, double slotRank) -> String`：唯一正式启动入口，验证 Key、队长和整数槽位 0..2。首次返回 FOLLOW_STARTED；无效控制拒绝且不修改路径。
- 同会话跟随在已存在的角色更新中运行；每次执行检查当前授权，不能只在 start 验一次。Lua 不逐 tick 重建输入表或重复启动。
- 停止仍用 `stopWithControl`；stopProbe 注销跟随并清原生移动，不新增独立释放 API。

- [x] 查当前 `PathFindBehavior2` 的目标更新、直达移动、碰撞/交互及取消分支；未采用含载具攻击分支的pathToCharacter。已记录证据。
- [ ] 先验证持续更新不调用完整 StopAllActionQueue，且没有第二个位移提交者。禁止直接把原 moveTo 改成高频调用。
- [x] 在受控出口内实现原型；普通工作 moveTo 与停止顺序保持语义；保留工作区已存在的原生根运动修正。
- [ ] 验证控制拒绝、过期 Key、原生动作正在运行、保存冻结、队长死亡/换世界和完整停止。无授权时不更新任何位置或速度。
- [x] Java与普通/Debug Lua编译通过；桥白名单95项，FollowProgress边界加入构建。原型不等于实机通过。
- [ ] 原型不支持可靠的持续移动或停止时登记具体分支，限制该能力；不复制参考控制器兜底。

## Task B：共享轨迹、显式槽位与局部通行

**Files:**
- Create: `java/src/main/java/emberroutes/probe/LeaderTrail.java`，固定容量环形数组、路程采样和断段。
- Modify: `CompanionNavigation.java`，编队目标、局部让路、楼梯进展和有界寻路。
- Modify: `MembershipService.lua`、`MembershipMenu.lua`、`Companion.lua`、`CompanionAgent.lua`，均在既有 client/EmberRoutesProbe 目录。
- Test: `java/src/test/java/emberroutes/probe/LeaderTrailTest.java`；扩展现有 membership-command/runtime 和 task-companion-runtime 定向测试。

**已定契约（设计 1.2 §11 决定，本计划据此执行）：**
- `LeaderTrail.record(float x, float y, int floor)`；`sample(float backDistance) -> boolean`，结果存实例复用标量字段，不按次分配结果对象。容量 96 点 × 0.25 格，断段阈值 2.5 格/换层/队长切换。
- 轨迹每队长一份，由 `SquadTrail` 引用计数管理（上限 4 条目），最后一个跟随者释放即移除；不做全局队伍扫描。
- 槽位由玩家命令显式选择 0..2，存 `npcMembership.byNpc[id].followSlot`；`request` 对 FOLLOW 要求整型 0..2，同队长占用返回 `SLOT_TAKEN`；离开 FOLLOW 即清除。
- 不升 `npcMembership.format`，不改 `ProbeCheckpoint` 封包，不迁移旧数据；当前 FOLLOW 行必须有合法槽位；缺失或冲突明确拒绝并保留原数据，不默认补 0。
- 节拍改为段末续段：路径未结束时**不重定向**（每次 `pathToLocationF` 会取消在途搜索），同层段终点跨度最多 2.5 格（不承诺原生绕行路径长度；跨层交引擎）；HOLD/BLOCKED 才清速度。

- [ ] 轨迹容量按覆盖距离核算（96×0.25=24 格，需 4.5 格）并登记折返、急转、历史不足、跳变、换层断段判定；不新建测试脚本，由既有定向套件与实机验证。
- [x] 实现每队一次采样、跟随者独立游标；最后成员退出清共享引用，不全世界扫队伍（0.29.41）。
- [x] 实现开放地形侧后方槽位、窄路临时列队及出通道复位；每个目标/下一段检查真实通行，必要时走原生寻路及交互（0.29.41，效果未实机）。
- [x] 实现固定侧短时保持、侧移与后退候选、玩家通过后归队；两侧不通时不超时硬顶。楼梯按时间与位置进展处理，不直接照搬 90/24 帧（0.29.41，效果未实机）。
- [x] 完成槽位命令、持久结构、恢复校验、CN/EN 文案和全部生产读取方；无旧 FOLLOW fallback。活动槽位与 pending 预约均校验，取消只释放预约。
- [ ] 按五类边界（急转/窄门/楼梯/换层/队内争道）做定向走查，并登记未实机项。

## Task C：生产切换与 WAIT/RETURN/自理/正常恢复

**Files:**
- Modify: `TaskController.lua`、`Driver.lua`，增加 `body.follow(actor, slotRank)`，依旧通过 Controller.dispatch 调用受控 bridge。
- Modify: `Companion.lua`、`CompanionAgent.lua`，FOLLOW 启动导航；业务 tick 读取状态，不重新逐帧投影/重寻路。
- Remove: `FollowPolicy.lua` 的被替代实现及全部生产引用；对应测试转换为新契约用例，不留下转发壳。
- Inspect/modify only where needed: `TaskResume.lua`、`MembershipRuntime.lua`、`MembershipReturn.lua` 及实际保存读取方。
- Test: `task-companion-runtime-test.lua`、`companion-handoff-test.lua` 及现有相关保存/恢复测试。

**行为：**
- FOLLOW 仅在获得 body 后启动；旧 body.current() 失效则旧 worker 不再派发。WAIT 经现有停止确认释放；RETURN 实际到达据点后转 SETTLEMENT。
- 跟随暂停给自理，沿既有 Resume 恢复有效意图，不另建小队自理引擎。普通战利品无新增入仓责任，旧托管不被清除。
- 保存只存命令/槽位等标量；轨迹、路径、回调、Key、避让状态全部重建。无新补偿日志或后台恢复平台。

- [x] 接入body.follow、正式bridge和新导航；删除FollowPolicy、无Runtime执行fallback、独立Companion调度及兼容字段元表。当前调用明确传rank=0，槽位尚待Task B。
- [ ] 验证两名 NPC 一人 WAIT/自理/RETURN 不影响另一人；被新命令覆盖的旧恢复意图不再启动。
- [ ] 验证身体已停后才释放与重新授权；未知资产效果不重放，错误可诊断。
- [ ] 验证正常保存重进的槽位与上下文，未做磁盘/游戏测试分别登记。
- [ ] 检查无额外账本、无新通用锁框架、无联机扩张和兼容分支。

## Task D：集中验证与交付

- [ ] 按风险运行本轮定向 Java/Kahlua 测试；修改 Java 须真实编译。运行 Lua 语法/结构与翻译检查，新增文档跑 doclink。
- [ ] 正式实机前集中运行一次完整回归和 preflight，按开始时脏树基线区分既有失败与新增失败；不逐切片重跑全历史。
- [ ] 实机检查直线、急转、反向、门口堵人、楼梯、三人互让、WAIT、自理、RETURN、正常保存重进；禁止用宿主通过代替。
- [ ] 对 1/3 人、静止/移动/受阻分别记录导航耗时、分配、寻路次数和可观察启动延迟。比较保留旧节拍的基线；未测量不宣称性能提升或同帧响应。
- [ ] 原位更新 BACKLOG 与对应证据；不关闭未经实机验证的边界，不自动发布或提交。

## 本轮检查与后续状态

2026-11-05：Task A生产原型和Task C必要接线已落代码，Task A实机及Task B仍OPEN。11套定向7过/4失败，四项在隔离对照也失败；Java/编译/桥/翻译通过。游戏、磁盘恢复和性能未验证。详见[实施证据](../../reviews/2026-11-05/companion-follow.md)，不同时启动车辆、搜刮或战斗。

## 增量执行队列（2026-11-06）

沿用户“每一个功能都要设计好、一直继续”在当前会话实施；常规选择不重复确认，不自动提交/发布，不代用户实机。每项先核对参考完整链路、记录设计与取舍，再写实现和对应证据；开放能力不按阶段表自动算完成。

1. **受阻后退方向修正**：[设计 §13](../specs/2026-11-05-companion-squad-follow-design.md#13-按功能增量补全受阻后退2026-11-06)。只改 tryBack 自身负向 0.9 格，无新接口/格式。先源码检查，真实编译和现有定向测试，再记录未实机项；游戏运行时用隔离快照构建。
2. **追赶速度与潜行同步**：先核对当前原生 AI 输入和速度约束，明确身体授权、停止清理、楼梯/翻越/让路降速；先证明是否可保留现有根运动，不把 D1 的所有候选能力合并成必选前提。16格终止与加载/实体恢复边界另做闭环，本片只交付范围内速度与潜行同步。
3. **主动避让与楼梯通行**：分别设计和交付，不能用普通路径能力冒充队伍主动让路/楼梯恢复；D1/D2 仍按原独占交接约束。
4. **战斗→载具→战术指挥→小队搜刮与自理差额**：每项以玩家可观察闭环定义最小可玩范围，细分交付不省略参考已有能力；具体顺序按前置依赖核对。人数/性能单独采样，暂无超过参考的结论。

第一项实施文件 `CompanionNavigation.java`；验证复用 `tools/build-probe.ps1`，构建输出和实机状态分别记录，不增加同义运行器/测试替身。后续项尚未因本队列成为已完成事实。

### 第二项实施：追赶与潜行姿态

依据[设计 §14](../specs/2026-11-05-companion-squad-follow-design.md#14-按功能增量补全追赶与潜行姿态2026-11-06)，沿当前会话原生输入实现，不切换 D1 执行器。

- 新增 `FollowLocomotion.java` 会话速度策略及对应现有 Java 测试目录内的定向测试：`running(distanceSquared, leaderFast, sneaking, precision, dirX, dirY, now)` 返回跑步意图，保存8/6滞回和650ms急转窗口；`pause()` 只清方向/时窗。先运行策略失败用例，再接正式实现。
- `CompanionNavigation` 保留每帧授权门禁，把现有导航体内聚为 advance，末端10Hz派生姿态；只正常、同层、实际有路径可移动的段可跑步。距离门禁暂不改：实体正常读档也有16格门禁，需另做恢复闭环。
- `ProbeNpc` 提供包内姿态写入及有界前方楼梯检测，不扩公开桥；closeFollow 对称清姿态，hold/stop 的既有停止链不变。
- `build-probe.ps1` 接策略测试；使用隔离快照构建，核对包内版本/JAR/源码。同步记录游戏运行中未热替换、实机未验收，用户无需逐片进游戏。

### 增量验证状态（2026-11-06）

后退和范围内跑步/潜行姿态代码已接，0.29.49隔离包及定向检查通过，见[本轮证据](../../reviews/2026-11-05/companion-follow.md#2026-11-06后退与原生跟随姿态隔离候选-02949)。未覆盖运行中的游戏JAR，未实机，不关闭首期。下一项先设计16格活动/实体恢复的共同边界，然后分别推进主动避让与楼梯；不以姿态更新冒充D1或远距离恢复完成。

### 第三项实施：已加载区域内追赶与原位恢复

依[设计§15](../specs/2026-11-05-companion-squad-follow-design.md#15-已加载区域内的远距离跟随与原位恢复2026-11-06)。本项是距离接受范围的明确契约变化；原格式、守卫的其他条件与原件身份不变。

- [x] 在`tests/lua/persistence-restore-queue-test.lua`直接驱动真实Persistence队列，先见一次性队列对延期用例失败；覆盖一tick一人/2秒/最多3次/成功及硬失败不重复/world与reset取消/空闲零native调用。
- [x] `CompanionNavigation`只保留跨层>16格拒绝；`CarrierRuntime.restoreCheckpoint`去掉玩家距离拒绝，原格检查仍先于构造及load。生产调用与桥签名不变，无兼容别名。
- [x] `Persistence.lua`原启动队列增加attempts/deferred/nextAt/world，三轮有界，仅重试保存格不可用；不引入其他调度器或持久字段。
- [x] 定向队列、runtime-idle、跟随/交接/成员正常恢复回归，Java真实构建；隔离包核对。记录原生/磁盘/性能未测。

第三项代码及隔离0.29.51验证完成，原生/磁盘/性能未验；构建后同期UI文件变化，隔离包未回写当前目录。下一项为主动避让玩家，与楼梯专项分别设计，不把本片当全跟随验收。
