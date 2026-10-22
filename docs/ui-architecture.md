# ISUI基础与实施边界

0.21.0已接[配方浏览与条件适配](reviews/2026-10-22/probe-0.21.0-crafting-browser.md)：CraftingPage仅管理内层视图生命周期；CraftingBrowser/CraftingDraft/RecipeGrid负责下单与图标槽，CraftingOrders复用工单视觉。目录缓存、只读预检、执行命令分开，代次取消和隐藏释放；新增实机/性能未验，下方提案与版本段落为历史截点。

下一轮设计提案：[制作浏览与条件适配](superpowers/specs/2026-10-22-crafting-browser-design.md)。原版条件驱动适用组件、分离配方草稿/工单、图标槽与下单预检，尚未实施。当前0.20.2只完成[制作说明修正](reviews/2026-10-22/probe-0.20.2-crafting-clarity.md)，下方版本段落为历史截点。

0.20.0制作页增加显式recipeId/数量命令及“已制作/已入库”双计数条，详情读取父单实际配方名称与目标，数量无效禁用下单。完整可搜索配方目录未进入本轮；当前只展示两个同机制样本。见[通用生产边界](reviews/2026-10-22/probe-0.20.0-generic-production.md)。

0.19.0新增[三页可视状态](reviews/2026-10-21/probe-0.19.0-visual-status.md)：StatusVisual共用几何状态标记、徽标、阶段轨道与数量条；CraftingCards准备列表/详情绘制数据，Summary显示真实盘点覆盖。绘制不测量，隐藏页仍释放订阅；阶段轨道不能冒充精确百分比。CN/EN替身宿主预览位于build/qa，新增实机未验。

0.18.0新增[单件制作页](reviews/2026-10-21/probe-0.18.0-crafting-orders-resume.md)：统一外壳三页，CraftingPage复用PageLifecycle、State、Layout和CachedList；CraftingService只在可见订阅置脏后构造标量副本，渲染不读库存。普通右键显式选择平台，不扫描家具。当前仅单件木制餐叉，新增实机未验。

0.16.1修复[物流进度与批次可见性](reviews/2026-10-21/probe-0.16.1-logistics-progress.md)：执行层统一数量/阶段事件；UI读sourceMode/phase及同据点的会话最近完成摘要，缓存纳入阶段与摘要。当前批次与上一批完成分开；不延迟接单、不加库存扫描或持久历史报表。摘要每NPC仅一条标量副本，clear/换世界清理。

0.16.0新增[统一据点窗口](reviews/2026-10-21/probe-0.16.0-settlement-tabs.md)：SettlementDashboard只管外壳/页签/身份/焦点；WarehousePage与LogisticsPage独立内容面板，PageLifecycle处理激活令牌、状态订阅和同步watch关闭时的释放句柄。仅当前页订阅，隐藏页停止查询/投影；后台物流不受影响。关闭/切页释放定位、帮助、下拉弹层与Tooltip；原物流入口转发同窗。尚无制作、报表页或通用第三方页注册API，当前原版按钮页签不等于完整通用组件库。

0.15.1修复物流页：原生ISTickBox构造高度即勾选框尺寸，必须传字号尺度，而非区域高度；LogisticsCards拆分稳定行样式与单卡滚动详情，复用原版滚动容器但不绘制逐条选中块/短文本Tooltip。关闭回调引用先清且幂等。见[实机故障与修复边界](reviews/2026-10-21/probe-0.15.1-logistics-repair.md)。

0.14.0新增[统一物流管理页](reviews/2026-10-20/probe-0.14.0-logistics-page.md)：复用主题/相对布局/State/稳定列表；业务事件置脏，在现有服务tick末合并只读摘要，未订阅不构造，关闭释放；姓名/行文案/详情由Presentation生成，绘制不查库存。只有窗口打开时的每秒权限/世界核查，不做生命/饥渴轮询。尚非完整据点主面板/BOM系统。

0.11.0新增WarehouseControls、WarehouseInput与WarehouseLocator。查询面板拥有WarehouseQuery.new缓存，源行保持稳定身份；排序后依选中类型同步页码并保留行偏移。来源定位以最新账本/物理身份复验，5秒租约与500ms权限复验只在标记存续时工作。WarehouseMetrics通过Java只读nanoTime按需记录有限CPU样本；不是GPU计时，关闭不读时钟。见[实现/基线/边界](reviews/2026-10-20/probe-0.11.0-warehouse-interaction.md)。

0.10.0实现仓储正式视觉初版：Theme统一视觉，ItemPresentation缓存脚本图标，WarehouseList提供缓存表格行样式，WarehouseDetails组装选中概要/来源。Dashboard负责布局、状态订阅和输入协调；数量变化复用条目及名称排版，技术ID放Tooltip，长说明由原生帮助窗口承接。见[实现与边界](reviews/2026-10-20/probe-0.10.0-warehouse-visual.md)。首次视觉方案已落地，实机待验，仍非完整经营UI或通用组件库。

0.9.2新增Summary：固定统计网格的setValues与独立setStatus分开更新；普通存取保留上次完成统计、状态单独切换，解释仅变化时排版；未知/撤权/错误清空旧量。字体度量与坐标仅初始化计算，无库存读取或额外订阅。见[修复与实机步骤](reviews/2026-10-20/probe-0.9.2-stable-summary.md)。

0.9.1补充：WarehouseRows.project把业务快照投影为稳定展示行，待核实count=false并标pending；CachedList.reconcile按稳定key复用条目与未变文字，只在成员变化时调整数组/滚动高度。Dashboard只在用户改变筛选/页码时重置浏览位置，普通数据通知保持位置。见[修复与测试](reviews/2026-10-20/probe-0.9.1-warehouse-dirty-ui.md)。这不是GPU局部重绘实现。

0.8.2增加TooltipAnchor：仅包装本模组实例，原版回调后统一跟随鼠标提示的屏幕坐标；固定/显式位置不覆盖，刷新和关闭释放。当前仓储为功能验证阶段，组件基础不等于最终视觉样式，见[修复与视觉状态](reviews/2026-10-20/probe-0.8.2-tooltip.md)。

日期：2026-10-20；从0.7.3开始适用。需求为唯一在线文档第11节，以及用户本轮重申。本文是实现契约和进度说明，不替代或修改在线需求。

## 当前可复用基础

客户端模块根：Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI。

| 模块 | 消费与产出 | 责任和生命周期 |
|---|---|---|
| Text | wrap(text,width,font) → lines | 兼容游戏Kahlua的Java字符与标准Lua UTF-8；保留显式换行。只在打开、尺寸/状态变化时排版，绘制不测量；UIFlow仅兼容入口 |
| Layout | axis(bounds,tracks,style) → rectangles或nil,reason | direction为row/column，bounds相对坐标，style提供padding/gap，track提供basis/grow/margin；不足空间拒绝负尺寸。文本wrap由Text承担 |
| State | new(snapshot) → store；setState(patch)；subscribe(fn) → unsubscribe | 浅快照替换，改变分支必须给新表；无变化不通知；视图关闭时释放订阅。没有每帧轮询、网络功能或自动深层代理 |
| CachedList（0.8.0） | create/fill缓存行与输入回调 | 通用只读列表，屏外短路；仓储使用60项分页，派生行由状态改变时缓存 |
| FilterList | create(owner,bounds) → 原版列表；refresh(owner) | 独立负责行文案/状态/高度缓存、可见行绘制和原版列表生命周期。配置规则仍由共享FilterEditor负责 |

StorageFilterPanel负责组装布局、键盘/手柄输入和提交。编辑时复制草稿并通过store:setState发布；订阅按变更分支刷新缓存。列表不访问世界、脚本库或库存；窗口打开时仅有界读取当前类型。底部按钮使用原版ISButton，未来其他面板直接复用上述契约，出现实际第二种需求后再提取新组件，避免预建未使用的组件库。

文本全部按游戏当前语言：通用动作优先原版键UI_btn_apply/UI_btn_cancel；专属文案使用模组CN/EN键；物品名getItemNameFromFullType，未知类型才回退fullType。实际容器名不自动覆盖，悬停追加用途与规则摘要。测试中的中文用例不代表产品强制中文。

## 每帧与更新边界

业务状态、物品索引、名称解析和排版仅在打开/配置/输入等离散变化时更新；未发生变化不做数据同步。原生ISUI依然按游戏帧绘制，不能把“事件驱动”说成GPU/绘制零开销。轻量选中和悬停效果沿用原版；不靠每帧扫描NPC状态维持UI。后续HUD必须接离散装备/成员/指令事件，而不能新增每帧生命/饥渴读取。

## 仍未实现

- 通用TabContainer、ItemSlotGrid、ProgressBar等组件及过渡动画：有对应业务时逐项实现，当前不能宣称完整组件库。
- 据点管理：0.8.0开始使用基础范围/只读仓储、搜索分页和来源面板，见[独立契约](settlement-storage-architecture.md)。完整经营、BOM委托和生产工单未实现。
- 队伍头像/姓名/装备HUD、网络UI状态镜像：未实现；目前单人优先。
- 对正在打开窗口的所有缩放/语言切换的即时自适应、任意UI模组兼容和完美4K观感：未验；当前在打开窗口时读取尺寸与字体。

## 必须补足的验证

标准Lua只是逻辑检查，不代表Kahlua字符串语义。tools/test-ui-kahlua.ps1使用当前安装JAR与stdlib.lua，读取真实CN/EN JSON，通过Java注入翻译字符串，覆盖文字保留、实际筛选组件、容器提示、行高、布局及订阅释放。ISUI宿主和字体测量为替身，因此仍不能代替游戏渲染/交互。

该脚本生成build/qa下CN/EN布局预览：实际组件的坐标/绘制调用与文字，由AWT字体绘制；不是游戏截图。实机检查还须观察中文/英文、原版容器悬停、选中/滚动、大字体、保存配置。性能须单独测量，不能由缓存设计推断支持某一规模。

本轮原因与证据见[0.7.3记录](reviews/2026-10-20/probe-0.7.3-ui-foundation.md)。
