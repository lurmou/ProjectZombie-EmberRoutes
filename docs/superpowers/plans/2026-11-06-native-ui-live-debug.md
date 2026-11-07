# Native UI Live Debug Implementation Plan

日期：2026-11-06｜状态：核心工作流已交付；快捷键物理验收及完整游戏 UI 保持 OPEN。用户已明确批准自动重载，要求“指出元素→修改真实源码→实时反馈”。

**Goal:** 原生预览窗口常驻，保存 UI/Lua/翻译后自动重建，显示错误并可恢复；能定位元素、截图并给出源码位置。

**Architecture:** 独立 JVM 保留 GL/字体/纹理环境；每代页面拥有独立 Lua 环境、模块缓存和依赖清单。旧页调用真实 close/dispose，再清理本调试 JVM 的 UI 数组与 Lua 事件/Hook，然后加载新代。每代失败以错误界面结束，不继续使用旧页面。文件轮询及防抖有界，不修改游戏世界/生产守卫。

**Tech Stack:** 当前安装 PZ JAR、Kahlua、LWJGL/GLFW、Java、PowerShell 7。

**Spec:** [已批准原生预览原型](2026-11-06-native-ui-preview-prototype.md)、[工具边界](../../tools/native-ui-preview.md)，以及本轮用户指令。

## Global Constraints

- 生产 UI 仍从原文件加载，不重写另一套页面；服务快照仍为夹具，禁止执行世界命令。
- 不加载存档、不启动游戏、不修改生产代码、不打包、不添加旧链路兼容。
- 页面重载会重置预览选择/临时编辑状态，窗口保留；当前不承诺文本输入/IME、完整 Dashboard 或像素一致。
- 原版 clearArrays 会清理 UI/toAdd/toRemove；LuaEventManager.Reset 和 LuaHookManager.Reset 的当前 JAR 公共入口已核对，仅用于专属调试 JVM。

## Review Focus

- 保存时短暂语法错误：显示错误，后续保存可恢复，不能保留旧按钮误导用户。
- 页面多次重建/切换：dispose、订阅、原生窗口与事件不得残留。
- 新增按钮/依赖：重新执行真实构造，Java 子控件随源码变化；失败的缺失依赖也须可监听恢复。
- 控制文件非完整 JSON/非法场景：保持有效配置并显示命令错误，不执行未知路径。
- 元素为画布自绘：通过场景读取真实缓存边界补充语义区域，不伪造 Java 子按钮；定位不等于自动知道用户所指对象。

### Task 1: 会话与重载闭环

**Files:** 拆分 `tools/ui-preview/PreviewSession.java`；修改 `NativeUiPreview.java`；新增 `PreviewLiveControl.java`。

- [x] 每代创建/正常释放/加载失败释放，以及真实来源/哈希记录。
- [x] 监听当前场景、加载及尝试加载的源码、所选翻译；250ms 检查+250ms 防抖。
- [x] 常驻控制文件支持 scene/language/reload/capture/inspect/quit，提供已验证的可点击工具栏。
- [x] 快捷键分支已接；自动化按键未触发、物理键盘未验收，保持单列限制，不宣称验收通过。
- [x] 原版渲染错误提示、latest/status/control 文件；保存失败后修复可继续。

### Task 2: 指认与反馈入口

**Files:** 新增 `PreviewInspector.java`；修改 `squad-scene.lua` / `settlement-scene.lua` 与启动脚本。

- [x] 点击定位模式高亮最深原生控件，输出类型/标题/几何/源码；自绘卡片提供真实缓存区域。
- [x] 截图与定位 JSON 同代同配置，源文件哈希可追溯。
- [x] `-Live` 常驻启动，运行目录/进程可发现，文档给出单命令使用路径。

### Task 3: 验证与交付

**Files:** 新增工具内 `PreviewLiveSelfTest.java`（只写 build 专属夹具），更新工具文档/证据/BACKLOG。

- [x] 真实窗口：一按钮→保存两按钮→自动重建；不改用户生产文件。
- [x] 语法错误→错误画面→修复恢复，缺失源码→恢复；另验证未闭合 stencil 后渲染报错恢复。
- [x] 切换真实 HUD/总览，检查清理及无重复 UI 根节点，验证截图/定位输出。13 项自测通过。
- [x] 原 Widgets Smoke 回归、故障释放、定向文档/空白检查；实机与完整中文保持未验证。

由当前聊天顺序执行，不默认委派子代理或创建提交。

交付与局限详见[验证记录](../../reviews/2026-11-06/native-ui-live-debug.md)。未改生产 UI/业务代码或打包。
