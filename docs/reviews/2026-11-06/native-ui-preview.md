# 原版 UI 独立预览原型证据

日期：2026-11-06。只验证外部调试工具，不变更生产 UI 或业务契约。

## 基线与实现

- 安装目录：`D:/Software/GameApp/steam/steamapps/common/ProjectZomboid`。
- `projectzomboid.jar` SHA256：`E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`。
- 实际 GPU 日志：`GL 4.6.0 NVIDIA 617.14`。自带 JVM 的 JOML/Unsafe 弃用警告保留，不作为失败隐藏。
- 当前 JAR 的 UIElement.DrawText → TextManager → AngelCodeFont；纹理 → SpriteRenderer。原版 Lua ISUIElement.instantiate 创建真实 Java 句柄。独立启动未调用游戏 MainScreenState/main，不加载世界或存档，不添加启动器 NPCFW/优化代理。
- 窗口创建/认领：[NativeUiPreview.java](../../../tools/ui-preview/NativeUiPreview.java) 的 Display.init/create；正常释放和异常释放共享 finally，移除 UIManager 根节点、销毁字体/纹理管理器、Display.destroy。清理后 System.exit 结束引擎非 daemon 文件线程；PowerShell 仅监护、超时终止自身子进程，不结束游戏进程。

## 已通过

1. 实际 Java 编译及原版渲染链启动：原版字体、贴图、面板、按钮、禁用样式、透明叠加、Stencil 裁剪和清除后继续绘制，均通过截图人工检查；没有 AWT 控件绘制。
2. 原版 UIElement 接收合成按下/释放坐标，真实 ISButton 触发一次回调；禁用按钮未触发回调。
3. 仓库真实 StepperInput 经根节点分发触发 +1，回调收到 6；设到 20 后继续增加维持 20。真实 CardPanel 绘制可见。
4. 原版 ISScrollingListBox 接收滚轮后目标为负数，截图可见从第 2 行开始及底部裁剪。此证据不替代真实鼠标滚动验收。
5. 正常退出及“原生 UI 创建后故意抛异常”均输出 `CLEANUP display destroyed`；故障运行返回非零且保留日志，不输出成功结果。

已查看的最终原生截图：[项目组件场景](../../../build/ui-preview-native/20261106-162116-209/native-ui.png)。对应运行目录含 run.json、stdout.log、stderr.log；禁用按钮与普通按钮持有相同回调，检查确实覆盖禁用守卫。非 Smoke 的两秒交互循环在 `build/ui-preview-native/20261106-162046-915/` 正常退出；最终宿主注入失败证据在 `build/ui-preview-native/20261106-162008-933/`，退出码为 1 且释放标记存在。核查无 NativeUiPreview 子 JVM 残留。早期排查截图/失败也保留在 build，不能当作最终成功结果。

本轮四份新增/相关说明入口的文档链接检查通过；包含 BACKLOG 的五文档检查失败于原有 `docs/BACKLOG.md:21` 仓库外 `.gemini/.../settlement-ui-redesign-spec.md` 断链，未修改该并发 UI 条目。定向 diff 空白检查通过。

## 未解决与未验证

- 中文：Java 注入的 Unicode“中文”样例正确可见；直接 Lua 中文字面量在 Reader 编译入口曾乱码，loadstring 入口的 Unicode 等值探针也失败。未修补游戏编译器、未改生产组件。部分测试用简体字在当前选中字体定义中无对应 char id；完整 CN 文案/字形仍需独立核对。
- 独立宿主鼠标轮询已可运行；真实点击/拖动/悬停、剪贴板、焦点、轮盘和手柄未人工验收。宿主仅转发 ESC，文本键盘输入/IME 尚未接入。输入路由只是调试宿主，不是完整游戏输入环境。
- 已加载真实 SquadHUD 和总览页面主体；完整 Dashboard 主窗口及其导航尚未加载。页面的真实 PageLifecycle 运行于业务订阅夹具，close/dispose 后夹具订阅归零；不能代替真实 Service 订阅、世界状态和业务验收。
- 没有匹配配置的游戏内截图，因此像素一致性未知。原版资产引用成功不代表所有资源包、人物头像、3D/世界背景均能离线显示。
- 已提供窗口尺寸与 CN/EN 参数，已查看 960×600 HUD 和 1280×800 总览英文截图；字号/分辨率/语言完整矩阵、热重载和性能预算均未验收。未跑模组全库测试、未重新打包、未启动游戏。既有全库回归失败不受本轮影响，也未宣称解决。

## 当前页面接入续记

- [真实小队 HUD 截图](../../../build/ui-preview-native/20261106-164834-424/native-ui.png)：原始 SquadHUD/SquadPresentation/Theme/Badge/Preferences/Lifecycle 直接加载，模块源码路径和 SHA256 记录于同目录 module-sources.tsv。三条服务 DTO、选择投影、四个原生子按钮数量检查通过；正常关闭与注入失败均执行真实 HUD.close，检查会话关闭、两项夹具订阅归零。异常证据：`build/ui-preview-native/20261106-165139-181/`，预期退出 1。
- [真实总览页面主体截图](../../../build/ui-preview-native/20261106-164618-556/native-ui.png)：SettlementOverviewPage 直接加载，三名工人、三条工单、库存快照仅由服务夹具输入；真实页面完成投影/绘制/dispose。外层是调试 ISPanel，未冒充完整 Dashboard 主窗口。该截图仍有符号缺失、齿轮/页脚重叠等问题，未修改生产布局。
- 复杂页面初次出现 VBO map 失败，核对 RenderThread 的上下文租约后改为整个帧经 invokeOnRenderContext 提交；同时逐帧 updateAsyncTransactions，并在 Smoke 首次绘制后排空懒加载资源，消除了截图中的未就绪红格纹理。后续总览渲染成功，原 Widgets 场景回归成功（`build/ui-preview-native/20261106-165454-007/`）。
- 完整 Dashboard 试加载失败于原版 ISInventoryPage / ISInventoryPane / ISInventoryTransferAction 的启动预加载互依，没有以 UI 替身绕过它；现保留实际总览页主体场景。
- 发现生产入口风险：`UI/SquadUI.lua:60` 在 `HUD.initialise` 后再次 instantiate，而 `UI/SquadHUD.lua:34` 的 addChild 按原版 ISUIElement.addChild 会先实例化父节点。实际复现第二次创建丢失四个原生按钮；预览按句柄存在性避免重复创建，生产代码未改。预览不能充当生产启动链完全等价的证据。

本轮只修改工具及说明；未改生产 Lua/JAR。真实鼠标/菜单/轮盘、中文、头像、游戏背景和像素对照仍保持 OPEN。

使用说明见[工具入口](../../tools/native-ui-preview.md)。
