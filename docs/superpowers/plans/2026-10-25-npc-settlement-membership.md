# 显式据点归属与驻扎运行接线 Implementation Plan

> 执行记录：用户审阅准备后明确“开始吧”，由本会话主代理直接原位实施；0.27.0开发接线完成，25份定向宿主及CN/EN UI宿主通过，真实游戏/故障/规模性能未验证。[实际证据与闲暇交接](../../reviews/2026-10-25/npc-settlement-membership.md)是执行结果；下方步骤保留原计划，不将未实际执行的红测或实机勾为完成。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用持久化据点身份和明确命令驱动NPC生活，经统一控制器安全交接，并交付闲暇侧可直接消费的稳定资格接口。

**Architecture:** MembershipService唯一维护成员事实与命令意图，纯策略处理按用途资格，运行适配器复用TaskRuntime与既有恢复责任。原Companion只承担获授权的移动/跟随执行，不再以HOLD定义业务身份。驻扎侧负责现有消费者资格接线和失效保护；不改变闲暇发现顺序、选择权重、冷却、坐姿或社交表现。

**Tech Stack:** PZ B42.21.0、Kahlua Lua、现有Java控制桥接、GlobalModData及当前宿主测试运行器。

**Spec:** [显式据点归属设计1.0](../specs/2026-10-25-npc-settlement-membership-design.md)，上位[NPC架构1.2](../specs/2026-10-22-npc-behavior-architecture-design.md)。

## Global Constraints

- 当前单人本地世界执行者唯一裁决；稳定npcId、factionId、settlementId，不用玩家槽位作为长期身份。
- 不兼容旧档，不编写旧FOLLOW/HOLD/RETURNING迁移器；当前新格式正常保存恢复必须支持；拒绝旧格式不删除原数据或世界原件。
- context固定SETTLEMENT/FOLLOW/WAIT/RETURN，命令固定SETTLE/FOLLOW/WAIT/RETURN/TRANSFER/UNASSIGN；函数签名与资格原因以设计§2.1为准。
- 普通候选失效不能删除借书、携货、未知效果或设施责任；身体停止核验完成后再授权，旧效果仍归原事实。
- 不自动传送；返回点缺失、未加载、不可达时明确等待并有界退避。完整解散/游荡者行为不在本次交付。
- 不启用子代理，不向另一聊天发送消息；工作区存在大量既有混合改动，只原位改本范围，不整体提交其他人的文件内容。
- CN/EN成对；修改Lua跑preflight，Java若有改动则构建及相关验证，文档跑doclink。宿主通过不等于实机通过。

## Review Focus

1. 新建世界、加载当前格式、旧世界缺标记三者不能混同；Task 1钉住旧档拒绝与新NPC登记。
2. pending接受到正式提交之间仍显示旧归属，但旧offer必须立即失效；Task 2/3覆盖延迟停止与旧邀请启动。
3. 玩家离开据点或死亡不能使所有居民丢失资格；Task 1/4覆盖NPC与玩家位置分离及角色生命周期。
4. Job.obligations为空不一定证明没有旧物流/制作/原件责任；Task 2汇总各现有账本并保守保留未知，不重复建账。
5. 新命令后恢复旧自理前驱、迟到到达回调、同坐标替换目标都可能越权；Task 2/4覆盖版本/原对象/角色代次。

---

## 文件职责

- 新建 `Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/MembershipPolicy.lua`：无引擎副作用的资格判定。
- 新建 `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/MembershipService.lua`：store/版本/命令/只读投影与定向失效。
- 新建同目录 `MembershipRuntime.lua`：pending推进、现有责任读取及身体交接；`MembershipReturn.lua`：返回点执行适配/观察/退避；`MembershipLifecycle.lua`：新档、角色与NPC生命周期及清理。
- 修改同目录 `Companion.lua`、`CompanionAgent.lua`、`NpcCommands.lua`、`TaskResume.lua`、`TaskPersistence.lua`、`SettlementLedger.lua`、`Driver.lua`：运行、恢复及权限边界。Driver/Java只在当前桥接缺失时做已查证的最小补充。
- 修改同目录 `PublicWork.lua`、`LogisticsService.lua`、`SelfCare.lua`、`SelfCareResources.lua`、`SelfCareFurniture.lua`、`SelfCareRepose.lua`、`StudyService.lua`、`LibraryIndex.lua`、`LeisureService.lua`、`SocialCoordinator.lua`：消费者资格与旧候选失效，不重构活动策略。
- 修改同目录 `PersonnelService.lua`、`OrderMonitorService.lua`、`UI/PersonnelPage.lua`、`SettlementMenu.lua`及上一级 `EmberRoutesProbe.lua`：可玩命令入口与投影。
- 修改 `Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Boot.lua`：安装、共享tick/预算、保存及跨世界清理。
- 修改 `Contents/mods/EmberRoutesProbe/42/media/lua/shared/Translate/CN/IG_UI.json`、对应EN文件、`version.txt`、`Contents/mods/EmberRoutesProbe/42/mod.info`及 `shared/EmberRoutesProbe/Build.lua`：文案和一致版本。实施交付前读取当时版本，递增一次，不预占另一会话版本号。
- 新建 `tests/lua/membership-policy-test.lua`、`membership-command-test.lua`、`membership-consumers-test.lua`、`membership-save-lifecycle-test.lua`；相关既有夹具显式初始化新契约，禁止生产代码隐式退回HOLD。

### Task 1: 成员模型、资格与新档边界

**Interfaces**

- Produces: `MembershipPolicy.evaluate(row,entry,purpose,observation,expectedRevision) -> eligibilityDTO`，无世界修改。
- Produces: `MembershipService.view(npcId)`、`check(npcId,purpose,observation,expectedRevision)`、`entry(npcId,scopeId)`，精确返回字段见设计§2.1。
- Internal: `MembershipLifecycle.newWorld()`、`register(npcId)`、`load()`，只有新世界创建事实可以建立格式标记；旧世界拒绝自动补标记。
- Storage: `ContainerRegistry.data().npcMembership={format=1,byNpc=...}`；成员索引只在内存重建，format未知保留并拒绝加载。

- [ ] 在membership-policy-test.lua加入：SETTLEMENT/圈内同据点可WORK/LEISURE/STUDY；FOLLOW/WAIT不可；SELF_CARE/RECOVERY不被宏观门禁一概拒绝；重叠区域不改籍；旧revision为STALE_MEMBERSHIP；返回点/阵营/圈外原因不混同。
- [ ] 在membership-save-lifecycle-test.lua加入：新档显式创建、旧世界已有NPC/任务且无标记拒绝、加载未知format保留表、当前格式重进不根据位置改籍；断言初始化的context为WAIT且settlementId为空。
- [ ] 运行新增文件，确认先因模块缺失失败，再实现模型、纯策略和生命周期入口；查当前原版事件定义/真实注册点后接新世界及角色事件，不猜事件签名。
- [ ] 新增内部NPC授权读取路径，核验factionId/settlementId，保持玩家Ledger.view位置权限；测试玩家在圈外、NPC在圈内仍可生活。
- [ ] 运行Task 1两个文件为PASS；验证读取DTO不能修改持久化行，scopeAt不再参与身份推导。

### Task 2: 命令交接、返回与责任

**Interfaces**

- Consumes: Task 1契约、`TaskRuntime.current():stop/status/owns/submit`、`TaskJobs.current():forNpc`及既有业务责任记录。
- Produces: `MembershipService.request(actor,npcId,command)`、`cancel(actor,npcId,requestId,expectedRevision)`、`setReturnPoint(actor,settlementId,point,expectedEntryRevision)`。
- Internal: `MembershipRuntime.tick()`在同一服务调度中推进，`obligations(npcId)`生成只读义务明细；实施中返回适配细化为`MembershipReturn.start(actor,binding,member)`，只在身体空闲/宏观context允许时向既有TaskRuntime提交MEMBERSHIP_RETURN，个人自理仍通过原接口抢占；不另建身体拥有者或任务线程。
- Notification: 成员revision改变发送现有LaborSignals.changed(npcId)，定向撤销Study/Leisure offer和旧社交邀请；不能为失效缓存直接释放原件声明。

- [ ] membership-command-test.lua加入SETTLE、FOLLOW、WAIT、RETURN、TRANSFER、UNASSIGN及cancel；断言跟随不改籍、旧责任未结时调驻保持原归属并显示书/货物/未知明细、重复请求不再次停止或提交、过期revision拒绝。
- [ ] 加入同步停止重入、身体未停、身体已停但效果未知、同tick替换pending、旧返回回调到达测试；断言不启动第二身体拥有者，过期事件不改新context。
- [ ] 验证测试初次失败；实现命令校验、revision规则、停止/事实保存/正式提交，汇总Job与既有物流/制作/自理原件责任，不只检查一个obligations表。
- [ ] 返回点保存进SettlementLedger条目并提升revision，get副本包含标量点及版本；返回适配复用已有body.move/stop协议，目标加载/可站立及实际到达独立重验。缺失/未加载/不可达均不传送、不静默切WAIT，有界退避复用现有预算。
- [ ] 测试显式RETURN成功转SETTLEMENT，圈外SETTLEMENT返回候选完成不改变context；取消/新命令后旧到达不生效。以上文件运行PASS。

### Task 3: 统一消费者与玩家入口

**Interfaces**

- Consumes: Task 1/2全部公共函数；现有消费者仍负责身体、健康、库存和资源校验。
- Produces: Leisure/Study offer及Social广告携带`membershipRevision`、`settlementId`，执行前按check重验；新 `LeisureService.invalidate(npcId,reason)`只撤旧offer/邀请，身体停止由统一命令交接处理。
- UI: 人员页/监控同一成员DTO，显示所属/命令/真实活动/具体等待义务；六类命令和返回点设置进入普通产品入口。

- [ ] membership-consumers-test.lua覆盖WORK/LEISURE/STUDY相同归属判定、WAIT/FOLLOW紧急自理、借书后换命令先处理归还、玩家远离不阻断居民；与两据点/重叠区同时运行，断言不串资源。
- [ ] 加入旧社交邀请在命令接受后不能accept/start、pending停止期间不产生普通offer、清offer不删借书声明测试；先验证失败，再接五类HOLD业务检查以及现有设施/资源发现入口。
- [ ] SelfCare/TaskResume恢复前驱核对成员revision；新命令后不能恢复旧FOLLOW意图，归还责任仍可运行。不能用SELF_CARE宏观allow绕过真实资源权限。
- [ ] UI与轮盘统一“驻扎/跟随/等待/返回/调驻/解除”，普通设家入口改为据点返回点；人员名单按归属而非站位筛选，未分配NPC仍有可达管理入口，不因人员页scope隐藏新NPC。
- [ ] 添加成对CN/EN文本及已有IDLE原因链；已有动作选择、权重、姿态和社交表现保持原行为。相关p35/研习/自理测试夹具显式建立新成员条件，然后运行消费者与相关最小宿主回归PASS。

### Task 4: 保存、生命周期、集中交付

**Interfaces**

- Consumes: 前三项契约、TaskPersistence现有屏障、NpcCommands移除及Boot共享服务生命周期。
- Produces: 当前格式重进恢复成员/意图/责任、角色更替不丢阵营权限、失效FOLLOW目标停止并转RETURN或WAIT；结清成员可回收、未知责任保留。
- Existing engine calls: 新事件及角色身份读写先用项目pz工具核实；如果Lua不能可靠识别角色生命周期，则在Driver/当前Java桥接增加经验证的标量身份，不退回玩家槽位/名称。

- [ ] membership-save-lifecycle-test.lua加入pending/停止中/返回中/借书调驻中保存重进；assert只恢复一次、责任先于身体、不重放消费、不按底层HOLD改context。
- [ ] 加入玩家死亡和换角色、目标临时未加载、迟到死亡事件、NPC确认死亡/移除以及短时载体缺失测试：前两类失效FOLLOW不自动跟新角色，临时缺失不按死亡清成员；未知责任行保留，结清后才回收。
- [ ] 实现保存/加载/撤销与生命周期接线；Boot共享预算推进、跨世界缓存清理和事件安装幂等；旧档拒绝恢复不删除其物理世界。
- [ ] 运行下列定向宿主、CN/EN UI、preflight；如新增Java运行构建与相应桥接测试。只在新失败/新增变更相关时扩展回归范围。
- [ ] 递增并核对版本，补齐两份待建文档：`docs/reviews/2026-10-25/npc-settlement-membership.md`记录代码/检查/未验证边界，`docs/testing/membership-runtime-acceptance.md`提供集中单人验收；原位更新BACKLOG及导航。现有缺料WAITING/workReady循环保留独立问题，不标修复。
- [ ] 提供闲暇侧交接：设计§2.1接口、实际调用点、新offer/邀请失效路径、验证结果及返回/角色继承的未验证项。向用户交付一次完整流程，实机与性能未运行均明确标注。

## 验证命令

新增测试的红/绿均用已安装Kahlua运行器；当前原版JAR基线见build-probe.ps1，测试native host为替身，不等于游戏。

```powershell
java --class-path 'D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/*' tests/java/KahluaLaborTest.java membership-policy-test.lua membership-command-test.lua membership-consumers-test.lua membership-save-lifecycle-test.lua
pwsh -NoProfile -File tools/test-ui-kahlua.ps1 -Language CN
pwsh -NoProfile -File tools/test-ui-kahlua.ps1 -Language EN
node ../.workbuddy/tools/pz.mjs preflight Contents/mods/EmberRoutesProbe
```

预期：四个新文件与受影响的最小原有宿主文件PASS；中文/英文UI宿主通过；preflight无本次新增缺陷。已有不相关失败保留原始输出、说明基线，不以大范围修改掩盖。性能沿BACKLOG P1的固定场景1/5/10/20 NPC，单次尖峰与累计ms/秒分别记录，不另立标准。

## 计划自审与执行门禁

设计§1/2→Task 1，§3/5/6→Task 2，§4/8→Task 3，§7/9→Task 4；四不变量与五项Review Focus均有明确场景。没有旧档迁移切片，也没有闲暇策略重构切片。运行适配不能凭“提交停止”当作已停；归属查询不能取代动作级校验。

本会话由主代理原位执行；未获子代理授权，不自动创建其他聊天或发送消息。writing-plans要求“review the plan … before implementation”；计划已给用户审阅，用户随后明确“开始吧”，按本会话直接执行。所提superpowers执行技能当前技能目录未检索到，未假称加载，依用户明确指令使用现有工具实施并记录验证；没有安装技能或启用代理。共享文件包含既有改动，未把这些文件整体提交冒充本轮独立提交。
