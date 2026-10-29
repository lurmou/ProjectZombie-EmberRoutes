# 0.24.6 任务读取与运行器分配优化

延续[Java只读下沉](native-read-performance.md)及[实施计划](../../superpowers/plans/2026-10-24-task-read-performance.md)，遵循[唯一架构](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)。本轮检查 console.txt 未发现新版 RUNTIME_PERF 分项日志，因此以下为源码确认的重复工作及离线测量，不作为150ms主因判定。

在线需求重新导出 SHA256 `1E802DFE03A43437C77DC8EF5D04A2E38EC9AE9970A71D349B302B9EFE2EFB08`，与此前审查一致；本轮没有修改架构职责或另建需求。

## 修正的重复工作

JobStore.forNpc 原来先深拷贝并排序某 NPC 的所有任务。SelfCare.personal、TaskResume.personal 和 BusinessJobs 的恢复责任检查随后仅寻找 SELF_CARE；与当前读取无关的制作/搬运 payload、原件ID和制作链也会被复制。对保留大制作任务的 NPC，单次查询的成本随这些 payload 增长。

新增可选 providerType 参数。SELF_CARE 查询直接使用 Store.open/create 已维护的 personalByNpc 唯一索引，仅复制当前个人任务；其他过滤类型在复制前筛选。无参数旧调用继续返回全部已排序副本。没有新增业务索引、另建持久数据、共享可变 payload 或跨 tick 缓存；更新后立即读到新版本，重开世界由原索引重建。

TaskRuntime 原来每次推进都会新建 handle.result，即使身份、类型、状态、原因和错误都没变。现在比较这6项后复用未变结果，状态/错误/身份变化仍发布新表；inspect 仍返回独立副本。空任务运行器继续推进 Controller 清理停止记录，但不创建业务遍历闭包。没有节流动作、停止确认或保存。

JobStore.update 的两次深拷贝本轮未删：它还承担旧记录及写入值的有界可序列化验证，不能把它作为普通无用复制去掉。

## 安装 Kahlua 离线对比

实际使用安装 JAR 的 Kahlua VM；世界和身体未运行。合成同一 NPC 的普通任务，每条 payload 含512条 id/source 数据，另有一条个人任务；预热5次，两种查询各运行30次。旧方式通过未过滤 forNpc 后寻找个人任务，新方式直接过滤查询。

| 普通任务数 | 旧方式30次查询 | 新方式30次查询 |
|---|---:|---:|
| 1 | 275.839ms | 1.659ms |
| 8 | 401.256ms | 0.355ms |

这是一次宿主VM采样，包含JIT/GC和顺序影响，不能作线性规模推断；8任务场景仅为任务库工作负载，不代表当前业务允许8个并行制作身体。没有据此推算整模组提速倍数。如果没有大普通任务，自理查询的收益会小得多。

## 验证

- JobStore32项：过滤、旧调用、缺失结果、副本隔离、更新即见及重新打开索引等通过。
- TaskRuntime61项：未变状态复用、inspect副本隔离、被改身份字段恢复及停止变化通过；原有排他、保存屏障及恢复断言保留。
- 自理服务9项、恢复23项、完整生活执行20项、结清16项、统一保存61项、公共派工51项、随从20项相关回归通过；原生世界为替身。
- 0.24.6构建通过，保留此前30项安装原生读取回归；完整 preflight 全部通过（153个Lua、0阻塞错误，仍有信息性类型提示）。release-check 0错误/77条现有UI中文硬编码提示，modscan 0文件替换冲突，相关5文档doclink 0断链。
- 归档与源码逐文件SHA256核对160文件一致；ZIP SHA256 `872F72B2E4DE0419E4848B46FEB802198C02B1ADF8F4BAA79CF24548BC57675E`。
- 游戏未运行；**Boot 1秒累计低于50ms与整体CPU改善比例仍未验证**。保存、未结义务和原件保护未放宽；无提交、无工坊发布，保留并行修改。

证据：build/logs/task-read-performance-tests.log、task-read-performance-integration.log、task-read-performance-build.log、task-read-performance-preflight.log、task-read-performance-release.log。测试Java宿主仅在显式 --timing 时导出测量时钟，不影响正常模组。
