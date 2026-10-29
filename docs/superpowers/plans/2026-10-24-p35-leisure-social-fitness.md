# P3.5 据点闲暇与双人社交实施计划

> **For agentic workers:** 按任务逐项执行与检查；当前用户要求开始P3.5，默认由当前会话原生执行，不启动子代理。技能建议的执行入口不覆盖项目禁止默认委派的约束。

**Goal:** 在现有单人多NPC内核中接通自主闲暇、原件消遣阅读与吸烟、观察/散步、徒手锻炼及双人主动邀约，保持工作优先和身体独占。

**Architecture:** 继续扩展现有SELF_CARE个人Job及微观BT，SocialCoordinator只管理双方意图和阶段；双方各自经TaskRuntime持权。公共工作增加不认领的只读探测，先安全结束闲暇再正式认领；原件继续由LaborStore/Claims裁决。

**Tech Stack:** PZ42安装版Lua/Kahlua、现有Java载体/动作桥、原版ISReadABook/ISEatFoodAction/ISFitnessAction。

**Spec:** [P3.5设计1.1](../specs/2026-10-24-p3.5-leisure-social-fitness-design.md)，从属于[NPC架构1.1](../specs/2026-10-22-npc-behavior-architecture-design.md)。

## 执行记录（0.26.0）

用户已确认计划并要求执行。任务1～5已形成运行接线并通过定向宿主验证；任务6开发检查/构建与文档已做，原生实机集中验收未运行。具体[实现证据及接口收敛](../../reviews/2026-10-24/p35-leisure-implementation.md)为实际记录；下面保留计划的细粒度核对项，不伪造“先失败再实现”的执行记录。回归使用7个P3.5用例及现有公共工作/P3/自理/家具/会话用例，不另复制工作抢占测试夹具。

- [x] 工作发现/闲暇停止分离，所有实际认领仍在原入口。
- [x] 原件消遣、吸烟与共享设施观察，复用借还/声明。
- [x] 徒手锻炼NPC修正及玩家倍速隔离，原版循环效果。
- [x] 双人唯一配对、独立Session、到位屏障、效果及取消。
- [x] 统一保存恢复接线、损坏记录校验、UNKNOWN不重放。
- [x] 0.26.0构建、Kahlua、CN/EN、完整preflight（含LuaLS）、证据与单份实机清单。
- [ ] 原生动画、真实效果、正常保存重进和规模性能验收。

## 全局约束与现状

- 单人优先，稳定npcId/jobId/socialId，身体、任务及原件声明分开；不增加工种调度器或第二资产账本。
- 闲暇不进入0～4工作矩阵，不抢工作/自理/跟随；观察未完成不等于没有工作。
- 1～3现实秒仅为发现工作并提出中断的待测目标，不包含停稳与借书归还。
- P3当前有接线及宿主证据，但完整床位/岗位/区域、实机阅读与保存尚未验收；本轮启动P3.5不补记P3通过。依赖失败必须诊断，不能当作闲暇成功。
- 仅借鉴ProjectRemnants机制；根NPCFW.jar基线见[审查](../../reviews/2026-10-24/p3.5-leisure-design-review.md)。读写当前安装Lua/JAR，技能索引只作导航。
- 不自动卸防卫武器、不点火、不自动开关门窗、不补造原件；CN/EN同步；保留混合工作区改动，不整体暂存或重置。
- 开发分步检查，向用户集中交付；原生动画、效果、正常保存和性能与替身测试分开记录。

## Review Focus

1. 活动动作使公共调度跳过NPC，导致新工作永远不能打断：任务1验证读探测不认领且可唤醒收束。
2. 双向邀约、同伴接受前已有新工作：任务4验证配对唯一、双方独立授权和取消。
3. 停止后延迟动画事件重新发经验或干预新动作：任务3验证失效attempt无权恢复currentExe或结算。
4. 保存落在社交结算/告别或部分吸烟之间：任务5验证不重发效果、不遗失原件责任。
5. 原件来源移走、配对目标失联或寻路预算耗尽：任务2/4验证保留责任、有限重试、未知等待。

## 文件职责

所有下列Lua模块位于`Contents/mods/EmberRoutesProbe/42/media/lua/`。

- 新增`shared/EmberRoutesProbe/LeisurePolicy.lua`：纯资格与活动权重/冷却判断，不读写引擎。
- 新增`shared/EmberRoutesProbe/LeisureRecord.lua`：校验个人闲暇payload及效果回执，持久化标量身份/阶段。
- 新增`client/EmberRoutesProbe/LeisureService.lua`：候选观察与既有个人服务接入，不注册独立tick。
- 新增`client/EmberRoutesProbe/LeisureActions.lua`、`LeisureFitness.lua`：观察/移动/吸烟叶与原版锻炼适配，全部经获授身体执行。
- 新增`client/EmberRoutesProbe/SocialCoordinator.lua`、`SocialActions.lua`：唯一配对及个人社交执行叶。
- 修改SelfCare、SelfCareRecord、SelfCareExecution、NeedsObserver、LibraryIndex、StudyActions、PublicWork、TaskPersistence、PersonnelService及CN/EN翻译；必要Java变更限定Driver/TaskController/ProbeRuntime/ProbeNpc的受控动作和停稳边界。
- 新增`tests/lua/p35-*-test.lua`定向测试、专题证据与单份集中实机验收。

## 任务1：闲暇候选与工作探测

**Interfaces:**

- `LeisurePolicy.allowed(kind,sample,context) -> boolean,reason`；`LeisurePolicy.choose(candidates,memory,gameHours,roll) -> candidate|nil`，roll由调用者提供。
- `LeisureService.offer(npcId,entry,workRevision,observedAt)`只接收已完成的无工作观察；`candidate(actor,binding,budget) -> candidate|nil,done,reason`。
- `PublicWork.probeIdle(actor,npcId,budget) -> READY|NONE|WAIT,revision`不认领工单、不申请身体；READY仅请求个人闲暇停止。正式认领沿用原入口。

- [ ] 写`p35-policy-test.lua`与`public-work-test.lua`：疲劳、疼痛、手持武器拒绝锻炼；冷却跨读档有效；WAIT不发闲暇；活动队列非空也可只读探测，READY不能直接开工。
- [ ] 在安装Kahlua中先运行，确认缺失接口导致预期失败。
- [ ] 接PublicWork/SelfCare分离“探测资格”和“正式认领资格”：仅闲暇可读探测，仍拒绝真实自理、携物未结和UNKNOWN；准备中的制作规划有界推进，不因闲暇放开材料认领。
- [ ] 实现共享预算、每人观察版本/时效、工作变化唤醒及活动记忆；不增加全员高频扫描。P3研习作为已有读书路径统一接受工作唤醒。
- [ ] 上述用例及现有public-work、自理恢复用例通过后记证据，不将宿主结果称为1～3秒实机达标。

## 任务2：原件消遣与观察/散步

**Interfaces:**

- `LibraryIndex.leisureUseful(npc,item) -> boolean`与共享`choose`的目的参数区分技能研习/消遣；原件资格、索引和借还仍同一套。
- `LeisureActions.new(c) -> BT leaf`消费现有执行上下文与budget；`LeisureRecord.valid(payload) -> boolean`用于SelfCareRecord验证。

- [ ] 写`p35-originals-test.lua`：普通消遣书可选而已无收益书不选；争同一本冲突；归还受阻不领无关工单；吸烟只对适用角色、真实香烟/火源、部分消费不重放；未加载/预算耗尽返回等待。
- [ ] 扩展个人记录、SELF_CARE执行叶与原件消费观察，保留P3阅读效果代理；吸烟火源纳入同次原件声明及效果核对，不绕过消耗协议。
- [ ] 观察和散步在允许据点范围产生有限目标，经body.move执行，到达后停稳；门窗只观察，原对象替换/危险变化中断。借用既有设施观察，不在每人路径中扫描整个据点。
- [ ] 增加人员可读状态及CN/EN，关闭页面不影响后台；运行定向用例和P3传阅/借还回归。

## 任务3：原版徒手锻炼适配

**Interfaces:** `LeisureFitness.new(c,exercise,minutes) -> BT leaf`；白名单squats/pushups/situp，`halt()`仅请求本尝试停止并返回是否可核对。

- [ ] 查当前ISFitnessAction/原生Fitness状态与动画转发，记录哈希；用pz ask核查方法、modscan检查目标动作替换。Java只在现有桥无法提供必要控制时修改。
- [ ] 写`p35-fitness-test.lua`：授权前不得构造动作；AI移动不误停；完成/取消后回调不发经验；currentExe仅有效尝试可恢复；双手/耐力变化停止；原生UI和setGameSpeed不得被NPC路径调用。
- [ ] 适配原版重复/经验/负担，替换玩家专属停止/完成副作用，避免全局覆写原版类或临时劫持setGameSpeed。保留构造/启动副作用与effect事实边界。
- [ ] 同时检查当前与延迟负担；读取不可靠时用保守训练上限/冷却，明确未知。停止证据包括原生锻炼/姿态，不只Lua队列为空；必要时扩充ProbeNpc.stopMask及受控桥。
- [ ] 运行锻炼与身体控制定向测试；Java有变更构建及会话回归。实机经验/酸痛/倍速列待验，不以替身通过宣称成功。

## 任务4：双人邀约与三段社交

**Interfaces:**

- `SocialCoordinator.offer(npcId,scopeId,candidates,now) -> socialId|nil`；`accept(socialId,npcId,attemptId) -> boolean`仅登记本人意图。
- `view(socialId,npcId) -> detached state|nil`；`arrived(socialId,npcId,attemptId) -> boolean`；`cancel(socialId,npcId,attemptId,reason) -> boolean`；`release(socialId,npcId,attemptId,bodyStopped) -> boolean`。
- `SocialActions.new(c,socialId) -> BT leaf`；双方各有自己的个人Job/Session，协调记录只管理配对/位置/阶段，不管身体或物品。

- [ ] 写`p35-social-test.lua`：A邀B与B邀A同时只成一对；第三人拒绝；一方接受前工作变化取消；一方停止异常不冻结另一方；旧参与代次不能取消新会话。
- [ ] 限候选与寻路预算，选择同层可达、无遮挡、不堵门站位；35现实秒超时、最多3次尝试作为参考初值，预算不足不记失败。到位/视线通过后才开始游戏时长。
- [ ] 各自Session下移动、朝向和已核实手势/气泡；动画3现实秒超时触发受控停止与诊断，不直接交权。取消后禁止旧派发，身体各自停止确认。
- [ ] 写入每人socialId效果标识：目标时长前取消不给完整收益；结算后可选告别，中断不重发。新配对不得与旧未核对身体/效果重叠。
- [ ] 运行配对用例及Runtime双NPC独占回归；无同伴时允许独处/待命，不持续重试。

## 任务5：保存恢复与跨活动收束

**Interfaces:** `LeisureService.prepareRecovery(receipt) -> true|false`接现有prepareCareRecovery链；不另注册引擎保存事件。SocialCoordinator运行索引按当前世界身份重建。

- [ ] 写`p35-save-test.lua`覆盖：交流中保存取消，结算/告别边界不重复，部分吸烟/借书原件继续核对，锻炼已发效果不重放，原生OnSave无后续tick仍保留事实。
- [ ] 通过TaskPersistence统一屏障取消/捕获，读档不恢复半段对话与原生动作队列；未知效果隔离、不自动重试发奖，原件义务不因闲暇结束清空。
- [ ] 更新Record验证与版本兼容：既有P2/P3个人记录正常读取，新闲暇格式拒绝损坏数据且保留原数据；不扩张旧任务迁移范围。
- [ ] 运行保存、Resume、当前P3借书/跟随恢复定向回归，核查停止超时及玩家命令不会被恢复逻辑覆盖。

## 任务6：集中交付与证据

- [ ] Lua修改跑`node ../.workbuddy/tools/pz.mjs preflight Contents/mods/EmberRoutesProbe`，保存完整输出、处理新命中；Java修改运行`./tools/build-probe.ps1`及相关会话检查。
- [ ] 定向Kahlua命令：`java --class-path 'D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/*' tests/java/KahluaLaborTest.java p35-policy-test.lua public-work-test.lua p35-originals-test.lua p35-fitness-test.lua p35-social-test.lua p35-save-test.lua`；期望各文件PASS，原生host mocked单独注明。
- [ ] CN/EN运行人员UI相关宿主验证；新增正常状态都可读，不用机器ID代替产品状态。
- [ ] 建立testing目录下的P3.5集中验收文档（实施收口时新增）单份场景：无活生活→双人社交/锻炼→工单与自理中断→原件归还→保存重进，附实际可运行条件。未运行保持未验证。
- [ ] 更新版本/构建产物采用仓库现有交付流程，版本号从当时工作区确定；不发布工坊，不整体提交混合修改。
- [ ] 记录reviews对应日期目录下的P3.5实现证据（实施时新增），原位更新BACKLOG与INDEX，doclink检查；报告具体已接、未接、静态/宿主/实机边界。

## 计划审查结论

设计各节映射任务1～6；原版接口在任务3查证，原件与保存单列用例；没有以原型失败为理由预先删功能。最高风险是公共工作发现与闲暇占用互锁，应先完成任务1再开活动入口。P2/P3未验收仍保留，不在本计划中虚报完成。
