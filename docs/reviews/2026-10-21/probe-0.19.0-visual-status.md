# 0.19.0 据点三页可视状态

## 范围与结果

用户明确要求同时优化仓储、物流、制作，重点是避免所有状态都由一行文字表达。已实现共用几何状态标记、阶段轨道、计数/进度条和制作情境主操作；保留必要标签和原因，未增加推算百分比或储物容量统计。见[设计](../../superpowers/specs/2026-10-21-settlement-visual-status.md)与[实施计划](../../superpowers/plans/2026-10-21-settlement-visual-status.md)。

仓储覆盖条为已加载容器/已登记容器，不表示填充量；不完整快照单独提示。物流数量条为当前批次已交付/总量，步骤轨道只表达真实阶段；没有任务不绘制0/0数量条。制作主按钮只在本工单中切换下单、暂停、继续，NPC执行其他任务时不能暂停制作；未知提交继续阻断。关闭、切页、任务执行及资产变化沿用既有边界。不可用按钮改为中性边框，红色用于需要核对的状态。

0.18.0用户截图及反馈说明当时制作页可用，不能据此宣称全部保存恢复和异常路径已实机验证。本轮在线需求文档读取失败，不记为已同步。

## 验证记录

CN/EN定向Kahlua各378项及物流页33项通过，输出build/logs/visual-ui-CN.txt、visual-ui-EN.txt。使用安装版Kahlua、原版ISTickBox和真实翻译，ISUI、业务数据、游戏绘制为替身。覆盖状态切换、唯一主操作、未知提交门禁、其他任务忙碌、隐藏释放、不同屏幕字体与绘制不测量。未运行历史全套测试。

可选预览命令：`./tools/test-ui-kahlua.ps1 -SettlementTabs -Preview -Language CN`（EN同理）。输出build/qa/settlement-visual-{warehouse,logistics,crafting}-{CN,EN}.png；来自实际Lua控件布局与准备后的绘制数据，AWT字体和绘制，不是游戏截图。业务数据为合成样例；预览不加载物品图标纹理，不证明原版按钮/手柄和GPU渲染全部正确。

0.19.0构建和固定JAR检查通过，输出build/logs/build-0.19.0.txt；未改Java业务代码。preflight通过，85个Lua语法零错误/警告，LuaLS零错误、既有3条信息提示（调试链重复字段2、旧容器控件构造1），输出build/logs/preflight-0.19.0.txt。发布检查零错误/提示，7份相关Markdown无断链。发布包92个文件与当前模组目录逐字节一致，SHA256为26EE3402D753682899047C35B6F477C99B917482334822840B2FC812F9D9B7D9，核对记录build/qa/probe-0.19.0-package-check.json。新增游戏内显示和交互未验证；没有性能实测结论。
