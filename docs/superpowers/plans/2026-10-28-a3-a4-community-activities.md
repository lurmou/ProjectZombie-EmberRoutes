# A3/A4 社区活动框架实施计划

> 执行方式：当前主代理在本会话实施，不派子代理。用户已确认设计§17全部推荐，D6更正为现有据点窗口标题区入口；未完成前不运行全量测试。

**Goal:** 交付指定居民安全收束工作、实际聚集交流、逐人退出恢复、手动/定时发起与正常保存收束的单人多NPC活动闭环。

**Architecture:** 五个核心单元：Registry、Store、Service、Attendance、Participant；复用TaskJobs/TaskRuntime、共享声明、成员权限与原业务恢复。场地、结果、定时和投影是辅助职责，不新增独立调度器。先使用已有交流手势/气泡及其已核查的属性量纲，不新增士气系统或未适配演讲动画。

**Tech Stack:** PZ B42 Lua/Kahlua、现有ZombieBuddy桥、原生ISUI、CN/EN JSON；没有独立线程/网络服务。

**Spec:** [从属设计](../specs/2026-10-28-a3-a4-community-activities-design.md)，以及[源码评审](../../reviews/2026-10-28/activity-framework-source-review.md)。

## 0.4续接修订：先公共生活子区，再FREE聚会

用户后续明确并确认模拟人生俱乐部式策略：禁用/允许/优先，NPC在行为集合内自主选择；普通生活和聚会共享选择器，只有演讲/仪式使用共同阶段。原Task2/4的固定共同流程不能直接用于所有聚会。先实施[最小子区](../specs/2026-10-28-public-life-zones-design.md)，再接临时聚会覆盖与小团体；区域规则不改变生存/原件优先级。

- [x] 子区后端：稳定ID、父据点、单楼层/范围、完整并集覆盖、修订/权限、技术限额、三档规则；候选查询不建新库存或身体权威。
- [x] 复用原有世界选择器，接公共生活区创建/重画与原生规则编辑窗口，启停/删除入口；CN/EN成对。
- [x] 日常LeisureService读取当前位置/候选目标规则，优先有界加权；社交邀请发现前过滤，消遣阅读实际开读复验；无区域保持旧规则。
- [x] 核对并记录上述代码的最小静态/边界检查：9份Lua语法、37对翻译键、16项纯Lua宿主边界；均非实机，未跑全量检查。
- [x] 主动前往公共区候选：增量取点、原扫描/路径预算、落点Claims、运输/娱乐分离、到场复验和旧目标失效；30项定向Kahlua接缝通过，原生移动/占用为替身。
- [x] FREE偏好上下文首批：Registry/Store/Service、名单与区域修订、游戏时间窗口、稀疏规则覆盖、签发令牌/重复命令、退出名单与保存/读档撤销；已接普通闲暇与消遣阅读，尚无出席执行/UI。29项定向Kahlua通过（时钟/成员替身）。
- [x] Attendance首批准入与指定赴场：NPC索引组合读取原Job/义务/效果、Runtime、携货与原生队列；停止认领新工，保留物流恢复/烹饪结算，旧闲暇/阅读由原owner退出。指定区域运输沿原个人Job/Session/Claims，到场仅记首个位置事实；31项定向Kahlua通过。尚非正式ACTIVITY参与Job/开场或完成回执，普通工作暂等原任务结清，不会中途取消工单。
- [ ] FREE实例提供临时偏好，不使每名NPC每次换行为都推进共同阶段；聚会小团体切换与已有Session/资产交接接通。
- [ ] SCRIPTED仍沿Task2/4的必需角色/阶段回执，按需嵌入聚会边界；不让音乐/进食未适配能力进入可执行列表。

这些勾选只表示源码接入，不代表游戏鼠标/动作/存档实机通过；整个A3/A4仍未完成，代码收齐前不跑全量测试。

## Global Constraints

- 指定名单普通工作安全收束后让位；危险/急救/紧急自理仍优先，所有未结责任须逐一核对。
- 身体、Job、原件/Claims/义务分别保留唯一权威；UNKNOWN、超时、暂停和队列空不能冒充结清。
- 不改另一AI正在修复的P4核心算法；活动只接最小收束接口，缺能力明确阻断。
- 不上传工坊、不清用户改动，不以单人接口宣称联机。
- 开工期间不跑全量测试；代码收齐后跑一次必要定向接缝、Lua preflight、翻译与发布结构检查。仅改文档时只检查文档。
- §17已确认：仅名单参加；到齐提前/截止满足法定条件开场；阶段边界迟到、不自动替补；保存收束不续演；一次/有界重复定时、不补积压；窗口标题入口；首个无耗材集体交流。

## Review Focus

1. Runtime空闲但暂停Job仍持料，或没有携货却有独立炉具监管：不得准入（Task3）。
2. 原生停止同步回调、玩家新命令及旧attempt迟到：不启动第二身体、不丢已发生效果（Task3/4）。
3. 邀请未决时提前开场、迟到扩大必需回执集合：按设计冻结和门槛推进（Task2/4）。
4. effect标记与角色属性写入之间保存：未知不重放、已确认不重复（Task4/5）。
5. 定时重进/跨多个时段、UI重复提交或关闭：不补办多场、不重复发起、不泄漏订阅（Task2/6）。

## 文件地图

Lua根：`Contents/mods/EmberRoutesProbe/42/media/lua/`。

- 新建shared/EmberRoutesProbe/ActivityRegistry.lua：定义及纯schema检查。
- 新建client/EmberRoutesProbe/ActivityStore.lua：持久实例/定时/有界命令回执。
- 新建client/EmberRoutesProbe/ActivityService.lua：唯一活动写入口、阶段推进、定时/投影与辅助位置处理。
- 新建client/EmberRoutesProbe/ActivityAttendance.lua：逐业务资格/收束/恢复，供工作和生活纯查询门调用。
- 新建client/EmberRoutesProbe/ActivityParticipant.lua：唯一Runtime下逐人行为、事实与退出。
- 新建client/EmberRoutesProbe/UI/ActivityDialog.lua：列表/发起/详情共用窗口，订阅生命周期与命令。
- 修改client/EmberRoutesProbe.lua：仅加载入口。
- 修改shared/EmberRoutesProbe/Boot.lua：按既有顺序接tick/reset，不靠性能采样时的自动发现替代正常tick。
- 修改client下PublicWork.lua、SelfCare.lua、SocialCoordinator.lua、TaskPersistence.lua、必要的Production/Work等收束接缝；每次编辑前重读对应函数。
- 修改client/EmberRoutesProbe/SettlementDashboard.lua：标题区按钮，不新建概览/页签。
- 修改shared/Translate/CN/IG_UI.json与EN成对文案。
- 最后更新Build/版本与必要打包入口，统一记录证据和BACKLOG。

以上是实施文件，不把每项辅助职责做成独立服务；有实际长度问题才拆纯辅助文件。

## Task 1: 定义、持久事实和命令身份

**Interfaces:** Registry.register(def)→ok,reason；Registry.get(id)→只读def；Store.current()→世界绑定数据；Store.commit(eventId,revision,patch)→ok,reason；所有写入拒绝userdata/闭包/循环表。

- [ ] 登记首个group conversation定义，角色host/listener、有限阶段、必要能力、完成和失败条件；ID/定义版本稳定。
- [ ] ActivityStore持久event、schedule、签发令牌与结果回执；byNpc和scope索引从事实派生，禁止镜像Job/Claims当前状态。
- [ ] 固定技术上限并明确无未结事实可淘汰时拒绝新请求；Job沿现有512额度，不另开任务额度。
- [ ] preview无副作用；UI令牌签发/消费/过期拒绝，活跃实例关联用于重复确认，不把未见token当全新请求。
- [ ] schema新增独立活动数据不迁入旧任务；未知版本保留原数据并拒绝自动运行。

交付：可以独立验证定义校验、重复命令和世界隔离，不运行身体。

## Task 2: 活动生命周期、定时和可观察投影

**Interfaces:** Service.preview(actor,args)、issue(actor)、start(actor,args,token)、cancel(actor,eventId)、schedule(actor,args,token)、view(actor,scope)、tick()；内部消息携带eventId/controlEpoch/participantEpoch/stageEpoch。

- [ ] 实现PREPARING/GATHERING/RUNNING/WINDING_DOWN/SETTLING/CLOSED与独立outcome，不以取消删除实例。
- [ ] 开场核对邀请明确决定、实际到场、必需角色、法定人数和有效场地；deadline只结束等待，不伪造成功。
- [ ] 角色/位置独立分配；使用已加载据点内合法同层位置、共享声明权威、不堵门；找位/路径使用有界预算与游标。
- [ ] 阶段开始冻结必需参与集合；迟到仅在允许边界接入，退出不缩小原完成度分母。
- [ ] 定时采用游戏时间、持久occurrence身份；修改不取消已发场次，错过只尝试最近有效窗口、旧场未结不补办。
- [ ] 只读视图显示到场/收束/阻塞原因；无订阅不构造整表，不把技术ID当姓名。

交付：有明确阶段与回执协议的活动业务根，尚不宣称原生闭环。

## Task 3: 逐业务安全收束与恢复

**Interfaces:** Attendance.inspect(actor,npcId,event)→READY/WAIT/REJECTED/UNKNOWN,reason,refs；request/observe/withdraw/resume均按intent代次和原Job版本核验；blocksOrdinary(npcId)为纯读。

- [x] 首批组合读取Membership/命令代次、Runtime、NPC索引全部Job及其声明/义务、携货与独立监管义务；未结/未知拒绝赴场，不只查当前身体。
- [x] 先发布名单/区域/命令代次的意图关联，再由原owner收束闲暇/阅读；公共派工停止新认领，原物流恢复/制作/烹饪继续原结算，不阻断紧急自理。中途按单件/安全责任边界让位仍待后续适配。
- [ ] 制作、HAUL/配送、SELF_CARE读书/家具、COOKING分别用其既有责任收尾算法；缺安全退出接口先补最小适配，不通过通用pause释放物资。
- [ ] 原责任已清但Job合法挂起则保存版本化恢复引用；活动结束后由原拥有者决定恢复，不复活已交接/结清任务。
- [ ] 原始taskStopped回调链与TaskPersistence先后顺序保留；错误处理幂等，不覆盖原回调、不建第二事件总线。
- [ ] 玩家新命令/调驻取消旧活动意图；迟到原件效果仍归原attempt，不能因控制代次过期丢弃。

交付：未安全收束者不进入活动；已确认安全退出者可以独立恢复。

## Task 4: 每名参与者的原生执行与交流结果

**Interfaces:** Participant.request(actor,binding,job,eventRef)→Runtime handle；observe/stop使用TaskBusinessStop；Service只消费带代次事实。

- [ ] ACTIVITY Job在既有TaskJobs创建并占普通额度；各自申请Runtime非抢占准入，不直接操作另一NPC。
- [ ] 小型Sequence执行到场/复验/等阶段/交流/退出，移动、朝向、手势和气泡沿当前已核查原版/桥能力。
- [ ] 危险/紧急需求退出通过既有身体仲裁；正常工作不打断已承诺活动。
- [ ] 实际到场并持续有效才累加参与；超时、失去视线、死亡、场地不可观察分别处理。
- [ ] 效果按既有社交适配的量纲与完成度记录；如首个活动需新增收益规则而非复用既有规则，先询问用户，不能暗定士气数值。
- [ ] 每人停止/效果确认后释放本人站位；最后一人未结不影响其他已安全退出者恢复。

交付：可从发起到多人实际交流、取消/早退和工作恢复的原生闭环；实机仍需集中验收。

## Task 5: 保存与正常恢复

- [ ] 活动接既有保存屏障，禁新派发；prepare可跨tick，OnSave同步捕获，不等待归还完毕。
- [ ] 停止/动作回执先核对Job事实，再归入活动；写入中断未知不重放。
- [ ] 读档重建声明与义务、实例/Job关联，旧活动只生成收束候选不续演；未知定义保留责任。
- [ ] 同世界正常保存完成后也收束旧活动；原任务恢复仍需命令代次/身体/原件复验。
- [ ] 定时occurrence、请求回执与结果不重复；退休只处理完全结清实例。

## Task 6: 玩家完整入口和本地化

- [ ] 标题区按钮打开共用活动窗口；不改现有页签和其他AI的UI功能。
- [ ] 列表/发起/详情提供地点、组织者、名单、立即/定时、预检、开始/取消；一次选择据点居民后可排除。
- [ ] 普通鼠标/键盘输入、长名单滚动、按钮禁用原因与命令失败反馈完整。
- [ ] 关闭释放订阅，不取消活动；换世界丢旧actor/event引用；CN/EN成对。

## Task 7: 代码收齐后统一验证、打包与记录

- [ ] 先自审规格覆盖/模块依赖/源码接缝，收齐全部入口、恢复、翻译后再开始验证。
- [ ] 仅新增一个高风险接缝夹具覆盖Review Focus，不为可逆UI和每字段写镜像测试。
- [ ] 跑相关定向Kahlua入口、Lua preflight及CN/EN一致性；仅有Java改动才构建并跑相关Java检查。
- [ ] 失败修复后只补受影响检查，不例行全历史重复跑；最终发布结构/包文件一致性核对。
- [ ] 更新版本/本地包、专题证据、BACKLOG及导航；不上传工坊。
- [ ] 明确未实机部分：真实站位/动作/停止、正常磁盘重进与性能；不把替身通过称玩法完成。

## 当前执行状态（2026-10-28）

FREE首版源码已接齐：正式参与Job与短等待Session、开场仲裁、个人行为接力、逐人停止/责任回执、保存收束、一次/有界定时、手动和公共制作安全让位与余量恢复、标题区完整入口及CN/EN。Task 2/4原共同Sequence中的演讲/仪式仍是SCRIPTED后续，不将其勾成完成；FREE不为每次个人行为同步全场阶段。上方早期复选框保留原任务定义，当前落实以本节和[证据](../../reviews/2026-10-28/public-life-zones.md)为准。

定向Kahlua接缝已通过；实机、磁盘重进与性能未验证。无新Java改动，版本保留0.29.16，不自动构建新桥或发布工坊。公共烹饪/物流原任务安全完成后参加，没有新增其部分交接算法。真正三人以上社交圈与SCRIPTED不是本次FREE闭环已实现能力。
