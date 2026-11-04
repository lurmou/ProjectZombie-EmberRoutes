# 浅层领域目录与 Java 桥表面收敛

用户于 2026-11-04 批准渐进领域分级与独立接口审计。基线为 phase-3a-consolidation / 4ccb093；本轮不扩展 UI 视觉、医疗或多目标搬运的业务行为。

## 目录决定

首批只迁移搬运执行领域 10 个模块，client/shared 保持原加载域，在各自 EmberRoutesProbe 下新增同名 Hauling 目录。名称仍保留原前缀，避免同一次修改同时重命名符号。主入口、跨领域调度、配送订单、物流候选规划及公共原生转移动作保持位置；其引用同步改为新路径。目录组织不构成新的运行时权威或领域注册机制。

client：Haul、HaulAgent、HaulingProvider、HaulJobRecovery、HaulJobs、HaulRouting、HaulRules、HaulWorkflowView。

shared：HaulJobRecord、HaulManifest。

目标路径为 EmberRoutesProbe/Hauling/<原名>。现有源码与测试均可同步更新，无已登记的第三方模块路径兼容契约，因此不保留根级转发文件。同步修改字面 require、测试 loaded 键、直接 dofile 与当前工具路径；历史证据文档保留历史路径，不伪造当时源码位置。其他领域以相同原则后续独立整理，本轮不全量移动。

## 语义不变量

只替换模块路径，移动模块正文经逆向路径替换须与基线一致。HAUL providerType、format=3、稳定 ID、声明键、动作、回执、UNKNOWN、取消及恢复规则不变，不修改存档。创建/认领沿 HaulJobs.claim；正常结清沿 settle/finish；异常沿 HaulAgent.pause 与 HaulJobs.prepareRecovery、HaulJobRecovery.restore。三条链迁移整体包含，但其共享 Store/Session 权威不迁入领域私有副本。

风险主要是遗漏动态路径/测试替身键，或新旧路径同时加载导致双份局部状态；以全仓精确旧路径残留扫描、大小写与 client/shared 唯一模块名检查、源文件等价核对及现有运行/暂停/恢复回归约束。只移动目录不宣称帧率改善或循环依赖已消除。

## Java 决定

当前 ProbeRuntime 共 96 个 public static 方法：91 个有直接/局部别名引用，laborCreate/laborMutate/laborCancel 使用字符串调用。log 只供同包 Java 使用，改为包可见；无生产、测试、工具或 Java 调用的 lumberjackSquareHasTree 转发入口删除，保留 CleaningFastScan 的实际实现。Lua 桥仍由 Main 暴露同一 ProbeRuntime、同一全局名，不引入新桥层。其余 94 个正式入口全部保留，不把公共方法数量当性能指标。

此项是有意收窄未登记接口的表面，不冒充目录等价重构；独立提交。反射测试固定正式方法名称集合，检查非 public 内部日志、无已删除入口及三个动态内核入口仍公开。测试只枚举 metadata，不运行世界动作。

## 验证边界

按迁移风险运行现有搬运、配送、物流、提交/暂停/恢复定向 Kahlua；Java 实际依赖构建与桥表面反射测试；最终一次集中历史回归及 preflight。失败按迁移前后集合比较，不为目录迁移修复无关业务或放宽守卫。实际游戏、磁盘重进和性能不由这些检查证明。构建包须检查旧 Lua 路径已删除、新路径齐全。保留其他会话的医疗调试入口，提交不夹带它。
