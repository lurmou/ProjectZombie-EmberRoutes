# 原版木叉制作原型实施计划

> 2026-10-21｜实施完成；实机待验｜用户已要求主代理直接实施；不派生子代理。按本计划在当前会话执行。

**Goal:** 提供可实测的单件木叉诊断链路，验证NPC调用B42原版制作、工具原件及中断/保存边界。

**Architecture:** 玩家在实际砧板附近显式提供自己主背包中的原件；同NPC通过原版转移动作接收、制作、归还。原型按npcId保存标量记录，并接入Work共享调度和暂停/删除门禁。完整生产父单、共享仓储锁料和BOM待原型通过后实施。

**Tech Stack:** PZ42.21.0 Lua/Kahlua，ZombieBuddy2.3.4现有ProbeNpc，ISHandcraftAction与ISInventoryTransferAction。

**Spec:** [已讨论设计](../specs/2026-10-21-commissioned-crafting-design.md)、[原版证据](../../reviews/2026-10-21/commissioned-crafting-review.md)。用户2026-10-21明确开始下一步实施。

## Global Constraints

- 主代理独立实施；SP优先；不占真实玩家槽位，不造材料、不升级技能、不自动教授。
- 玩家知识、NPC独立知识与实际技能、真实砧板均需通过；传授独立显式命令。
- 原型只使用玩家/NPC主背包中的原件，局部有界查询；不接私人世界容器或远程扣料。
- 只在Debug诊断菜单暴露；使用原生动作，不全局替换原版类；工作台释放只清自己的占用。
- 保存暂停、过期动作隔离；不确定提交阻断重放；不宣称崩溃无损。

## Review Focus

1. 取消双回调/重复perform：单件效果只允许一次，完成凭资产核对。
2. 原料/刀具被移动或换成同类：核对原件ID、实例、位置及实际IO集合。
3. 占台冲突和权限/知识/技能变化：效果前再次核验，拒绝后无消耗。
4. 消耗后异常/产物落地：保留输出ID与待核对记录，不自动再做。
5. 运行/暂停/重进时抢工人或删除载体：共享Work门禁覆盖持货，保存后只显式归还，不自动重放。

## Task 1：配方适配与原件核对

**Files:** 新建`CraftRecipeAdapter.lua`（client/EmberRoutesProbe，下同）；新建`tests/lua/craft-probe-test.lua`。

**Interfaces:** `Adapter.inspect(actor,npc,object,requireKnowledge)`返回已核验recipe/bench/IO或原因；`Adapter.select(actor,npc,spec,owner)`选择一件SmallHandle和一把原生输入可用刀；`Adapter.manual(spec,material,tool)`构建真实IO索引映射；`Adapter.applied(logic,material,tool)`核对最终输入。

- [x] 定向逻辑夹具先验证技能、知识、IO和占台拒绝，不运行历史全套。
- [x] 核对当前JAR签名/原版调用后实现适配器；限制玩家主背包扫描，固定单件白名单。

## Task 2：可暂停的原版动作链路

**Files:** 新建`CraftProbe.lua`；修改`Work.lua`、`DebugMenu.lua`及CN/EN `IG_UI.json`。

**Interfaces:** Work新增`registerExecutor(kind,hooks)`与`wake(npcId)`，hooks提供busy/retains/pause/pauseAll/tick/reset；CraftProbe提供execute(actor,command,object)、按npcId的记录和执行上下文。

- [x] 接收原料/刀具→一次原生制作→归还产物/工具，所有转移用原版TA；保存仅标量原件ID和单件结果，不存userdata。
- [x] 原版performRecipe前守卫并标COMMITTING；实际消耗/工具/产物核对后才确认，取消/异常/旧代次不误结算。
- [x] 原型动作接Work现有全局预算；启动暂停竞争行为，运行和待归还阶段阻挡物流接单/载体删除。暂停/保存清自有队列，重进仅显式归还，不自动执行制作。
- [x] 入口仅Debug：显式传授、试制一件、归还/报告/停止；无额外正式产品菜单。
- [x] 定向Kahlua检查覆盖Review Focus五项，并跑相关多工人调度回归。

## Task 3：版本与交付

**Files:** 版本生成文件、HANDOFF/BACKLOG、版本证据及简短实测说明。

- [x] Lua preflight（含结构/翻译/类型）与文档链接检查；必要构建保证版本/JAR/包一致。
- [x] 记录实际执行的检查及未实机验证边界；本地交付0.17.0，不发布工坊，不提交整个未跟踪仓库。
- [x] 集中实测说明只保留正常制作、取消/占台、保存重进三组必要操作；完整BOM与仓储生产锁料不记完成。

## 执行结果

原型已实现，新增定向合同检查69项通过，相关多工人/物流进度回归通过。必要门禁、版本构建与包一致性收尾结果见[0.17.0证据](../../reviews/2026-10-21/probe-0.17.0-native-crafting.md)。游戏引擎未启动，三组实机由用户后续确认；没有实施完整生产父单或BOM。
