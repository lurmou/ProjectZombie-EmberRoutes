# P3.5 闲暇重构：0.28.0 开发证据

> 日期：2026-10-25｜状态：实现与门禁完成；实机动画、活动节奏、保存重进与性能未验证。
> 设计：[P3.5设计1.2](../../superpowers/specs/2026-10-24-p3.5-leisure-social-fitness-design.md)｜[实施计划](../../superpowers/plans/2026-10-25-p35-leisure-refactor.md)｜上位：[NPC架构](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)｜资格来源：[驻扎设计1.0](../../superpowers/specs/2026-10-25-npc-settlement-membership-design.md)。

## 1. 基线

version.txt/mod.info/Lua Build=0.28.0。安装JAR基线不变：projectzomboid.jar SHA256 `E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`、ZombieBuddy.jar `EB79B9876332010733A8E0D7CE4FE0377846059A9E28859029E2A0FB449F6CF2`。本轮Java产物与包哈希以 build/probe-build.json 为准（jar `456F11A231147909146DE48AFEA9BBE5059BCD99D001A046D0081F09B9682B21`、zip `A4C603B4F86FBDA6E84EA73BED0C811607C04DC0291F740E5FAE824E097EDB66`，最终构建 `2026-10-25T06:12:36.7953748Z`）。本轮成功重取在线v3.3相关正文并核对既有用户决定，未写在线需求，未向其他聊天发消息。

## 2. 本轮实现（按计划执行组）

### 2.1 记录准入与独立发现

- 修复SIT记录拒绝：SelfCareRecord.valid 此前仅REST/SLEEP可携带site，SIT候选携带家具证明写入任务时即被拒——日志里的ACTIVE只代表候选选中，不代表任务成立，与"选中SIT、画面无动作"现象吻合。现 `LEISURE`+`activity=='SIT'` 允许携带经ReposeRecord校验的site（shared/EmberRoutesProbe/SelfCareRecord.lua:74-76），并新增真实Record校验的完整启动链回归。
- PublicWork只发布短期只读工作观察（READY/IDLE/OBSERVING），READY须有可执行候选；SelfCare不再等待offer。无新鲜观察时仅允许无原件托管、无设施预约、无社交配对、无移动的短时原地观察并持续评估工作；确认无可执行工作后才进入完整候选比较。不把观察未知当作没有工作。
- 闲暇活动记忆容量按七活动事实修正（LeisureRecord.memory 经 SelfCareRecord.valid:21 强制校验）。

### 2.2 有限候选池与退避

- LeisureService收集有限候选，慢速图书/座位发现不阻塞已知低成本候选；Policy按距离/收益/最近活动在同一池内比较，冷却按活动区分；成功普通活动采用重复降权而非统一禁用，失败按对象与期限退避。
- 工作启动失败按NPC×候选退避并加workReady防抖：资源在实际认领时变化后，同一NPC/候选进入退避，不再每轮收束闲暇（定向测试覆盖）。
- 旧金样本的固定链序预期按设计1.2有意替换；版本/预算断言保留。

### 2.3 姿态

- 新增 LeisurePosture 为同一身体Session内的暂态适配器：先核对家具原件/预约并持久化启动围栏，再经body.repose进入REST标志，复用安装版ISRestAction的方向、对象、事件契约；`isSittingOnFurniture` 与 `SitOnFurnitureStarted` 均成立才开始有效就座计时，8现实秒看门狗失败请求统一停止。退出（起身）请求保留控制权，直至真实姿态清除后释放声明，不以请求发出当作已起身。原版契约以安装JAR javap核对（build/logs/p35-native-seat-javap.txt、p35-native-character-javap.txt）。

### 2.4 社交与投影

- 修复驻扎改造后的参数不匹配：SocialCoordinator.eligible 按据点对象（entry.id）比对（client/EmberRoutesProbe/SocialCoordinator.lua:14-15），闲暇调用处此前传据点ID会使邀约资格必然失败。
- 社交只接受当前可用者；选择其他活动时撤销广告/闲置配对。人员投影显示发现/等待/启动失败原因。
- 新增文案CN/EN成对配置（IG_UI.json），UI宿主按实际翻译运行。

## 3. 验证（全部为开发宿主与静态检查，非实机）

命令入口沿用计划第5步：Kahlua经 `java --class-path 安装目录/* tests/java/KahluaLaborTest.java`、`node ../.workbuddy/tools/pz.mjs preflight Contents/mods/EmberRoutesProbe`、`tools/build-probe.ps1`、doclink 经 `pz.mjs gate md`。

- Kahlua：23份宿主文件集中运行，另含10组关联检查，全PASS、0 FAIL（build/logs/p35-refactor-kahlua.txt，13:47）。本轮新增 p35-record-admission / p35-posture / p35-service-social 三份，更新既有 p35-discovery / p35-execution / p35-social / p35-sit / p35-candidate-golden / public-work 等；覆盖SIT完整记录准入、慢发现不阻塞、坐下/起身异步握手、认领冲突退避与旧链序金样本替换。
- 集成宿主：repose执行、全据点选床、统一保存等关联夹具全PASS（build/logs/p35-refactor-integration.txt，13:43）。
- CN/EN UI宿主：实际翻译与多分辨率标签检查全PASS（build/logs/p35-refactor-ui-CN.txt 13:43、p35-refactor-ui-EN.txt 13:45）。
- Java构建：`[EmberRoutes v0.28.0] BUILD_OK`，产物 build/packages/EmberRoutesProbe-0.28.0.zip（build/logs/p35-refactor-build-final.txt；初次构建日志保留用于追溯）。
- preflight（Lua结构/翻译/索引新鲜度/luals/fresh）：全部通过（build/logs/p35-refactor-preflight.txt，13:51）。
- doclink：pz gate md 通过，0断链（2026-10-25 13:52复验）。

## 4. 边界与未验证

- 实机动画、活动节奏、磁盘保存重进与性能未验证，不宣称玩法通过；站姿阅读不伪称坐姿阅读。
- 未扩展多人聚会、坐姿阅读组合与宏观离线；缺料WAITING工单的workReady循环属公共调度P0邻域，本轮只加防抖与退避，不记根治。
- 观察时长未承诺固定秒数；停止/恢复仍走既有停止握手、原件责任与UNKNOWN协议。

## 5. 收尾复核

最终包初次核对发现4份Lua落后于源码（LeisureRegistry、LeisureService、LeisureTimed、LeisurePolicy）：构建发生在最后修改之前。已重新运行完整构建，逐字节比对包内189份实际文件与当前模组目录，0差异，包哈希与构建报告一致。初始包不能代表最终源码；以§1最终构建为准。preflight为0 LSP Error / 293 Warning，保留原版0.0f语法解析盲区，不宣称零告警。实机边界不变。
