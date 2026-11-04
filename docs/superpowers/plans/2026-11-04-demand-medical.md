# 需求与工单分离、个人医疗实施计划

2026-11-04；用户已批准先完成基础需求页与工单页，再实现个人医疗。以远端 c1229b7 为集成基线，保留其 DEC-003 Java 内核；原工作区及其旧内核改动不覆盖、不整体合并。

**目标：**需求显示紧迫程度、影响对象、是否有人处理和当前阻碍；同一问题只一条。工单显示既有生产/配送等安排，动作步骤在详情展开。个人医疗不为领取绷带另建公共搬运工单。

**架构：**沿现有 Demand/Order/Job/Session/Claims 边界。只读需求投影复用现有观察事实与 Job 关联，不成为新权威。个人医疗扩展 SELF_CARE，使用原版 ISApplyBandage 与唯一 Session；专业医生、缝合、异物、夹板不在首批实施。公共原件领取保持仓储权限与真实物理转移。

## 依据与代码闭环

- 在线唯一需求 v4.0：医疗两阶段，先脱离威胁就地止血，再专业医护。当前安装 ISHealthPanel 的 HApplyBandage:perform 先移入主库存，再 ISApplyBandage:new(doctor,patient,item,part,true)；原版 complete 消耗绷带并写身体部位，不直接增加健康值。参考当前 NPCFW.jar SelfCareCoordinator 有急救、取药/归还分支，不迁入其独立身体控制器。
- 创建认领：SelfCare.personal/Record.create、LaborStore.claimPersonal、SelfCareResources。扩展类型和严格版本化医疗事实，不放宽其他个人任务守卫。
- 正常释放：SelfCareExecution.finish、SelfCareCustody.returns、finishPersonal。仅经部位效果与原件消耗证据释放；换药的原版副产物也需归属。
- 异常：SelfCareExecution.stopAdapter/persistFailure、SelfCareReconciliation、TaskResume。读档或中断效果不明保留责任，不依据物品消失自动重试。

## 实施顺序

- [x] 集成已存在的玩法修复，保留远端容量参数、终态前工具核对、配送与分配详情；构建并核验接口。
- [x] 需求/工单基础：DemandMonitorService + 纯投影；PageRegistry 新需求页，复用 CachedList/Cards/FilterChips/PageLifecycle。清洁需求、现有最低库存需求进入需求页；现有执行与生产/配送安排保留工单页，清洁执行按原件责任分组。后台原始数据不因切页或隐藏删除。
- [x] 添加严格的 MEDICAL 个人记录与伤势观察；区分外部威胁、持续出血及一般低健康。止血优先吃喝和工作，持续掉血不一概阻止急救。资源先随身再允许的公共仓储；不可达/缺料有限等待，需求说明原因。
- [x] 原版自我包扎及必要换药；各部位逐次事实与原件消耗/副产物核对。工作/个人物品互不偷用，保留容量和最多16项个人声明约束；紧急撕布未实现，不伪造材料。
- [x] 治疗后的重新仲裁/恢复。普通生产、物流、公共派工、库存与预览改用观察到的伤势资格；独立健身/诊断探针的专属身体门槛保留。明确健康等待、中断及恢复原因。
- [x] 定向检查及候选包构建：去重/被处理关联/阻碍/切页释放；原版包扎start/complete/perform；仓储取药、争用、缺药、换药、中断和恢复。宿主及实际Java已检查，实机未验证；完整历史门禁并非全通过，见证据。

## 展示和恢复约束

需求转入处理不表示已解决，取消工单不抹掉真实问题。源/目标身份缺失或未知效果必须可见；普通保管不刷成工单。所有UI render只读缓存，订阅和扫描由激活token关闭；不增加隐藏页面扫描。CN/EN成对。

医疗事实为 medical.version=1，含 partIndex/itemId/fullType/attemptId/phase/replace/removed/applied/effects/outputs；移除阶段另记 oldType，明确原版停止另记 stopped。正向回执与未知阶段分别处理，不把物品消失当作治疗成功。首批支持当前格式保存恢复，不自动迁移不受支持旧格式。健康资格改变属于明确缺陷修复，已独立检查。

已有个人任务待还原件时，只扩展同一Session的随身急救分支（独立relief医疗事实、共享Claims），不增加并行身体控制。此分支不借第二批公共原件；没有随身包扎材料且旧原件无法归还时，继续保留责任并提示缺料。公共取药在正常MEDICAL任务中支持。专业治疗、撕布配方、真实寻路/动画/磁盘恢复仍见[本轮证据及未验证项](../../reviews/2026-11-04/demand-medical.md)。
