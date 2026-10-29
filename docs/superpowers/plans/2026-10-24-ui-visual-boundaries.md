# UI视觉与视口修整

日期：2026-10-24。状态：实施中。依据已确认settlement-ui-design及用户继续改善授权。

1. 复用Layout/Text/Theme/State/CachedList，补Viewport有界自绘和恢复遮罩契约；不另建UI框架。
2. 修仓储自绘网格缺失视口、提示越界，保留部分可见内容自然裁剪；空列表也受视口约束。
3. 人员长详情改CachedList滚动；说明移至提示，优先级显示数字与形状，避免重复长句。
4. 工单列表以图标、名称、人员、阶段及数量进度表达；异常保留文字，不能仅用颜色传义。
5. 复核当前原版Lua裁剪接口，Kahlua覆盖边缘/异常恢复及双语页面，preflight/构建。历史PZ Optimization缓存根因未确认，不能宣称GPU实机已修复。

当前实施结果与未验边界见[记录](../../reviews/2026-10-24/ui-visual-boundaries.md)，新增InfoList/Viewport及BlueprintRows；最终preflight/解析/结构检查通过，未做GPU实机验收。
