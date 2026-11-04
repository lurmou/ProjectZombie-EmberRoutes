# UI 字段归属：导航分组 Slice 1

2026-11-04；实施依据为用户指定的 `ui-nav-grouping-slice1-brief.md` 字段归属表。本表承接该权威，不设第二套业务事实源。基线：phase-3a-consolidation / b9da0f2 / 0.29.38。

| 字段／内容 | 维度与唯一归属 | 事实／编辑边界 |
|---|---|---|
| 成员名册 | 人员 / PersonnelPage，按稳定 npcId | 沿用现有成员快照 |
| 健康、出血、感染 | 人员 / PersonnelPage | 只展示现有健康事实，不实现医疗 |
| 技能、知识详情 | 人员 / PersonnelPage | 沿用现有详情服务 |
| 档案抽屉 | 人员 / PersonnelPage | 仍由人员页拥有和释放 |
| 0～4 优先级矩阵 | 成员 × 工种 / PersonnelPage，唯一编辑处 | 表达谁更愿意做哪类活；不是据点规程 |
| 工种规则草稿 | 据点 × 工种 / 工作 → WorkPolicyPage，唯一编辑处 | `JobPolicyService.getDraft(settlementId, category)` |
| 开关字段 | 工作 → WorkPolicyPage | 字段 key、默认值与校验由 JobPolicyRegistry 对应工种定义；不复制定义 |
| 滑杆及其他数值字段 | 工作 → WorkPolicyPage | 同上，沿用现有编辑器与守卫 |
| 区域下拉字段 | 工作 → WorkPolicyPage | 仅引用区域；不定义区域 |
| 据点范围 | 据点，后续聚合页 | 本刀不新建或搬移编辑器 |
| 区域定义 | 据点 / SettlementZones | 本刀不改定义与持久化 |
| 设施 | 据点 / SettlementFacilities | 本刀不改设施能力 |
| 据点账本 | 据点 / SettlementLedger | 本刀不改账本 |
| 活动、活动计划 | 据点 → 既有 ActivityPage | 本刀仅挂组，不重写活动 |
| 防务内容 | 据点 → 既有 DefensePage | 本刀仅挂组，不改业务 |
| 库存、来源、容器规则 | 仓储 / WarehousePage，唯一编辑处 | 现有快照与命令；不复制工单监控 |
| 物品发起制作／配送 | 仓储 → 工作内既有安排入口 | 本刀仅保留现有入口与子视图关系，不新增物品上下文业务 |
| 哪里出问题、影响谁 | 工作 → DemandPage | DemandMonitorService 的只读投影，不新增工单 |
| 谁在处理、缺什么、卡在哪里 | 工作 → DemandPage | 同一问题的既有事实；不伪造处理者或进度 |
| 已安排的工作、当前执行者 | 工作 → OrderMonitorPage | OrderMonitorService，展示不成为执行权威 |
| 真实成果 | 工作 → OrderMonitorPage | 沿用现有事实口径，不新增共同完成百分比 |
| stop / resume / return | 工作 → OrderMonitorPage | 只保留现有命令与守卫，不增加指派 |
| 物流、制作子视图 | 工作 → orders 的 logistics / crafting | 保留 `parentTab=orders`，不复制监控 |

同一工种名出现在人员矩阵与工作规程中表示两个维度，不能合并为一个编辑器。其他页面可以显示摘要或跳转，但不得增加同字段的第二编辑权威。

本刀已做：四组导航、组内单叶页面激活、工作默认需求、窗口会话记忆，以及稳定 ID 上下文管线。人员支持 `npcId`，工单支持 `orderId`，需求支持现有问题行标识 `problemId`；失败留在当前页面。详细契约、证据和 open 项见[切片记录](../../reviews/2026-11-04/ui-nav-grouping-slice1.md)。

本刀未做：据点聚合页、需求／工单构图重构、人员分工细化、头像缓存、ItemSlot、Theme/Layout 扩展、页面重绘风格、手动指派、共同工单与业务调度变化。物品／区域定位、需求按其他关联标识解析仍为 open；不以接口接受 ID 冒充能力完成。
