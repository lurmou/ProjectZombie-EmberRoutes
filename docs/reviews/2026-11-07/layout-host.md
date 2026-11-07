# Phase 2 LayoutHost 与仓储工具栏试点证据

日期：2026-11-07。用户授权“开始吧”，范围为冻结承载契约、Host 实现及仓储工具栏试点；Phase 3、自动测量、全库迁移均未启动。

## 生产链路与责任

- `UI/LayoutHost.lua:53` 登记入口预检目标、父级和重复登记；`:41` 创建 Node item 后挂载，最后提交 `_leafItems`。失败用 `:30` release 回滚，回滚失败保留 `_pending`/owners/错误信息；rect 失败恢复原 visible。
- `:103` apply 在所有项预检通过后逐项执行公开 setter；尺寸先于位置，可见性最后应用。原生父级同时核查 Lua getParent 与 Java getParent。只允许左/上固定、右/下不伸缩、未开启 keepOnScreen 的叶子。
- `:136` resolveLayout 分开 solvedRevision 与 appliedRevision；同一求解/应用失败不逐帧重试；`:165` retryLayout 从第一项完整重放。原生应用可能部分完成，不宣称回滚原子性。
- `:82/83/90` 使用既有 PageLifecycle ActivationScope；失活不销毁树。`:174` dispose 先隐藏解绑，成功后清登记和拓扑；部分失败保持 closing 状态，可继续 dispose，不能再激活。
- `WarehouseControls.new(owner,nativeParent,bounds)` 全部生产调用方已更新；搜索、分类、排序及制作/最低库存按钮保持 Page owner，不迁移 Store 或 Tooltip。Page 在 activate/deactivate/dispose 接入 Host，调整宽度时安全更新；共享 Combo 弹层清理核对 parentCombo。
- Node 增加 revision；同值 Setter 不置脏/递增，真正变更仍向上冒泡。Host 构造时调用 claimRoot，已认领但尚未发布的根也不可被其他树挂载。solve 的失败保留几何与 dirty 语义不变。

## 最终源码基线

| 文件 | SHA256 |
|---|---|
| LayoutHost.lua | 41E2D6306EE984F2D5F9F7102A748FBD6B556E4394F7B404D98E050D618A4CD7 |
| LayoutNode.lua | 36932D0ECD4E3E004DF74BC67B35E0522B6D94CE8A4874421C0095E71DD82880 |
| WarehouseControls.lua | B10F7115CD86323F903F5CDD3901A86ACC64B89DF9138F6B6390A73A4E65C30B |
| WarehousePage.lua | 31CAF3B9DA46C45C15B6143E38E8C1007A415E319F43868BD1A7F1869AD5D49A |
| 安装版 UI2.pack（仅预览取资源） | 7CE945D34A6A3700DF5315B0590E4332C2127203B111CB5686740DCBB136920F |

## 执行证据

生产实际控件由 `tools/ui-preview/layout-scene.lua` 创建，通过当前安装 JAR、原版 Lua、原生 UIElement 和 OpenGL 执行；导航/查询身份是明确的夹具，未加载游戏世界。没有修改 Java Runner；没有交付新 tests 脚本。

| 检查 | 结果 |
|---|---|
| Phase 1 安装版 Kahlua 回归 | 136 项通过，`build/layout-phase2-math.log` |
| Host/工具栏故障注入 | 原生场景 smoke 通过：非零偏移、Lua/Java/屏幕坐标、输入框 focus/unfocus、业务回调 owner、真实嵌套按钮点击分发、全局共享 popup 定位、干净版本不重复 setter、同值 Setter 版本不变 |
| 故障恢复 | 求解失败同版仅一次；第二控件 setter 抛错后第三项未执行，显式 retry 从第一项重放；旧激活令牌下不更新；重新激活复用；挂载后登记异常回滚；rect 登记失败恢复可见性；解绑失败保留责任、重试成功；原业务控件重新登记；嵌套虚拟节点的 rect 坐标 |
| 静态依赖 / i18n | check-architecture 0 error；check-i18n 2084 对通过，无新增界面文案 |
| PZ 结构检查 | lint 对 Host、WarehouseControls、WarehousePage 未发现问题；工具知识库有原版 Fluids 中 `0.0f` 解析缺口，扫描器已说明跳过，不作为全库无误证明 |
| 最终构建 | `build/layout-phase2-build-delivery.log`，exit 0 / BUILD_OK；376 份 Lua 普通/Debug 编译通过，固定 JAR 哈希与构建自带检查通过。产出 0.29.59 包包含工作区其他已有改动，不是隔离发布包 |
| LuaLS | 完整模组检查长期未返回诊断，已停止；改用同一工具与 Umbrella 对本轮五份源码的哈希一致快照检查，最终0 error / 139 warning；不作为全模组类型通过。命令 `node ../.workbuddy/tools/pz.mjs luals build/layout-phase2-lsp --warnings`，日志 `build/layout-phase2-luals-focused-final.log`。need-check-nil 集中于 release 的 entry.item/target 动态联合类型，已按登记/回滚/清理调用链核对；未为消除告警放宽生产守卫。未复制的依赖模块类型不在该范围内 |

## 原生截图回读

执行 `pwsh -File tools/preview-native-ui.ps1 -Scene layout -Smoke -Language <CN/EN> [-Width 800 -Height 600]`。

| 场景 | 路径 |
|---|---|
| EN 960×600 | `build/ui-preview-native/20261107-115335-509/preview-r1.png` |
| CN 960×600 | `build/ui-preview-native/20261107-115405-474/preview-r1.png` |
| EN 800×600 | `build/ui-preview-native/20261107-115455-602/preview-r1.png` |
| CN 800×600 | `build/ui-preview-native/20261107-115647-048/preview-r1.png` |
| EN 后续故障覆盖回归 | `build/ui-preview-native/20261107-115915-682/preview-r1.png` |
| CN 最终夹具回归 | `build/ui-preview-native/20261107-120009-902/preview-r1.png` |
| EN 根认领守卫最终回归 | `build/ui-preview-native/20261107-120345-489/preview-r1.png` |

CN/EN 及960/800宽截图均已回读：工具栏五项无相互重叠，Host 偏移未重复叠加，按钮文本可读，下拉层越过 Host 边界显示；长分类名按原生 popup 宽度裁切，未新增自动增宽策略。后续故障注入回归截图也已回读。

预览缺少 UI2.pack 的 ArrowDown，初跑在 Combo prerender 报错，没有记成功；后使用当前 JAR TexturePackDevice 字节码核对 pack v1 格式，将安装包中的原图解出到本轮允许的 cache 目录，并仅为预览 Combo 实例设置 image。准备由 extract-ui-arrow.py 完成，临时 Lua 模块由 PowerShell 创建/结束删除。未修改游戏文件，未向生产代码增加缺图 fallback。预览音频静音，字体来自安装环境；不等价于完整游戏初始化。

## 失败与未验证

- `settlement-ui-test.lua`：适配了原生 parent/instantiate/setter 替身契约；执行在旧 `panel.itemList.emberColumns` 断言失败（此前 storage-panel 的24项通过）。当前 WarehousePage 使用 itemGrid，测试还引用旧 itemList、controls.clear 等已不存在接口。本轮保留失败断言，没有为过测试加入生产兼容字段；不是全套回归通过。
- 首轮没有实现一个覆盖所有原生后代的通用剪裁器；不能承诺任意非法缩窗保留旧矩形时都不会超出 Host。当前真实试点仅验收表中正常宽度，求解拒绝与恢复通过故障注入验证，极端缩窗的完整页面体验仍待实机核对。
- 未在实际游戏世界中验收仓储业务、IME/真实键盘输入、其他 UI 缩放、其他页面、全库布局或 GC/性能。不从 native smoke 的程序化 focus 和回调推导物理键盘已通过。
- 首轮 Host 仅允许初次激活前登记，不支持动态叶子添加/移除及跨根迁移；不宣称通用第三方控件适配已验证。
