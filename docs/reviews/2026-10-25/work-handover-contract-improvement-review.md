# 公共工作交接契约六项改进建议评审

> 日期：2026-10-25｜状态：静态评审（未运行测试与游戏）｜评审对象：本轮转交的六项改进建议——工作机会交接、按用途可用性、资源结果语义、长任务开工准备、工种Provider契约、设施关系分离。

## 基线

- 代码：工作区0.26.0未提交混合改动。核对 `PublicWork.lua`（578行）、`LeisureService.lua`、`LeisureRegistry.lua`、`MembershipService.lua`、`shared/MembershipPolicy.lua`、`shared/NeedsPolicy.lua`；git显示 Membership*/Leisure*/SelfCare*/Repose* 等均为未跟踪新文件。
- 文档：唯一架构v1.2、[统一任务协议](../../superpowers/specs/2026-10-23-unified-task-dispatch-design.md)、[成员归属设计1.0](../../superpowers/specs/2026-10-25-npc-settlement-membership-design.md)、BACKLOG（含“新发现嫌疑”行）。
- 在线需求：本轮两次读取失败（Google Docs txt导出307重定向至签名googleusercontent URL后返回HTTP 400）。按已归档[v3.3快照](online-requirements-v3.3-export.txt)（SHA `6cef0b26...`）做方向核对，不宣称已同步最新在线正文。

## 总体结论

**六项方向全部与已确认架构一致，均予采纳；但没有一项是全新设计。** 1、4已在BACKLOG登记（1为“公共调度P0邻域，待用户确认排位”，4为P2行“当前未实现”）；2、3、6是既有契约的收口与延续；5实质是推进统一任务协议§5已定Provider契约的实施。建议按“推进已登记项＋偿还两处具体债务”消化，不另立一轮重构计划，也不因本评审改动用户已确认的P0/P1/P2排位。

六项中价值最高的新增事实：①代码自认“无身体预约”（PublicWork.lua:483注释）与“认领/启动失败无退避”（:513、:519-522无cool()）组合成结构性循环，印证BACKLOG嫌疑行；②消费者以`string.find`嗅探原因子串（:453、:543）代替类型化结果，是建议3所指“统一结果语义”的具体债务。

## 逐项评审

### 1 工作机会：从“发现候选”到“具备交接条件”——采纳，定性为协议§8认领事务的落位

事实核对：

- 收束点：`PublicWork.lua:498-501`——候选被选中且NPC处于闲暇探测（careProbeWork）时调用 `Probe.leisureWorkReady(npcId)` 后直接return，认领发生在后续轮次；`LeisureService.lua:45-54` workReady撤offer、withdraw社交并停当前闲暇Job（reason `LEISURE_WORK_READY`，带WORK_READY诊断日志）。
- 无身体预约是代码自认：`PublicWork.lua:483-485`注释 "One bounded grace window, without a body reservation"。
- 退避覆盖不对称：预检失败有退避——扫描期inspect失败 `cool()`（:470）、预检plan失败 `cool()`（:545），键为orderId×npcId、8s+抖动（:396）、`Wake.changed` 条件变化可提前唤醒（:398-401）、容量上限512（:390-396）；但**认领成功后启动失败无退避**——craft路径 `Production.execute` 非QUEUED时工单回WAITING仅signal（:513），haul路径 `Work.assign` 失败仅release候选（:519-522），retryAt不覆盖haul键。建议所述“归还书→启动失败→回闲暇→再打断”循环在代码上成立，与BACKLOG嫌疑行记载一致；实际频率未实机确认（诊断日志已加）。

评审意见与修正：

1. 建议的“取得可失效的短期预约→身体交接→最终启动”即统一任务协议§8认领事务的中间态，实施应对齐该协议（复验→占槽→建Job→申请会话→申请资源→授权；准备失败只撤销无效果分配），不另发明预约协议。
2. 修正实施顺序：把workReady触发点从“候选被选中”挪到“认领事务提交成功之后”（或引入轻量body-intent声明），即**先锁定可失效预约、再打断闲暇**——这是本项的核心改动，其余按协议既有租约边界执行。
3. 退避键建议 `npcId×orderId×失败原因类` 即可，不必细到“失败条件版本”；保留Wake条件变化提前唤醒，避免对家不响应时饿死。haul候选需要同等的失败退避。
4. 排位维持BACKLOG原文：“待用户确认排位后实施”，不因本评审自动插到搬运P0之前。与P0“状态机边界核查”共享停止/交接机制，宜同批设计。

### 2 NPC可用性：从“忙不忙”到“能否承担这类任务”——采纳，限定为纯组合查询

事实核对：宏观按用途资格已存在——`MembershipPolicy.lua:3` purposes=WORK/LEISURE/STUDY/SELF_CARE/RECOVERY/RETURN，:17 SELF_CARE/RECOVERY恒允许（对应“跟随中仍可喝水自救”）；`PublicWork.eligible`（:368-383）已调用 `M.check(npcId,'WORK',...)`。但身体/责任门禁仍各业务自拼：eligible自组bindId＋Work.busy＋careBlocksWork＋crafts未释放＋动作队列空＋健康≥95七项，decide内另有hasCargo（:414、:536）。建议所称缺口（组合层）属实。

评审意见：组合查询必须是**纯函数**——读Work.record/hasCargo、BusinessJobs、TaskRuntime、Membership.check等既有权威，返回allowed＋映射回各权威的reason；不新增可写状态、不缓存派生“NPC总状态”（建议自己已提出此红线，正确）。组合层位于MembershipService.check之上，不并入成员服务（成员设计§2.1明确check不替代身体/原件前置）。收益主张以维护性为主、性能另测，与BACKLOG纪律一致。

### 3 资源判断：从“没找到”到“为什么暂时不能使用”——采纳，属架构§6既定语义的收口

事实核对：区分已散落存在——扫描未完成/未知：UNLOADED/OBSERV/SCAN_LIMIT置scan.unknown（:453、:543），complete判定不成立时不许诺闲暇/研习（:490-491）；库存未知：`observed.state~='READY'`→INVENTORY_UNKNOWN（:277）；床：0.25.1已按“未知/未加载不当无床”；预算未完：Leisure各seek返回done=false续投预算（LeisureService.lua:140、:153、:171）；失败目标短冷却：ReposeSites blocked 5s（:180）。唤醒机制PlanningWake贯穿调度路径。

具体债务：消费者用`string.find(reason,'UNLOADED',1,true)`等子串嗅探（PublicWork.lua:453、:543）——非类型化结果，新增原因枚举即静默失配。

评审意见：以**类型化结果（枚举＋观察版本＋唤醒句柄）**替换字符串嗅探，先收口公共调度热路径（PublicWork/PrecheckQueue/Wake），床/书/设施沿用各自实现逐步对齐；不重写索引（建议已自我限定，正确）。

### 4 长任务开工准备——认可，无新增内容

事实核对：`NeedsPolicy.lua`确有enter/leave阈值（DRINK 0.20/0.05、EAT 0.25/0.10、SLEEP 0.70/0.25、REST 0.25/0.80）＋active时+0.15连续性加分。BACKLOG P2行已登记本任务及验收标准（先从属设计、小范围接入、同负载对比中断次数/重复路程/有效产出/CPU；不引入GOAP/HTN；当前未实现）。

评审意见：按BACKLOG执行即可；“先喝水再走远路”的例子与登记验收标准一致，本轮无补充。

### 5 工种扩展：Provider契约——采纳，重新定性为协议§5的实施推进

事实核对：`LeisureRegistry.lua`确为内部注册表（注释明确"NOT a public modding API"，SOCIAL/READING/SMOKE/SIT四def）；公共工作确有制作/搬运分支（PublicWork.lua:509-521 craft路径/haul路径分叉；:373 crafts独占检查）。统一任务协议§5已定义完整Provider协议（discover/evaluate/prepare/createBehavior/requestStop/observeStop/recover/settle），§14固定“以不同模型验证接口”的顺序。

评审意见：建议的六段契约是协议§5的子集，应作为**实施推进**立项而非新设计；“先制作、搬运验证”即当前仅有的两工种，与§14一致；不承诺第三方API与LeisureRegistry注释、BACKLOG A1“明确不对外承诺第三方API”一致。抽象过早的风险已由§14验证顺序覆盖。

### 6 设施关系：位置/可用/预约/责任四分离——采纳，属既有方向延续＋生命周期缺口补齐

事实核对：床三策略＋唯一预约＋整件身份＋政策版本已接（0.24.3/0.25.1，架构§5.3）；短期预约与持续义务分离是架构§2术语既定；NPC死亡/解除归属的“未结清不删行”已在工作区实现（MembershipService.retire :167-175；advance的OBLIGATION_PENDING门槛 :135，未实机）；据点解散完整流转（账本/标签/留守人员）成员设计§1.1自认未实现；炉具监管P4未接。v3.3快照中医务病床位专属（§3.x）、哨卫疲劳动态交接条款与本项方向一致。

评审意见：真正缺口＝解散生命周期、未来设施类型（灶台/岗位/活动点）的拆除与改归属处理、义务与预约的清理矩阵。建议把“拆除/改归属/死亡/解散 × 预约/义务”整理成一张清理矩阵放入对应从属设计，避免逐案补丁；“预约可过期、携货/借书/监管不能靠超时消失”与架构红线一致。

## 排序评估

建议的顺序（1→2/3→4/5）与用户2026-10-24确认的P0（搬运停止诊断、状态机边界核查）→P1（性能、收口）→P2（长任务）存在排位交叉。本评审不替用户改排位，仅建议：项目1与P0状态机边界核查共享停止/交接机制，宜同批设计实施；项目2/3的string.find债务与组合查询可并入P1性能细分时的读取路径收口；4、5按登记顺序；6的清理矩阵随对应阶段从属设计提交。**前提**：成员驻扎实施状态须先由负责会话在BACKLOG原位澄清（见下）。

## 与建议开头的两点核对

- “驻扎重构没让位置判断失去作用”——正确，成员设计§4明确几何继续约束实际活动安全，归属只裁决身份。
- “部分文档仍写运行未实施，不能认定整体完成”——正确且当前成立：BACKLOG与成员设计1.0仍写“运行未实施/待计划审阅”，但工作区已有MembershipService/Policy/Runtime/Lifecycle/Return/Menu/Text全套实现（未跟踪）、4个membership测试文件、14个消费模块（PublicWork.eligible:377-381、LeisureService、SelfCare、LogisticsService、StudyService等已调用）。“已接线”不等于按实施计划四项任务完成；本轮未运行任何测试，验收状态未知，BACKLOG应由负责会话更新而非本评审代改。

## 未验证边界

静态评审；未运行Kahlua/宿主/游戏验证；在线需求读取失败，方向核对基于v3.3归档快照；工作区0.26.0未提交且并行会话在改，行号以本轮文件为准（PublicWork.lua共578行）。六项建议本身的性能收益均未测量，不因本评审宣称。
