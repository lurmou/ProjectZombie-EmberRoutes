# Production / Haul 真实业务切换证据

> 日期：2026-11-01｜修改前 HEAD：`b1146d6`｜业务代码 HEAD：`14e8878`｜分支：`phase-3a-consolidation`｜状态：开发候选可集中实机；PZ 实机未运行，B.5 未关闭。

用户后续指令“生产未切换实机验证什么？先做完吧”覆盖此前 Stage C 实施冻结。先完成真实制作、搬运与必要结清，再集中实机；不宣布 B.5 已关闭，不恢复旧档迁移，不加入通用事务层。实机操作仍由用户执行，外部 AI 独立审查。

## 最终实现与契约变化

- `Production.lua` / `ProductionActions.lua` 使用 `ProductionJobs` 的脱离式执行草稿；创建经 `createClaimedJob`，后续资源、阶段和终态经 `mutateJob`。真实手动、公共制作、BOM 连续制作、取消归还及活动让位仍由原业务链提供证据。
- `CraftRecord.validProduction` 复用完整业务字段校验；真实 CRAFT format=4 必须带 `executor=PRODUCTION`、匹配 envelope 的 id/npcId、sequence/generation。此前最小原型仍不能作为真实原生执行参数。此项属于接受范围收紧，不是等价改名。
- native 调用前先提交 `nativeAttempt=COMMITTING`、UNKNOWN 与责任；拒绝提交则不调用 native。产物/消费观察成功后提交 APPLIED 回执；Claim/CAS 失败将所有已知产物交给既有 SYSTEM_QUARANTINE，并仅在最新记录仍是同一未决尝试时保留观察事实。不重放旧提案，不自动重做物理效果。
- 同一回执重报在执行边界幂等；不同回执明确拒绝。提交通知后 revision 再变化即停止使用原草稿，不借新 revision 覆盖后续事实。
- JobStore 维护由未决制作尝试派生的作用域索引。新 Job 创建及 Cooking/Field/Personal/Activity/Craft/Haul/旧探针执行守卫拒绝同作用域其他 Job；冷启动重建。自身返还仍受原业务证据守卫，绝不因例外而重放制作。此保护只覆盖本模组声明的作用域与接入路径，不约束玩家/其他模组直接操作，也不承诺强杀零损失。
- 自主物流和配送经 `HaulJobs` 创建完整 HAUL format=3，转移前持久化 attempt，确认物理原件位置后结清 manifest、Claims 与容量；终态成功后才报告身体任务完成。物流策略、任务监视与保存入口同步识别新格式。
- Haul 容量变更在同一现有 mutateJob 边界协调；先核对命令与 proposed reservation，拒绝后无扩展副作用，CAS 拒绝恢复原容量。未携货不能单独证明责任结清，clear 拒绝仍有原件或未决动作的任务。
- 读档恢复递增执行代次，正常已知任务暂停后续作；未决原生尝试保留核对责任，不重放 native。JobStore 与 Claims 仍是唯一持久状态、资源权威，两个新增模块只持有可失效的执行草稿。

## 仍保留的旧接口

Production 不再使用 claimNative / replaceNative / extendNative / finishNative / publishCraft / refresh 写持久状态。自主 Haul 的旧形状 Store 入口按 format=3 进入统一 API，format=1/2 探针适配仍保留。`BusinessJobs.legacyCrafts/legacyHauls` 只服务这些现役旧调用，新格式查询是脱离式投影，flush 不写新格式。

CraftProbe 的格式 1/2 原生探针及显式搬运仍实际调用旧接口，因此本轮不删除。旧写入口物理退役须在真实业务实机验收后核查调用，不以“不兼容旧存档”代替该证明。

## 实际检查

集中标准 Lua 回归：原有 11 个核心套件，加 task-production-runtime、delivery-service、activity-craft-yield、settled-task-retirement、hauling-provider、task-save-runtime、work-format-admission、public-work-test，共 19 套件通过。[命令及实际输出](production-haul-test-output.txt)随本轮提交；原始分套件输出位于本地 `build/logs/cutover-*.txt` 与 `cutover-regression.json`。套件有嵌套复用，断言数不相加冒充独立数量。

Production 专项增加：native 前 CAS 拒绝零次效果；native 后 Claim 冲突、revision 变化保留产物隔离与 UNKNOWN；回执重报幂等；旧回调不重做；观察抛错保留 COMMITTING 并阻断未知产物作用域；冷启动恢复作用域索引；两次独立内存重建后仍可打开同一完整 Job 并保留同一原件认领。标准 Lua 当前 100 项 controlled 检查，原生身体、物品效果和磁盘均为替身。

测试适配包括：真实格式号/脱离式草稿预期、完整的旧业务夹具字段、重载 Store 时一并重载对应执行适配器、Stage B 腐坏注入改为对应 legacyHauls 边界、保存协调替身补齐 Haul 恢复调用。没有为测试放宽生产 Validator 或删除失败场景。

代码提交：`44f0a18` 为真实两链切换，`7ee062f` 保留搬运恢复的既有 UNKNOWN，`14e8878` 区分无写入拒绝与草稿过期，并在意图安全拒绝时恢复执行草稿的原阶段，不制造虚假未决效果。

安装版 Kahlua：制作 100 项、搬运 30 项、配送 46 项、保存协调 71 项、独立公共派发 77 项所在套件通过；数目含既有替身链，不作独立用例加总。原生游戏效果及磁盘仍是替身。末轮两个适配器定向 Lua lint：0 error / 0 warning。

完整 preflight 对 `44f0a18` 隔离源码快照通过，退出码 0：Lua/结构检查、候选规则检查、索引新鲜度均通过；LuaLS 为 0 error / 709 warning，warning 未逐条审查，不宣称全量静态审查已完成。后续两处适配器语义修复（`7ee062f`、`14e8878`，生产 Diff 仅两个文件）已补标准 Lua、安装版 Kahlua 与定向 lint，不把该完整 LuaLS 结果冒称成末轮两个文件的精确版本检查。此前工作区检查因源码仍在修改而取消，不能作为最终证据。

发布扫描：退出码 1，两个 error 均是基线 `UI/PageLifecycle.lua:22,347` 的 print，另有 23 条既有硬编码中文提示。本轮未改并行 UI，不宣称正式发布门禁通过。

独立 `public-work-test.lua` 首次在加载 ToolReturnService 时因夹具缺依赖而失败。已明确提供“无工具保管/无归还任务”的 Store/Service 替身（意外启动归还会报错），保留真实 Provider 注册和发现链，未改生产守卫；77 项在标准 Lua 与安装版 Kahlua 均通过。实际公共制作另经 Runtime/Production 集成验证，不用派发替身冒充原生制作。

候选包 `EmberRoutesProbe-business-14e8878.zip`：341 文件逐一与 Git archive 字节及 manifest SHA256 比对通过（唯一非 Git 文件为下述已核验 JAR），没有 QA overlay，没有包含并行未提交 UI 改动。输出路径保存在本地 `build/logs/cutover-delivery-path.txt`；未安装、未发布、未运行游戏。固定游戏 JAR SHA256：`E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`。Java 运行时源码本轮未修改，不重复构建；候选包须核对既有 build report 和 JAR 哈希。

## 集中实机范围

使用可丢弃的新世界，按真实产品入口验证：手动制作一单、公共制作一单、BOM 连续制作；取料/制作/交付期间暂停与取消，原工具归还；自主搬运混合货物分仓、部分交付与暂停续作、配送取消退回。至少保留一份携带真实原件的暂停任务，正常保存、完整退出、重新载入两次，核对同一 Job 身份、物品 ID、容量与任务进度，确认不重复制作或配送。

不把宿主深拷贝等同于 PZ ModData 磁盘验证；不宣称任意配方/模组、跨作用域人工移动、强杀恢复、规模性能或联机已通过。不存在本轮新增的历史存档清洗/迁移。完整源码 Diff 由 Git 提供；并行人员/UI/生命周期改动保留且不混入本轮提交。

## 首次实机加载阻断：Debug 编译局部变量表

用户随后报告游戏错误计数 59。`console.txt` 从 20:25:54 开始反复记录同一 `LaborStore.lua` 编译异常：`ArrayIndexOutOfBoundsException: Index 200 out of bounds for length 200`，发生在 `LexState.new_localvar:730`。包含退出重载在内，采集时日志中有 114 次相同异常，不能把屏幕计数理解为 59 种独立缺陷。加载路径是 Workshop 工作区，不是隔离候选目录。

固定安装 JAR 的 javap 证明：Debug 分支用函数内累计局部变量编号索引固定 200 项 `actvarline`，已离开作用域的局部声明仍占编号；普通模式不执行此分支。同一生产文件 `Core.debug=false` 编译通过，`true` 完整复现越界。修改前 `b1146d6` 同样可复现，因此不是某个实际制作效果产生的资源异常；但此前宿主未开启该编译分支，是本轮验收遗漏，旧候选包撤回。

修复是等价的阶段隔离：将身份冲突图恢复与类型化 Job 认领恢复分别置于同步局部函数，保留原执行位置、扫描顺序、共享 Claims 和最终缓存发布时点。`git diff -w` 仅新增 11 行，没有删除恢复链、放宽 Validator 或改变持久格式。

新增 `tests/java/KahluaCompileTest.java`，用当前安装编译器只编译全部生产 Lua（不执行世界逻辑），逐一切换普通/Debug 两种模式，构建入口 `build-probe.ps1` 已接入此门禁。实际结果：两种模式各 326 文件、0 失败，所有函数最大局部名称表为 134；LaborStore 定向 lint 0 error / 0 warning；标准 Lua Stage B 包含 482 Evidence 检查通过；安装版 Kahlua 制作/搬运/配送通过。额外尝试的完整 Stage B Kahlua 在 Part 6 已通过后，于 Evidence 夹具 `quarantine-evidence-test.lua:23` 因宿主未提供 `io.stdout` 失败，未把这一宿主夹具缺口计为通过，也未修改生产代码规避它。

复现新门禁：`java --class-path "D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/*" tests/java/KahluaCompileTest.java`。这证明 Debug 编译阻断已消除，不证明游戏重启后业务与磁盘验收已通过；需完整退出再启动，不能用热重载替代重新初始化。
