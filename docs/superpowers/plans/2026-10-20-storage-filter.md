# 0.7.0 存储过滤实施计划

依据[设计](../specs/2026-10-20-storage-filter-design.md)。按用户授权由当前代理实施，不派生代理，不提交未跟踪仓库。

1. StorageFilter共享模块：有界配置、树分类注册、具体类型例外、旧标签映射。纯Lua测试隐私优先、覆盖顺序、未知类型、模组适配与无效配置。
2. ContainerRegistry/Work接过滤：configure/read/accepts，源权限与目标物品接纳分离；计划和效果边界双重验证。保留现有任务格式与正常存取协议，测修改过滤后的中断和续工。
3. StorageFilterPanel/StorageTabs接入：原版生命周期、字体相对布局、只编辑草稿、应用再验证；容器栏右键与缓存角标，世界菜单备用。测试按钮池重绑、原菜单保留、草稿/提交、取消和配置事件。
4. 版本0.7.0、CN/EN、完整集中测试；构建及Lua/preflight/release/doclink，归档在线快照与差异、本地证据和未验边界。更新本地BACKLOG/HANDOFF，不编辑在线需求。

结果：上述本地实施完成，构建/Lua/完整门禁/发布/文档检查通过，原版UI/CleanUI/存取与性能实测未运行。证据见[版本记录](../../reviews/2026-10-20/probe-0.7.0-storage-filters.md)。
