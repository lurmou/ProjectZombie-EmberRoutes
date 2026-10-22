# 0.11.0 仓储查询与交互收口

日期2026-10-20；状态：本地检查完成，新实机待验。用户批准排序/筛选、来源定位、交互状态和性能基线，主代理独立实施。见[设计](../../superpowers/specs/2026-10-20-warehouse-interaction-design.md)、[计划](../../superpowers/plans/2026-10-20-warehouse-interaction.md)、[集中复测](../../testing/single-player-warehouse-interaction.md)。

在线唯一需求本轮导出仍为v3.2，SHA256为794B68E2357A42451BA76DED8B266E707B94FD1C390ACAEE47AFF5207A2C9BA4。基线仍PZ42.21.0（JAR E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33）、ZombieBuddy2.3.4。单人优先，未改资产权威、真实转移或存档数据格式。

## 查询与组件

WarehouseQuery.new按行数组身份、规范化搜索、类别和排序缓存匹配顺序及fullType→位置表，翻页只提取最多60项；一次性page旧接口保留。新增名称/数量升降，默认仍沿用后台稳定顺序；未知数量最后，tie按fullType，原始快照不变。名称是当前语言字符串比较，不承诺中文拼音排序。

实际安装Kahlua的table.sort自定义比较器在2048项倒序输入上发生递归栈溢出，本轮用显式循环的自底向上归并排序替换查询路径，O(n log n)比较、O(n)辅助空间，无递归。没有扩大类型上限；后端既有分片归并未变。排序/筛选仍在条件或快照变化时同步执行，不能声称无限数据量无卡顿。

WarehouseControls组装搜索/清空/类别/排序；WarehouseInput负责列表焦点和激活；WarehouseDetails保留来源选中及定位按钮；Dashboard协调状态。普通数据更新锚定选中fullType及其页，CachedList在结构变化时可按选中行偏移调整滚动。主动查询/翻页重置浏览，派生页码同步回State时避免递归重置；不再把实际页码和State页码分离。

按钮状态由数据变化更新；加载/空结果/错误分别呈现。Tab/Enter、手柄左右/A及旧快捷键沿用同一动作，搜索框、下拉弹出和帮助拥有输入时列表不抢键；手柄按左右摇杆分别清搜索/循环排序。输入硬件与原生事件分发仍待实机。

## 只读来源定位

WarehouseLocator捕获世界账本及cell，只接受稳定容器ID；Ledger.view、Geometry、Registry.describe/resolve依次复验当前权限、位置、范围和真实分区。未加载、移除、私有、重复身份、作用域变化均拒绝；不从旧行猜物理目标。成功用原版addAreaHighlightForPlayer在XYZ显示5秒，短租约注册OnRenderTick，500ms重新校验身份/权限，不每帧扫描库存；到期/时间倒退/世界cell变化立即释放，权限变化最多500ms生效。一个活动定位租约，跨面板重定位替换旧租约；关面板后保留剩余时间方便观察。

原版证据：ISRemoveItemTool动态Add/Remove OnRenderTick；FireBrushUI和ISAddDesignationAnimalZoneUI调用addAreaHighlightForPlayer的半开矩形参数；ISTextEntryBox.isFocused、ISComboBox.expanded/setToolTipMap、ISButton.setEnable及JoyPadSetup左右摇杆常量均由当前安装Lua核对。没有替换原版文件，modscan无整文件冲突；不等于真实CleanUI兼容验收。

## 有界性能采样

ProbeRuntime新增只读diagnosticTimeNanos调用System.nanoTime，由已有Exposer暴露；没有修改引擎渲染。WarehouseMetrics默认关闭；调试菜单开启/结束，一次汇报聚合数据。固定7阶段、每阶段最多2048样本，只留128值窗口算近期p95，关闭不读时钟；跨世界自动停止。ui.open、ui.query、ui.update、index.slice、ui.panel、ui.items/ui.sources分别对应打开、纯查询、更新、后台切片、自有面板和列表绘制提交。

这些是带采样开销的CPU墙钟；index.slice包含可能的订阅更新，ui.update也包含查询，不是互斥阶段，不能相加估计整帧。没有GPU计时、驱动同步或FBO注入，不能推断GPU瓶颈。

纯VM基线：CN/EN真实Kahlua各对2048类型预热30次，再平均30次完整数量排序及300次缓存翻页。最终CN完整排序均值14.6380ms、缓存页0.0181ms；EN分别15.2541ms、0.0206ms，详见build/logs/0.11.0-ui-CN.txt与EN.txt。该输入是替身数据，没有引擎库存、GPU或整帧测量；机器噪音与JIT影响存在，不能宣传固定性能倍率。

index.slice也包含有订阅但无实际工作/尚在防抖等待的调用；平均值不代表一次完整盘点，需结合max、采样场景和其他阶段看。实际安装stdlib.lua:67–81使用首元素pivot并递归调用quicksort_comp，与本轮栈溢出根因相符。

## 验证边界

当前双语Kahlua73据点UI、77仓储、24筛选、21侧栏；新增7查询、7采样、13定位（真实Registry/Ledger配替身世界）通过。标准Lua据点UI69项，少4项真实翻译宽度检查。覆盖未知量/稳定tie/缓存/跨页、行重排保持选中屏幕偏移、拒绝旧世界/私有/卸载/移除、标记到期/替换/复验频率、禁用采样不调Java时钟与容量上限。

AWT捕获build/qa/probe-0.11.0-warehouse-CN.png及EN.png由实际组件调用生成并目视检查，宿主/贴图为替身，不能冒充游戏截图。真实标记可见性、手柄、Java暴露时钟、游戏缩放与实际耗时仍待用户集中复测。本地构建/静态/包比对最终结果在交付补记。

最终补记：preflight（build/logs/0.11.0-preflight-final.txt）49生产Lua、0错误/0警告；固定基线构建65Java/42检查点门禁及override-first加载冒烟通过。release-check零错误/提示、8文档doclink零断链/提示；modscan无文件冲突。包内56文件与当前源码逐字节一致，0.11.0 ZIP SHA256为5226BA250F25FCE07DFB48F6E9CF634B039AE78523C86B7E725D93FB84C5B01D。当前原版ISFluidEmptyAction.lua含0.0f而语料解析跳过，为既有工具覆盖边界。
