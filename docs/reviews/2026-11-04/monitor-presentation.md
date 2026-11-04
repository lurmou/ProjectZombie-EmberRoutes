# 需求与工单展示整理

基线：phase-3a-consolidation / dd2199e；候选版本 0.29.37。

自动清洁只在需求页汇总，工单服务不再投影 FIELD_WORK 清洁；原 Job 和原件责任不变。需求处理状态取实际执行事实，已分配处理者时隐藏过期的“等待空闲人员”文案；暂停与 UNKNOWN 不伪装进行中。

订单详情改为现有 InfoList、CardPanel、SemanticBadge 和 StatMeter 组合：摘要、真实数量进度、当前人员/行动、按物品与托管状态分组的原件。坐标、归属和步骤只在展开后显示。清洁工具不增加独立托管工单。列表取消技术步骤轨道，空计数筛选默认隐藏。新增卡片分支的文字测量与布局在 prepare 完成，draw 消费缓存；不宣称既有整个 UI 已达到零分配。

人员职业拒绝泄露未翻译的 IGUI_/UI_ 键；楼层按用户要求仅显示时四舍五入，物理 z、寻路与任务目标未变。

验证：安装版 Kahlua 的 demand-monitor、order-monitor-service、order-monitor-view、personnel-enrich、demand-page 五套通过；其中新增卡片绘制在文字测量接口抛错时仍通过。CN/EN 实际组件的 AWT 合成布局预览可生成，预览不是游戏截图。真实渲染、鼠标与原生动作未验证。既有完整历史回归及 preflight 的基线问题见同日 demand-medical 专题，不把本轮定向通过扩写为全门禁通过。

视觉方向参考 [Frostpunk 2 UI 设计师作品](https://kugalus.artstation.com/projects/QKDWZB)与 [Relictor UI/UX 概念](https://goodmantactics.artstation.com/projects/DYAyYA)。本提交完成信息整理及组件复用；用户要求的更强游戏感视觉仍待进一步设计实现，不以卡片化宣称高级感验收完成。混装多目标搬运也尚未由本提交实现。
