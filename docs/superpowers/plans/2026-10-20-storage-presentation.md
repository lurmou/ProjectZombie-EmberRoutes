# 仓储呈现实施计划

依据[设计](../specs/2026-10-20-storage-presentation.md)。用户已批准整套方案；主代理实施、Luna只读复核，不提交整个未跟踪仓库。

目标：小容器按钮在原有空间清楚表达仓库用途，筛选操作可读。

架构：StorageTabs只在绑定和注册事件更新ISButton.image/tooltip，不再包装render；撤销仅恢复自己仍拥有的字段。Panel保留Editor规则与原版列表输入，缓存绘制数据。Lua、原版ISButton/ISScrollingListBox，CN/EN。

重点：按钮池复用、其他模组改变图像、缺失纹理、已保存但当前无实例的具体类型、长中文/大字体。

1. 修改StorageTabs.lua及storage-tabs-test.lua：原版绑定先撤销自有字段、再捕获新image/tooltip，配置刷新替换主图；未配置/禁用探针恢复；测试池复用、事件、原render和菜单、悬停、例外及缺失纹理。
2. 用户确认窗口范围后修改StorageFilterPanel.lua及storage-panel-test.lua：行名称/状态/换行缓存、方框绘制、分组层级；getItemNameFromFullType仅刷新调用，未知回退。保留Editor草稿、键盘与手柄提交检查。
3. CN/EN文案与0.7.2版本；构建、相关Lua测试、preflight、release-check、doclink。归档证据，更新HANDOFF/BACKLOG和同会话集中测试。实机未运行如实记录。

实际发布范围和执行结果在版本评审记录更新；不给未执行步骤打勾。

执行结果：上述三项已实施；构建、两套针对性Lua回归、preflight及发布/文档检查通过。Luna发现的不可见行绘制问题已修正。实机待验，见[版本记录](../../reviews/2026-10-20/probe-0.7.2-storage-presentation.md)。
