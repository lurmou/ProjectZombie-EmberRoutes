# Claims 与领域契约收敛证据

日期：2026-11-14。main，HEAD cc77901b6968f5903403cf2e4c0aae60b4a90377 加未提交工作区。保留之前的责任账本、身体拆分、QA 和翻译等改动；本轮未提交或推送。版本 0.29.62。

## 范围与语义

1. **单实现收敛**：LaborClaims 删除 Lua 认领、容量、隔离、重建和释放算法，只保留调用适配及只读查询。ClaimsKernel 执行写操作，ClaimsRecovery 实现同一运行时图的隔离/重建；LaborCommitKernel 继续拥有提交发布与撤销。不是两套 authority，也没有复制账本。LaborStore 的 token 图缓存清除也经 Java 操作，不再直接写图。正常提交的严格新增资源与领域幂等增补保留不同前置条件，共用 Java 增补机制。
2. **明确的接口边界变化**：新增固定操作 claimsCommand，缺失即 CLAIMS_JAVA_REQUIRED，无 Lua 写 fallback。两种语言以前的宽松/严格输入差异不再构成两套可选实现；新建认领、容量恢复等以既有 Java 的正式输入守卫为准，不能再依靠旧 Lua 对非法键/空目标的宽松接受。缺 claimId 时 Java 统一生成调用协议所需的运行时身份，生产 Job 的持久 claimId 仍来自既有世界序列分配。未改变 v2 持久格式或责任结清证据。
3. **等价提取领域证据**：Cooking、Hauling、Crafting、SelfCare、Field 各自的 shared JobObligationContract 接管逐记录对应、Job 反向引用、结清与退休证明。JobStore 保留原位置的通用终态、归属、npc 和 claim 守卫；领域校验仍强制执行。结清策略按注册顺序检查，以继续拒绝责任语义与 Job 领域不符的操作，不因选择当前 provider 而跳过拒绝。未放宽 UNKNOWN、取消、移交或退休语义。
4. **契约原因归属**：scopeBlockedReason 移到实际阻断领域契约并登记 errorCodes；JobStore 和 LaborJobCommit 不再反向读取制作清单取得拒绝原因。注册时拒绝非函数义务钩子及缺少已声明原因的 scope blocker。相关测试契约同步适配。
5. **缺陷修复**：LogisticsService.recover 将 LOGISTICS_STOPPED 识别为可恢复的系统暂停。此前停止服务后的持货 Job 因公共派工 retained 门禁无法继续；现在服务重新启动后可沿用同 Job/原件。publicDispatch、suspended、健康、成员、运行时接纳与不确定状态守卫保留，服务停止期间不自行恢复。

## 闭环入口

- 创建/认领：LaborDomainAdapters.claimCooking / claimPersonal / claimActivity / claimField 等经 LaborClaims 调用 Java；LaborCommitKernel.create 继续负责 Job 与认领的受控发布。
- 正常释放：LaborDomainAdapters.finishCooking、ClaimsKernel.release/shrink；领域 JobObligationContract 在 JobStore 原入口验证消费/交付/炉火与退休证明。身体停稳不替代责任结清。
- 异常/冷恢复：LaborStore.data 调用同一 Java 图执行隔离和恢复；ClaimsRecovery.restore 的冲突拒绝在修改前完成，重复恢复不重复计容量；旧 token 不能释放新 owner。事务撤销仍在 LaborCommitKernel.Tx，发布后未知失败仍触发既有围栏。

## 测试适配及缺陷区分

- logistics-test 不再调用已删除的私有派工链，改用真实 PublicWork、HaulingProvider、TaskRuntime 与保存屏障，提供完整身体/队列替身。保留批量路由、过滤、模式切换、手动接管、保存后同 Job 继续、停服务留货、重启交付、提交前撤销取货规则和规划预算。该测试暴露上述物流恢复缺陷，生产修复单独记录。
- persistence-test 不再复用只含 cancel 的 Companion 替身或旧自由身体 API。测试当前真实 Companion、TaskRuntime、TaskPersistence、Persistence：正常保存/同 Job 恢复、缺磁盘回执拒绝、清理拒绝/异常、原生捕获失败、actor/driver 未就绪、三次限额的 tile 重试、手动重试、只读报告、异步 saveworld、现有 MP 守卫、禁用状态和未停稳保留控制。原生清理/快照/磁盘是明确替身；被阻断运行时的下一场景通过显式新宿主重建开始，不靠修改一个标志伪造恢复。
- task-save-diagnostics 适配正式根 v2，使用真实 Actions/Haul 保存清理：中途搬运保存、后续新 batch、保留无关原件及其状态、缺失原件阻断并保留责任。补足 persistence 测试中的清理替身边界。
- boot-pause 使用受控时钟，移除对 Boot 已安装 retirement handler 的重复注册；不再假设每三次渲染回调推进一次。
- 新增 claims-kernel-recovery，实际 Java 执行令牌轮换、隔离容量、重复冷恢复、冲突无写、受领人核验、精确认领释放及缺桥无 fallback。JobStore/JobContracts 夹具适配当前根、独立测试领域和新增回调/原因声明，不放宽生产守卫。
- KahluaLaborTest 默认七项现在自动装配真实提交/选择桥；只有开关、没有文件名时也执行默认套件，不再静默运行零项。显式文件列表仍按对应 Java 开关装配。claims 桥延迟解析，纯 UI 测试不被迫提前加载 claims 类。

## 最终检查

- `tools/build-probe.ps1`：0.29.62 BUILD_OK。456 份生产 Lua 普通/Debug 编译、Java 编译、架构/未声明全局门禁、2189 翻译键检查和固定构建回归通过。桥面 119 个方法名、20 个身体签名以及 claimsCommand 完整签名检查通过。日志 `build/claims-contract-build.log`。
- 最终构建 classes 上的安装版 Kahlua + 实际 Java：31 组全部通过，0 失败；包含默认七项、此前 20 组责任链、claims 恢复、JobStore/JobContracts 及实际诊断保存。日志 `build/claims-contract-final-tests.log`。这不是全历史测试库全绿声明。
- Python 上下文门禁 42 项通过；日志 `build/claims-context-gates.log`。diff 行尾/文件尾空白检查通过。
- 产物 `build/packages/EmberRoutesProbe-0.29.62.zip`。包内 513 个文件逐项与当前工作区一致，JAR/ZIP SHA-256 与 build/probe-build.json 一致。

未验证：游戏内行为/延迟、真实磁盘保存和崩溃恢复、性能。Java 图操作需跨语言桥接，未测量其开销或收益。本轮不实施账本增量提交、桥面拆分、UI 收敛或全库命名格式化；现有 Java 烹饪容量资源键特殊处理不在本轮下沉范围。不宣传零损失、永不卡死或性能提升。
