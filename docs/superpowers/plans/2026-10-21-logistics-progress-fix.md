# 物流进度与批次可见性修复计划

用户已批准[核查建议](../../reviews/2026-10-21/logistics-progress-audit.md)并要求开始修复。主代理独立执行；使用brainstorming确认的范围与writing-plans实施清单，不派生代理。在线正文已重读，SHA256仍为3A179F1907B8971E0DD13F8FC2FFA300F0661E6F68C7AA0E7EC3E37202499834。

**目标：** 0.16.1修复自动批次漏发进度；明确入库/错放、取货/交付、当前批次和最近完成。保持原件认领、容量仲裁和接单节奏。

**设计：** WorkBatch只选择与计数，WorkAgent统一提交delivered与阶段通知，包括完成分支。LaborStore按NPC暂存本次世界会话的一条完成标量摘要，Work.lastCompleted提供副本，Service.status附带该据点的摘要；不新增持久化格式、库存扫描、延迟接单或历史报表。UI通过既有State/Presentation/Cards事件投影，缓存须比较阶段与摘要。

**接口：** Store.recent(npcId)和Work.lastCompleted(npcId)返回摘要副本或nil；摘要含id/settlementId/sourceMode/delivered/total。世界切换清空，显式clear清掉该NPC摘要；不持有原件或引擎对象。

**重点边界：** 同帧DONE→新单仍能读到上一单；阶段变化但计数不变也通知；暂停不伪造完成；清理与跨世界不保留旧摘要；隐藏页不更新；未完成物品继续被认领排斥。

- [x] 新增真实控制器Kahlua回归，先确认原代码在部分进度通知处失败。
- [x] 修改WorkBatch/WorkAgent/LaborStore/Work/LogisticsService，验证进度、阶段、换单摘要、标量副本和认领排斥。
- [x] 修改LogisticsPresentation/Cards及CN/EN；验证同进度的阶段变化、当前/完成批次身份、最近完成显示与缓存更新。
- [x] 相关双语Kahlua、preflight与版本构建；0.16.1本地包核对，更新接力/待办/修复记录。未运行真实游戏明确记录，不跑历史全套。
