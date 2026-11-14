# 自理、医疗、睡眠与闲暇领域

> 更新：2026-11-06｜状态：active｜以当前源码校准。此页是导航与现行契约，不是未来能力承诺；功能完成度见BACKLOG。

## 1. 职责与非职责
SelfCare为循环个人routine，医疗/睡眠/进食与闲暇各叶处理原版能力和事实；不是公共Order的别名。

## 2. 数据权威
SELF_CARE Job及SelfCareRecord保留 attempt 与业务进度，原件责任进入独立 ObligationLedger，Claims 独立；消费、派生产出和返还各凭实际回执结清，UNKNOWN 留责，旧 RETURN_ORIGINALS 不再作为生产权威；LeisureRecord验证同一payload的闲暇部分。原生健康值/物品/设施仍是实际效果依据。

## 3. 现行生命周期
个人step有IDLE/REQUESTED/STOP_CONFIRMED/ACTING/SETTLING/RESTORE_PENDING/RECONCILE_REQUIRED；kind有EAT/DRINK/REST/SLEEP/STUDY/LEISURE/MEDICAL。需按现有调度与停止证据交接，不承诺任意时刻最高优先级立即接管。

## 4. 真实接口入口
- `SelfCare.blocksWork(id) / activity(id) / force(id,kind) / prepareRemoval(id)`
- `HealthAssessment.read(npc) / canWork(npc) / part(npc,index)`
- `MedicalCare.observe(npc,id,sample,now) / eligible(item) / demands(scope)`
- `LeisureService.workState(id,entry,state) / status(id) / workReady(id)`

参数和返回细节以链接中的生产调用方/定义为准；这里不定义第二套API，也不为手册示例添加兼容别名。

## 5. 依赖边界
业务模块不引用UI；原版UI接入由Integration负责。shared只依赖实际存在的shared模块；客户端执行/账本组合放client。跨业务调用须经当前公开服务，已有组合依赖不等于所有内部文件都能任意引用。身体只通过TaskRuntime/TaskController/Driver当前授权链执行。

## 6. 源码地图
- `BodyBridgeContract.ReposeKind` 与 `FurniturePhase` 为 Java 内部命令类型；Lua 仍提交正式字符串。未知输入保持拒绝，退出休息仍可忽略 kind；不把枚举转换当作身体授权或姿态准入。
- Java 姿态：[NpcPosture.java](../../java/src/main/java/emberroutes/probe/NpcPosture.java) 管理原生休息/睡眠适配、锚定、家具部件与退出；复用 BedPoseMotion 和 FurnitureExitState。由 ProbeNpc 的现有引擎帧推进，全身停止仍由 ProbeNpc 协调；不拥有床位声明或 SELF_CARE 结算权。Lua 继续消费 ProbeRuntime 的正式授权桥。
- [client/EmberRoutesProbe/SelfCare/SelfCare.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare/SelfCare.lua)
- [client/EmberRoutesProbe/SelfCare/HealthAssessment.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare/HealthAssessment.lua)
- [client/EmberRoutesProbe/SelfCare/MedicalCare.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare/MedicalCare.lua)
- [client/EmberRoutesProbe/Leisure/LeisureService.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Leisure/LeisureService.lua)
- [shared/EmberRoutesProbe/SelfCare/SelfCareRecord.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/SelfCare/SelfCareRecord.lua)
- [shared/EmberRoutesProbe/Leisure/LeisureRecord.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Leisure/LeisureRecord.lua)

## 7. 验证入口
自理、睡眠、借书归还与companion-handoff定向Kahlua；床位/动画/磁盘恢复须另验。

## 8. 易错边界
无isCritical/triggerEmergencyCare/getAvailableMedicine/findAssignedBed/startLeisure这组想象接口；闲暇记忆属于个人记录，不是纯瞬态一概丢弃。

自动化、原生替身、实机、磁盘恢复与性能分开记录；源码存在和构建通过不等于玩法已验收。
