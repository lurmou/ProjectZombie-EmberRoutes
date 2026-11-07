# ISUI 基础与实施边界

> 更新：2026-11-06｜状态：active。本文只维护当前工程契约；历史版本流水从Git查询，当前进度见[BACKLOG](BACKLOG.md)。

## 导航与权威

设计方向见[全项目前端视觉与交互原则](architecture/frontend-design-principles.md)；工程入口见[UI领域](domains/ui.md)、[运行时架构规格](architecture/ui-framework-architecture-spec.md)、[当前布局设计](superpowers/specs/2026-11-05-ui-consolidation-design.md)和[国际化](architecture/i18n-invariants.md)。规格中的目标不自动表示所有组件已实现；生产实现仍须查实际源码与验收记录。
UI是业务快照消费者和意图提交者，不保存第二套订单、资产或身体控制状态。姓名/图标/数量与未知状态真实显示；显示偏好可以通过专用服务保存，与业务权威分离。

## 当前基础设施

源码根为client/EmberRoutesProbe/UI。使用前读取当前方法签名，不从旧流水推断接口：

| 组件 | 用途 |
|---|---|
| Text / Layout / State | Unicode换行、相对布局、快照订阅；只在数据/布局变化时派生 |
| CachedList / FilterList | 缓存行、可见行绘制、原生滚动承载与清理 |
| CardPanel / Theme | 统一卡片与已登记配色，不能重造背景/强调条 |
| SemanticBadge / StatusVisual | 语义标记、阶段与数量；比例须有实际事实 |
| Viewport | pcall保护的Stencil成对裁剪；只裁剪调用期间的自绘canvas，不自动覆盖之后绘制的原生子控件 |
| PageLifecycle | 实例lifetime与活跃activation两层所有权，token拒绝晚到回调 |
| TooltipManager | register/update/clear/dismissOwner/unregisterOwner；仅管理所属实例和原生提示挂钩，无旧模块转发入口 |

## 引擎生命周期与渲染

new/initialise/instantiate分开。原生Java句柄存在后才调用依赖它的设置方法；未实例化父对象上addChild不作为安全证据。
render/prerender只读缓存，禁止table分配、拼接/格式化、JNI测量或实体扫描。原生ISUI仍按帧绘制，事件驱动不等于GPU零开销。
可滚动画布通过Viewport的闭合作用域绘制；部分可见内容交给stencil。提示框是独立浮窗，不在卡片裁剪区内部画；由TooltipManager定位并按owner释放。

## 刷新与关闭

已有Service事件接事件；引擎无事件的健康/状态等可在活跃视口有界定期读取。隐藏停止无效刷新。不要每帧全员扫描，也不要声称纯事件驱动却悄悄轮询。
页面切出/隐藏unmount，销毁dispose；订阅、watch、提示注册、浮窗、输入焦点和刷新任务由所属scope对称清理，不影响别的页面。原生共享菜单必须先确认仍属自己才关闭。

## 验证边界

CN/EN成对登记，动态键纳入check-i18n；模块路径/静态边界用check-architecture。Kahlua文本、生命周期和原生替身布局能验证接缝，不能替代游戏鼠标、渲染、缩放/模组共存、磁盘恢复或性能证据。按变更选最少必要检查，未运行明确标记。
