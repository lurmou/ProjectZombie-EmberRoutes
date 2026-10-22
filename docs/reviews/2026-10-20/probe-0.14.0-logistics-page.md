# 0.14.0 统一物流管理页

日期2026-10-20；状态：本地实现与必要门禁，游戏新页面未验。

用户批准轻度实施统一物流页。已重新读取唯一在线v3.2，SHA256仍为794B68E2357A42451BA76DED8B266E707B94FD1C390ACAEE47AFF5207A2C9BA4。PZ42.21.0/ZombieBuddy2.3.4基线保持；当前JAR javap核对IsoGameCharacter.getFullName，原版ISTickBox核对new/addOption/setSelected与回调参数。

正式右键“余烬商路 → 据点物流管理 - 据点名”直接开窗口，替代旧物流命令子菜单。顶部启停和两个模式，中部工人姓名/交付数/等待原因与任务来源目标，底部加入空闲/当前NPC、移出、指定工人重试、重新扫描与打开仓储。个体重试不打断其他工人，不覆盖未完成手动任务；移出不销毁原货。关闭只释放订阅，不停止物流。重进后仍需明确启动。

职责：LogisticsDashboard组装Layout/Theme/State/CachedList；LogisticsPresentation缓存姓名与稳定行并生成详情；LogisticsText统一CN/EN状态翻译。LaborSignals只发送离散工单状态/交付变更，观察者异常不撤销资产。Service.watch置脏后在既有tick末合并只读DTO，没订阅不构造界面快照，绘制不读库存。按npcId复用行并保持选择/滚动；窗口打开时每秒核查权限/世界，不轮询生命/耐力。当前基础键盘列表导航、ESC及手柄列表/切换、X重扫/Y启停/B关闭已接原组件；没有宣称所有按钮完整手柄导航或4K观感已实测。

实现次序见[计划](../../superpowers/plans/2026-10-20-logistics-page.md)，使用见[物流说明](../../testing/single-player-automatic-logistics.md)。只跑必要静态/发布检查与版本构建，没有重复历史Lua全量断言；具体输出留build/logs/0.14.0-*。实际布局、鼠标/手柄和事件刷新仍需日常游戏确认，不新增长实测清单。

完整preflight通过；窗口构造器类型声明补齐后最终LuaLS为0错误、1条原有Debug链式替换字段警告（未屏蔽）。最终67个Lua语法0错误/警告，release-check0错误/提示，7份Markdown断链/提示0；构建完成，74文件ZIP与模组目录逐字节一致。最终包SHA256 `1946DFE5E1EFFC2E47DE7191E37AE91D50D89A85D6DDBBD1CAF0332D375BB972`，见build/qa/probe-0.14.0-package-check.json。
