# EmberRoutes 任务文档导航

> 更新：2026-10-24｜按本轮任务读取，不要求全文加载。当前进度只见[BACKLOG](BACKLOG.md)，本页仅维护文档职责与入口。

## 先读与文档职责

| 文档 | 用途 |
|---|---|
| [AGENTS](../AGENTS.md)、[HANDOFF](HANDOFF.md) | 稳定约束、接手顺序 |
| [BACKLOG](BACKLOG.md#npc-架构执行记录) | 当前阶段、阻塞、下一步、验证边界；每轮原位更新 |
| [开发规则](development-rules.md) | 修改代码与交付检查要求 |
| [在线需求](https://docs.google.com/document/d/1aTOBrzZvh_iCDkv045HNAV13i7vNf7OHk6E_sE7TWNM/edit) | 唯一需求来源；读取失败不能宣称已同步 |
| [NPC唯一架构](superpowers/specs/2026-10-22-npc-behavior-architecture-design.md) | NPC行为工作的必读设计入口；架构变更需用户确认 |
| [统一任务协议](superpowers/specs/2026-10-23-unified-task-dispatch-design.md) | 从属细化；公共/个人/责任候选、认领与UI契约 |

设计说明契约，计划说明步骤，reviews说明证据，testing说明验收操作；都不能仅凭标题、日期或版本认定已完成。下列旧计划应结合BACKLOG及关联证据阅读，不能整份重跑。

## 按任务选择

显式据点归属B已按用户决定接入0.27.0，不兼容旧档；[成员设计§2.1](superpowers/specs/2026-10-25-npc-settlement-membership-design.md)固定与闲暇共享接口，唯一架构v1.2登记。[实施计划](superpowers/plans/2026-10-25-npc-settlement-membership.md)、[实际开发证据与闲暇交接](reviews/2026-10-25/npc-settlement-membership.md)、[集中实机验收（未运行）](testing/membership-runtime-acceptance.md)分别维护步骤、事实与验收；不重构闲暇策略，不因宿主通过宣称实机完成。

2026-10-24用户确认的跨阶段执行顺序与验收标准见[BACKLOG可靠性与扩展任务](BACKLOG.md#可靠性与扩展任务优先级2026-10-24用户确认)：搬运恢复/状态机边界优先，其次性能尖峰与P2/P3收口，再进行长任务准备；流水线和宏微观交接保留为独立设计/原型。该表调整任务优先级，不以评审风险替代实现证据。

| 任务 | 设计/约束 | 实施与验证入口 |
|---|---|---|
| Phase 3A 收敛与 B.5 验收 | [主规格 v1.5](superpowers/specs/2026-10-31-phase3a-job-contract-standardization-design.md)、[同步勘误](superpowers/specs/2026-10-31-phase3a-v14-final-errata.md)：取消旧档迁移，先关闭 B.5，再制作/搬运真实接入 | 当前进度只见 [BACKLOG](BACKLOG.md#npc-架构执行记录)；[格式门禁实施](superpowers/plans/2026-11-01-phase3a-format-admission.md)与[验证](reviews/2026-11-01/phase3a-format-admission.md)；[Production 切换准备](superpowers/plans/2026-11-01-production-job-cutover.md)尚未实施；F1 修复、LuaLS、PZ 磁盘重进分别记录，未验收不解冻 Stage C；外部 AI 独立审核。 |
| 公共生活子区与行为规则 | [最小子区设计](superpowers/specs/2026-10-28-public-life-zones-design.md)，日常生活与聚会稀疏覆盖共用禁用/允许/优先规则 | [实现证据](reviews/2026-10-28/public-life-zones.md)：CRUD/规则UI、主动赴场和FREE聚会接通；原生位置/动作与磁盘保存未实机 |
| A3/A4 多人活动框架与出席仲裁 | [从属设计0.4](superpowers/specs/2026-10-28-a3-a4-community-activities-design.md)，FREE自主选择与SCRIPTED共同环节分开 | [计划](superpowers/plans/2026-10-28-a3-a4-community-activities.md)、[参考评审](reviews/2026-10-28/activity-framework-source-review.md)、[实现证据](reviews/2026-10-28/public-life-zones.md)：FREE首版正式参与/开场/退出/保存、制作让位恢复、定时与标题区UI源码已接；SCRIPTED、新动作及实机未完成 |
| 仓储呼叫配送重构 | [配送执行链设计](superpowers/specs/2026-10-27-delivery-rebuild-design.md)、[配送 UI 局部重构](superpowers/specs/2026-10-28-delivery-ui-design.md)，服从 NPC 唯一架构及统一任务协议 | [实施计划](superpowers/plans/2026-10-27-delivery-rebuild.md)、[实现与验证证据](reviews/2026-10-28/delivery-rebuild.md)；0.29.14 执行链/UI 已接并本地打包，真实鼠标/动作/重进尚未验收，当前状态见 BACKLOG |
| P4 自主厨师与设施监管 | [详细设计0.4（已授权实施）](superpowers/specs/2026-10-26-p4-cooking-and-supervision-design.md)，在线v4.0及用户全员持续计入、按成品饱食度的决定 | [执行计划](superpowers/plans/2026-10-26-p4-cooking.md)、[原版接缝与实现证据](reviews/2026-10-26/p4-cooking-foundation.md)。首批自主备餐/指定请求/BOM关联工单/研习/消费、公共派发与恢复接班、持久容量及渐进倒液体/外接供水代码已接。当前验证状态以BACKLOG为准；物理效果、磁盘重进和规模性能未实机，不宣称完整P4验收通过；区域随对应工种接入 |
| P1身体控制、停止、保存 | 唯一架构第3～5节、统一任务协议 | [运行接入计划](superpowers/plans/2026-10-23-p1-runtime-integration.md)、[保存接线证据](reviews/2026-10-23/p1-unified-save.md)、[已通过的约定验收](testing/p1-runtime-acceptance.md) |
| 公共工单、逐NPC认领 | 统一任务协议 | [共享Job切换计划](superpowers/plans/2026-10-23-shared-job-cutover.md)、[公共工作证据](reviews/2026-10-23/shared-public-work.md)、[交接契约六项建议评审](reviews/2026-10-25/work-handover-contract-improvement-review.md)（认领失败退避/身体预约/类型化结果债务，静态） |
| 搬运途中拒收、可变交付路线 | 唯一架构§3.5/4/5、统一任务协议；[原件责任与可变交付路线设计0.2](superpowers/specs/2026-10-26-haul-routing-and-custody-design.md) | 用户已确认R1及当前有效任务有界升级；[实施计划](superpowers/plans/2026-10-26-haul-routing-r1.md)、[0.29.6实施与验证证据](reviews/2026-10-26/haul-routing-r1.md)。R2与人工核销延期；实机未验证 |
| P2吃喝、休息、恢复 | 唯一架构P2与资源/恢复契约 | [P2计划](superpowers/plans/2026-10-24-p2-self-care.md)、[计划评审](reviews/2026-10-24/p2-plan-review.md)、[实现证据](reviews/2026-10-24/p2-living-loop.md)、[集中验收](testing/p2-runtime-acceptance.md) |
| 床/沙发、据点选床 | 唯一架构第5.3节；范围修订见BACKLOG | [全据点共享发现计划](superpowers/plans/2026-10-24-settlement-repose-discovery.md)、[0.25.1实现与边界](reviews/2026-10-24/settlement-repose-discovery.md)、[初版家具策略](reviews/2026-10-24/repose-sites.md)、[集中实机验收](testing/p2-runtime-acceptance.md) |
| P3人员、矩阵、实体书研习 | 唯一架构P3、统一任务协议第10/16/17节；[P3实施细化](superpowers/specs/2026-10-24-p3-personnel-study-design.md) | [实施计划](superpowers/plans/2026-10-24-p3-personnel-study.md)、[核心实现证据与剩余项](reviews/2026-10-24/p3-personnel-study.md)、[集中实机验收（未运行）](testing/p3-runtime-acceptance.md)、[当前缺口与顺序](BACKLOG.md#p2收口与p3待办) |
| P3.5闲暇、锻炼与双人社交 | [P3.5设计1.4](superpowers/specs/2026-10-24-p3.5-leisure-social-fitness-design.md)、[设计审查与来源复核](reviews/2026-10-24/p3.5-leisure-design-review.md) | [实施计划](superpowers/plans/2026-10-24-p35-leisure-social-fitness.md)、[0.28.2连续性计划](superpowers/plans/2026-10-25-p35-leisure-continuity.md)、[0.28.1家具/坐读修正](reviews/2026-10-25/p35-seating-reading.md)、[坐读计划](superpowers/plans/2026-10-25-p35-seating-reading.md)、[0.28.0闲暇重构](reviews/2026-10-25/p35-leisure-refactor.md)、[重构计划](superpowers/plans/2026-10-25-p35-leisure-refactor.md)、[0.26.0开发接入与验证边界](reviews/2026-10-24/p35-leisure-implementation.md)、[实机问题诊断与交接核验](reviews/2026-10-25/p35-runtime-fixes-and-handoff-review.md)、[集中实机验收（未运行）](testing/p35-runtime-acceptance.md)；4.5活动延伸与坐姿缺口见[BACKLOG活动系统延伸](BACKLOG.md#p3545-活动系统延伸2026-10-25-交接登记未开工) |
| UI产品交互 | [据点UI设计](superpowers/specs/2026-10-23-settlement-ui-design.md)、统一任务协议第16/17节 | [UI基础契约](ui-architecture.md)、[可用性计划](superpowers/plans/2026-10-24-ui-usability.md)及[证据](reviews/2026-10-24/ui-usability.md)、[视口计划](superpowers/plans/2026-10-24-ui-visual-boundaries.md)及[证据](reviews/2026-10-24/ui-visual-boundaries.md) |
| UI 运行时架构与基础设施 | [UI 运行时规范](architecture/ui-framework-architecture-spec.md)、[现状核验](architecture/ui-framework-current-state.md)、[阶段零审查与纠偏](architecture/ui-framework-phase1-review.md) | [阶段一计划](architecture/ui-framework-phase1-plan.md)；四层解耦、双层生命周期、统一调度器与零 GC 渲染 |
| UI调研建议 | [UI/UX调研指南](superpowers/specs/2026-10-24-settlement-ui-ux-master-guide.md) | 从属参考，不单独批准功能扩张或覆盖产品/工程契约 |
| 仓储、库存、据点身份 | [仓储读取与权威边界](settlement-storage-architecture.md)、统一任务协议 | [容器配置旧计划](superpowers/plans/2026-10-20-container-config.md)、[仓储脏更新旧计划](superpowers/plans/2026-10-20-warehouse-dirty-ui.md)，仅查原模块背景，不表示仍待整份实施 |
| 生产负重、原件与结清清理 | 唯一架构第5.2节 | [负重旧计划](superpowers/plans/2026-10-22-production-carry.md)、[持续更新的负重证据](reviews/2026-10-22/production-carry.md)、[清理计划](superpowers/plans/2026-10-24-settled-task-retirement.md)及[证据](reviews/2026-10-24/settled-task-retirement.md) |
| 性能、扫描、批读取 | 唯一架构第6节、开发规则 | [调度证据](reviews/2026-10-24/dispatch-performance.md)、[常驻证据](reviews/2026-10-24/runtime-performance.md)、[原生读取](reviews/2026-10-24/native-read-performance.md)、[任务读取](reviews/2026-10-24/task-read-performance.md)、[协调优化](reviews/2026-10-24/coordinator-performance.md)、[最新实采](reviews/2026-10-24/live-performance-and-haul-interruption.md) |
| P4/P5及宏微观扩展 | 唯一架构阶段表；先读在线需求 | [A-Life参考](superpowers/specs/2026-10-23-alife-ecosystem-and-settlement-architecture.md)为approved-reference，不表示功能已实现；[综合架构整理](ember-routes-comprehensive-architecture.md)不能作为第二NPC实施入口 |
| 原版API、可行性 | 当前安装JAR/原版Lua；基线变化须复核 | [引擎对齐审查](reviews/2026-10-23/vanilla-engine-interface-alignment.md)、[初始可行性证据](reviews/2026-10-18/feasibility-review.md)、[架构审查](reviews/2026-10-24/architecture-audit/review.md)、[2026-10-28 架构一致性与复用静态审查](reviews/2026-10-28/architecture-audit.md)（仅静态，未跑测试/未进游戏） |
| 需求一致性、开发流程与框架适配 | 在线需求+唯一架构+全量文档的总检查点；2026-10-27在线正文为v4.0；与仓库[v3.3快照](reviews/2026-10-25/online-requirements-v3.3-export.txt)的P3.5相关差异及未确认项见[P3.5复核](reviews/2026-10-24/p3.5-leisure-design-review.md#2026-10-27-在线-v40-与仓库-v33-复核)，审计中旧版本和"待粘贴"记录为历史 | [2026-10-25需求与框架一致性审计](reviews/2026-10-25/requirements-framework-consistency-audit.md)、[P3.5诊断证据中的在线复核](reviews/2026-10-25/p35-runtime-fixes-and-handoff-review.md) |

## 历史与维护规则

本轮性能：[分级降频方案](superpowers/specs/2026-10-25-performance-cadence-design.md)、[实施计划](superpowers/plans/2026-10-25-performance-cadence.md)、[0.28.4实施证据](reviews/2026-10-25/performance-cadence.md)。含监控器3秒累计口径及旧入口开销推论的修正，50ms目标未实机验证，不覆盖唯一NPC架构。

- [旧HANDOFF](history/2026-10-24-handoff-before-navigation-cleanup.md)、[旧BACKLOG](history/2026-10-24-backlog-before-navigation-cleanup.md)、[旧README](history/2026-10-24-readme-before-navigation-cleanup.md)完整保留整理前内容，相对链接已换算到原目标。旧分支、旧下一步和旧“当前”只用于追溯。
- requirements中的本地正文为历史快照；history中的聊天、reviews中的旧实现结论都不自动成为当前授权。
- 新增有效设计、实施计划或重要证据时，在对应任务行补链接，并原位更新BACKLOG；替代旧方案时说明替代关系，保留原文追溯。
- doclink检查引用是否有效，不能证明内容一致或不存在遗漏；续接仍须核查源码与相关证据。
