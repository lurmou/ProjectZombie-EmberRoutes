# 原版 UI 实时调试验证

日期：2026-11-06｜状态：live workbench verified within stated scope。

目标由用户明确批准：用同一真实 UI 源码实现“指出元素→修改→自动刷新反馈”。生产 UI、世界/存档和业务契约均未修改。

## 实现与所有权

- [NativeUiPreview](../../../tools/ui-preview/NativeUiPreview.java) 拥有 Display、GL 上下文、输入回调链和常驻循环。底部工具栏可点击切页、重载、语言、定位及截图。保留原版 GLFW 回调，退出时还原/释放自己添加的回调。
- [PreviewSession](../../../tools/ui-preview/PreviewSession.java) 每代创建新的 Lua 环境/模块缓存。重载先调用场景的真实 close/dispose，解除文本焦点/鼠标捕获，再清理本调试 JVM 的 UI/待加入队列和 Lua Events/Hook。没有连接游戏进程，不清理用户游戏资源。
- [PreviewLiveControl](../../../tools/ui-preview/PreviewLiveControl.java) 监听场景、成功/尝试加载的源码、当前翻译；250ms 轮询+250ms 稳定期。读源码前记录 stamp，避免读取期间再次保存被确认动作吞掉。失败后保留相关监听，支持修复恢复。
- [PreviewInspector](../../../tools/ui-preview/PreviewInspector.java) 使用真实 Java 控件树和实际缓存区域；原生按钮报告创建页面/控件源码，自绘卡片/区域读取真实缓存边界。截图携带同代 metadata，换代明确清除旧定位。
- 控制文件仅接受当前 format=1、场景/语言白名单和完整字段；原子更新。加载或 Lua 渲染错误显示独立错误画面，不保留旧页面伪装成功。
- 按原版 UIManager.render 重置 stencil 深度的同包桥 [PreviewFrame](../../../tools/ui-preview/PreviewFrame.java) 仅加入本工具 classpath，没有替换游戏类或修改 JAR。

## 基线

仍使用原型相同的安装 JAR：SHA256 `E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`；OpenGL 日志 `4.6.0 NVIDIA 617.14`。每代实际源码字节 SHA256 记录于 `module-sources-rN.tsv`；配置、状态、错误、截图均在 build 专属目录。

## 已通过

`pwsh -File tools/preview-native-ui.ps1 -SelfTest`，最终证据目录：`build/ui-preview-native/20261106-175821-736/`，selftest.json complete=true、13 项通过，退出码 0。

1. 原生窗口渲染一按钮；保存专属测试源码后自动出现两按钮，非点击重载或启动第二个 JVM。
2. 语法错误→错误画面（旧根移除）→保存修复后恢复三按钮。
3. 删除专属场景文件→错误→恢复文件后自动恢复。
4. 定位真实 ISButton，记录标题/几何及正确的安装版 ISButton.lua 来源，生成同代截图。
5. 非完整控制 JSON 被拒绝，不改变有效场景，后续有效配置恢复。
6. 原生回调中设置 stencil 后故意抛错，错误被捕获；修复后可恢复，没有残留裁剪污染后续 HUD。
7. 控制文件切到真实 SquadHUD，再重载一次，真实页面 close/dispose 的夹具订阅断言通过，UI 根维持一个。
8. 切页像素检查：旧页面/错误字样不残留；真实 HUD 卡片可见。
9. 控制文件切到真实 SettlementOverviewPage 主体并正常退出释放。

最终 Widgets Smoke 运行：`build/ui-preview-native/20261106-180100-450/`，真实 StepperInput 回调/上限、原版列表与页面渲染通过（退出 0）。这些是原生独立宿主证据，不是游戏世界或完整业务验收。

最终独立故障释放：`build/ui-preview-native/20261106-180325-021/`，`-Scene squad -Smoke -InjectFailure` 预期退出 1，日志含真实 HUD 释放与 `CLEANUP display destroyed`。它是故障注入通过，不计作普通成功运行。

## 真实鼠标验证

用 computer-use 在独立工作台内验证，未操作其他应用：

- 点击底部 **Pick OFF**，切为 **Pick ON**。
- 点击原生“All”按钮，正确选择 ISButton，source 指向生产 SquadHUD.lua。
- 点击自绘 Ada 成员卡，黄色框使用实际卡片缓存，得到 `member:preview-ada` 和生产 SquadHUD.lua，自动生成截图及 selection.json。

最终留给用户的活动窗口目录：`build/ui-preview-native/20261106-175431-905/`；[指认画面](../../../build/ui-preview-native/20261106-175431-905/capture-1.png)。运行时以 active.json 为准，不以此历史路径定位当前窗口。

## 排查中纠正的问题

- 早期仅看控件计数曾通过，但截图黑屏/出现切页残影。回到当前 JAR 核对 SpriteRenderer.prePopulating 的 clear/numSprites/GLState 初始化，补齐每帧调用，增加像素检查，最终图片已确认。
- 严格捕获渲染回调后发现原版 ISPanelJoypad 依赖 JoypadState；定向加载原版 env/JoyPadSetup，未伪造 UI 表隐藏缺依赖。
- Prototype.filename 曾指向旧编译全局的 Sandbox 文件；按原版 LuaManager.RunLua 设置 FuncState.currentFile/currentfullFile，定位断言通过。
- 这些排查中的失败截图/日志保留，不计为最终通过。

## 未完成与边界

- 自动化键盘注入未触发快捷键；物理键盘仍未验收。已验证的操作路径是可点击工具栏和控制脚本，不声称快捷键已通过。文本输入/IME、完整菜单/轮盘/手柄/拖动仍未验收。
- 没有自动修改源文件的后台代理：用户选中后在聊天提出修改要求，助手读取 selection/status/capture 后执行修改。聊天本身不自动知道用户光标位置。
- 重载重建页面，临时选择/编辑状态会重置。Java 宿主、贴图和未加载页面不属于 Lua 自动重载范围。
- 完整 Dashboard、中文/徽章字形、头像、世界背景与游戏内像素一致性保持 OPEN；业务快照是夹具、世界命令禁用。
- 原生产 SquadUI 重复 instantiate 风险未修改。没有构建模组包、改 JAR、启动游戏、操作存档或运行全库测试。

使用[说明](../../tools/native-ui-preview.md)，实施[计划](../../superpowers/plans/2026-11-06-native-ui-live-debug.md)。


## Overview 悬停报错修复（2026-11-06 晚间）

用户窗口 `build/ui-preview-native/20261106-234309-478/status.json` generation 2：`render: attempted index: new of non-table: null`。安装版 `ISButton.lua:316–338` 悬停/手柄焦点进入 `ISToolTip:new()`；`ISToolTip.lua:358` 再调用 `ISRichTextPanel:new()`，两者由游戏完整启动环境提供，定向预览之前没有加载。不是业务快照字段缺失。

- `PreviewSession.load` 定向预载两个原版模块，不改生产页面或伪造 UI 类；回调错误附控件类型/方法及 Kahlua trace。
- `PreviewSession.draw` 通过仅在工具 classpath 的 `PreviewFrame.flushPendingUI` 消费原生 UIManager 加入/移除队列，绘制实际浮动 UI 根；不再只绘制场景子树。
- `settlement-scene.lua` 的 smoke 以真实按钮的手柄焦点触发同一 updateTooltip 分支；自测覆盖浮层出现、隐藏移除，以及切走后的真实 dispose/watch 归零。没有自动化物理鼠标悬停证据。
- `tools/preview-native-ui.ps1 -SelfTest`：`build/ui-preview-native/20261106-235439-433/`，16 项通过、12 代、退出 0、正常 CLEANUP。之前失败 `235359-897` 保留：只补 ISToolTip 仍因缺 ISRichTextPanel 失败，不计通过。截图已检查页面显示；小窗底部调试条遮挡与符号缺字仍存在，不宣称视觉验收完成。

### 另一个未决故障：GLFW 原生闪退

`build/ui-preview-native/20261106-232956-365/` 在约 41 秒后 EXCEPTION_ACCESS_VIOLATION，`glfw.dll+0x10fa1`、`Display.processMessages`；control.quit=false，没有 closed.json。这与 Lua 页面异常分开追踪，本次依赖修复和短时自测不能证明 GLFW 闪退已经解决。窗口激活复现曾被用户 Escape 中止，未得结论。
