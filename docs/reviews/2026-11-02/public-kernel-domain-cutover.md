# 公共内核与领域边界收敛：实施与验证

日期：2026-11-02。基线：phase-3a-consolidation@eb65db6，候选版本 0.29.21。工作树修改，未提交/推送/发布。用户批准四项职责边界；随后明确只做必要测试，实机由用户验收。

## 实际改动

- 公共派工中的制作预检/250ms等待、搬运加载后恢复、工具归还抢占和清洁需求观察已移入对应 Provider。PublicWork 通过注册 hooks 调用；多个领域的观察依赖按任一变化唤醒，公共层不解释各自策略。订单业务门面仍有制作订单操作与内置装配，不将其冒充通用派工算法。
- JobContracts 保存进程内领域契约；BuiltinJobContracts 负责内置装配。JobStore 的记录校验、业务转换、个人分类、作用域阻塞与所有权交接改为委托契约。未注册类型沿用 envelope-only 行为，SELF_CARE 不额外收紧加载接受范围。
- LaborJobCommit 承接通用创建/提交算法，领域容量准入与 token 分类来自契约；认领、容量预检、提交、缩减、失败隔离、终态释放的次序保留。
- LaborDomainAdapters 承接既有烹饪、生活、活动、现场、搬运、制作适配；LaborStore 保留兼容公开入口。domainState 只引用原所有者的同一 root/claims/token 表，世界发布时统一换绑，不是第二套账本或缓存。
- LaborRecovery 编排恢复；六类 JobRecovery 各自解释领域记录。HaulLegacyRecovery/CraftLegacyRecovery 承接仍在使用的适配记录恢复，不是新增旧档迁移，不提前删除仍有调用的路径。
- claimId 冲突仍先完整扫描，再重建资源；CRAFT/HAUL 的碰撞状态解释移到领域契约。全局冲突顺序、UNKNOWN 范围和物理清偿条件不变。
- FIELD 续批、HAUL 动态路线、COOKING 加料/炉具监管保持领域自主；没有统一固定阶段执行器。
- HaulJobs 将目标状态投影与单步合法转换分开。原多次合法转换和通知保留；搬运和制作提交后读取只读 envelope 引用，避免再次深复制整个 payload。没有删除现行存档 state 字段，也没有宣称所有历史镜像已退役。
- JobStore.update 构造浅层候选，校验后仅进行一次有界深复制。校验/转换函数为只读契约。
- Java JobData 处理任务记录表的有界复制，经 ProbeRuntime.jobDataCopy 一次桥接；不是复制 InventoryItem，不改变原版物品转移。未提供桥能力的启动/独立 Lua 宿主沿用等价 Lua 路径；Java 执行失败不自动降级重试。

## 当前闭环入口

路径根为 Contents/mods/EmberRoutesProbe/42/media/lua。

- 创建认领：client/EmberRoutesProbe/HaulJobs.lua 的 claim → LaborStore.createClaimedJob（由 LaborJobCommit.install 安装）→ 原唯一 Claims/JobStore。
- 正常交付：HaulAgent.knownTransfer 核对实际原件与容器 → settleHaulLines → HaulJobs.settle/finish → 通用提交释放。
- 异常：HaulAgent.stopAdapter → TaskBusinessStop；HaulJobs.prepareRecovery 与 HaulJobRecovery 分别解释领域恢复和重建声明。FieldSession 停止/结算仍走唯一 TaskRuntime。
- 现有原件、工具与炉具责任未改为会话退出自动释放；兼容入口未因文件拆分删除。

## Java 边界与性能证据

以当前安装 projectzomboid.jar 的 javap 核对 KahluaTable/Iterator。实际 VM 确认 Lua #string 等于 Java UTF-16 String.length；保留 8192 节点、16 层、16384 字符串长度及非负整数/字符串键约束。共享子表分别复制，环拒绝，与原 Lua 路径一致。

宿主微基准：32 条物品标量记录，预热 1000 次，读取复制 10000 次，单次观测 Lua 1933.6447 ms / Java 112.9919 ms。宿主使用直接 JavaFunction/反射桥，未覆盖游戏 Exposer、帧调度、真实负载或 GC 尖峰；不作为实机性能提升结论。

## 已运行

- JobStore 既有 35 项及新增注册扩展/引用隔离检查通过；同一用例使用 Java 复制路径也通过。
- Java JobData 19 项安装 VM 契约检查通过：中文/代理对长度、共享子表、数值键、环、非法值、深度与宽度边界。
- 最后派工收口后仅补 public-work（78项）、hauling-provider、tool-return（102项）定向回归通过，未重跑全套。
- 搬运改道、FIELD workflow/连续作业、工具返还、烹饪接班、生产 Runtime 等定向入口通过；原生实体为替身，不是实机证据。
- 一轮集中宿主扫描：180 套，通过 142，失败 38。隔离 eb65db6 原始扫描 137/43；补齐同样 build/qa 生成数据后重跑五套缺夹具用例，五套均通过。失败套件集合与当前 38 套一致，无新增失败；不能将差额五套称为修复。
- 38 套失败含旧迁移预期、UI/原生替身缺口及既有断言；未为通过测试放宽生产契约。phase3a-stage-b 主体 Part 1～6 通过，随后加载 quarantine-evidence-test 在 io.stdout 宿主缺口失败，整套记失败。
- Java 构建、安装版 Lua 普通/Debug 编译、CN/EN 键集检查通过。最终构建日志：build/logs/kernel-build.txt；包：build/packages/EmberRoutesProbe-0.29.21.zip。
- PZ lint 未报本模组问题；知识库中原版 ISFluidEmptyAction.lua 因原版 Java 式 0.0f 字面量无法解析，覆盖缺口保留。
- 首次 preflight 错传仓库根，扫描到 build 下诊断脚本而失败，不能作为产品源检查结果。纠正为 mod 根后静态步骤通过，到完整 LuaLS 时按用户后续要求停止；完整 LuaLS/preflight 未完成，不记通过。独立全模组 LuaLS 亦已停止。
- 最终公共派工78项/清洁需求15项定向通过；Markdown 4份引用零错误，git diff --check 无错误。最终候选包 363 文件逐项哈希与工作区一致。

## 交付边界

仅做本轮直接相关必要检查，不继续扩展模拟场景或重复全套测试。真实物品转移、动作打断、保存重进、工具与炉具恢复、多 NPC 帧耗时由用户实机验收，均未验证。旧公开领域门面和仍在使用的适配记录保留；不宣称全仓库所有兼容路径已移除。
