# A3/A4 活动框架：参考源码评审

日期：2026-10-28。状态：静态源码/字节码评审完成；设计建议待用户确认，未实施、未运行参考项目或游戏。目的：为 A3 多人活动协调与 A4 出席仲裁提供可追溯依据，不建立平行需求。

后续决定：用户在本评审后明确选择“指定名单安全收束普通工作后参加”；已落实到[从属设计草案0.1](../../superpowers/specs/2026-10-28-a3-a4-community-activities-design.md)。下文“政策尚待选择”为评审时截点，不覆盖此决定；其他未批准玩法见草案§17。

## 1. 范围与证据等级

- 在线唯一需求 v4.0 已在本次设计会话通过 Drive 读取，§4.5要求活动注册、组织者、手动/定时发起、到场与完成度；工作停稳和责任结清后参加。出席政策中“指定名单是否压过普通工作”仍未得到明确选择，不把笼统“可以”视为确认。
- 环世界本体：本机已检查的 `D:/Software/GameApp/steam/steamapps/common` 无 RimWorld 目录；不代表其他磁盘不存在。第三方本体反编译仓库 Chillu1/RimWorldDecompiled 的 GitHub API 返回 HTTP 451，未继续获取。没有审查本体 LordJob_Ritual 完整实现，不能声称已验证其全部状态机。
- CustomRitualFramework（作者公开模组源码，下称 CRF）：固定提交 `6520449248e3b4af0632b3f35d416fa4ff681d5d`。读了 1.5 XML 示例及角色、行为工厂、阶段触发、搬运/进食和结算扩展代码。它证明扩展层实际写法，不证明 RimWorld 本体内部行为，也不因项目名称判断成熟度。
- Temporal TypeScript SDK：固定提交 `8b53edd8c5ced2338ecd8b83739431308d650101`。读了 CancellationScope、工作流派发、活动取消选项及取消示例。本轮范围是 TypeScript SDK 的取消链，不含 Rust Core、服务端或端到端持久化保证。
- ProjectRemnants：以当前根目录 `D:/Project/ProjectRemnants/NPCFW.jar` 为准，SHA256 `5229EB5A6871514DE274FEB91E8DB353FDBDE8FB42FD9741493D40CDE85BA19E`。先用 `_decompiled/src` 导航，再用 `javap -c -p` 核对 SafehouseSocialSystem 的 begin、tickApproach、tickConversation、prepareForSave、finish。Lua 手势桥已读。仅覆盖双人社交相关分支。
- Unreal Smart Objects：只有官方说明与 API 文档，未取得并审阅引擎实现源码；本轮不列为源码级验证对象。

## 2. 环世界模组：可吸收的结构

[CRF 完整 XML 示例](https://github.com/thesePeople/CustomRitualFramework/blob/6520449248e3b4af0632b3f35d416fa4ff681d5d/1.5/Defs/Custom_Ritual_Example.xml)把活动可用性、角色、阶段职责和质量因素分开。角色声明 required、substitutable、maxCount、countsAsParticipant；阶段可以为不同角色分配不同 duty 和位置策略，质量使用独立因素组合。

[行为工厂](https://github.com/thesePeople/CustomRitualFramework/blob/6520449248e3b4af0632b3f35d416fa4ff681d5d/Source/TPRitualAttachableOutcomes/TPRitualAttachableOutcomes/ModExtensions/RitualBehaviorWorker_Speech_Custom.cs)从 speaker 角色分配取得实际主持者，再构造 LordJob_Joinable_Speech；不是简单沿用传入 organizer。[角色资格实现](https://github.com/thesePeople/CustomRitualFramework/blob/6520449248e3b4af0632b3f35d416fa4ff681d5d/Source/TPRitualAttachableOutcomes/TPRitualAttachableOutcomes/RitualRoles/RitualRoleNonSlaveColonist.cs)返回资格及可显示原因。[结算扩展](https://github.com/thesePeople/CustomRitualFramework/blob/6520449248e3b4af0632b3f35d416fa4ff681d5d/Source/TPRitualAttachableOutcomes/TPRitualAttachableOutcomes/RitualOutcomes/RitualOutcomeEffectWorker_FromQuality_Custom.cs)接收 totalPresence、活动实例和 outcome，再交给额外效果处理。

设计建议：分开发起者、组织者和执行角色；资格返回原因；质量计算读取实例参与事实。以上是本项目推导，未直接沿用 RimWorld 类型或数值。

## 3. CRF 不能照搬的实现

| 源码事实 | 限制与风险 | A3/A4 建议 |
|---|---|---|
| [ActionsComplete](https://github.com/thesePeople/CustomRitualFramework/blob/6520449248e3b4af0632b3f35d416fa4ff681d5d/Source/TPRitualAttachableOutcomes/TPRitualAttachableOutcomes/RitualStages/StageEndTrigger_ActionsComplete.cs) 返回的谓词恒为 true | 此类不检查异步动作是否完成；不能仅凭类名把它当完成屏障 | 每个必需动作取得匹配实例/阶段/参与代次的结果；缺回执不得成功 |
| [交付或超时触发器](https://github.com/thesePeople/CustomRitualFramework/blob/6520449248e3b4af0632b3f35d416fa4ff681d5d/Source/TPRitualAttachableOutcomes/TPRitualAttachableOutcomes/RitualStages/StageEndTrigger_ThingDeliveredOrTimeout.cs)在物资足量和计时耗尽时均返回 true | 结束本阶段不等于交付成功；调用方必须另判结果 | 阶段结果至少分成功、超时、失败、取消，禁止用同一布尔值承担全部语义 |
| 同一触发器缓存 curAmount，通过 checkThings 通知重扫 | 有事件唤醒思想，但本文件不能证明覆盖玩家拿走物品等全部变化 | 事件唤醒+预算内复验；真正提交时重新核对原件、位置及数量 |
| 触发器/动作对象中存 ticksRemaining、checkThings、enoughConsumed 等运行字段；[失败触发器](https://github.com/thesePeople/CustomRitualFramework/blob/6520449248e3b4af0632b3f35d416fa4ff681d5d/Source/TPRitualAttachableOutcomes/TPRitualAttachableOutcomes/RitualStages/StageFailTrigger_ThingNotConsumed.cs)遍历 definition.stages 找动作并清状态 | 这些字段确实存在；是否被本体逐实例克隆未查明，不能断言已有串场故障。跨实例污染是风险推导 | 定义只读；状态全部归 eventId/stageEpoch/participantEpoch，不写注册定义 |
| [消费动作](https://github.com/thesePeople/CustomRitualFramework/blob/6520449248e3b4af0632b3f35d416fa4ff681d5d/Source/TPRitualAttachableOutcomes/TPRitualAttachableOutcomes/RitualStages/RitualStageAction_ConsumeThing.cs)按附近物品类型统计，直接改 stackCount/Destroy | 所读方法中没有本项目要求的原件权限/Claims/提交回执；不能作为 PZ 真实进食链 | 只引用既有资产/原生消费适配器，不由协调器直接扣物品 |
| [进食 JobGiver](https://github.com/thesePeople/CustomRitualFramework/blob/6520449248e3b4af0632b3f35d416fa4ff681d5d/Source/TPRitualAttachableOutcomes/TPRitualAttachableOutcomes/RitualStages/JobGiver_IngestThing.cs)直接 return null；对应 [JobDriver](https://github.com/thesePeople/CustomRitualFramework/blob/6520449248e3b4af0632b3f35d416fa4ff681d5d/Source/TPRitualAttachableOutcomes/TPRitualAttachableOutcomes/RitualStages/JobDriver_IngestThing.cs)只 yield 通知步骤 | 在所读实现里没有实际进食闭环，不能拿类存在当功能成熟 | 定义注册时声明所需适配能力；缺能力活动不可发起，不能通知成功冒充效果 |

另读 JobDriver_HaulToRitualSpot：实际取物、行走、放置与通知分步，值得参考执行/协调分离；完成通知遍历定义对象修改触发器，不适合直接作为本项目实例隔离协议。

## 4. Temporal：取消请求不是完成事实

[CancellationScope 源码](https://github.com/temporalio/sdk-typescript/blob/8b53edd8c5ced2338ecd8b83739431308d650101/packages/workflow/src/cancellation-scope.ts)中的 cancel() 发出拒绝信号；consideredCancelled 另受 cancellable 控制。[派发实现](https://github.com/temporalio/sdk-typescript/blob/8b53edd8c5ced2338ecd8b83739431308d650101/packages/workflow/src/workflow.ts)在取消时发 requestCancelActivity，且检查对应 completion 是否仍存在；它不在此处直接完成业务效果。

[活动选项源码](https://github.com/temporalio/sdk-typescript/blob/8b53edd8c5ced2338ecd8b83739431308d650101/packages/common/src/activity-options.ts)明确区分 ABANDON、TRY_CANCEL、WAIT_CANCELLATION_COMPLETED，普通 Activity 默认 TRY_CANCEL；子工作流默认等待取消完成。**不能笼统说 Temporal 默认取消都会等清理完成。**[官方源码示例](https://github.com/temporalio/sdk-typescript/blob/8b53edd8c5ced2338ecd8b83739431308d650101/packages/test/src/workflows/cancel-requested-with-non-cancellable.ts)收到取消后仍等待已有操作结束。

本项目建议：活动停止新派发，参与者逐人确认停稳；未确认者保留执行责任，其他已安全退出者不被整场冻结。清理也须受身体/危险仲裁，不能照搬 nonCancellable 成为无法被危险打断的行为。看门狗只能报告阻塞，不伪造停止。框架不引入 Temporal，不承诺其持久化能力，不对物理消费自动重试。

## 5. ProjectRemnants 当前 JAR

字节码事实：begin 拒绝双方已有会话并预约地点；tickApproach 复验位置、处理寻路失败和超时；tickConversation 在实际对话条件成立时推进，到期先 applyMoodBenefit，再可能进入 CLOSING；prepareForSave 对唯一会话调用 finish(false, "save snapshot")。

finish 的实际顺序是移除参与索引、取消精确 pending 任务、释放地点、清双方手势/任务并设冷却。此方法没有本项目式逐人持久停稳确认；不能以它证明完整身体交接安全，也不据此断言参考模组实机必然出错。

吸收：接近与交流分相、到场复验、精确取消旧任务、成功收益不绑告别动画。拒绝迁入：协调器直接控制双方身体、未确认停稳即释放共享资源、按参考浮点值直接写本项目属性。

注意：参考 JAR 有 CLOSING，本项目当前 SocialCoordinator 只有 APPROACH/CONVERSE。不能混用两者推断当前实现。

## 6. 本项目接入核查

当前 SocialCoordinator 用 attempt 验收接受/到场/释放，release 要求 stopped；SocialActions 用 sameAttempt/body.retained 限定手势操作。LeisureTimed 在应用标记未结时可置 UNKNOWN。这些适合继续沿用，不宜整套替换。

限制：SocialCoordinator.available 主要检查 SELF_CARE 记录，不是所有公共工作/原件责任的统一出席授权；配对状态为世界内暂态表，没有多人事件持久记录。TaskResume.prepare 仅支持 SELF_CARE 及明确列出的前任任务，包含 SELF_CARE 原因和恢复语义，不能把它改名就当活动的通用收束接口。

SocialActions 先持久化 applying，再写多项原版属性，最后由外层持久化完成。此顺序能留下不确定标记，但不是磁盘与角色属性的原子事务。A3/A4 应保留“未知不重放”，不得宣称 exactly-once 生理效果或零损失。

本轮读取 SHA256：

| 文件（client/EmberRoutesProbe 下） | SHA256 |
|---|---|
| SocialCoordinator.lua | 2264C10E6FF33D334E55B375024CE6AA388B279E22F06805225B477C0970C8D0 |
| SocialActions.lua | 5226701045525F14B3F065056ABFFC629B8C798BB429FB55BECF7041CCF30B78 |
| TaskResume.lua | 0AE5F20A716971B93A2FD3A73E6343B381E311178F5AFF79C0F0F2B79861D704 |
| TaskRuntime.lua | 68CD151632075F7BC9808D0EEBD4CAE18F378C614DA742457A11F55CC633B923 |
| LeisureTimed.lua | A20E471AF0F336EA0C17F4FF023C8D3AD09D8E1E673F30283D34A587AA5142FC |

工作区存在其他会话改动，这些哈希只标识本轮读取截点；实施前须重验相关接口。

## 7. 应进入 A3/A4 草案的结论

1. 只读 ActivityDef 与持久 ActivityInstance 分离；角色、阶段、位置策略、质量因素各有明确契约。
2. 阶段进入/退出均接收带代次的事实；“结束”“成功”“身体停稳”“资产已知”分别表达。
3. 所需能力注册校验；回调存在不代表原生动作已适配，未具备能力不得开放对应活动。
4. 出席仲裁由原责任拥有者返回安全收束事实，活动协调器不清队列、不核销货物、不替炉具监管者签字。
5. 结果提交、停止收束和责任清理分别跟踪；未知不自动重放，已安全退出者可独立恢复。
6. 质量读取实际参与记录；迟到/早退、部分阶段和部分消费分别核算。是否随机结果、负面收益、具体数值由用户决定。
7. 外部框架仅提供机制依据；尚缺本体仪式、UE 引擎源码及本项目多人活动实机证据，不标完整设计或玩法验收完成。

## 8. 检查边界

只读网络源码、当前参考 JAR 字节码和本地接缝，新增本评审及导航/待办链接。没有修改 Lua/Java、构建、运行逻辑测试或游戏，也未复制外部实现。后续继续细化设计，尚未进入实施计划或功能开发。
