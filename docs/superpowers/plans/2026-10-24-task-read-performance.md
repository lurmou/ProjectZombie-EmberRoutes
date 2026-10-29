# 任务读取与运行器分配优化

继续用户批准的整体性能优化，遵循[唯一架构](../specs/2026-10-22-npc-behavior-architecture-design.md)。

- [x] JobStore.forNpc 增加可选 providerType 过滤；SELF_CARE 复用现有唯一索引，其他类型在深拷贝前筛选，不改变旧调用或副本隔离。
- [x] 自理、恢复与结清检查使用过滤查询，避免无关制作/搬运 payload 深拷贝。
- [x] TaskRuntime 复用内容完全未变的结果，空任务时不创建执行遍历闭包；保留控制器停止/清队列推进。
- [x] 验证副本隔离、恢复和结清门禁；用安装 Kahlua 对比读取工作量，记录为离线数据；完成 preflight、构建和发布检查。

没有新版游戏采样时不宣称这些是150ms的主要来源或已达50ms。
