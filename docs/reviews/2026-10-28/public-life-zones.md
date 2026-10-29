# 公共生活区：首批代码与验证边界

日期：2026-10-28；状态：区域/规则入口及现有闲暇消费源码已接；整组活动未完成，未实机验收、未构建/打包/发布。

## 本轮决定

用户确认最小功能子区、自定义行为禁用/允许/优先，以及日常公共生活＋聚会偏好覆盖。设计更新为[活动0.4](../../superpowers/specs/2026-10-28-a3-a4-community-activities-design.md)，最小空间协议见[子区设计](../../superpowers/specs/2026-10-28-public-life-zones-design.md)。在线v4.0本轮读取成功，修改时间仍为2026-10-27T00:53:08.694Z；§3.1.1有自然识别/显式子区，不把本轮基础称整节完成。

## 已接代码

- SettlementZones：父据点数据根中的独立format=1分支；稳定zoneId、单整数楼层、名称/范围/三档规则、修订校验、权限及每据点32/总1024技术限额。用父矩形边界扫描证明整个范围落在复合并集，拒绝跨内部空洞；不会只检查角点。覆盖查询按父/子revision缓存。
- LifeZoneMenu及UI/LifeZoneSelector、LifeZoneRules：据点右键菜单提供创建、重画/重命名、规则、启停和移除。复用原SettlementSelector世界拖拽/高亮/原生输入，增加共用选择器占用入口，避免两个选择器同时接外部鼠标。锁定楼层，切层/世界/撤权退出。
- LeisureService：规则作用于原有普通候选及持续复评，资格/资源/退避仍在原系统；社交发现先过滤、目标双方位置复验，优先提高邀请机会；优先候选有界加权并参与同级选择，未配置时保留旧分层回退。
- StudyActions：仅消遣阅读开读位置的规则复验，按原停止/归还链退出；工单驱动研习和责任恢复不套普通娱乐禁令。
- CN/EN各37个LifeZone键。移除/停用只改变规则，不触碰身体/原件/座位声明；重叠普通区域禁用优先。规则窗口只显示当前已实现行为，不显示音乐/唱歌为可用。

## 实际检查

1. Lua5.1 loadfile只解析9份新增/修改Lua，输出 `SYNTAX_OK 9`。不是Kahlua执行或原生UI检查。
2. JSON解析与LifeZone键集合比对，输出 `LIFE_ZONE_TRANSLATIONS_OK 37`。不等于实机排版通过。
3. 一次临时Lua宿主边界核查16项，输出 `ZONE_BOUNDARIES_OK 16`：父并集覆盖/内部空洞、楼层隔离、默认允许、读取副本隔离、撤权、过期revision、重叠禁用/删除恢复、父revision变化、缺失ID/未知行为、换世界及未知格式拒绝。宿主替换了Ledger/Registry，不验证原生ModData、引擎或鼠标。

遵用户“未完成前不需要全量测试”，未跑完整preflight/全历史宿主/Java构建或游戏。完整检查留到整组代码收齐。现有Boot要求Lua Build版本与Java桥精确一致，未在这个未打包开发截点单独提升Lua版本；最终构建统一递增版本、桥与包，不制造已发布的新版本记录。

读取截点SHA256：SettlementZones.lua `44F9D6F499AE28F5E7CC55A08A85100C13A1433B69C20DAE14FD0D6FF15DD3E6`；LeisureService.lua `229A6A20376CCB3CF9D3DB4F12BDE00CB8266C0A1EAF88843899B9EAC96C8F2B`。

## 后续首批：主动前往公共生活区

源码追加LifeZoneVisits（发现辅助，无独立tick/控制器），注册PUBLIC_LIFE运输候选，仍使用原OBSERVE个人Job/Session及共享scan/path预算。region目标绑定ID/revision，近侧窗口按稳定npcId分散，单轮最多4点、每区最多64采样，未观测或暂不可用不声明无容量。已在可用区域不重新搬家，路途不广告为双人社交空闲者。

落点声明沿LaborStore.claimPersonal使用leisureTile键，发现先只读排除已被预约的格，真正准入仍由唯一Claims裁决。到场要身体实际位于该区域/楼层，不把距离容差当入区；仅保存位置事实，不发社交/娱乐效果，保持原移动间隔但跳过额外娱乐决策停顿，随后本地重选。

参考根NPCFW.jar（SHA256见活动源码评审）用javap核对tickMoveStroll的目标失效/接近/排队/到场分支，Lua发现/执行独立实现，不迁入参考的控制器。发现原A.move以`and/or`求目标时，函数返回nil会退回函数对象；本次新增途中失效用例实际触发崩溃，已改显式if分支，随后重跑定向用例通过。

新增tests/lua/life-zone-visits-test.lua，安装版Kahlua运行30项断言通过（移动、站位占用为替身）：预算耗尽/分片/退避、稳定分散、已在区/移动冷却/危险、共享预约、区域楼层/修订/删除、非法目标、到场位置复验、途中停用和社交运输互斥。Lua5.1语法检查10份通过，3对新增状态文案JSON检查通过；末轮缓存复用/到达判据变更已由同一30项Kahlua覆盖。未跑全量测试、完整preflight、Java构建/打包或游戏。

## FREE临时偏好上下文首批

新增shared/ActivityRegistry及client/ActivityStore、ActivityService，沿本项目MembershipService/TaskResume的稳定成员与命令代次，以及前述源码评审已核查的幂等意图/取消不等于执行完成机制独立实现。仅登记当前7种行为；FREE_GATHERING不是音乐等未适配能力的占位入口，公开第三方注册接口尚未冻结。

Store保存在ContainerRegistry世界根communityActivities(format=1)，只记录意图，不镜像Job、Claims或资产。实例携带稳定ID、区域ID/revision、指定名单及成员revision/命令epoch、规则和游戏时间窗口。至多128条记录；只淘汰CLOSED且无身体/资产的本批偏好意图，未结不淘汰；已消费或过期令牌不能再次创建事件。后续加入身体/义务后须扩展终态结清证明，不能直接沿用本批无资产前提。持久行拒绝循环、闭包、userdata、非有限值和过深/过大嵌套；未知格式保留、不自动启用覆盖，日常区域规则继续生效。

Service提供preview/issue/start/cancel/view及policyAt，命令复验权限。120秒技术令牌绑定发起者/据点；重复提交返回同一不可变意图。只对名单内、成员与命令代次仍匹配、位于目标区域/楼层且窗口有效的候选应用显式稀疏覆盖；未设置行为继承日常规则，显式偏好可替换普通区域的行为禁令，但不替换安全、权限、资源或身体门槛。名单外和区域外不受影响。区域/父范围修订、新命令、成员转移、期限、取消均使覆盖失效；视图/新发起收集退席记录和清理索引。区域有效性按父/子修订缓存，NPC索引直接定位上下文，无新增每NPC tick。窗口到期查询立即回退，持久关闭在视图/后续命令收集，不声称实现完整活动调度器。

LeisureService候选、连续复评、实际执行有效性、社交双方落点及StudyActions消遣阅读开读统一调用该上下文查询。没有修改工单研习、工作派发/责任收束或另建身体控制。TaskPersistence.prepare撤销偏好场景；重新打开世界也关闭残留意图，保留记录，无续演和完成收益。未知偏好数据不阻断既有全局保存屏障。

当前GATHERING只表示已登记的召集/偏好意图，未经过Attendance/Participant的身体准入与到场回执，不能转为RUNNING/成功或宣称活动已完成。暂不开放玩家发起按钮：当前没有安全收束工作/定向赴场的完整执行链，直接开放会让玩家看到已发起却无人按名单出席的半成品。

新增activity-context-test.lua，安装版Kahlua29项通过：权限/令牌、重复发起/关闭不重开、并发名单、稀疏覆盖/读书禁用、名单/空间/楼层隔离、过期revision、新指令退席、窗口到期、区域修改、保存/读档、未知格式与不支持行为。世界身份、时钟、成员为替身，不验证原生UI、动作或ModData磁盘保存。最后一轮同时运行已有life-zone-visits-test.lua的30项通过；Lua5.1解析本轮8份源码/定向夹具通过，4份相关文档doclink零错误。仅此两份定向执行入口，没有全历史测试、preflight、Java项目构建或游戏。

## Attendance首批准入、指定赴场与位置事实

新增ActivityAttendance，inspect只经现有NPC Job索引组合读取Membership/玩家命令代次、所有原Job效果/声明/义务、Runtime当前及待准入身体、原生动作队列与Work.hasCargo（包含独立原生executor）。CRAFT未released、HAUL未DONE、COOKING duty/claims或任何业务义务、SELF_CARE未回IDLE/持物/前任恢复未结，以及UNKNOWN分别阻断。台账或身体已明确阻断时不扫描原生库存；没有新增NPC tick或资产裁决者。

PublicWork的共同eligible门和Work自动派工门读取活动意图，停止名单成员认领新工。后者允许已存在的未结物流任务继续走原owner的恢复路径，避免携货未结却被活动门封住；已排队/运行任务也继续沿原Runtime/业务结算。CookingService/P4算法没有修改，已有炉灶监管和归还继续由其原恢复/结算链处理。SelfCare在已观测安全、无优先自理/强制睡眠时，请求原owner正常停止区域外闲暇/阅读或工单研习；不提前清书、座位或任何Claims。

本批没有冒用制作return或烹饪stop作为活动让位：当前Production.return最终把原工单映射为CANCELLED，Cooking.stop保留责任，均不能当结清证明。当前普通工作采用保守边界——等原有有限任务整体结清；长制作/大搬运任务可能错过聚会窗口，人工暂停/未知效果仍等待原业务处理。按单件/安全责任边界提前收束并保留余量需求，尚未适配，不能称用户要求的生产打断策略已完整交付。

LeisureService对已通过准入的名单提供唯一指定区域的运输候选，优先于普通闲暇发现；SelfCare暂停其工单研习发现，避免重新抢回。LifeZoneVisits复用原scan/path预算与站位Claims，发现缓存含eventId；route保存区域ID/revision和eventId。到区后保留个人选择器，在本场区域内选择行为；社交已有邀请也复验双方目标区域，普通公共区吸引不把成员再拉走。临时OBSERVE允许可以覆盖普通区域禁用，但几何/权限/安全门独立；禁用静立的聚会仍缺合法首批运输落点，不伪造已到场。

移动仍是原SELF_CARE LEISURE运输尝试，非正式ACTIVITY参与Job。动作到点/停稳后复验实际NPC位置、同层、合法站位、活动/成员代次、原Job责任，以及当前同一运输Job/Claims，才记录首个arrival位置和游戏时间。距离容差在区域外、其他Job/错误站位声明、UNKNOWN或旧eventId均不能报到。Runtime.step处理期间禁止新准入，但允许同一已授权的ACTIVE运输Session报告事实；这个例外不签发第二身体。到场不给娱乐收益/全场成功，原个人Job在正常停止确认后自行释放站位。取消、期限、区域或成员变化使旧路途失效；存档仍沿既有个人保存屏障收束。

本批参考继续沿已核查的NPCFW/CRF/Temporal机制边界及项目统一任务协议；没有新造引擎API。具体适配核对了当前Production.advance/finish、PublicWork制作reconcile、Work/Logistics恢复、CookingService.command/recover、TaskRuntime.step/status与SelfCare正常停止/归还链，未复制参考控制器。新增16对CN/EN闲暇状态文案。

新增activity-attendance-test.lua：安装版Kahlua31项通过，覆盖多业务未结/暂停/独立炉灶/UNKNOWN/原生队列/待准入身体、阅读正常停止且不释放书、紧急睡眠不抢占、无日常派工offer的指定赴场、区域规则覆盖和持久ref、Runtime处理期间同Session到场、位置/声明/旧邀请复验、幂等首到事实和取消后正常停止。首次失败来自新夹具每次返回不同Ledger根、导致Zone数据换世界，已改为稳定世界替身；随后通过。末轮同时运行activity-context-test.lua29项与life-zone-visits-test.lua30项通过，最后补非个人Job声明检查后单跑31项再次通过。Lua5.1解析12份本轮源码/夹具通过，新增16对翻译JSON/键集合通过（ACTIVITY前缀另有既有INTERRUPTED键），4份相关文档doclink零错误。未跑全量preflight/全历史测试、Java项目构建或游戏。原生移动/占用/携货、Runtime和成员仍为替身；不证明真实停止/路径、磁盘保存、多人拥挤或游戏性能。

## FREE首版闭环落实（2026-10-28，替代前文阶段性未接入描述）

Registry/Store/Service/Attendance/Participant五单元已接；ActivityRecord、ActivitySchedule与ProductionYield为纯协议辅助。正式ACTIVITY Job占既有普通任务额度，赴场仍沿个人移动链，到场停稳后申请短ACTIVITY Session与同一Claims中的站位。真实Session、位置、控制代次、原责任和站位证明齐全才可开场。提前开需全部邀请决定与接受者实际就绪；截止需组织者及最低人数。FREE只有开场一个加入边界，迟到者退出，不在运行中替补组织者。

开场后短等待Session确认停止并释放站位，参与Job保持SUSPENDED/FREE，既有个人Session在本场区域内自主选择允许行为。取消/保存/危险/新命令使旧ref失效，个人原件仍由原owner归还；未确认停止、UNKNOWN或未结责任保留声明和恢复围栏。逐人完全结清才退休，其他已结清成员可以独立恢复。有效参与只统计当前同一场、同一attempt、实际区域内且动作已开始的个人Session时间；不把运输、等待或加载间隔当娱乐，不新增士气或奖励。

Production在完成当前单件后走既有returnOnly归还链。公共制作保留原工单数量，按已确认最终产物累计，原执行结清后仅派剩余需求；中间BOM产物不重复抵扣。手动制作保留同一Job ID及原始目标，已归还全部原件后才标assetFree，活动期间不自动恢复；结束后复验原命令/成员代次、身体及生存门，仅恢复剩余目标。BusinessJobs投影同步该原Job，不另建资产账本。物流和烹饪继续完成原责任，未加入提前部分交接；长任务可能错过集合截止。

ActivitySchedule使用游戏时间、稳定occurrence ID和有界计数，只尝试最近有效窗口，先消费索引后发起，不积压补办；上场未结则跳过。取消计划仅停止后续场次。保存先撤销场景意图，再进入既有身体/原件屏障；读档按原Job事实收束，未有停止证明者保持未知，不续演或重放消费。

玩家入口位于现有据点窗口标题区，原生ISUI共用窗口提供列表、名单/场地、组织者、行为覆盖、人数/时间、立即/有界定时和详情取消。关闭只关窗口，权限丢失自动解除UI引用。CN/EN配对。UI预览发现详情列表错误走场景行分支，已改为按列表身份区分；安装版Kahlua复验并生成两语名单/规则/列表预览。

定向检查：activity-context 29、activity-attendance 31、life-zone-visits 30、activity-lifecycle 24、activity-craft-yield 30、activity-dialog 128项通过。制作夹具复用既有649项生产检查作为前置；生命周期使用真实Runtime/Controller/Jobs/Claims，原生身体与个人动作仍为替身。UI用替身ISUI和AWT预览，已查看CN规则/列表与EN名单布局，不等于游戏渲染。静态检查结果见本节后续记录。版本保留0.29.16，没有Java源码改动或新桥构建，不打包或上传。

## 仍未验证或未实现

实际多人路径/站位/动作/退出、区域规则变更后的原生起身、读书原件归还、正常磁盘重进和性能未实机。当前为FREE首版源码闭环；现有双人社交可同时形成多对，不是三人以上共享对话圈。SCRIPTED主讲/仪式执行、音乐/唱歌、聚餐共享消费、关系/喜好与新收益属于后续内容，不能称整个§4.5或自由生活系统完成。没有改另一AI的P4供水/烹饪核心算法。

补充引擎核对：当前安装projectzomboid.jar的IsoGridSquare.isFree(boolean)字节码在参数true时才检查movingObjects；本次沿既有standable使用false并独立核验允许的占用者，不因NPC自身已在格内就必然拒绝到场。此静态事实不证明真实路径可达。文档链接检查5份零错误。

末轮接缝自审补齐消遣阅读的实际区域门：候选合法不代表开读/持续阅读时仍在本场区域，StudyActions开读与StudyService已开读校验均复验活动范围；结算归还沿原settle通道，不因区域失效丢书。旧P3夹具缺少在线区域账本，显式替换该边界依赖后，33项阅读检查（含越界拒绝）及既有座位/退出夹具通过；活动上下文29与生命周期24复验通过。活动相关105对CN/EN键一致。

最终静态结果：全模组preflight扫描261份Lua，lua_lint为0错误/9警告，结构规则/候选不变量/索引新鲜度通过；原版ISFluidEmptyAction.lua中的0.0f不被工具解析，属于参考库覆盖限制。LSP初跑8个Error均为既有ItemLockMenu.lua同一行的Lua5.2十六进制转义，已等价改为Lua5.1十进制UTF-8字节转义，保留图标语义；没有改物品锁业务。对修复文件及末轮阅读两文件做独立LSP复核0错误/0警告，并以Lua5.1 luac解析通过。全模组LSP其余752个Warning保留为信息性动态类型噪音；未把初跑preflight记作全绿，也未再跑全历史替身测试。原始输出保留在build/qa/activity-preflight.txt，修复定向输出在build/qa/activity-static-fix.txt。相关源码diff --check通过。
