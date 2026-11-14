# 移动状态类型化试点

范围：用户已批准的等价重构；原生移动、身体授权、持久格式和 Lua 返回值保持原状。当前 ProbeMovement 枚举是成熟参考，不引入通用状态机。

比较：继续字符串状态无法约束赋值；把载体状态直接合入 Outcome 会混淆观察与执行结果；采用分离的 MoveStatus、PathStatus，通过穷尽 switch 连接执行结果。原生诊断大小写显式保留。

生命周期核对：ProbeNpc.java:643 moveTo 启动；:931 movement.tick，终态按原分支停止再记录结果；:771 stopProbe、freeze 与 :829 suspendCarrier 负责异常停止；ProbeRuntime.java:282 acquireBodyControl、:293 releaseBodyControl 维持授权与身体停止检查，不修改释放判据。CarrierRuntime.java:84 motionResult 经 ProbeNpc.java:553 lastMoveResult 保持字符串边界。路径诊断只用于日志，不作为持久或权威状态。

实施与验证：
- [x] 核对全部字段读写和安装 JAR 的 BehaviorResult 三个值。
- [x] 替换两个字符串字段及所有生产赋值，边界保持字符串。
- [x] 在既有 ProbeLogicTest 增加桥接词汇与原生日志大小写检查；复用停止、超时、暂停恢复测试。
- [x] 运行构建及相关检查，审阅 diff，登记实际结果。

验证：设置 GAME_ROOT 为当前安装目录后 build-probe.ps1 BUILD_OK（0.29.59）；102 项逻辑断言、115 项桥接方法名、移动/跟随/身体授权及构建固定检查通过。首次构建因未设置 GAME_ROOT 找不到 stdlib.lua，在环境修正后重跑通过。保持现有空格缩进，使用 git -c core.whitespace=blank-at-eol,blank-at-eof,space-before-tab diff --check 检查通过；仓库默认检查将现有风格的多层空格缩进报告为 indent-with-non-tab。

不新增兼容入口；不修改跟随状态、停止顺序、退避、参数或已发现的其他逻辑问题。实机与性能本轮未验证，不声称性能收益。

## 第二步：移动执行职责收敛（用户批准，完成整组后集中测试）

目标：把移动流程及其状态一起移出 ProbeNpc，减少阅读床姿代码时必须理解的导航细节；不是只把字段包装成另一个对象。

方案比较：只搬字段仍需跨文件追踪整个流程；通用控制器/Host 接口引入不必要的抽象；采用每身体拥有一个 NpcLocomotion，直接组合现有 ProbeMovement、CompanionNavigation、LocomotionSteering。成熟参考为本项目上述已接入组件及已确认原生位移设计；不新增引擎能力。

边界：NpcLocomotion 持有路径、跟随、起点、诊断、退避、进度节拍、家具接近证据和区块卸载的移动恢复目标；负责普通/家具/床/尸体接近、原生路径推进与终态处理。ProbeNpc 保留引擎覆写与 super 调用、床姿/家具姿态、全身停止协调和载体存活门禁。组件没有线程、事件订阅、任务授予或资产权威；继续由原来的 update/doDeferredMovement 驱动。

停止顺序：stopProbe 先通知移动组件释放门口和跟随，再按原顺序结束动作/姿态，最后停止移动并清掉根运动。完成端仍调用 stopProbe 或跟随分段停止；freeze、死亡、卸载和退休仍走原协调入口。卸载只搬迁恢复目标的存放位置，不修正当前实现与注释之间的差异。

调用方：同步更新 CarrierRuntime、ProbeRuntime、CompanionNavigation；删除 ProbeNpc 上被替代的移动方法和状态，不保留兼容转发。组件仅包内可见；对外桥面、校验顺序、返回值和持久格式保持原状。

- [x] 迁移移动字段和完整流程，保留原生 super 边界。
- [x] 切换所有生产调用方并删除被替代入口。
- [x] 人工核对启动/正常收束/异常停止与原代码语义、成员访问及生命周期。
- [x] 整组完成后运行一次构建及相关既有回归；失败按证据修正。
- [x] 更新 BACKLOG 与结果；实机、磁盘恢复、性能没有运行则明确未验证。

第二步结果：ProbeNpc 从本步开始时的 1187 行收敛到 718 行；新 NpcLocomotion 527 行。整组实现后集中运行一次 build-probe.ps1，设置 GAME_ROOT，BUILD_OK（0.29.59）。Java 编译、115 项桥接方法名、102 项逻辑断言，以及脚本固定的移动/跟随/身体授权/门口互斥/寻路/保存数据接缝等检查通过，无失败；原生引擎未启动。未新增复制实现的永久测试，也未改动旧测试预期。

一次性结构比对核对了 22 个迁移方法体、迁出的移动 tick、展开组件后的全身停止顺序；在限定的接收者替换、访问方法和跟随构造参数变更后保持一致。这是静态重定位证据，不证明原生效果。全身停止仍先 NpcLocomotion.beginStop（释放门口、清理跟随），再 ProbeNpc 的动作/姿态退出，最后 NpcLocomotion.stop（取消路径、清输入、清根运动）。ProbeNpc.consumePathRootMotion 的原生 super 与 finally 恢复仍保留。

当前源码入口：NpcLocomotion.java:142 普通移动创建，:210/:225/:246 尸体/家具/床接近，:469 移动推进和正常收束，:439/:448 卸载目标捕获与恢复；ProbeNpc.java:535 全身停止，:559 freeze，:572 卸载暂停，:637 引擎位移入口，:669 根运动消费。ProbeRuntime 的授权校验与释放判据未改。实机行走、转弯、家具接近、拖尸、退出动画、卸载恢复、磁盘故障与性能均未验证；不宣称完整 Java 治理已完成或已有性能提升。

## 第三步：床姿与家具退出职责收敛（用户批准，整组完成后测试）

范围：把姿态的原生适配及暂态状态一起迁入每身体一个 NpcPosture；保留 BedPoseMotion 的纯插值与 FurnitureExitState 的退出证据模型。只迁移正式调用，不新增兼容入口，不改变睡眠效果、定位、原生动画、碰撞恢复和停稳判据。

依据：本步前 ProbeNpc.java:358 prepareFurniturePose 校验家具部件并建立 furnitureExit 与姿态足迹；:493 settleFurnitureExit 在原生姿态退出和位置校验后 finish 并清除足迹；:535 stopProbe 的 request → 动作清理 → endRepose → locomotion.stop 次序，:559 freeze 与 :572 suspendCarrier 共同使用这个入口。保存沿 TaskController.beginSave → 停止/停稳证据 → ProbeRuntime.releaseBodyControl，不把消失的姿态引用当作资产结清。以上行号是本步前快照。

取舍：仅迁字段不能缩短理解链；把床姿和家具退出拆成两个控制器会使共享足迹、锚点、退出观察跨模块互调。采用单一 NpcPosture 管理进入/推进/正常退出/异常退出，ProbeNpc 只保留原生覆写/super、载体生命周期、stopMask 聚合和全身停止协调。组件无事件订阅、线程、任务授予、资源声明或保存权威；不改 Lua 业务责任。

参考核对：指定只读 ProjectRemnants 的 NPCFW_SleepActions.lua、NPCFW_BedPoseResolver.lua，以及当前根 NPCFW.jar（SHA256 5229EB5A6871514DE274FEB91E8DB353FDBDE8FB42FD9741493D40CDE85BA19E）中 SafehouseSleepSystem/AnimationController 的字节码用于核对锚点/进入/退出分工。正式迁移依据仍为本项目当前已接入代码，不照搬参考控制器。当前游戏 JAR SHA256 E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33；位置与方向更新方法的当前访问签名已核对。本步不新增 PZ API。

- [x] 迁移姿态字段、进入/推进/退出流程，原生位移互斥条件移入组件并保持短路顺序。
- [x] 更新全部 ProbeRuntime 调用方，删除被替代的 ProbeNpc 入口；保持公开桥签名、拒绝条件及异常围栏。
- [x] 对迁移方法、停止次序、update 推进和原生位移门禁做结构比对与人工核对。
- [x] 全部实现后集中构建，复用床姿插值/中断/退出及身体授权等现有检查；不为等价抽离复制业务测试。
- [x] 记录实际通过/失败及未验证边界，更新领域导航和 BACKLOG。

第三步结果：ProbeNpc 从本步前 718 行收敛为 248 行，新 NpcPosture 为 504 行。26 个原姿态方法（包含 beginRepose 两个正式重载）迁移；结构比对保留字符串字面量，核对接收者替换后的方法体，以及展开组件后的 stopProbe、update、stopMask 和 doDeferredMovement 门禁/短路/finally 顺序，通过。ProbeRuntime 的全部姿态调用已切换，无旧转发；BedPoseMotion、FurnitureExitState 和 Lua 生产代码未修改。

全部实现后运行一次 build-probe.ps1（GAME_ROOT 指向固定安装目录），BUILD_OK 0.29.59。115 项桥接方法名、102 项逻辑断言（含既有床姿锚点/中断插值/家具退出证据检查）、身体授权、移动/跟随及脚本固定回归通过；Java 编译、440 份 Lua 普通/Debug 编译、2186 键国际化检查通过。限定空白检查通过。未启动引擎，实机入睡/起立/家具碰撞/中断/保存加载、真实磁盘故障及性能未验证。

当前生命周期入口：NpcPosture.java:334 prepareFurniturePose 建立姿态占用，:469 settleFurnitureExit 核验后清理；:95 endRepose 发起正常或中断退出；ProbeNpc.java:83 stopProbe 保留移动前置清理 → 姿态退出请求 → 动作停止 → 姿态停止 → 移动停止次序，:102 freeze、:115 suspendCarrier 仍走该入口。身体授权释放和原件责任没有迁入姿态组件。现行实现位置见 kernel/selfcare 领域导航；后续可评估 Java/Lua 桥接边界，未在本步改契约。

## 第四步：身体桥接内部类型与协议检查（用户批准）

问题：ProbeRuntime.java:380/:424 的休息种类以及 :408 的家具阶段以字符串一路进入内部适配；ProbeNpc.stopMask 和 NpcPosture 的姿态豁免分别硬写 2048 等协议位。现有 ProbeBridgeSurfaceTest 只核对 115 个公开静态方法名，不检查参数和返回类型。前几步记录中称其为“签名检查”不准确，本步明确纠正，不把历史方法名检查算作类型证据。

范围与取舍：继续原样无法让编译器约束内部阶段；建立通用授权执行器会混淆移动/停止/保存在冻结期间的不同权限和守卫顺序。本步只新增无状态、无引擎依赖的 BodyBridgeContract：集中定义 REST/SLEEP、FLOOR/PREPARE/STAND_TARGET/ALIGN_BED/LIE 和 14 个既有停稳位。ProbeRuntime 继续是正式 Lua 出入口，在原有授权围栏内把输入映射为内部枚举；不改变公开方法、Lua 字符串/数字、位值、拒绝值或持久格式，不引入通用结果封装和新授权入口。

语义要求：大小写精确匹配，不 trim/别名/兼容转换；未知 kind 在内部以未识别值保留原 guard 的执行次序并拒绝，不能提前跳过原有原生检查。enter=false 仍忽略 kind 并执行原 endRepose，不因类型化收紧退出路径。家具 object==null 仅允许 FLOOR 的原前置条件保留；枚举分发穷尽，未知 phase 返回原 false。stopMask 条件及 OR 短路顺序原样保留，-1 仍为不可观察、0 仍仅表示原生身体停稳，不能证明业务效果已知。

生命周期依据：ProbeRuntime.java:282 acquireBodyControl → :327 起各授权操作及 controlCalls 的 finally → :288 bodyStopMask → :293 releaseBodyControl。正常、取消、保存和冻结期间的 stopping 参数及原件责任沿用现有链路，不移动 authority/controlCalls 或生命周期状态。生产结构仅替换字段/参数类型和常量，不删除或放宽守卫。

- [x] 定义内部命令类型与停稳信号，替换正式内部消费者，桥接保持原参数/返回类型。
- [x] 给现有检查补上身体控制公开方法的参数/返回类型；为协议精确解析、未知输入与位值增加最小独立契约检查。
- [x] 人工和结构核对守卫顺序、退出分支及 stopMask 数值表达。
- [x] 整组实现后集中构建和相关回归，更新真实验证范围。

第四步结果：新增 BodyBridgeContract，仅包含精确匹配的内部枚举、14 个停稳位和 0/-1 哨兵；NpcPosture 内部不再接收休息种类字符串，家具命令由穷尽枚举 switch 分发，叶方法收为私有。ProbeRuntime 仍接受原字符串，转换发生在现有 try/finally 授权围栏内；退出分支不解析 kind。stopMask 逐项命名，表达式和短路顺序保持原状；未修改 Lua、BodyAuthority 或 controlCalls 的权威归属。

验证：整组实现后集中构建。首次静态门禁把新注释中的否定句“compatibility aliases”识别为新增兼容标记，改写注释后通过，未修改门禁。随后 build-probe.ps1 BUILD_OK 0.29.59：115 个公开方法名 + 19 个身体入口完整参数/返回类型检查、143 项逻辑断言（新增 41 项协议词汇/拒绝输入/位值契约检查）、现有身体授权/移动/跟随/保存接缝等固定检查通过；440 份 Lua 普通/Debug 编译和 2186 键国际化检查通过。结构核对确认 facade 除声明过的枚举/常量转换外无变化，停稳表达式还原位值后与本步前一致。限定空白检查通过。没有运行实机、真实保存故障或性能测试。

范围边界：19 个身体入口有完整签名检查，其余 96 个公开方法仍只有名称检查；未宣称全桥面已类型化。历史记录中 115 项的称呼已纠正为“方法名”。本组没有引入通用授权执行器、统一结果对象、新守卫或兼容入口；状态类型化的收益为编译期约束与协议集中维护，不宣称性能提升。
