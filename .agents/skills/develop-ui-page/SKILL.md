---
name: develop-ui-page
description: Build EmberRoutes UI with current widgets, native instantiate order, pure presentation and activation-owned resources.
---

# UI 页面与面板开发手册

更新：2026-11-06｜状态：active。必读[全项目前端设计方向](../../../docs/architecture/frontend-design-principles.md)、[UI领域](../../../docs/domains/ui.md)、[运行时规范](../../../docs/architecture/ui-framework-architecture-spec.md)与[国际化约束](../../../docs/architecture/i18n-invariants.md)。

0. 先定义用户任务、使用环境、信息层级、布局与主要交互状态，再接入业务字段。首版按适用功能完成可发现的入口、选择/输入、反馈及退出恢复；不要把视觉与交互留作业务接通后的补丁。
1. 从INDEX任务路由找到真实页面与Service；核对现有Widgets。数值输入复用StepperInput，列表复用CachedList/FilterList，卡片复用CardPanel，状态复用SemanticBadge/StatusVisual，颜色使用Theme实际字段（如Theme.accent、Theme.status.ERROR），没有Theme.getColor接口。
2. 区分new/initialise/instantiate；在原生Java句柄存在后配置输入和按钮。参考当前SquadHUD与StepperInput的真实初始化链，不把父容器尚未实例化时addChild当作Java句柄已经存在。
3. 展示层只接收Service快照和提交意图。Presentation只在数据/布局变化时投影；render/prerender仅读缓存，不创建table、拼接文本、测量或扫描实体。裁剪使用Viewport.draw的闭合调用；不把prerender开Stencil、render关Stencil当作所有原生生命周期都安全的通用模板。
4. 生命周期使用PageLifecycle.createLifetimeScope/createActivationScope。订阅、Service watch、浮窗和刷新由所属scope拥有；回调用wrapCallback。关闭/切出通过unmount/dispose对称释放，停止后台刷新，不能只移除面板。
5. 提示只使用TooltipManager当前接口：`register(widget,{method='updateTooltip',owner=page})`注册/挂钩；`update(widget,text)`置内容；`clear(widget)`隐藏；`dismissOwner(page)`暂时隐藏；`unregisterOwner(page)`永久移除注册/还原hook。生命周期结束需要永久移除的资源不能只dismiss。不保留TooltipAnchor、attach或clearOwner兼容入口。
6. CN/EN成对添加文案和有限动态键，运行check-i18n与check-architecture；定向运行真实页面的Kahlua测试，必要时运行tools/test-ui-kahlua.ps1做文本/布局检查。该脚本不是全库调度回归。用户负责实机时，不把替身渲染、编译或构建记成实机通过。

所有UI改动说明复用了哪些Widgets、裁剪边界及资源在哪个scope释放。可参考UI/SquadHUD.lua（独立HUD）和UI/PersonnelPage.lua（仪表盘页面）；人员详情的颜色/文本派生在UI/PersonnelPresentation.lua，业务Service不依赖Theme。

交付将视觉/交互验收与逻辑/构建结果分开：验证真实使用背景、主要任务、不同窗口/字号/语言及异常状态；外部预览必须说明渲染/输入/数据哪些是真实、哪些是替身。

快速视觉迭代与强制自检使用[原版实时调试工具](../../../docs/tools/native-ui-preview.md)：
每次修改或新增 UI 布局后，必须运行 `pwsh -File tools/preview-native-ui.ps1 -Scene <scene> -Smoke`（支持 squad、settlement、widgets、native），回读生成的原生截图进行视觉核对（压字、穿模、多语种排版溢出与徽标），严禁要求用户启动游戏截屏充当“视觉测试员”。调试可用实时热重载：`tools/preview-native-ui.ps1 -Live -Scene squad -Language EN`。未接入页面须先提供业务快照夹具，不复制 UI 绘制、不放宽生产守卫。
