# 0.10.0 仓储正式视觉初版

日期2026-10-20；用户批准紧凑布局、图标/数量分列、来源详情和统一主题并要求开始。主代理独立实施，未派子代理。依据[设计](../../superpowers/specs/2026-10-20-warehouse-visual-design.md)、[计划](../../superpowers/plans/2026-10-20-warehouse-visual.md)，实机按[集中复测](../../testing/single-player-warehouse-visual.md)。

唯一在线需求v3.2本轮重新导出，SHA256仍为794B68E2357A42451BA76DED8B266E707B94FD1C390ACAEE47AFF5207A2C9BA4。安装游戏JAR基线仍为E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33（42.21.0）；ZombieBuddy基线沿用2.3.4。只读仓储及单人优先边界不变。

## 结果与职责

- Theme集中暗色、细边框、金色强调和交互色；原生按钮保留悬停/焦点行为。窗口由屏幕和UIFont计算尺寸，初始最大90%屏宽、80%屏高，字体单位限制最大尺寸；打开时确定布局，不宣称运行中自动响应系统缩放。
- WarehouseList缓存图标/名称/数量的独立列和行高，可见行才绘制；右对齐数量。CachedList仅新增可选prepare/draw样式，旧筛选组件继续沿用原路径；仓储仍通过reconcile复用条目。
- ItemPresentation按fullType缓存脚本图标或缺失标记；照当前原版ISInventoryItem先取getNormalTexture、有getIconsForTexture时取首项的规则，不创建真实InventoryItem，不保存世界物品引用。未知类型显示占位，不影响盘点。
- WarehouseDetails拆分选中物品概要与来源列表；来源优先自定义名，再使用原版容器翻译键，最后通用容器名。坐标/楼层单独显示，完整稳定ID进入Tooltip。选中名称布局在数量变化时保持同一缓存。
- 顶部固定统计和独立状态、搜索分类、分页保留；长解释移入帮助Tooltip与原生ISModalDialog，面板底部仅一行提示。帮助只开一份，父窗口关闭释放帮助与Tooltip、订阅及图标缓存。
- 通用名称/关闭直接使用原版IGUI_Name/UI_btn_close；其他新增键CN/EN成对，物品名跟随游戏语言。帮助修正此前“仅主容器”的过期说明，明确含已登记冰柜分区。

## 原版契约来源

核对当前安装media/lua/client/ISUI中的ISInventoryItem.lua（renderScriptItemIcon）、ISTextEntryBox.lua（setPlaceholderText）、ISButton.lua（backgroundColorMouseOver、Tooltip）、ISScrollingListBox.lua（addItem第三参数Tooltip、render清Stencil）、ISModalDialog.lua（new/initialise/destroy及确认回调）；FindItem由当前原版ISLootZed等调用支持。没有从旧反编译树猜接口。

空态文字在列表原生render后绘制，避免被列表背景遮住，行数受可用高度限制。新绘制只读缓存，不访问库存、不重新解析名称、不重新度量文字；原生ISUI仍每帧绘制，不能宣传GPU只绘脏区或零CPU。

Text.wrapLimited复用原有Kahlua/UTF-8字符边界，截断时把省略号纳入宽度计算；长名称、来源和底部提示不会因为追加省略号挤入相邻列。翻译字符串的限行和列宽由标准Lua与实际Kahlua共同检查。

原生ISModalDialog.destroy会恢复游戏速度；帮助实例单独限定destroy为隐藏/移出UI，确认回调负责恢复面板焦点，父窗口关闭统一释放。这样打开或关闭只读帮助不改变玩家暂停/倍速。

## 已运行与边界

实际安装Kahlua和CN/EN真实翻译分别通过59项据点UI检查；标准Lua55项。覆盖旧分页/搜索/行身份/选择/滚动/权限清理，以及新图标缓存、缺失缓存、技术ID显示边界、帮助生命周期、概要缓存、四种分辨率/字号下两栏可用高度和数量列边界；绘制阶段强制禁止字体度量调用。Kahlua仍通过77仓储、24过滤窗口、21侧栏检查。

捕获build/qa/probe-0.10.0-warehouse-CN.png与EN.png已目视检查，使用实际组件布局/绘制调用和AWT字体；ISUI宿主和图标为替身，此捕获不是游戏截图。真实图标、Tooltip、手柄、CleanUI兼容、GPU耗时和实机缩放未运行。

固定基线构建通过65项Java、42项检查点门禁及override-first类加载冒烟，包为build/packages/EmberRoutesProbe-0.10.0.zip。完整工具输出在build/logs/0.10.0-*；静态门禁/包比对结果在最终补记记录。

本轮没有更改库存权威、候选有效性、真实搬运、存档协议；未加入自动分拣/BOM/生产/网络镜像。后续业务复用小组件，不把本轮当作完整UI框架或全部需求完成。

最终补记：preflight完整通过，45个生产Lua、0错误/0警告；最终输出以build/logs/0.10.0-preflight-complete.txt为准。release-check零错误/提示，8文档doclink零断链/提示。包内52文件与当前源码逐字节一致；SHA256为067B05EEFDD2A15272C5EB13743C2F203F7E925608DFF12C1E26F92FFD63947B。原版语料的ISFluidEmptyAction.lua含0.0f而工具解析跳过，此为既有原版覆盖边界，不是本模组错误。新实机仍待用户复测。
