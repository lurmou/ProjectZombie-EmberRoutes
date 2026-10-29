# 0.24.7 协调链路重复工作清理

延续[任务读取优化](task-read-performance.md)及[实施计划](../../superpowers/plans/2026-10-24-coordinator-performance.md)，遵循[唯一架构](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)。用户要求继续优化；本轮检查 console.txt 仍无新版 RUNTIME_PERF 数据，不据代码问题数量判定游戏的实际耗时比例。

用户本轮明确回复尚未测试新版，因此150ms仅为旧版基线，不记录为0.24.4～0.24.7实测失败。在线需求再次导出SHA256 `1E802DFE03A43437C77DC8EF5D04A2E38EC9AE9970A71D349B302B9EFE2EFB08`，与此前一致。

## 为什么此前仍有大量重复开销

历史开发验证重点是原件、停止、保存和开工等待。多个服务分别读取状态、构建快照、全量对账，正确性与固定成本等待测试没有替代整模组常驻CPU测试。因此源码确实存在叠加的重复工作；已有优化未经过游戏CPU验收，不能说150ms问题已经解决，也不能把全部源码候选称为已测热点。

## 同一调用链的改动

| 路径 | 旧工作 | 新工作 |
|---|---|---|
| 普通派工资格 | 轮转筛选后，决定函数立即对同一NPC再次完整检查 | 将刚取得的binding/entry直接传入决定步骤，普通路径只检查一次；在途预检结果仍重新验证，不跨tick复用 |
| Job容量 | 每个决定重新遍历全局普通及个人Job | 查询JobStore已有普通任务计数，创建/安全删除维护，读档重建；容量上限和创建端最终拒绝保留 |
| 公共对账 | 无已领取工单也先构建全量CRAFT记录映射 | 有jobId链接时才构建映射；无工单且无在途搬运时清理直接返回 |
| 空普通任务清理 | 仍遍历全部个人Job、建立空回收列表 | 普通任务计数为0时停止业务flush和回收准备，不扫描持续自理记录 |
| 责任表 | 每次flush都为每个业务Job新建责任表 | 仅完全相同的空表或business=true表复用，状态/未知效果与非规范责任结构变化仍重建 |
| 单一状态查询 | 读取controller完整快照后只使用state | 增加只读标量state查询，运行器status与收尾结果不再创建这份中间表；公开inspect仍隔离副本 |

无制作工单但有搬运时，仍运行原对账释放已完成搬运候选，再跳过不需要的制作flush。没有缩减身体停止、保存、领取和物理资产重验；没有增加新世界缓存或延后UNKNOWN传播。业务Signal的全量刷新语义保持。

## 验证

- 安装版Kahlua最终8组相关回归通过：JobStore35项、公共派工56项、规划预算/优先级/唤醒模拟、结清18项、Runtime61项、Controller33项、统一保存61项、完整自理执行20项。身体/世界仍为替身。
- 新断言确认普通决定只绑定一次NPC、空/无链接订单不构建CRAFT映射、空公共清理不重复flush、没有制作订单也释放完成搬运候选、普通计数随创建/删除/重开正确、责任表形状变化仍修正、标量状态不泄漏可变控制记录。
- 0.24.7构建通过，保留此前30项安装Java库存边界回归；完整preflight全部通过（153个Lua，0阻塞错误，319信息性类型提示未清零）。release-check为0错误/77条现有UI中文硬编码提示；modscan为0文件替换冲突，相关5文档doclink为0断链。
- 最终包与当前源码逐文件SHA256核对160文件一致；ZIP SHA256 `DE9DAF7DD8B854FC2884E4C965CE3FF02ED645D3009ADE2DD7E9C4CFE33BE6C4`。没有提交、发布工坊或覆盖并行工作。
- **2026-10-24用户实机反馈：优化后稳定低于50ms。** 记录为用户当前测试场景的目标通过；本次消息未重述版本、人数及具体工作负载，不扩展为多NPC、复杂制作、最大库存或单次tick峰值已验收。开发侧未取得原始分项日志。本轮此前“游戏未验”是反馈前状态；离线模拟仍不能代替实测。最新包累计包含0.24.4～0.24.6改动。

日志：build/logs/coordinator-performance-final-tests.log、coordinator-performance-final-dispatch.log、coordinator-performance-runtime-tests.log、coordinator-performance-build.log、coordinator-performance-preflight.log、coordinator-performance-release.log、coordinator-performance-modscan.log。
