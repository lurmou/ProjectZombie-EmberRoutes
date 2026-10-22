# 0.16.0 统一据点窗口

日期：2026-10-21。状态：实现与必要本地检查完成；真实游戏渲染/交互未验证。主代理独立实施，未派生子代理。

## 需求与实现

用户批准[设计](../../superpowers/specs/2026-10-21-settlement-tabs-design.md)后实施[计划](../../superpowers/plans/2026-10-21-settlement-tabs.md)。本轮重新读取唯一在线需求，正文SHA256仍为 `3A179F1907B8971E0DD13F8FC2FFA300F0661E6F68C7AA0E7EC3E37202499834`。安装基线经版本构建核对仍为PZ42.21.0、ZombieBuddy2.3.4，对应JAR哈希未变。

SettlementDashboard只负责标题/页签/统一关闭、单例与每秒世界/玩家/据点权限复验。WarehousePage和LogisticsPage是独立ISPanel内容页，复用原有WarehouseControls/Rows/List/Details、Summary、LogisticsCards/Presentation、State等组件。物流旧open入口转发统一窗口的物流页；同玩家/同据点重复打开复用外壳，换据点先销毁旧窗口。

页签由原版ISButton组成，不改全局ISTabPanel。顶部为仓储、物流和统一关闭；选中页使用金色边框。键盘PageUp/PageDown切页，手柄在左栏左侧/右栏右侧按方向键切页，中间方向仍在列表间移动；仓储LB/RB翻页保留。操作提示放在页签Tooltip。外壳以屏幕和字号限制尺寸，720p大字体时仓储降低间距，保留定位反馈行和可用来源列表，不通过压出负尺寸挤入控件。

## 生命周期与性能边界

PageLifecycle.mount/unmount以激活令牌守卫通知，先清活动状态与引用再释放。watch同步回调关闭窗口时，watch返回的释放句柄立即执行；外壳先加入UIManager再激活，避免同步关闭后被addToUIManager再次加入。关闭与释放幂等，晚到的旧通知不更新隐藏页面。

切走仓储时释放Index.watch、状态订阅、Tooltip、独立下拉弹层、帮助窗口和定位标记，并取消输入焦点；切走物流时释放视图订阅。隐藏页不运行查询/状态投影/排版。物流后台会话与原工单继续，由原服务负责，不被窗口关闭或切页停止。

仓储最后一个消费者退出会删除该盘点上下文，这是原WarehouseIndex的语义。重新访问可能重新有界扫描；本轮没有添加隐藏订阅或长期库存缓存掩盖这一点。筛选/排序/查询保留，返回UPDATING时不显示旧可用数量，READY时按稳定fullType恢复合法页码/选择和滚动。物流按npcId保留工人选择。没有Java批量读取或ID定位迁移，没有更改资产效果/任务认领与调度。

## 验证与证据

- `tools/test-ui-kahlua.ps1 -SettlementTabs -Language CN/EN`：当前安装Kahlua与stdlib，显式next=nil，真实CN/EN翻译；统一窗口与两个真实页面303项检查（包含控件挂载断言），另21项实际安装ISTickBox构造/物流布局检查通过。覆盖仅初始页挂载、重复入口/切页、隐藏通知、恢复查询/选择/滚动、弹层/帮助释放、同步关闭、世界/玩家/权限变化及720p大字体/1080p/2K/4K相对布局。其余ISUI宿主为替身，不是游戏截图或实机输入证据。
- 标准Lua5.1可执行文件因本机DLL重定位错误未能启动；尝试单独启动历史settlement-ui夹具也因其原生控件依赖未齐备未通过，不记作通过。未以此展开历史全套排障，改用上述本轮完整页面的限定Kahlua宿主验证；旧内容夹具仅更新新页面入口。
- 版本构建通过，保留原Java业务源码，仅重编版本元数据与本地包；构建内置基线/逻辑/检查点/名单/类来源/表迁移检查通过。不以这些替代本轮UI实机验证。
- 必要原始输出位于 `build/logs/0.16.0-ui-CN.txt`、`0.16.0-ui-EN.txt`、`0.16.0-build.txt`、`0.16.0-preflight.txt`。最终LuaLS输出另留 `0.16.0-luals-final.txt`，文档/发布检查分别留 `0.16.0-doclink.txt`、`0.16.0-release-check.txt`。

尚未运行实际游戏。日常只需从原入口打开，切换仓储/物流并关闭重开，观察运行中的NPC继续物流；无需重跑历史十项验收。真实绘制、输入路由、其他UI模组兼容和性能规模仍未验证。

最终收尾：完整preflight通过；74个Lua文件语法0错误/警告，结构/祖先绘制/候选约束检查通过。详细LuaLS最初提示据点窗口构造参数类型缺失，已补齐注解；最终0错误，只保留DebugMenu动态包装与ContainerConfigControls分阶段构造的两条既有信息提示。原版Fluids/ISFluidEmptyAction.lua含0.0f的已知解析缺口仍单独报告，不把它当作模组无错误的证据。doclink检查8个文档，0断链/错误；release-check为0错误/提示。

最终ZIP为 `build/packages/EmberRoutesProbe-0.16.0.zip`，81个文件与当前模组目录逐字节一致；SHA256为 `58A88CA949B900408BB1DA9C1C2922CF9B3FFDC8515D279B2173DB6FB3931CC2`。机器可读核对为 `build/qa/probe-0.16.0-package-check.json`。工作目录已更新，无工坊发布。
