# 原版 UI 独立预览与实时调试

日期：2026-11-06｜状态：live workbench；原版一致性仍待验收。

无需进入存档，直接使用本机游戏 JAR、Lua、字体、贴图和 OpenGL 渲染。用于组件视觉调试；完整游戏 UI 的像素一致性尚未验收。

## 日常使用：指出元素，修改真实代码，自动看结果

```powershell
pwsh -File tools/preview-native-ui.ps1 -Live -Scene squad -Language EN -Width 1280 -Height 800
```

1. 在常驻窗口底部点击 **Squad / Overview / Widgets / Native** 切换已接入的页面。
2. 点击 **Pick OFF** 进入 **Pick ON**，再点击要改的按钮、卡片或总览区域。出现黄色边框，并自动截图，记录元素标题、边界和真实源码文件。
3. 告诉当前聊天“刚选中这个，改成……”；助手读取活动预览的 `selection.json` 和截图，修改真实生产 UI 源码。没有指出对象时，助手不能仅凭“这个”猜目标。
4. 保存当前页面已加载的 Lua、场景或当前语言翻译后自动重建。新增按钮会重新执行真实构造；按钮若受业务条件控制，仍需夹具满足该条件。重建会重置本轮选择/临时编辑状态，窗口保留。
5. 底部 **Reload** 强制重建，**CN/EN** 切换语言，**Capture** 保存画面。关闭可用窗口右上角关闭按钮，或控制脚本的 Close。

工具每 250ms 检查相关文件，并等待 250ms 稳定保存后重载。实际延迟还包括 Lua 重建、资源加载；不承诺零延迟。错误时显示原生错误画面与日志，下一次修复保存可恢复，不把旧画面留作成功结果。

仅监测当前加载/尝试加载的源码和所选翻译。未接入页面、Java 宿主和贴图变更不属于当前 Lua 自动重载范围；Java/窗口尺寸变更需关闭并重启工具。

F1–F4 切页、F5 重载、F6 语言、F7 显隐工具栏、F8 定位、F9 截图及 ESC 分支已接入。当前自动化键盘注入未触发快捷键，物理键盘未验收；**推荐使用已验证的可点击工具栏**。文本输入与 IME 尚未接入。

## 其他启动方式与检查

声明式布局试点新增 `-Scene layout -Smoke -Language CN`（以及 EN，建议分别运行 960 与 800 宽）。此场景加载生产 WarehouseControls/LayoutHost，以夹具提供查询/导航身份；执行原生焦点、点击/弹层、solve/apply 失败抑制、完整重应用、登记回滚和解绑失败重试。仅支持有界预览，不加入实时切页工具栏、不修改 Java Runner。

ComboBox 的 ArrowDown 位于安装版 UI2.pack；预览使用 `tools/ui-preview/extract-ui-arrow.py` 从当前包解出原图到本轮缓存，经临时 Lua 模块提供给场景，结束删除临时模块。只替换预览实例的 image 引用，不修改游戏文件、生产控件或缺图守卫；依赖 Python Pillow。此资源准备不代表游戏纹理包加载已被完整模拟。

在仓库根目录，用 PowerShell 7 和 PATH 中的 JDK 运行：

```powershell
# 原版控件样例，默认两分钟自动结束，可用窗口关闭按钮退出
pwsh -File tools/preview-native-ui.ps1

# 项目真实 Widgets：CardPanel、StepperInput，以及原版滚动列表
pwsh -File tools/preview-native-ui.ps1 -Scene widgets

# 当前小队 HUD：真实 HUD/排版/偏好/生命周期，业务数据为夹具
pwsh -File tools/preview-native-ui.ps1 -Scene squad -Language EN

# 当前据点总览页主体，独立调试容器，未加载完整 Dashboard 导航
pwsh -File tools/preview-native-ui.ps1 -Scene settlement -Language EN -Width 1280 -Height 800

# 有界渲染检查，自动点击使用合成坐标，不冒充真实鼠标验收
pwsh -File tools/preview-native-ui.ps1 -Scene widgets -Smoke

# 异常释放检查：预期返回失败，日志应包含 CLEANUP display destroyed
pwsh -File tools/preview-native-ui.ps1 -Smoke -InjectFailure

# 13 项原生保存/恢复/切页/定位自测（只写 build 夹具）
pwsh -File tools/preview-native-ui.ps1 -SelfTest
```

可选 `-GameRoot <安装目录>`、`-Seconds 300`、`-Language CN/EN`、`-Width/-Height`。字体与模组翻译字典使用所选语言；原版核心键沿用原生解析。当前本机基线使用游戏自带 JVM 和 `.lwjgl/3.4.1-snapshot/x64` 原生库；依赖缺失直接报错，不启动游戏作为降级。

`-Live` 常驻直到关闭，不使用两分钟限制；不要与 Smoke/SelfTest/InjectFailure 混用。`-SelfTest` 会在 build 专属夹具中验证保存后增加按钮、错误恢复、清理与页面切换，不修改生产文件。

每次运行生成 `build/ui-preview-native/<时间戳>/`：每代截图 `preview-rN.png`、手动/定位截图 `capture-N.png` 及对应 JSON，当前画面 `latest.png`、状态 `status.json`、配置 `control.json`、定位 `selection.json`、错误 `error-rN.log`、来源与 SHA256 清单 `module-sources-rN.tsv`、隔离缓存 `cache/`。关闭后写 stdout/stderr、run.json、closed.json。

图片读取原版 GL framebuffer，BufferedImage 仅保存 PNG，没有 AWT 代画。捕获元数据携带当前代、场景、语言和选中对象；新代会明确清除旧定位，避免误改上次对象。

## 助手控制入口

`build/ui-preview-native/active.json` 指向最近启动的 Live 窗口。控制脚本校验活动目录/进程，不连接游戏：

```powershell
pwsh -File tools/control-native-ui.ps1 -Action Status
pwsh -File tools/control-native-ui.ps1 -Scene settlement
pwsh -File tools/control-native-ui.ps1 -Action Reload
pwsh -File tools/control-native-ui.ps1 -Action Inspect -X 200 -Y 140
pwsh -File tools/control-native-ui.ps1 -Action Capture
pwsh -File tools/control-native-ui.ps1 -Action Close
```

坐标使用工具截图的客户区坐标，不含 Windows 标题栏。可见点击无需坐标输入。指认只选择/记录对象，不自动修改源码；用户仍需在聊天说明要怎样修改。

## 真实与替身边界

| 项目 | 当前实现及证据范围 |
|---|---|
| 绘制 | 原版 Display/着色器/SpriteRenderer/TextManager/UIElement；已检查真实截图 |
| 原版组件 | 安装版 ISPanel、ISButton、ISScrollingListBox、UITextBox2；直接加载源码和 Java 类 |
| 项目组件/页面 | 直接加载仓库 CardPanel、StepperInput、SquadHUD、SquadPresentation、SettlementOverviewPage 及其展示依赖，没有复制其绘制实现 |
| 场景与业务 | 自带合成场景；页面的世界向 Service 由显式夹具提供 DTO/订阅释放。未加载模组启动器、世界或存档，世界命令禁用；NPC 头像未生成，完整轮盘/菜单未验收 |
| 输入 | 左键使用事件队列并保留原版 GLFW 回调；移动/滚轮转发给原版根 UIElement。真实鼠标点击工具栏、原生按钮定位及自绘卡片定位已验证；完整键盘/拖动/焦点/菜单仍待验收，不是完整 UIManager 输入环境 |
| 声音 | 原版 DummySoundManager，静音 |
| 中文 | Java 注入的“中文”样例可见；Lua 源码中文字面量曾出现乱码，部分简体字在当前字体资源中缺字，均未解决；不以短样例证明完整中文支持 |
| 一致性 | 没有同配置游戏内截图对照，不能声称完整 1:1 或代替实机验收 |

## 维护方式

- 窗口宿主：[NativeUiPreview.java](../../tools/ui-preview/NativeUiPreview.java)，每帧按原版 prePopulating 清绘制队列，持有 RenderThread 上下文再提交；[PreviewFrame.java](../../tools/ui-preview/PreviewFrame.java) 是仅在调试 classpath 的同包桥，按 UIManager.render 重置包可见的 stencil 深度，不替换游戏类或 JAR。
- 每代页面：[PreviewSession.java](../../tools/ui-preview/PreviewSession.java)，close/dispose、解除原生输入焦点/捕获、清理独立 JVM 的 UI/待加入队列和 Lua Events/Hook 后创建新环境。记录实际字节的 SHA256；按原版编译入口设置 FuncState.currentFile/currentfullFile，源码定位不依赖过期全局文件名。
- 控制与监测：[PreviewLiveControl.java](../../tools/ui-preview/PreviewLiveControl.java)，严格配置校验、原子文件更新、有界防抖；[PreviewInspector.java](../../tools/ui-preview/PreviewInspector.java) 遍历真实 Java 控件树，读取场景提供的真实自绘缓存边界。调试 JVM 退出前释放窗口和 GL；随后终止其非 daemon 引擎文件线程。
- 样例：[native-scene.lua](../../tools/ui-preview/native-scene.lua)、[widgets-scene.lua](../../tools/ui-preview/widgets-scene.lua)。后者复用前者，增加项目组件。场景不进入生产模组目录。
- 页面场景：[squad-scene.lua](../../tools/ui-preview/squad-scene.lua)、[settlement-scene.lua](../../tools/ui-preview/settlement-scene.lua)。`PreviewServices` 仅能替换业务模块，拒绝替换 UI 模块；卸载时走真实页面 close/dispose，检查夹具订阅归零。
- 模块加载器只定向加载原版 shared/client 与本项目 shared/client，不执行整套 Lua 目录。保留模块返回值，缺模块或递归加载直接失败；未实现模组覆盖顺序、全量游戏启动环境。
- Live 模式修改相关 Lua/翻译后自动重载；尚无字号切换器及完整业务页面场景工厂。不要为预览方便放宽生产组件守卫。
- 工具保持与模组构建分离，不打入玩家安装包，不修改游戏启动器、JAR、现有存档或联机适配。

原型[证据](../reviews/2026-11-06/native-ui-preview.md)；实时调试[计划](../superpowers/plans/2026-11-06-native-ui-live-debug.md)与[验证](../reviews/2026-11-06/native-ui-live-debug.md)。

## 当前页面显示的限制

- 完整 Dashboard 的原版依赖涉及库存 UI 预加载互依；现阶段总览场景只加载真实页面主体，并明确标注调试容器，没有以简化导航冒充完整主窗口。
- 生产 `SquadUI.show` 当前仍在 HUD.initialise 后无条件再次 instantiate；安装版 addChild 已能提前实例化父节点。预览观察到重复实例化丢失四个按钮，宿主按一次 Java 句柄创建加载，生产入口尚未修改。因此预览不是生产启动链的逐步复刻。
- 截图仍可见部分徽章符号缺失与页面重叠，且没有游戏内同条件对照。页面能显示不等于已获得原版 1:1 或视觉验收通过。
