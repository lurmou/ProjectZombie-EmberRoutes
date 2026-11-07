# 原版 UI 独立预览原型

日期：2026-11-06。用户已批准尝试；这是调试工具原型，不改变游戏 UI 架构。

目标：不进入游戏世界，在独立窗口验证当前安装版的原版 UI 渲染链。先证明字体、贴图与 UIElement 绘制确实提交到 OpenGL，再评估 Lua 控件和输入覆盖。不得用 AWT/浏览器代绘结果宣称原版一致。

## 实施与验收

1. 对照当前 projectzomboid.jar 字节码定位 Display、RenderThread、SpriteRenderer、AngelCodeFont 与资产初始化契约。参考现有 KahluaUiTextTest，仅复用经验，不复用其 AWT 绘制替身。
2. 工具独立于模组运行目录；使用本机游戏 JAR/资源，不复制资源、不加载启动器的 NPCFW/优化代理，不启动游戏可执行文件、不加载存档。缓存、编译产物、日志和截图全部归 build/ui-preview-native。
3. 单进程拥有窗口与 GL 上下文；正常关闭和异常路径都在 finally 释放。提供有界冒烟运行，避免初始化死锁遗留进程。
4. 逐项记录窗口/字体/纹理/控件/裁剪/输入的实际证据。只有真实截图和交互结果才能标为通过。加载类或编译通过不算渲染通过。
5. 启动依赖超出可隔离范围时保留诊断与边界，不能以整套游戏启动冒充轻量预览。完整像素一致、世界实体画面、中文/字号及所有控件均需独立验证。

## 已核对入口

- 原版 ISUIElement.lua:instantiate 创建 UIElement Java 句柄。
- UIElement.DrawText → TextManager → AngelCodeFont；贴图 → SpriteRenderer。
- RenderThread.invokeOnRenderContext 在未初始化时借用 Display 上下文执行；不调用依赖 GameInput/世界设施的整套 shutdown，按本工具实际创建资源释放。
- 当前 JAR SHA256：E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33。

## 原型交付

已接通独立原版渲染、原版控件与项目 Widgets 两个样例；启动、截图、合成坐标事件、禁用/步进上限、列表滚动目标与裁剪、正常/注入异常释放有证据。使用[工具说明](../../tools/native-ui-preview.md)，事实与剩余边界只记录于[证据](../../reviews/2026-11-06/native-ui-preview.md)。真实输入、完整中文、业务页面和游戏内像素对照保持未验证，不把本原型扩大为正式 UI 框架。

后续用户要求显示当前 UI：在同一宿主中增加真实 SquadHUD 与 SettlementOverviewPage 场景；以显式业务模块夹具提供快照，保留真实 UI/Presentation/生命周期。提供 CN/EN 与窗口尺寸参数、源码哈希清单；复杂绘制使用 RenderThread 上下文租约，逐帧泵送异步资源。完整 Dashboard 因原版库存 UI 预加载依赖未接通，保留为后续；不改生产代码以迎合宿主。
