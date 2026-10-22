# 仓储正式视觉初版实施计划

日期2026-10-20；状态：用户批准设计范围，主代理顺序实施。

**Spec:** [设计](../specs/2026-10-20-warehouse-visual-design.md)

- [x] 查当前原版图标/占位文字/按钮契约；Theme.lua、ItemPresentation.lua缓存视觉资源，不创建真实物品。
- [x] CachedList可选prepare/draw样式；WarehouseList.lua缓存名称与数量分列/类型图标/来源位置，保留reconcile条目稳定性与滚动。
- [x] WarehouseDetails.lua拆出选中概要和来源列表；Dashboard采用紧凑相对布局、帮助提示与原版关闭/名称键；Summary稳定性不变。
- [x] 扩展双语Kahlua及标准Lua检查；更新捕获宿主呈现主题背景/图标占位，检查实际组件布局。捕获不冒充游戏渲染。
- [x] 构建0.10.0、preflight/release-check/doclink/包源码核对；记录性能边界和集中实机复测，进度本地更新。

不安排代理、不复制AE2实现、不自动提交仓库未追踪内容。无额外审批：用户已批准前述视觉方案并要求开始。
