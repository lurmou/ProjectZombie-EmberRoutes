# 余烬商路 · Ember Routes

当前0.21.0：[配方浏览与委托制作](docs/reviews/2026-10-22/probe-0.21.0-crafting-browser.md)。可搜索/分类浏览配方，图标预览产物、材料工具及条件，按实际需求显示平台操作，独立管理工单；新增实机未验，见[使用](docs/testing/single-player-crafting-browser.md)。

当前0.20.2：[制作页说明修正](docs/reviews/2026-10-22/probe-0.20.2-crafting-clarity.md)。手持配方不再提示平台，展示每批材料、保留工具及产物，区分目标件数与整批实际产量；新增UI实机未验。

当前0.20.1：[原版配方覆盖补充](docs/reviews/2026-10-22/probe-0.20.1-recipe-coverage.md)。制作候选扩为7项，新增无工具、多材料/三工具、多件/多种产物和替代材料；实际脚本驱动检查通过，新增实机未验。

当前0.20.0：[通用物品配方与按量生产](docs/reviews/2026-10-22/probe-0.20.0-generic-production.md)。制作页可选木叉/木勺并输入数量，分别追踪制作和入库；多件共用工具、缺料可续工。新增实机未验，见[简短使用](docs/testing/single-player-generic-production.md)。

当前0.19.0：[据点三页可视状态](docs/reviews/2026-10-21/probe-0.19.0-visual-status.md)。仓储覆盖条、物流进度和制作阶段轨道，配合情境主操作；新界面游戏内待确认。

当前0.18.0：[单件制作与保存续工](docs/reviews/2026-10-21/probe-0.18.0-crafting-orders-resume.md)。统一据点窗口新增制作页，支持暂停、继续及分类归还；成功保存后安排续工。新增实机未验证，见[简短使用](docs/testing/single-player-crafting-orders.md)。

当前0.17.3：[制作启动自占用修复](docs/reviews/2026-10-21/probe-0.17.3-craft-self-reservation.md)。已定位并修复重复规划误判自身耗材的问题，新增实机未验证。

当前诊断版0.17.2：[制作停工定向诊断](docs/reviews/2026-10-21/probe-0.17.2-craft-stop-diagnostics.md)。原停工根因未确认，新增实机未验证。

当前 **0.17.1**：[分类仓储与通用平台修正](docs/reviews/2026-10-21/probe-0.17.1-classified-crafting.md)。制作从既有分类箱取料，产物和原工具分别归类入库；新单不拿玩家物品，木叉无需砧板。相关逻辑检查与构建通过，实机按[简短说明](docs/testing/single-player-native-crafting.md)确认。下方0.17.0借用/砧板原型为历史实现，已被替换。

当前 **0.17.0**：[原版制作原型](docs/reviews/2026-10-21/probe-0.17.0-native-crafting.md)。Debug下显式借用玩家原件，在真实砧板由NPC制作一把木叉并归还工具/产物；暂停、保存与待归还门禁已接入。定向本地检查与构建通过，[实机三组检查](docs/testing/single-player-native-crafting.md)待运行；完整委托生产/BOM尚未实现。

当前 **0.16.1**：[修复物流进度与批次提示](docs/reviews/2026-10-21/probe-0.16.1-logistics-progress.md)。修复中途交付漏通知，显示取货/交付、自动入库/错放、当前批次和上一批完成摘要，避免换单被误认为数量减少。相关本地检查通过，新实机待确认。

当前 **0.16.0**：[统一据点窗口](docs/reviews/2026-10-21/probe-0.16.0-settlement-tabs.md)，仓储/物流同窗切页，保留搜索与选择；隐藏页释放视图订阅，后台物流继续。相关双语Kahlua检查和版本构建通过，实机待日常确认。下方为历史记录。

当前 **0.15.1**：[修复物流启动/关闭并整理视觉](docs/reviews/2026-10-21/probe-0.15.1-logistics-repair.md)。移除游戏未注册的next调用，关闭幂等；正常尺寸横排模式框、紧凑工人列表和滚动详情卡。新增实机待确认。

当前更新 **0.15.0**：[容器配置收尾](docs/reviews/2026-10-21/probe-0.15.0-container-config.md)，统一世界/侧栏入口、用途与权限摘要、八种预设及规则复制/粘贴草稿；原版“应用”才保存。在线需求2026-10-21已更新并读取，见[新增边界与差异](docs/reviews/2026-10-21/requirements-update.md)。新增实机待日常确认，下方为历史。

当前更新 **0.14.0**：[统一物流管理页](docs/reviews/2026-10-20/probe-0.14.0-logistics-page.md)集中启停、双模式、工人名单、进度与阻塞详情，支持单人重试和仓储跳转。入口为右键“余烬商路 → 据点物流管理”，关闭不停止工作；[简短使用](docs/testing/single-player-automatic-logistics.md)。新增实机未验，下方保留版本历史。

当前更新 **0.13.1**：正式入口与原版Debug诊断分离，容器设置独立；细分物流等待原因与各工人旧任务阻塞。见[更新记录](docs/reviews/2026-10-20/probe-0.13.1-menu-waiting.md)、[简短配置](docs/testing/single-player-automatic-logistics.md)。新增实机待确认，下方0.13.0是功能基础。

> 日期：2026-10-21｜状态：0.16.1物流进度与批次提示修复；新增实机待确认；单人优先

Project Zomboid 社区经营、商队贸易与人类 NPC 模组的新项目。

当前包 **0.13.0**：据点共享入库分拣与错放整理，多NPC自动领单，不必逐人配置源/目标；同源同目标按角色负重和目标容量组批，一趟多件，最多30件，原版动作仍逐件转移原实例。用途/过滤/权限分离，保留人工接管及持货恢复。完整退出后重启以加载配套Java，见[配置与十项集中实测](docs/testing/single-player-automatic-logistics.md)、[实现与边界](docs/reviews/2026-10-20/probe-0.13.0-automatic-logistics.md)。本地检查通过，真实游戏的并行动作、吞吐和保存恢复仍待验收。

此前 **0.12.0**：每NPC独立载体/工单/随从、集中物品与容量预留、任务代次、共享轮转预算、逐人保存恢复及旧数据迁移。菜单新增选择和生成另一名NPC；显式搬运首先接入。见[实现与边界](docs/reviews/2026-10-20/probe-0.12.0-multi-worker.md)、[双NPC集中实测](docs/testing/single-player-multi-worker.md)。真实双NPC与规模性能未单独验收，本轮合并覆盖。

此前 **0.11.0**：名称/数量排序与查询缓存、清空搜索、来源身份复验及短暂定位、列表输入焦点和按钮状态、默认关闭的调试CPU采样。用户反馈整体测试无大问题，见[实施与基线](docs/reviews/2026-10-20/probe-0.11.0-warehouse-interaction.md)、[集中复测](docs/testing/single-player-warehouse-interaction.md)。无新增独立性能数据。

此前 **0.10.0**：紧凑相对布局、原版物品脚本图标、名称/数量分列、选中物品与来源详情、统一暗色主题和原生帮助；保持稳定统计及脏行/选择/滚动。见[实施记录](docs/reviews/2026-10-20/probe-0.10.0-warehouse-visual.md)、[集中复测](docs/testing/single-player-warehouse-visual.md)。

此前 **0.9.2**：固定顶部统计位置，分离状态提示，保留上次完成统计说明，避免普通存取反复替换整条统计。见[修复与复测](docs/reviews/2026-10-20/probe-0.9.2-stable-summary.md)。

此前 **0.9.1**：修复NPC存取时整栏清空/重建和浏览位置重置，采用稳定行差分、待核实数量标记，保留权限/错误清理和更新中无旧候选的边界。用户确认整栏闪烁已消失，见[复测](docs/testing/single-player-warehouse-dirty-ui.md)及[记录](docs/reviews/2026-10-20/probe-0.9.1-warehouse-dirty-ui.md)。

此前 **0.9.0**：统一物理端点复验、分片去重/汇总/归并排序、自适应登记成员查询、通知合并与中断上限、只读候选物资接口。见[合并复测](docs/testing/single-player-warehouse-contracts.md)、[基础契约](docs/settlement-storage-architecture.md)及[记录](docs/reviews/2026-10-20/probe-0.9.0-warehouse-contracts.md)。保留旧存档/容器身份，不包含BOM/自动分拣/防刷新/MP。

此前 **0.8.0**：独立据点账本、世界框选/扩展/改名、已配置仓库的只读汇总、搜索分类分页和来源定位信息。见[原测试](docs/testing/single-player-settlement-storage.md)及[记录](docs/reviews/2026-10-20/probe-0.8.0-settlement-storage.md)。

此前 **0.7.3**（用户反馈没有问题）：修复游戏Kahlua中的中文丢失/行重叠与容器提示缺字；拆分排版、布局、状态和列表基础。文字跟随游戏语言；见[本轮记录](docs/reviews/2026-10-20/probe-0.7.3-ui-foundation.md)、[UI基础边界](docs/ui-architecture.md)与[复测](docs/testing/single-player-storage-filters.md)。

此前 **0.7.2**（用户实机发现排版故障）：整枚仓储用途图标、清晰方框/分类层级、本地化物品名及三态例外；见[本轮记录](docs/reviews/2026-10-20/probe-0.7.2-storage-presentation.md)和[集中测试](docs/testing/single-player-storage-filters.md)。

此前 **0.7.1**：[修复完成任务阻挡下一单](docs/reviews/2026-10-20/probe-0.7.1-task-rollover.md)。完成后放入下一批直接开始，无需清除；暂停/带货任务仍受保护，失败新单保留旧完成报告。用户反馈本轮测试还行，属于用户通过反馈。

此前 **0.7.0**：树状多选存储过滤、具体物品例外、原版容器栏右键设置和缓存角标，以及目标规则约束的真实搬运。见[集中测试](docs/testing/single-player-storage-filters.md)、[实现记录](docs/reviews/2026-10-20/probe-0.7.0-storage-filters.md)。在线需求已更新至v3.2，见[读取与差异](docs/reviews/2026-10-20/requirements-update.md)；进度只在本地维护，实机尚未验证。

此前 **0.6.0**：用途标签、真实物品搬运、暂停/保存后显式续工和带货保护。见[集中测试](docs/testing/single-player-real-haul.md)、[实现记录](docs/reviews/2026-10-19/probe-0.6.0-real-haul.md)。标签、库存视图、派单与原版执行分模块，后续分类/生产/商队复用；本版实机未验证。

接手先读 [AGENTS.md](AGENTS.md) 和 [接力说明](docs/HANDOFF.md)。
唯一需求来源为[在线Google文档](https://docs.google.com/document/d/1aTOBrzZvh_iCDkv045HNAV13i7vNf7OHk6E_sE7TWNM/edit)；本地[v3.1原文](docs/requirements/2026-10-19-v3.1-original.txt)仅作历史快照。
当前工作见 [待办](docs/BACKLOG.md)、[NPCFW 首轮参考评审](docs/reviews/2026-10-19/npcfw-reference-review.md) 与 [首个载体探针设计](docs/superpowers/specs/2026-10-19-phase0-carrier-design.md)。
安装见 [载体说明](docs/testing/phase0-carrier.md)。此前的 [0.2.0 十项动作测试](docs/testing/phase0-actions.md)、[动作记录](docs/reviews/2026-10-19/probe-0.2.0-actions.md) 与 [0.1.2 修复记录](docs/reviews/2026-10-19/probe-0.1.2-stairs-retirement.md) 保留为历史。

0.5.0加入 **NPC保存与恢复**，见 [集中测试](docs/testing/single-player-persistence.md)、[技术记录](docs/reviews/2026-10-19/probe-0.5.0-persistence.md)、[设计](docs/superpowers/specs/2026-10-19-sp-persistence-design.md) 和 [实施计划](docs/superpowers/plans/2026-10-19-sp-persistence.md)。正常保存时保留活人物，恢复原版人物和物品实例、驻点及意图；损坏/重复恢复失败阻塞，不承诺崩溃无损。

0.5.1 [修复基线检查误认pzopt JAR导致全部操作停用](docs/reviews/2026-10-19/probe-0.5.1-startup-fix.md)，并纠正“Java未加载”的误导提示；最新实机日志已确认启动恢复。

0.5.2 [修复样本名称误判、健康不足时开工与取消提示](docs/reviews/2026-10-19/probe-0.5.2-sample-haul-fix.md)。0.5.1日志已确认启动和一次人物/库存恢复。

此前 **0.5.3**：[筛选搬运靠近点，并将INVALID_TILE等预期拒绝记录为步骤失败](docs/reviews/2026-10-19/probe-0.5.3-approach-fix.md)。用户反馈修复成功，正常单人存取主流程通过；中途保存、同UUID/样本恢复及删除后不恢复有日志证据，第11步样本清理未确认，见[实机验收记录](docs/reviews/2026-10-19/probe-0.5.3-runtime.md)。

此前的 [0.3.0 实体容器搬运 17 步测试](docs/testing/phase0-world-haul.md)、[技术记录](docs/reviews/2026-10-19/probe-0.3.0-world-haul.md) 保留；前置动作已获 [0.2.0 实机验收](docs/reviews/2026-10-19/probe-0.2.0-runtime.md)。
搬运已有 [0.3.0 实机验收](docs/reviews/2026-10-19/probe-0.3.0-runtime.md)。用户已决定 [专注单人、保留联机口子](docs/decisions/2026-10-19-sp-first.md)；此前的 [0.4.0 随从集中测试](docs/testing/single-player-companion.md) 和 [实现记录](docs/reviews/2026-10-19/probe-0.4.0-companion.md) 继续用于回归。
最新 [0.4.0 实机反馈与证据](docs/reviews/2026-10-19/probe-0.4.0-runtime.md) 已归档。
原需求对应的 [可行性评审](docs/reviews/2026-10-18/feasibility-review.md) 保留为基线证据，不代表已覆盖 v3.1 的全部新增需求。

本目录包含独立实现的载体探针，未迁入旧模组实现。单机候选驱动的基础动作已有实机证据；多人端仅诊断并拒绝创建，完整经营系统尚未验收。



