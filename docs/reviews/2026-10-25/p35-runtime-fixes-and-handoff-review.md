# P3.5 实机问题诊断与交接核验（2026-10-25）

> 性质：用户实机观察报告的代码级诊断与修复；另一会话交接文档（P3.5→4.5 活动系统补充任务）的事实核验。
> 基线：工作区 version.txt=0.26.0（未提交混合改动）；projectzomboid.jar SHA256 `E1A69EB7...F058A33`（与既有证据一致）。本轮未运行游戏；用户观察会话的 console.txt 已被后续短会话覆盖，无当次运行日志。

## 1. 用户报告一：锻炼约一秒即停止

### 已确认的缺陷（已修复）

`LeisureFitness.lua` 构造动作时设置 `stopOnRun=true, stopOnAim=true`。引擎事实（javap 反汇编）：

- `IsoGameCharacter.StopAllActionQueueRunning()/StopAllActionQueueAiming()` 读取 `BaseAction.stopOnRun/stopOnAim`，角色进入跑步/瞄准即停止队首动作并清空动作栈。
- AI 驱动的 IsoPlayer 载体转向会被引擎视作移动输入；参考实现（ProjectRemnants `NPCFW_LeisureFitnessAction`，根JAR `5229EB5A...`）为此将三个 stop 标志全部置 false，并注明“原版动作因 AI 转向自取消”。
- 本模块自身 update() 已带业务化守卫（瞄准/攀爬/持物/耐力等，经停止协议与责任处理），Java 侧 walk/run/aim 快速取消是冗余且有害的。

修复：`stopOnWalk/stopOnRun/stopOnAim` 全部置 false（LeisureFitness.lua:43-46），真实危险条件仍由业务 update() 守卫。

### 剩余候选机制（本次同时加了判别日志，待实机区分）

| 假设 | 机制 | 日志特征（复验时看 console） |
|---|---|---|
| A. 外部清除 | Java StopAllActionQueue* 或其他持有者清队列 | `FITNESS_STOP cause=EXTERNAL_STOP`，elapsed≈1000ms |
| B. 动画不循环/状态被退出 | FitnessState 动画单次播放后退出，动作存活到 5 游戏分钟时限 | `cause=TIME_CAP`，reps=0或1，elapsed≈游戏时间换算值 |
| C. 工单预检循环 | PublicWork 预检选中"认不了"的候选→`workReady` 收束闲暇→认领失败→回到闲暇→再收束（见§3） | 停止前先出现 `WORK_READY npc=... job=...`，`cause=HALT` |
| D. 原生 FitnessFinished 事件 | 动画事件参数 `FitnessFinished=TRUE` 提前到达 | `cause=ANIM_FINISHED`，reps 值为到达前完成数 |

新增日志（Log.write，"LEISURE" 类别）：`FITNESS_START`（npc/exercise）与 `FITNESS_STOP`（npc/cause/reps/elapsedMs）。cause 枚举：`UPDATE_SAMPLE_NIL/UPDATE_UNSAFE/UPDATE_ENDURANCE/UPDATE_HUNGER/UPDATE_THIRST/UPDATE_FATIGUE/UPDATE_HANDS/UPDATE_AIM/UPDATE_CLIMB/ANIM_FINISHED/NO_CURRENT_EXE/TIME_CAP/WAIT_TIMEOUT/HALT/COMPLETE/EXTERNAL_STOP`。

排除项（已核查不必修）：NeedsObserver.sample 无 TTL、每次现查；`Fitness.exerciseRepeat`/`IsoPlayer.setFitnessSpeed` 对 NPC 安全（反汇编确认无玩家专属解引用）；`LuaTimedActionNew.update` 正常做时间簿记，hasStalled 不会误伤；ProbeMovement 静止时 tick 返回 IDLE，不会迟到触发 `stopProbe()`；Java 不消费 Lua `isValidStart`。

## 2. 用户报告二：NPC 不找沙发/椅子坐下，一直站着

根因（非回归，属设计内未交付）：

- 闲暇候选管线（LeisureService.candidate）只有 SOCIAL/READING/SMOKE/FITNESS/STROLL/OBSERVE 六种活动，全部站立执行；READING 走 StudyActions 亦无坐姿。
- 座位使用只存在于 P2 REST/SLEEP 自理路径（ReposeSites 接受床/座位能力 + SelfCareFurniture.move + beginRepose），由疲劳阈值触发；未达疲劳的空闲 NPC 没有任何坐下途径。
- 设计 1.1 §2.2"使用安全、可达、有容量的现有休闲点"与 §5"坐家具…分别适配起身/唤醒"隐含闲坐于座位，但 0.26.0 交付片未实现；单份实机验收清单也无坐姿场景。交接审查指出的"坐姿已有部分适配 vs 架构坐卧动画未适配"出入，以本轮结论为准：**闲暇坐姿不存在，仅有锻炼 waitToStart 的起身让位处理**。

处置：登记为 P3.5 交付缺口（见 BACKLOG）。实现需小设计：座位型 OBSERVE/READING（ReposeSites 预约复用 + 进入坐姿的原生适配 + 停止起身核对），与 A1 注册表化同一交付组最省；不并入本轮。

## 3. 交接文档核验（A1～A6 及第三方审查修正）

逐条核对当前源码，结论：**全部实质声明属实**，可作后续依据。细节出入仅行号漂移（文件其后被编辑）：standable 实际在 LeisureService.lua:67（非:58）、晚间社交概率在:93（非:84）。已核实项：candidate 硬编码优先级链、LeisurePolicy 全部阈值与冷却（hunger≥0.25/thirst≥0.20/fatigue≥0.70/endurance≤0.25；FITNESS fatigue<0.38/endurance>0.65/pain<0.18/双手空闲/无酸痛；冷却 12/2.5/0.5/0.25 游戏小时；重复权重×0.15；18-21点 0.7/其余 0.25）、STROLL±2格、设施观察距离²≤100、standable 占用上限16、配对距离²≤900 与 checked≥4、35s 到位/3s offer TTL/手势 6s/3s、权重 1/0.6/0.7/2、`CLOSING` 相位全库不存在（SocialActions 以 ends 到时收束）、READING/STUDY 双管线契约如交接所述。

**新确认的风险（交接未覆盖）**：PublicWork.lua:497-500 的预检路径在 `Selector.choose` 选中候选后立即触发 `workReady` 收束闲暇并 return，认领失败无 (npc,工单) 级退避；若存在"可选中但认不了"的工单（如材料缺失的 WAITING 单），将形成"收束→认领失败→回闲暇→再收束"循环，可同时解释"一直站着"与闲暇短命。本轮已加 `WORK_READY` 日志；根治（认领失败退避或预检过材料门）属公共调度 P0 邻域，登记待排，不在本轮擅改。

## 4. 本轮修改与验证

| 文件 | 修改 |
|---|---|
| client/EmberRoutesProbe/LeisureFitness.lua | stop 三标志置 false；FITNESS_START/FITNESS_STOP 诊断日志与 cause 归因 |
| client/EmberRoutesProbe/LeisureService.lua | workReady 收束时输出 WORK_READY 日志（仅实际触发收束路径） |
| tests/lua/p35-fitness-test.lua | 新增：三标志断言、START/UPDATE_ENDURANCE/ANIM_FINISHED 日志断言、FitnessFinished 事件场景 |
| tests/lua/p35-discovery-test.lua | 补 DebugLog mock |

验证：安装 Kahlua 8 文件（7 个 P3.5 + public-work）全部 PASS（2026-10-25 本轮重跑，原生 host mocked）；`pz.mjs preflight` 全部通过（含结构与 LuaLS）。CN/EN UI 宿主未重跑——本轮无 UI/翻译改动。**修复未经实机验证**：日志与标志改动的实际效果需下次进游戏复验；若仍复现，按 §1 表格的日志特征定位剩余机制。

## 5. 下一步

1. 用户带新构建进游戏复验锻炼：观察是否持续 5 游戏分钟、真实经验/酸痛；收集 FITNESS_START/STOP 与 WORK_READY 日志区分 A～D。
2. 若 WORK_READY 高频出现：确认工单预检循环，按 P0 邻域排修复（认领失败退避）。
3. A1/A2 重构按交接顺序先行（金样本 fixture 先行固化 Policy.choose 与 candidate 行为）；坐姿缺口与 A1 同组设计与交付。
4. 在线需求已于本轮前变为 v3.3（SHA `6cef0b...`，详见当日一致性审计的续接说明），A3 设计动笔前按交接 A6 要求重取核对。

## 6. 复验后续（同日晚间，用户复测后第二轮）

### 6.1 锻炼一秒即停：真因确认并修复

用户带诊断日志复测，console.txt 捕获两例：`FITNESS_STOP cause=NO_CURRENT_EXE reps=0 elapsedMs=4672（squats）/1041（situp）`——第一处对应 §1 表格之外的第五种机制：**第一个 ActiveAnimLooped 到达时 `getCurrentExe()` 为 nil，且重设也不生效，动作在第一次循环回调自杀**。动画事件本身正常到达（排除假设 B 的"不循环"变体）。

根因（javap 反汇编 `BodyDamage.Fitness`）：`setCurrentExercise(name)` 从 `exercises` HashMap 取定义对象赋给 `currentExe`；该 map 仅由 `Fitness.init()` 填充（读取全局 `FitnessExercises.exercisesType`），而原版只有 `ISFitnessAction:serverStart()` 会调 init。NPC 载体的 Fitness 从未 init → map 为空 → `setCurrentExercise('squats')` 查不到定义、**静默把 currentExe 设为 null**。构造器在授权后早已调用过 setCurrentExercise，同样无效。

修复：LeisureFitness 构造动作前补调 `fitness:init()`（init 幂等：map 非空即返回，无玩家专属逻辑，反汇编确认）。测试断言 init 必须被调用（p35-fitness-test `inits>=1`）。前一轮的 stop 三标志修复仍保留（独立缺陷，防 AI 转向误杀）。

### 6.2 新增：SIT 坐姿闲暇活动

用户批准补上坐姿缺口（§2）。实现复用 P2 已验证原语，不新增原生交互：

- 候选（LeisureService）：SMOKE 之后、加权池之前，经 `ReposeSites.new(actor,npc,id,'REST',blocked)` 共享设施扫描（预算 min(8,scan)，迭代器与失败站点 5s 退避存 offer.seat），`Sites.prepare` 产出 proof、`Sites.keys(proof,'REST')` 资源键随 LEISURE 载荷认领——与 P2 REST 占用检查同储互通。需 `EmberRoutesProbeJava.reposeAtWithControl` 存在，否则回退站立活动。找到座位即直接选中（用户期望闲坐可见；节流靠 0.5/0.25 游戏小时冷却）。
- 接线：SelfCare 认领处把 `candidate.site/claims` 写入个人 Job；执行树 = `SelfCareFurniture.move(c,'REST')`（新增可选 kind 参数，REST 分支原语义不变）→ 新叶 `LeisureSit`：resolve 重验（凭 jobId 认领）→ 先 persist 围栏再 `body.repose('REST',true,object,quality)` 进原生就座 → 每拍核验 isResting → 10 游戏分钟到时 `repose('REST',false)` 离座并核验；中断/停机走同一 leave 协议，未明确退出置 UNKNOWN（停稳掩码含 isResting/bed，TaskController 等其清零才放权，与 P2 相同）。读档取消纯闲暇，存档捕获经 stopProbe→endRepose 清原生标志。
- 资格：LeisurePolicy 通用门禁（不另设阈值）；LeisureRecord activities 增加 SIT；人员监控新增 CN"坐着休息"/EN"Sitting for a while"。

### 6.3 硬编码（交接 A2）：平衡层已配置化

上一轮未动，本轮随 SIT 一并做了 A2 的平衡层：新增 shared/`LeisureConfig.lua`（资格门禁、FITNESS/STROLL 阈值与退出阈值、冷却 12/2.5/0.5/0.25、重复权重×0.15、晚间窗口与概率 0.7/0.25、池权重、锻炼 5/闲坐 10/观察 10 游戏分钟），LeisurePolicy/LeisureService/LeisureActions/LeisureFitness/LeisureSit 全部改读配置，数值与原先逐项相同（既有测试即金样本）。协议/预算类常量（35s 到位、3s TTL、占用 16、距离²900/100、checked≥4、手势 6s/3s、扫描步长 8）按交接审查建议**保留在调用点**，待 A1 注册表化时集中命名并标注"非平衡参数"。A1（候选管线表驱动/注册表）未做，仍按交接顺序待金样本先行。

### 6.4 本轮修改与验证

| 文件 | 修改 |
|---|---|
| LeisureFitness.lua | 构造前 fitness:init()（真因修复）；时长/退出阈值改读 LeisureConfig |
| LeisureService.lua | SIT 座位候选分支（offer.seat 迭代器+退避）；valid 拒绝无 proof 的 SIT；社交概率/权重配置化 |
| LeisureSit.lua（新增） | 就座执行叶：进入/时长/离座/中断协议 |
| LeisureActions.lua | SIT 路由到 move+sit；观察时长配置化 |
| SelfCareFurniture.lua | move 增加可选 seatKind 参数 |
| SelfCare.lua | LEISURE 认领透传 site/claims |
| shared/LeisurePolicy.lua | 改读 LeisureConfig；SIT 资格 |
| shared/LeisureConfig.lua（新增） | 平衡数值集中表 |
| shared/LeisureRecord.lua | activities 增加 SIT |
| CN/EN IG_UI.json | Monitor_body_SIT 各一条 |
| tests/lua/p35-sit-test.lua（新增）、p35-fitness-test.lua | SIT 候选/叶子/中断/记录用例；init 断言 |
| tests/java/TranslatorFormatTest.java | 计数围栏 58→70（并行 UI 会话新增 12 个带格式键后已过期，本轮 SIT 键无格式符与其无关；逐键校验逻辑不变） |

验证（2026-10-25 第二轮）：安装 Kahlua 9 文件（8 个 P3.5 含新增 sit + public-work）全部 PASS；preflight 全过；KahluaUiTextTest（中文排版宿主）PASS；TranslatorFormatTest 70 条 PASS。**未实机**：锻炼 init 修复、SIT 实际就座动画/占用竞争/保存重进待下次进游戏；若仍有异常，FITNESS 日志与 SIT 失败原因（c.reason）继续定位。

## 7. A1 注册表化（同日第三轮）

先建金样本再重构：新增 `p35-candidate-golden-test.lua` 对重构前实现固化八组行为——链序（配对社交＞消遣阅读＞吸烟＞座位＞站立池）、(nil,false,reason)/(nil,true) 返回协议、预算切片（阅读 1 次＋座位 min(8,scan)）、offer 状态生命周期（同 offer 跨调用续迭代器、换 entry 重建）、paths 预算被邀约消耗且 paths=0 时短路在骰子之前。重构后金样本逐字节一致。

重构内容：

- 新增 client/`LeisureRegistry.lua`：内部注册表（明确非公开 modding API，def 形状{id,budget,seek}，id 唯一、budget 限 paths/scan、返回协议注释在案），4.5 落地后再设计公开 registerActivity。
- `LeisureService.candidate` 硬编码优先级链改为注册表迭代：SOCIAL/READING/SMOKE/SIT 四个 def 在模块装载时 `Registry.define`；每 def 私有状态从 offer.smoke/offset/seat/siteOffset 迁入 `offer.state[def.id]`；SITE_OBSERVE 池段状态同样入桶。采样窗口内按 `Leisure.<活动>` 分桶计时（RuntimeMetrics），满足 BACKLOG P1"Leisure 成本混入 SelfCare 分项须单独计数"；设施观察段计时暂未单列（仍混在池内，属剩余项）。
- `LeisureActions` if 链改为 builders 表（id→执行叶构造），与候选注册表成对；加活动=一处 def＋一处 builder。
- `standable` 导出为 `Service.standable`（A3 聚会站位复用）。
- READING/STUDY 双管线契约未动（decorateLeisure、probeable、workReady 收束原样）；统一任务协议、SELF_CARE 个人 Job、全局预算边界不变。

验证：金样本＋既有 10 个 Kahlua 文件全部 PASS（重构前后一致）；preflight 通过。未实机（纯结构重构，行为由金样本锁定）。剩余项：协议/预算常量尚未集中命名（现在仍散在调用点，下一步 A1 收尾或与 A3 设计合并做）；设施观察段计时单列；对外 API 仍不承诺。

## 8. 第四轮：用户报告"全部 NPC 零闲暇、站立不动"（11:51 会话）

console.txt 核查：整会话无任何 Lua 报错（模块加载正常）、无 FITNESS/WORK_READY 日志——闲暇候选从未产生。位置证据：本会话地点为 1912,14384（昨日据点在 2155,6087，完全不同区域），仅恢复 1 个旧 NPC（HOLD）、新刷 1 个 NPC（z=1 楼上）。闲暇第一道门是 PublicWork 资格判定"NPC 恰在一个已登记据点内"→ 才会调用 idleLeisure 发 offer；新地点若无登记据点/矩形未罩住站位/新 NPC 非 HOLD，offer 根本不会发出，NPC 永远站立且无任何日志。**未确认根因，环境前置条件为最大嫌疑**；A1 重构嫌疑低（金样本+10 文件全绿，且昨日同管线在旧据点产出过候选）。

已加三段低噪诊断链（转换门控+10 秒节流，重启游戏生效）：`LEISURE OFFER npc entry`（PublicWork 发 offer）、`LEISURE IDLE npc reason=NO_OFFER/NO_ENTRY/NOT_ELIGIBLE/NO_CANDIDATE`（LeisureService 门禁）、`LEISURE ACTIVE npc activity`（候选选中）。下次会话看缺哪段即定位断点。Kahlua 10 文件+preflight 复跑全过。
