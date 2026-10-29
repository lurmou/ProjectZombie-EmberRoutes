# 显式驻扎模型：0.27.0开发接线与闲暇交接

> 日期：2026-10-25｜工作区混合修改，保留其他会话内容｜单人开发验证；游戏实测、强退恢复与规模性能未验证。
> 设计：[成员归属1.0](../../superpowers/specs/2026-10-25-npc-settlement-membership-design.md)，上位：[NPC架构1.2](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)。

## 1. 基线与已接内容

version.txt/mod.info/Lua Build为0.27.0；Java构建重新生成同版BuildInfo。安装JAR基线继续固定：projectzomboid.jar SHA256 `E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`，ZombieBuddy.jar SHA256 `EB79B9876332010733A8E0D7CE4FE0377846059A9E28859029E2A0FB449F6CF2`。包和Java产物哈希以本地build/probe-build.json为准，不用版本号代替实机证据。

本轮在线版仍未重新同步，沿用用户授权的v3.3快照SHA `6CEF0B267016E0DA3E6A61CB4F4EC6D5D781FC4D0DBC89642CD64CB2602D98F8`与明确决定。不兼容旧档，不创建旧状态转换器，不清理旧世界或原件。

- MembershipPolicy/MembershipService：持久化factionId/settlementId、SETTLEMENT/FOLLOW/WAIT/RETURN、revision、pending和最多128条技术回执；读取副本和按据点可重建成员索引。store为ContainerRegistry.data().npcMembership，format=1。
- MembershipRuntime/MembershipReturn：统一任务控制器内交接；返回是MEMBERSHIP_RETURN Session，35秒单次看门狗、失败至少5秒退避；返回点按据点/点版本重验。驻扎圈外的移动不改宏观context，显式RETURN到达才转SETTLEMENT。
- MembershipLifecycle：仅OnInitGlobalModData(isNewGame=true)初始化新世界；OnNewGame只绑定角色身份。当前格式加载先核对成员再恢复任务；旧格式/无标记世界拒绝启用，保留原数据。
- 身份失效：FOLLOW绑定玩家角色ModData中的标量UUID，死亡或换角色不丢阵营/据点、不继承旧跟随目标。有归属转RETURN，否则WAIT；目标临时缺失与确认死亡分开处理。
- 命令接受即停止旧普通派发并失效offer/邀请，身体仍按现有停止证据交接；调驻/解除归属等待旧义务。可观察时显示未还物品/货物/效果核对，原件未结不删除。
- 已停止载体可以带着保留/未知原件向原据点移动；不会以未知结果重放生产或释放声明。驻扎恢复会先尝试原制作/搬运责任，不能让WAIT→驻扎后永久卡在暂停记录。
- 人员、详情和监控显示归属/宏观命令/原活动；普通“设家”归并为据点返回点，产品“返回”走所属据点；低层锚点仅保留在诊断适配器中。

## 2. 调用点与职责边界

工作：PublicWork.eligible及LogisticsService的新认领不再读HOLD；Production与WorkAgent在身体授权前再次核验新普通任务的成员revision。已有任务恢复不套用新单门禁。CraftSupply按受管NPC归属读内部权限，已持原件恢复可在圈外启动；玩家据点编辑的Ledger.view位置权限保留。

生活：SelfCare、SelfCareResources和ReposeSites消费同一成员来源。SELF_CARE.allowed表示宏观自救门禁，sharedResources单独表示可使用所属据点资源；WAIT圈内仍可必要吃喝，FOLLOW/RETURN优先随身资源。闲暇/研习另外检查LEISURE/STUDY，不能把共享自理资格当成可以闲逛。借书归还的settle不因新研习资格失效而永久转为“只等待紧急需求”。

闲暇/研习：LeisureService/StudyService的offer和候选保存成员revision与据点revision；SelfCare写入Job.payload的membershipRevision/settlementRevision，启动及继续执行重验。SocialCoordinator广告/配对保存逐人成员revision，accept/view/arrive均拒绝旧身份邀请；invalidate仅撤候选和邀请，已获资源等真实停止后释放。

清理：确认死亡/显式移除退出活动成员；未结责任保留，身体/原件/恢复关系结清后有界回收成员行。JobStore.visitNpc复用现有逐NPC索引，只读遍历，不为每个成员扫完整Job表或复制整份payload。

玩家权限继承目前限本地世界的稳定factionId与新角色授权，不能宣称实现MP账户继承。完整据点解散（标签注销、游荡者流转）、宏观离线生活和闲暇策略重构均未在本轮实现。

## 3. 给闲暇侧的固定接口

入口为client/EmberRoutesProbe/MembershipService.lua；详细签名见设计§2.1。

| 消费接口 | 注意事项 |
|---|---|
| view(npcId) | 副本含settlementId、settlementName、context、revision、pending、reason、obligations；pending时正式归属/命令仍读旧值 |
| check(npcId,purpose,observation,expectedRevision) | observation使用NPC x/y/z，可带scopeId；候选必须传采样revision。返回allowed/reason/revision/settlementId/context/entryRevision；SELF_CARE/RECOVERY另有sharedResources |
| entry(npcId,scopeId) | 内部只读条目，不检查玩家是否站在基地；不能直接修改或交给UI |
| members(settlementId) | 分据点的稳定ID副本；nil为未分配，不包括retired成员，不能据此假定实体已加载 |
| request/cancel/setReturnPoint | 通过命令入口，不直接写store或Companion运动模式 |

候选携带membershipRevision与settlementRevision；读到STALE_MEMBERSHIP、COMMAND_PENDING、CONTEXT_WAIT/FOLLOW/RETURN、NO_MEMBERSHIP、TARGET_LOST、ACCESS_DENIED、OUTSIDE_SETTLEMENT时给出对应原因，不统一吞为NO_OFFER。位置变化不必提升成员revision，启动仍须读最新位置；据点/返回点版本另外检查。

本轮只改资格、候选版本和撤销接线。固定链序、发现阻塞、选择、冷却退避、坐姿及社交表现保持既有策略，交给后续闲暇工作。缺料WAITING工单的workReady循环仍独立保留，不记作由B解决。未向另一聊天发送消息。

## 4. 原版接口查证与修正

- 项目pz工具查询并核对原版ProfessionVehicles.lua中的OnInitGlobalModData(isNewGame)注册；该参数来自引擎的新世界事实，不用OnNewGame推断。
- 角色getModData用法核对安装版XpUpdate.lua；角色UUID为标量，运行时actor/handle不入成员档。
- 当前JAR的javap确认IsoGameCharacter.OnDeath触发OnCharacterDeath；IsoPlayer的OnPlayerDeath仅在local player分支触发，不能替代受管NPC死亡事件。
- 旧carrierId调用carrierPresent，死亡后返回空串；新增ProbeRuntime.ownedCarrierId仅在当前世界、同线程本地权威与实际owned body匹配时返回稳定ID。该接口不授予移动/库存权限；Boot要求同版桥接存在。

## 5. 验证与限制

开发侧：6份新增驻扎宿主文件覆盖纯资格、命令/取消/回执上限、旧邀请、生命周期事件/旧档拒绝、返回执行/借书调驻及返回点版本/物理检查。初始红测为模型/命令模块不存在，其余为实现过程的定向补测；不伪称每份测试都先红后绿。

集中运行25份Kahlua宿主文件，包含上述6份及JobStore、控制器、运行器、激活、自理、研习、金样本、社交、共享选床/家具执行/坐姿、实际制作适配、搬运、监控与统一保存。原先依赖HOLD的夹具显式建立新成员契约；旧移动/锚点诊断夹具显式调用debug适配器，不在生产增加身份推导回退。boot-pause旧夹具同时对齐已有EvenPaused每三次render派发一次的事实，未改该生产节流器。

检查输出留在本地build/logs：membership-kahlua.txt、membership-ui-CN.txt、membership-ui-EN.txt、membership-preflight-final-stable.txt、membership-build.txt；构建报告为build/probe-build.json。preflight保留类型/动态字段warning和原版ISFluidEmptyAction中0.0f解析盲区，不宣称无warning。最终结果以本节末的交付记录为准。

收尾补验：监控卡片缓存签名加入成员revision/context/据点名/原因，命令变化即使未改变底层bodyMode也会刷新；membership-consumers定向回归通过。release-check为0 error、76条硬编码中文提示（现有混合UI内容），未擅自重构这些页面。整工作区git diff --check还命中混合改动的大量“indent with spaces”配置提示，未全量重排；本轮主要接线文件按trailing-space/space-before-tab规则定向检查通过，保留LF/CRLF提示。

未验证：游戏中的新建世界事件顺序、真实多NPC寻路/跨层、身体停止/借书归还效果、NPC死亡与玩家重生继承、正常磁盘保存重进、强退一致性、真实UI绘制与控制器输入、1/5/10/20 NPC固定负载性能。宿主通过不能替代这些验收，不承诺零损失、MP或规模容量。

集中游戏操作见[单份驻扎验收](../../testing/membership-runtime-acceptance.md)。

### 最终交付核验

- 25份定向Kahlua宿主文件全部PASS；监控缓存补验PASS；CN/EN UI宿主PASS。均不运行真实游戏世界。
- 最终稳定源码preflight全部通过；LuaLS为0 Error / 330 Warning，告警未逐条结清，不将0 Error解释成零缺陷。新鲜度10项通过；无EOL目录的check_health按工具规则跳过。
- 0.27.0构建BUILD_OK；release-check 0 error / 76提示；7份相关文档doclink无断链。
- 包为build/packages/EmberRoutesProbe-0.27.0.zip，SHA256 `E6EBEB323AE33288E0AD8F9B2D601450A8713DB8F0FBB7E5CEA303F51FEC7710`；扩展JAR SHA256 `B56F7B8AB27A9BEB095436F023B7486B75236CC9E4DDD1F1497E02654370B1B6`。包内7份成员模块及监控卡片文件与当前源码逐字节哈希一致。
- 代码仍处于用户原有混合工作区，未整体提交其他会话改动；没有发布工坊、替换用户存档、启动游戏或向其他聊天发送消息。
