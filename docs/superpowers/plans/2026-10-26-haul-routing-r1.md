# 搬运 R1 实施计划

> 日期：2026-10-26｜状态：R1开发交付完成，实机未验证。

依据[已确认的从属设计0.2](../specs/2026-10-26-haul-routing-and-custody-design.md)及NPC唯一架构v1.2。用户本轮“开始吧”包含当前有效共享Job的有界升级，不包含R2、人工核销或显式交付语义变更。保留其他会话改动。

- [x] 原件模型与资源权威：新增HaulManifest，完整items不变；LaborStore按未结集合恢复声明，提供受控逐行结算；LaborClaims增加安全shrink，处理空集合。
- [x] 搬运适配：新增HaulRouting及HaulAgent，复用WorkTransfer和TaskRuntime；WorkAgent只将自主LOGISTICS委托新路径，显式搬运不改语义。动作捕获不可变端点/尝试；拒收后停止、核验并恢复选箱。
- [x] 恢复与投影：LogisticsService接统一有界责任恢复、PlanningWake依赖和低频兜底；当前有效format=1只在停稳且逐ID证据完整时升级；监控区分已交付/撤回/持货，CN/EN成对。
- [x] 定向验证与交付：26项新断言及6个相关Kahlua入口、中文UI宿主、完整preflight、构建和release-check通过；版本包198文件一致。实机未运行，见[专题证据](../../reviews/2026-10-26/haul-routing-r1.md)与BACKLOG。

不生成新库存账本、不复制原件、不引入独立调度循环；新适配只在现有共享tick下推进。测试只针对本次恢复与接口风险，不重跑全部历史套件。
